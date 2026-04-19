import 'dart:async';
import 'dart:convert';
import 'dart:developer';
import 'dart:math' as math;

import 'package:collection/collection.dart';
import 'package:dio/dio.dart';
import 'package:fstore/common/typesdef.dart';
import 'package:graphql/client.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import '../../../common/config.dart' show kAdvanceConfig, kShopifyPaymentConfig;
import '../../../common/constants.dart';
import '../../../data/boxes.dart';
import '../../../generated/l10n.dart';
import '../../../models/cart/cart_model_shopify.dart';
import '../../../models/entities/currency.dart';
import '../../../models/entities/filter_tags.dart';
import '../../../models/entities/index.dart';
import '../../../models/index.dart'
    show
    Address,
    CartModel,
    Category,
    CheckoutCart,
    Order,
    PaymentMethod,
    PaymentSettings,
    PaymentSettingsModel,
    PaymentShopify,
    Product,
    ProductModel,
    ProductVariation,
    RatingCount,
    ShippingMethod,
    User;
import '../../../models/vendor/store_model.dart' as store_model;
import '../../../services/base_services.dart';
import 'shopify_query.dart';
import 'shopify_storage.dart';
import 'shopify_token_store.dart';

// ─── API version constants ────────────────────────────────────────────────────
const _storefrontApiVersion = '2026-01';

// ─── Customer Account API credentials ────────────────────────────────────────
// client_id: from Shopify Partner Dashboard → Apps → Customer Account API
// client_secret: from same location — required for confidential client token exchange
const _kShopifyClientId     = 'eba394e8-4043-4d28-a9d5-6f31068c0fbc';
const _kShopifyClientSecret = 'YOUR_CLIENT_SECRET_HERE'; // ← paste from Partner Dashboard
const _kShopifyRedirectUri  = 'https://account.fawaah.com/callback';

class ShopifyService extends BaseServices {
  ShopifyService({
    required String domain,
    String? blogDomain,
    required String accessToken,
    super.reviewService,
  })  : client = _getStorefrontClient(
    accessToken: accessToken,
    domain: domain,
    version: _storefrontApiVersion,
  ),
        super(domain: domain, blogDomain: blogDomain);

  /// Storefront API client — catalog, cart, checkout, password auth
  final GraphQLClient client;

  ShopifyStorage shopifyStorage = ShopifyStorage();

  @override
  String get languageCode => super.languageCode.toUpperCase();
  String? get countryCode => SettingsBox().countryCode;

  final _cacheCursorWithCategories = <String, String?>{};
  final _cacheCursorWithSearch = <String, String?>{};

  // ── Customer Account API GraphQL endpoint ────────────────────────────────
  // Confirmed by browser devtools: Shopify's own account portal uses:
  //   POST https://account.fawaah.com/customer/api/unstable/graphql
  //   Authorization: Bearer shcat_...
  //
  // IMPORTANT: `domain` is the Storefront domain (www.fawaah.com) — the CA API
  // lives on the account subdomain (account.fawaah.com), so we hardcode it.
  // The /.well-known discovery returns '2026-01' which rejects shcat_ tokens.
  // 'unstable' is what Shopify's own JS uses and is the only version that works.
  static const _kCaApiUrl =
      'https://account.fawaah.com/customer/api/unstable/graphql';

  String? _resolvedCustomerAccountApiUrl;

  Future<String> _getCustomerAccountApiUrl() async {
    _resolvedCustomerAccountApiUrl ??= _kCaApiUrl;
    printLog('CA API url: $_resolvedCustomerAccountApiUrl');
    return _resolvedCustomerAccountApiUrl!;
  }

  // ── Client factories ──────────────────────────────────────────────────────

  static GraphQLClient _getStorefrontClient({
    required String accessToken,
    required String domain,
    String? version,
  }) {
    final httpLink = version == null
        ? HttpLink('$domain/api/graphql')
        : HttpLink('$domain/api/$version/graphql.json');
    final authLink = AuthLink(
      headerKey: 'X-Shopify-Storefront-Access-Token',
      getToken: () async => accessToken,
    );
    return GraphQLClient(cache: GraphQLCache(), link: authLink.concat(httpLink));
  }

  Future<GraphQLClient> _customerAccountClient(String token) async {
    final url = await _getCustomerAccountApiUrl();
    final preview = token.substring(0, math.min(30, token.length));
    printLog('CA API client url: $url');
    printLog('CA API token preview: "$preview..."');

    // Shopify CA API expects the raw token with no "Bearer" prefix —
    // confirmed from browser devtools: authorization: shcat_eyJ... (no Bearer).
    final authLink = AuthLink(
      headerKey: 'Authorization',
      getToken: () async => token,   // raw shcat_ token, no "Bearer " prefix
    );
    final httpLink = HttpLink(url);
    return GraphQLClient(
      cache: GraphQLCache(),
      link: authLink.concat(httpLink),
    );
  }

  // ── Token refresh (Customer Account API) ──────────────────────────────────

  /// Returns a valid shcat_ token for [cookie]:
  /// - If [cookie] is not a CA token, returns it unchanged.
  /// - If not expired (per ShopifyTokenStore), returns [cookie] as-is.
  /// - If expired, attempts silent refresh via refresh_token.
  /// - If refresh fails, returns null → caller should trigger re-login.
  /// Called when silent refresh succeeds — update user.cookie in UserModel.
  void Function(String newToken)? onTokenRefreshed;

  /// Called when token is expired AND refresh failed — trigger logout.
  void Function()? onTokenExpired;

  Future<String?> _validCaToken(String cookie) async {
    if (!_isCaToken(cookie)) return cookie;

    // Check if stored token is still valid
    final stored = await ShopifyTokenStore.validAccessToken();
    if (stored != null) return stored;

    // Try to refresh
    printLog('shcat_ token expired — attempting refresh');
    final newToken = await _refreshAccessToken();
    if (newToken != null) {
      printLog('Token refresh succeeded');
      onTokenRefreshed?.call(newToken);
      return newToken;
    }

    // Refresh failed — clear stale tokens and force re-login
    printLog('Token refresh failed — clearing session, forcing re-login');
    await ShopifyTokenStore.clear();
    onTokenExpired?.call();
    return null;
  }

  /// Exchanges the stored refresh_token for a new access_token.
  /// Returns the new shcat_ token on success, or null on failure.
  Future<String?> _refreshAccessToken() async {
    try {
      final storedRefresh = await ShopifyTokenStore.refreshToken();
      if (storedRefresh == null) {
        printLog('_refreshAccessToken: no refresh token stored');
        return null;
      }

      final oidcResponse = await http
          .get(Uri.parse('$domain/.well-known/openid-configuration'))
          .timeout(const Duration(seconds: 5));
      if (oidcResponse.statusCode != 200) return null;

      final oidcConfig = jsonDecode(oidcResponse.body) as Map<String, dynamic>;
      final tokenEndpoint = oidcConfig['token_endpoint'] as String?;
      if (tokenEndpoint == null) return null;

      final response = await http
          .post(
        Uri.parse(tokenEndpoint),
        headers: {'Content-Type': 'application/x-www-form-urlencoded'},
        body: {
          'grant_type':    'refresh_token',
          'refresh_token': storedRefresh,
          'client_id':     _kShopifyClientId,
        },
      )
          .timeout(const Duration(seconds: 10));

      printLog('_refreshAccessToken: status=${response.statusCode}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final newAccess = data['access_token'] as String?;
        if (newAccess != null && newAccess.startsWith('shcat_')) {
          final newRefresh = data['refresh_token'] as String?;
          final expiresIn = (data['expires_in'] as num?)?.toInt() ?? 7200;
          await ShopifyTokenStore.save(
            accessToken: newAccess,
            refreshToken: newRefresh ?? storedRefresh, // keep old if not rotated
            expiresIn: expiresIn,
          );
          return newAccess;
        }
      }
      return null;
    } catch (e) {
      printLog('_refreshAccessToken error: $e');
      return null;
    }
  }

  // ── OTP login (Storefront API) ────────────────────────────────────────────

  @override
  Future<bool?> sendVerificationCode(String email) async {
    try {
      printLog('sendVerificationCode: $email');
      final result = await client.mutate(
        MutationOptions(
          document: gql(ShopifyQuery.sendEmailVerificationCode),
          variables: {'email': email},
        ),
      );
      if (result.hasException) {
        printLog('sendVerificationCode error: ${result.exception}');
        return false;
      }
      final errors = result.data?['customerSendEmailVerificationCode']
      ?['userErrors'] as List?;
      if (errors != null && errors.isNotEmpty) {
        printLog('sendVerificationCode userErrors: ${errors[0]['message']}');
        return false;
      }
      printLog('sendVerificationCode: OTP sent');
      return true;
    } catch (e) {
      printLog('sendVerificationCode exception: $e');
      return false;
    }
  }

  @override
  Future<String?> loginWithCode(String email, String code) async {
    try {
      printLog('loginWithCode: $email');
      final result = await client.mutate(
        MutationOptions(
          document: gql(ShopifyQuery.loginWithCode),
          variables: {'email': email, 'verificationCode': code},
        ),
      );
      if (result.hasException) {
        printLog('loginWithCode error: ${result.exception}');
        return null;
      }
      final errors = result.data?['customerAccessTokenCreateWithCode']
      ?['userErrors'] as List?;
      if (errors != null && errors.isNotEmpty) {
        printLog('loginWithCode userErrors: ${errors[0]['message']}');
        return null;
      }
      final token = result.data?['customerAccessTokenCreateWithCode']
      ?['customerAccessToken']?['accessToken'] as String?;
      printLog(
          'loginWithCode: token=${token?.substring(0, token!.length.clamp(0, 20))}...');
      return token;
    } catch (e) {
      printLog('loginWithCode exception: $e');
      return null;
    }
  }

  // ── Password-based auth (Storefront API) ──────────────────────────────────

  @override
  Future<User> createUser({
    String? firstName,
    String? lastName,
    String? username,
    String? password,
    String? phoneNumber,
    bool isVendor = false,
  }) async {
    try {
      final result = await client.query(QueryOptions(
        document: gql(ShopifyQuery.createCustomer),
        variables: <String, dynamic>{
          'nRepositories': 50,
          'input': {
            'firstName': firstName,
            'lastName': lastName,
            'email': username,
            'password': password,
          },
        },
      ));
      if (result.hasException) throw Exception(result.exception.toString());
      final listError =
      List.from(result.data?['customerCreate']?['userErrors'] ?? []);
      if (listError.isNotEmpty) {
        throw listError.map((e) => e['message']).join(', ');
      }
      final userInfo = result.data!['customerCreate']['customer'];
      final token =
      await createAccessToken(username: username, password: password);
      return User.fromShopifyJson(userInfo, token);
    } catch (e) {
      printLog('createUser error $e');
      rethrow;
    }
  }

  Future<String?> createAccessToken({username, password}) async {
    try {
      final result = await client.query(QueryOptions(
        document: gql(ShopifyQuery.createCustomerToken),
        fetchPolicy: FetchPolicy.networkOnly,
        variables: <String, dynamic>{
          'nRepositories': 50,
          'input': {'email': username, 'password': password},
        },
      ));
      if (result.hasException) throw Exception(result.exception.toString());
      return result.data!['customerAccessTokenCreate']['customerAccessToken']
      ['accessToken'];
    } catch (e) {
      printLog('createAccessToken error $e');
      rethrow;
    }
  }

  @override
  Future<User?> login({username, password}) async {
    try {
      final accessToken =
      await createAccessToken(username: username, password: password);
      return await getUserInfo(accessToken);
    } catch (e) {
      throw Exception(
          'Please check your username or password and try again. If the problem persists, please contact support!');
    }
  }

  // ── Customer Account API token exchange ───────────────────────────────────
  // The OAuth callback delivers a `shcac_` code. This must be exchanged for a
  // proper `shcat_` access token via POST to the token endpoint before any
  // Customer Account API GraphQL calls can be made.

  /// Exchanges a `shcac_` authorization code for a `shcat_` access token.
  /// Returns the `shcat_` token on success, or null on failure.
  /// Exchange an OAuth `shcac_` authorization code (+ PKCE verifier) for a
  /// `shcat_` Customer Account API access token.
  ///
  /// [codeVerifier] must be the exact verifier that was used to compute the
  /// code_challenge when building the authorization URL — without it Shopify
  /// returns 401 "client credentials invalid".
  /// Exchange a `shcac_` authorization code for a `shcat_` access token.
  ///
  /// [sessionCookie] — the value of the `_shopify_essential` cookie captured
  /// from the WebView after the user completes login. Shopify's token endpoint
  /// validates the session server-side, so this cookie must accompany the POST.
  /// Without it the endpoint returns 401 "client credentials invalid".
  Future<String?> exchangeCustomerAccountToken(
      String shcacCode, {String? sessionCookie}) async {
    try {
      final oidcResponse = await http
          .get(Uri.parse('$domain/.well-known/openid-configuration'))
          .timeout(const Duration(seconds: 5));

      if (oidcResponse.statusCode != 200) {
        printLog('CA token exchange: OIDC discovery failed ' + oidcResponse.statusCode.toString());
        return null;
      }

      final oidcConfig = jsonDecode(oidcResponse.body) as Map<String, dynamic>;
      final tokenEndpoint = oidcConfig['token_endpoint'] as String?;
      if (tokenEndpoint == null) {
        printLog('CA token exchange: no token_endpoint in OIDC config');
        return null;
      }
      printLog('CA token exchange: endpoint=' + tokenEndpoint);

      final headers = <String, String>{
        'Content-Type': 'application/x-www-form-urlencoded',
        'Origin': domain,
        'Referer': domain + '/',
      };
      if (sessionCookie != null && sessionCookie.isNotEmpty) {
        headers['Cookie'] = '_shopify_essential=' + sessionCookie;
        printLog('CA token exchange: attaching session cookie (' + sessionCookie.length.toString() + ' chars)');
      } else {
        printLog('CA token exchange: WARNING no session cookie — exchange may fail');
      }

      final response = await http
          .post(
        Uri.parse(tokenEndpoint),
        headers: headers,
        body: {
          'grant_type':   'authorization_code',
          'code':         shcacCode,
          'redirect_uri': _kShopifyRedirectUri,
          'client_id':    _kShopifyClientId,
        },
      )
          .timeout(const Duration(seconds: 10));

      printLog('CA token exchange: status=' + response.statusCode.toString() + ' body=' + response.body);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final accessToken = data['access_token'] as String?;
        if (accessToken != null && accessToken.startsWith('shcat_')) {
          printLog('CA token exchange: SUCCESS ' + accessToken.substring(0, math.min(20, accessToken.length)) + '...');
          // Persist access + refresh tokens for future auto-refresh
          final refreshToken = data['refresh_token'] as String?;
          final expiresIn = (data['expires_in'] as num?)?.toInt() ?? 7200;
          await ShopifyTokenStore.save(
            accessToken: accessToken,
            refreshToken: refreshToken,
            expiresIn: expiresIn,
          );
          printLog('CA token exchange: saved to store, expiresIn=${expiresIn}s, hasRefresh=${refreshToken != null}');
          return accessToken;
        }
        printLog('CA token exchange: unexpected format: ' + (accessToken ?? 'null'));
        return null;
      }

      printLog('CA token exchange: FAILED status=' + response.statusCode.toString() + ' body=' + response.body);
      return null;
    } catch (e) {
      printLog('CA token exchange exception: ' + e.toString());
      return null;
    }
  }

  /// Called from LoginScreen after the OAuth WebView delivers a `shcac_` code.
  /// [sessionCookie] must be the `_shopify_essential` cookie from the WebView.
  Future<User?> loginWithOAuthCode(String shcacCode, {String? sessionCookie}) async {
    final shcatToken = await exchangeCustomerAccountToken(
        shcacCode, sessionCookie: sessionCookie);
    if (shcatToken == null) {
      printLog('loginWithOAuthCode: token exchange failed');
      return null;
    }
    return _getUserInfoCustomerAccount(shcatToken);
  }

  // ── User profile ──────────────────────────────────────────────────────────
  // getUserInfo is called for persisted tokens (shcat_) and password tokens.
  // For the initial OAuth login use loginWithOAuthCode() instead.

  @override
  Future<User?> getUserInfo(cookie) async {
    final token = cookie as String?;
    if (token == null || token.isEmpty) return null;

    printLog('getUserInfo: prefix=' + token.substring(0, math.min(10, token.length)) + ' len=' + token.length.toString());

    if (token.startsWith('shcat_')) {
      return _getUserInfoCustomerAccount(token);
    }

    // Password-based Storefront API token
    return _getUserInfoStorefront(token);
  }

  Future<User?> _getUserInfoCustomerAccount(String rawToken) async {
    try {
      final token = await _validCaToken(rawToken);
      if (token == null) {
        printLog('_getUserInfoCustomerAccount: token expired and refresh failed');
        return null;
      }
      // ── Raw HTTP sanity check ──────────────────────────────────────────────
      // Test the token + endpoint with a plain http.post before using GraphQL.
      // This lets us see the exact response without GraphQL client interference.
      final rawResp = await http.post(
        Uri.parse(_kCaApiUrl),
        headers: {
          'Authorization': token,  // CA API: raw token, no Bearer prefix
          'Content-Type': 'application/json',
        },
        body: '{"query":"{ customer { id emailAddress { emailAddress } firstName lastName } }"}',
      ).timeout(const Duration(seconds: 10));
      printLog('CA raw HTTP status: ' + rawResp.statusCode.toString());
      printLog('CA raw HTTP body: ' + rawResp.body.substring(0, math.min(500, rawResp.body.length)));
      // ── End sanity check ──────────────────────────────────────────────────

      final caClient = await _customerAccountClient(token);
      final result = await caClient.query(
        QueryOptions(
          document: gql(r'''
            query {
              customer {
                id
                emailAddress { emailAddress }
                firstName
                lastName
                displayName
                phoneNumber { phoneNumber }
                defaultAddress {
                  address1 address2 city firstName id lastName zip
                  phoneNumber name province country zoneCode territoryCode
                }
                addresses(first: 10) {
                  edges {
                    node {
                      address1 address2 city firstName id lastName zip
                      phoneNumber name province country zoneCode territoryCode
                    }
                  }
                }
              }
            }
          '''),
          fetchPolicy: FetchPolicy.networkOnly,
        ),
      );

      printLog('CA getUserInfo hasException=${result.hasException}');
      if (result.hasException) {
        printLog('CA getUserInfo exception=${result.exception}');
      }
      printLog('CA getUserInfo data=${result.data}');

      if (result.hasException || result.data?['customer'] == null) {
        printLog('CA getUserInfo failed — customer is null or exception');
        return null;
      }

      final user = _userFromCustomerAccountData(
          result.data!['customer'] as Map<String, dynamic>, token);
      printLog('CA getUserInfo success: ${user.email} / ${user.name}');
      return user;
    } catch (e, s) {
      printLog('CA getUserInfo exception: $e\n$s');
      return null;
    }
  }

  Future<User?> _getUserInfoStorefront(String cookie) async {
    try {
      final result = await client.query(QueryOptions(
        document: gql(ShopifyQuery.getCustomerInfo),
        fetchPolicy: FetchPolicy.networkOnly,
        variables: <String, dynamic>{
          'nRepositories': 50,
          'accessToken': cookie,
        },
      ));
      if (result.hasException) throw Exception(result.exception.toString());
      final user =
      User.fromShopifyJson(result.data?['customer'] ?? {}, cookie);
      return user.cookie == null ? null : user;
    } catch (e) {
      printLog('_getUserInfoStorefront error: $e');
      return null;
    }
  }

  User _userFromCustomerAccountData(Map<String, dynamic> c, String cookie) {
    final emailData = c['emailAddress'];
    final email =
    emailData is Map ? emailData['emailAddress'] as String? : null;
    final phoneData = c['phoneNumber'];
    final phone =
    phoneData is Map ? phoneData['phoneNumber'] as String? : null;

    final addressEdges =
    (c['addresses']?['edges'] as List? ?? []).map((e) {
      return {'node': _normalizeAddress(e['node'] as Map<String, dynamic>)};
    }).toList();

    return User.fromShopifyJson(
      {
        'id': c['id'],
        'email': email,
        'firstName': c['firstName'],
        'lastName': c['lastName'],
        'displayName': c['displayName'],
        'phone': phone,
        'defaultAddress': c['defaultAddress'] != null
            ? _normalizeAddress(c['defaultAddress'] as Map<String, dynamic>)
            : null,
        'addresses': {'edges': addressEdges},
        'createdAt': null,
      },
      cookie,
    );
  }

  Map<String, dynamic> _normalizeAddress(Map<String, dynamic> a) => {
    'id': a['id'],
    'address1': a['address1'],
    'address2': a['address2'],
    'city': a['city'],
    'firstName': a['firstName'],
    'lastName': a['lastName'],
    'zip': a['zip'],
    'phone': a['phoneNumber'] ?? a['phone'],
    'province': a['province'] ?? a['zoneCode'],
    'country': a['country'] ?? a['territoryCode'],
    'name': a['name'],
    'latitude': a['latitude'],
    'longitude': a['longitude'],
    'countryCode': a['territoryCode'] ?? a['countryCode'],
  };

  @override
  Future<User?>? getUserInfoFromNewAPI(accessToken) => getUserInfo(accessToken);

  /// Update profile — Customer Account API, Storefront fallback.
  @override
  Future<Map<String, dynamic>> updateUserInfo(
      Map<String, dynamic> json, String? token)
  async {
    json.removeWhere((key, value) => key == 'deviceToken');
    try {
      final input = <String, dynamic>{};
      if (json['firstName'] != null) input['firstName'] = json['firstName'];
      if (json['lastName'] != null) input['lastName'] = json['lastName'];
      if (json['phone'] != null) {
        input['phoneNumber'] = {'phoneNumber': json['phone']};
      }
      if (json['email'] != null) {
        input['emailAddress'] = {'emailAddress': json['email']};
      }

      final caClient = await _customerAccountClient(token!);
      final result = await caClient.mutate(
        MutationOptions(
          document: gql(r'''
            mutation customerUpdate($input: CustomerUpdateInput!) {
              customerUpdate(input: $input) {
                customer {
                  id
                  emailAddress { emailAddress }
                  firstName lastName displayName
                  phoneNumber { phoneNumber }
                }
                userErrors { field message code }
              }
            }
          '''),
          variables: {'input': input},
        ),
      );
      if (result.hasException) throw Exception(result.exception.toString());
      final errors =
          result.data?['customerUpdate']?['userErrors'] as List? ?? [];
      if (errors.isNotEmpty) throw errors.map((e) => e['message']).join(', ');
      final c = result.data?['customerUpdate']?['customer']
      as Map<String, dynamic>? ??
          {};
      return _userFromCustomerAccountData(c, token).toJson();
    } catch (e) {
      printLog('updateUserInfo CA error: $e — trying Storefront fallback');
      final options = QueryOptions(
        document: gql(ShopifyQuery.customerUpdate),
        fetchPolicy: FetchPolicy.networkOnly,
        variables: <String, dynamic>{
          'nRepositories': 50,
          'customerAccessToken': token,
          'customer': json,
        },
      );
      final result = await client.query(options);
      if (result.hasException) throw Exception(result.exception.toString());
      final userData = result.data?['customerUpdate']['customer'];
      final newToken = result.data?['customerUpdate']['customerAccessToken']
      ?['accessToken'];
      return User.fromShopifyJson(userData, newToken).toJson();
    }
  }

  // ── Orders (Customer Account API) ─────────────────────────────────────────

  @override
  Future<PagingResponse<Order>> getMyOrders({
    User? user,
    dynamic cursor,
    String? cartId,
  }) async {
    try {
      final rawToken = user?.cookie;
      if (rawToken == null || rawToken.isEmpty) return const PagingResponse();

      final token = await _validCaToken(rawToken);
      if (token == null) {
        printLog('getMyOrders: token expired and refresh failed — re-login required');
        return const PagingResponse();
      }

      final caClient = await _customerAccountClient(token);
      final result = await caClient.query(
        QueryOptions(
          document: gql(r'''
            query Orders($first: Int, $after: String) {
              customer {
                orders(first: $first, after: $after, sortKey: PROCESSED_AT, reverse: true) {
                  nodes {
                    id
                    name
                    confirmationNumber
                    customerFulfillmentStatus
                    totalPrice { amount currencyCode }
                    processedAt
                    cancelledAt
                    paymentInformation { paymentStatus }
                    lineItems: lineItemContainers {
                      ... on RemainingLineItemContainer {
                        id
                        lineItems(first: 50) {
                          nodes {
                            id
                            lineItem {
                              id name quantity
                              image {
                                altText
                                thumbnail: url(transform: { maxWidth: 400, maxHeight: 400 })
                              }
                            }
                          }
                        }
                      }
                    }
                  }
                  pageInfo { hasNextPage endCursor }
                }
              }
            }
          '''),
          fetchPolicy: FetchPolicy.noCache,
          variables: <String, dynamic>{
            'first': 50,
            if (cursor != null) 'after': cursor,
          },
        ),
      );

      if (result.hasException) {
        printLog('getMyOrders exception: ${result.exception}');
        return const PagingResponse();
      }

      final customerData = result.data?['customer'];
      if (customerData == null) {
        printLog('getMyOrders: customer null — token expired?');
        return const PagingResponse();
      }

      final nodes = customerData['orders']?['nodes'] as List? ?? [];
      printLog('getMyOrders: ${nodes.length} orders');

      final list = nodes.map((n) {
        final converted =
        _convertCustomerAccountOrder(n as Map<String, dynamic>);
        return converted.isNotEmpty ? Order.fromJson(converted) : null;
      }).whereType<Order>().toList();

      return PagingResponse(
        cursor: customerData['orders']?['pageInfo']?['endCursor'] as String?,
        data: list,
      );
    } catch (e, s) {
      printLog('getMyOrders error: $e\n$s');
      return const PagingResponse();
    }
  }

  @override
  Future<Order?> getLatestOrder({required String cookie}) async {
    try {
      final token = await _validCaToken(cookie);
      if (token == null) {
        printLog('getLatestOrder: token expired and refresh failed');
        return null;
      }
      final caClient = await _customerAccountClient(token);
      final result = await caClient.query(
        QueryOptions(
          document: gql(r'''
            query {
              customer {
                orders(first: 1, sortKey: PROCESSED_AT, reverse: true) {
                  nodes {
                    id
                    name
                    confirmationNumber
                    customerFulfillmentStatus
                    totalPrice { amount currencyCode }
                    processedAt
                    cancelledAt
                    paymentInformation { paymentStatus }
                    lineItems: lineItemContainers {
                      ... on RemainingLineItemContainer {
                        id
                        lineItems(first: 50) {
                          nodes {
                            id
                            lineItem {
                              id name quantity
                              image {
                                altText
                                thumbnail: url(transform: { maxWidth: 400, maxHeight: 400 })
                              }
                            }
                          }
                        }
                      }
                    }
                  }
                }
              }
            }
          '''),
          fetchPolicy: FetchPolicy.noCache,
        ),
      );
      if (result.hasException) return null;
      final nodes = result.data?['customer']?['orders']?['nodes'] as List?;
      if (nodes == null || nodes.isEmpty) return null;
      final converted =
      _convertCustomerAccountOrder(nodes.first as Map<String, dynamic>);
      return converted.isNotEmpty ? Order.fromJson(converted) : null;
    } catch (e) {
      printLog('getLatestOrder error: $e');
      return null;
    }
  }

  /// Fetch a single order by its GID (e.g. "gid://shopify/Order/123456789")
  /// Called by the order-detail screen — mirrors the browser's `OrderDetails` operation.
  @override
  Future<Order?> getOrderById({
    required String id,
    String? cookie,
  }) async {
    try {
      final rawToken = cookie;
      if (rawToken == null || rawToken.isEmpty) return null;

      final token = await _validCaToken(rawToken);
      if (token == null) {
        printLog('getOrderById: token expired and refresh failed');
        return null;
      }

      final caClient = await _customerAccountClient(token);
      final result = await caClient.query(
        QueryOptions(
          document: gql(r'''
            query OrderDetails($id: ID!) {
              order(id: $id) {
                id
                name
                confirmationNumber
                customerFulfillmentStatus
                totalPrice { amount currencyCode }
                totalShippingPrice { amount currencyCode }
                totalTax { amount currencyCode }
                subtotalPrice { amount currencyCode }
                processedAt
                cancelledAt
                paymentInformation { paymentStatus }
                shippingAddress {
                  firstName
                  lastName
                  address1
                  address2
                  city
                  province
                  zip
                  country
                  phone
                }
                lineItems: lineItemContainers {
                  ... on RemainingLineItemContainer {
                    id
                    lineItems(first: 50) {
                      nodes {
                        id
                        lineItem {
                          id name quantity
                          price { amount currencyCode }
                          image {
                            altText
                            thumbnail: url(transform: { maxWidth: 400, maxHeight: 400 })
                          }
                        }
                      }
                    }
                  }
                }
              }
            }
          '''),
          variables: {'id': id},
          fetchPolicy: FetchPolicy.noCache,
        ),
      );

      if (result.hasException) {
        printLog('getOrderById exception: ${result.exception}');
        return null;
      }

      final node = result.data?['order'] as Map<String, dynamic>?;
      if (node == null) return null;

      final converted = _convertCustomerAccountOrderDetail(node);
      return converted.isNotEmpty ? Order.fromJson(converted) : null;
    } catch (e, s) {
      printLog('getOrderById error: $e\n$s');
      return null;
    }
  }

  /// Like [_convertCustomerAccountOrder] but also maps shipping address,
  /// per-item price, and the extra totals returned by the OrderDetails query.
  Map<String, dynamic> _convertCustomerAccountOrderDetail(
      Map<String, dynamic> node) {
    try {
      final currencyCode =
          node['totalPrice']?['currencyCode'] as String? ?? '';
      final totalAmount = (node['totalPrice']?['amount'] ?? '0').toString();
      final totalShipping =
      (node['totalShippingPrice']?['amount'] ?? '0').toString();
      final totalTax = (node['totalTax']?['amount'] ?? '0').toString();
      final subtotal = (node['subtotalPrice']?['amount'] ?? '0').toString();

      // Build line-item edges from lineItemContainers
      final containers = node['lineItems'] as List? ?? [];
      final List<Map<String, dynamic>> convertedEdges = [];

      for (final container in containers) {
        if (container is! Map) continue;
        final containerLineItems = container['lineItems'];
        if (containerLineItems == null) continue;
        final containerNodes = containerLineItems['nodes'] as List? ?? [];
        for (final wrapper in containerNodes) {
          final lineItem = wrapper['lineItem'] as Map<String, dynamic>?;
          if (lineItem == null) continue;
          final image = lineItem['image'] as Map<String, dynamic>?;
          final itemPrice =
          (lineItem['price']?['amount'] ?? '0.00').toString();
          convertedEdges.add({
            'node': {
              'id': lineItem['id'],
              'title': lineItem['name'],
              'quantity': lineItem['quantity'] ?? 1,
              'cost': {
                'totalAmount': {'amount': itemPrice, 'currencyCode': currencyCode}
              },
              'variant': {
                'id': '',
                'title': lineItem['name'] ?? '',
                'image': image != null
                    ? {'altText': image['altText'], 'url': image['thumbnail']}
                    : null,
                'price': {'amount': itemPrice, 'currencyCode': currencyCode},
                'selectedOptions': [],
                'product': null,
              },
            }
          });
        }
      }

      // Status
      final paymentStatus =
      node['paymentInformation']?['paymentStatus'] as String?;
      final fulfillmentStatus =
      node['customerFulfillmentStatus'] as String?;
      final financialStatus = (paymentStatus?.isNotEmpty ?? false)
          ? paymentStatus!
          : _convertFulfillmentStatus(fulfillmentStatus);

      // Shipping address — CA API returns it directly on the order
      final addr = node['shippingAddress'] as Map<String, dynamic>?;

      return {
        'id': node['id'],
        'orderNumber': (node['name'] as String?)?.replaceAll('#', '') ?? '',
        'financialStatus': financialStatus,
        'currencyCode': currencyCode,
        'processedAt': node['processedAt'],
        'totalPrice': {'amount': totalAmount},
        'totalShippingPrice': {'amount': totalShipping},
        'totalTax': {'amount': totalTax},
        'subtotalPrice': {'amount': subtotal},
        'lineItems': {'edges': convertedEdges},
        'shippingAddress': addr != null
            ? {
          'firstName': addr['firstName'] ?? '',
          'lastName': addr['lastName'] ?? '',
          'address1': addr['address1'] ?? '',
          'address2': addr['address2'] ?? '',
          'city': addr['city'] ?? '',
          'province': addr['province'] ?? '',
          'zip': addr['zip'] ?? '',
          'country': addr['country'] ?? '',
          'phone': addr['phone'] ?? '',
        }
            : null,
        'statusUrl': '',
      };
    } catch (e) {
      printLog('_convertCustomerAccountOrderDetail error: $e');
      return {};
    }
  }

  Map<String, dynamic> _convertCustomerAccountOrder(
      Map<String, dynamic> node) {
    try {
      final currencyCode =
          node['totalPrice']?['currencyCode'] as String? ?? '';
      final totalAmount =
      (node['totalPrice']?['amount'] ?? '0').toString();

      // lineItems is lineItemContainers — an array of container types.
      // We only care about RemainingLineItemContainer entries (have 'lineItems').
      final containers = node['lineItems'] as List? ?? [];
      final List<Map<String, dynamic>> convertedEdges = [];

      for (final container in containers) {
        if (container is! Map) continue;
        final containerLineItems = container['lineItems'];
        if (containerLineItems == null) continue; // not RemainingLineItemContainer
        final containerNodes = containerLineItems['nodes'] as List? ?? [];
        for (final wrapper in containerNodes) {
          final lineItem = wrapper['lineItem'] as Map<String, dynamic>?;
          if (lineItem == null) continue;
          final image = lineItem['image'] as Map<String, dynamic>?;
          convertedEdges.add({
            'node': {
              'id': lineItem['id'],
              'title': lineItem['name'],
              'quantity': lineItem['quantity'] ?? 1,
              'cost': {
                'totalAmount': {'amount': '0.00', 'currencyCode': currencyCode}
              },
              'variant': {
                'id': '',
                'title': lineItem['name'] ?? '',
                'image': image != null
                    ? {'altText': image['altText'], 'url': image['thumbnail']}
                    : null,
                'price': {'amount': '0.00', 'currencyCode': currencyCode},
                'selectedOptions': [],
                'product': null,
              },
            }
          });
        }
      }

      // paymentStatus from paymentInformation, fall back to fulfillment status
      final paymentStatus =
      node['paymentInformation']?['paymentStatus'] as String?;
      final fulfillmentStatus =
      node['customerFulfillmentStatus'] as String?;
      final financialStatus = (paymentStatus?.isNotEmpty ?? false)
          ? paymentStatus!
          : _convertFulfillmentStatus(fulfillmentStatus);

      return {
        'id': node['id'],
        'orderNumber': (node['name'] as String?)?.replaceAll('#', '') ?? '',
        'financialStatus': financialStatus,
        'currencyCode': currencyCode,
        'processedAt': node['processedAt'],
        'totalPrice': {'amount': totalAmount},
        'totalShippingPrice': {'amount': '0.00'},
        'totalTax': {'amount': '0.00'},
        'subtotalPrice': {'amount': totalAmount},
        'lineItems': {'edges': convertedEdges},
        'shippingAddress': null,
        'statusUrl': '',
      };
    } catch (e) {
      printLog('_convertCustomerAccountOrder error: $e');
      return {};
    }
  }

  String _convertFulfillmentStatus(String? status) {
    switch (status?.toUpperCase()) {
      case 'FULFILLED':
        return 'PAID';
      case 'PARTIALLY_FULFILLED':
        return 'PARTIALLY_PAID';
      case 'UNFULFILLED':
        return 'PENDING';
      case 'CANCELLED':
        return 'VOIDED';
      case 'RESTOCKED':
        return 'REFUNDED';
      default:
        return 'PENDING';
    }
  }

  // ── Logout ────────────────────────────────────────────────────────────────

  @override
  Future logout(String? token) async {
    // Always clear the persisted token store on logout
    await ShopifyTokenStore.clear();
    if (token == null) return;
    // shcat_ = proper CA API access token — revoke via end_session
    // shcac_ = raw OAuth code, was never exchanged — nothing to revoke
    // anything else = Storefront password token
    if (token.startsWith('shcat_')) {
      await _logoutCustomerAccountToken(token);
    } else if (!token.startsWith('shcac_')) {
      await _logoutStorefrontToken(token);
    }
  }

  Future<void> _logoutCustomerAccountToken(String token) async {
    try {
      final response = await http
          .get(Uri.parse('$domain/.well-known/openid-configuration'))
          .timeout(const Duration(seconds: 5));
      if (response.statusCode == 200) {
        final config = jsonDecode(response.body) as Map<String, dynamic>;
        final endSessionEndpoint = config['end_session_endpoint'] as String?;
        if (endSessionEndpoint != null) {
          await http
              .post(
            Uri.parse(endSessionEndpoint),
            headers: {
              'Content-Type': 'application/x-www-form-urlencoded'
            },
            body: {'id_token_hint': token},
          )
              .timeout(const Duration(seconds: 5));
          printLog('CA logout: end_session called');
          return;
        }
      }
    } catch (e) {
      printLog('CA logout error (non-fatal): $e');
    }
  }

  Future<void> _logoutStorefrontToken(String token) async {
    try {
      await client.mutate(
        MutationOptions(
          document: gql(ShopifyQuery.deleteToken),
          variables: {'customerAccessToken': token},
        ),
      );
    } catch (e) {
      printLog('Storefront logout error (non-fatal): $e');
    }
  }

  // ── Password reset (Storefront API) ───────────────────────────────────────

  @override
  Future<String> submitForgotPassword({
    String? forgotPwLink,
    Map<String, dynamic>? data,
  }) async {
    final result = await client.mutate(MutationOptions(
      document: gql(ShopifyQuery.resetPassword),
      variables: {'email': data!['email']},
    ));
    if (result.hasException) {
      throw result.exception?.graphqlErrors.firstOrNull?.message ??
          S.current.somethingWrong;
    }
    final errors =
    result.data!['customerRecover']['customerUserErrors'] as List?;
    if (errors?.isNotEmpty ?? false) {
      if (errors!.any((e) => e['code'] == 'UNIDENTIFIED_CUSTOMER')) {
        throw Exception('UNIDENTIFIED_CUSTOMER');
      }
    }
    return '';
  }

  // ── Categories (Storefront API) ───────────────────────────────────────────

  Future<List<Category>> getCategoriesByCursor({
    List<Category>? categories,
    String? cursor,
    langCode,
  }) async {
    try {
      var variables = <String, dynamic>{
        'nRepositories': 50,
        'pageSize': 250,
        'langCode': langCode?.toString().toUpperCase(),
        'countryCode': countryCode?.toString().toUpperCase(),
      };
      if (cursor != null) variables['cursor'] = cursor;

      final result = await client.query(QueryOptions(
        fetchPolicy: FetchPolicy.networkOnly,
        document: gql(ShopifyQuery.getCollections),
        variables: variables,
      ));
      if (result.hasException) printLog(result.exception.toString());

      final list = categories ?? <Category>[];
      for (var item in result.data!['collections']['edges']) {
        list.add(Category.fromJsonShopify(item['node']));
      }

      if (result.data?['collections']?['pageInfo']?['hasNextPage'] ?? false) {
        final lastCursor =
        result.data!['collections']['edges'].last['cursor'] as String?;
        if (lastCursor != null) {
          return getCategoriesByCursor(
              categories: list, cursor: lastCursor, langCode: langCode);
        }
      }
      return list;
    } catch (e) {
      return categories ?? [];
    }
  }

  @override
  Future<List<Category>> getCategories({lang}) async {
    try {
      return await getCategoriesByCursor(langCode: lang);
    } catch (e) {
      printLog('getCategories error $e');
      rethrow;
    }
  }

  @override
  Future<PagingResponse<Category>> getSubCategories({
    String? langCode,
    dynamic page,
    int limit = 25,
    required String? parentId,
  }) async {
    try {
      final result = await client.query(QueryOptions(
        document: gql(ShopifyQuery.getCollections),
        variables: <String, dynamic>{
          'nRepositories': 50,
          'pageSize': limit,
          if (page != null) 'cursor': page,
        },
      ));
      if (result.hasException) printLog(result.exception.toString());
      final list = <Category>[];
      String? lastCursor;
      for (var item in result.data!['collections']['edges']) {
        lastCursor = item['cursor'] as String?;
        list.add(Category.fromJsonShopify(item['node']));
      }
      return PagingResponse(data: list, cursor: lastCursor);
    } catch (e) {
      return const PagingResponse(data: <Category>[]);
    }
  }

  // ── Products (Storefront API) ─────────────────────────────────────────────

  Future<List<Product>?> fetchProducts({
    String? lang,
    int page = 1,
    int? limit,
    String? order,
    String? orderBy,
  }) async {
    final sortKey = getProductSortKey(orderBy);
    final reverse = getOrderDirection(order);
    try {
      final variables = <String, dynamic>{
        'nRepositories': 50,
        'pageSize': limit ?? apiPageSize,
        'sortKey': sortKey,
        'reverse': reverse,
        'langCode': lang?.toString().toUpperCase(),
        'countryCode': countryCode,
      };
      final markCategory = variables.toString();
      if (page == 1) _cacheCursorWithCategories[markCategory] = null;
      final currentCursor = _cacheCursorWithCategories[markCategory];
      if (currentCursor?.isNotEmpty ?? false) {
        variables['cursor'] = currentCursor;
      }

      final result = await client.query(QueryOptions(
        document: gql(ShopifyQuery.getProducts),
        fetchPolicy: FetchPolicy.networkOnly,
        variables: variables,
      ));
      if (result.hasException) throw result.exception.toString();

      final list = <Product>[];
      final edges = result.data?['products']?['edges'];
      if (edges is List && edges.isNotEmpty) {
        _cacheCursorWithCategories[markCategory] = edges.last['cursor'];
        for (var item in edges) {
          final product = item['node'];
          if (kAdvanceConfig.hideOutOfStock &&
              product['availableForSale'] == false) continue;
          list.add(Product.fromShopify(product));
        }
      }
      return list;
    } catch (e) {
      printError('fetchProducts error $e');
      rethrow;
    }
  }

  @override
  Future<PagingResponse<Product>> getProductsByCategoryId(
      String categoryId, {
        String? langCode,
        dynamic page,
        int limit = 25,
        String? orderBy,
        String? order,
      }) async {
    try {
      final result = await client.query(QueryOptions(
        document: gql(ShopifyQuery.getProductByCollection),
        fetchPolicy: FetchPolicy.networkOnly,
        variables: <String, dynamic>{
          'nRepositories': 50,
          'categoryId': categoryId.toString(),
          'pageSize': limit,
          'query': '',
          'sortKey': getProductCollectionSortKey(orderBy),
          'reverse': getOrderDirection(order),
          'cursor': (page != null && page != '') ? page : null,
          'langCode': languageCode,
          'countryCode': countryCode,
        },
      ));
      if (result.hasException) printLog(result.exception.toString());

      final list = <Product>[];
      String lastCursor = '';
      final node = result.data?['node'];
      if (node != null) {
        final edges = node['products']['edges'];
        if (edges.isNotEmpty) lastCursor = edges.last['cursor'];
        for (var item in edges) {
          final product = item['node'];
          product['categoryId'] = categoryId;
          if (kAdvanceConfig.hideOutOfStock &&
              product['availableForSale'] == false) continue;
          list.add(Product.fromShopify(product));
        }
      }
      return PagingResponse(data: list, cursor: lastCursor);
    } catch (e) {
      return const PagingResponse(data: []);
    }
  }

  @override
  Future<List<Product>?> fetchProductsLayout({
    required config,
    lang,
    ProductModel? productModel,
    userId,
    bool refreshCache = false,
  }) async {
    try {
      if (config['layout'] == 'imageBanner' ||
          config['layout'] == 'circleCategory') return <Product>[];
      return await fetchProductsByCategory(
        categoryId: config['category'],
        orderBy: config['orderby'].toString(),
        productModel: productModel,
        lang: lang,
        page: config.containsKey('page') ? config['page'] : 1,
        limit: config['limit'],
      );
    } catch (e) {
      printLog('fetchProductsLayout error $e');
      return null;
    }
  }

  String getProductCollectionSortKey(orderBy) {
    if (orderBy == 'price') return 'PRICE';
    if (orderBy == 'date') return 'CREATED';
    if (orderBy == 'title') return 'TITLE';
    return 'COLLECTION_DEFAULT';
  }

  String getProductSortKey(orderBy) {
    if (orderBy == 'price') return 'PRICE';
    if (orderBy == 'date') return 'UPDATED_AT';
    if (orderBy == 'title') return 'TITLE';
    return 'RELEVANCE';
  }

  @override
  bool getOrderDirection(order) => order == 'desc';

  @override
  Future<List<Product>?> fetchProductsByCategory({
    categoryId,
    tagId,
    page = 1,
    minPrice,
    maxPrice,
    orderBy,
    lang,
    order,
    attribute,
    attributeTerm,
    featured,
    onSale,
    ProductModel? productModel,
    listingLocation,
    userId,
    nextCursor,
    String? include,
    String? search,
    bool? productType,
    limit,
  }) async {
    print('tagiidd/d${tagId}');
    if (categoryId is String? && (categoryId?.isEmpty ?? true&&tagId==null)) {
      return fetchProducts(
        orderBy: orderBy,
        lang: lang,

        page: page,
        limit: limit,
        order: order,
      );
    }

    print('tagIdssss${tagId}');
////
    if (tagId != null) {
      search = (search?.isNotEmpty ?? false)
          ? '$search AND tag:$tagId'
          : 'tag:$tagId';
    }

    if (search == null && categoryId == null) return <Product>[];

    try {
      if (page == 1) {
        _cacheCursorWithCategories['$categoryId'] = null;
        _cacheCursorWithSearch['$search'] = null;
      }

      // Route to Searchanise for text/tag search or empty category
      if ((search != null && search.isNotEmpty) ||
          categoryId == kEmptyCategoryID) {
        final currentCursor = _cacheCursorWithSearch['$search'];
        final result = await searchProducts(
          name: search,
          page: currentCursor,
          sortKey: orderBy,
          reverse: getOrderDirection(order),
        );
        print('asdsadsxxxxx${search}');
        _cacheCursorWithSearch['$search'] = result.cursor;
        return result.data;
      }

      // Route to Shopify collection query
      final currentCursor = _cacheCursorWithCategories['$categoryId'];
      final result = await client.query(QueryOptions(
        document: gql(ShopifyQuery.getProductByCollection),
        fetchPolicy: FetchPolicy.networkOnly,
        variables: <String, dynamic>{
          'categoryId': categoryId,
          'pageSize': limit ?? apiPageSize,
          'sortKey': getProductCollectionSortKey(orderBy),
          'reverse': getOrderDirection(order),
          'langCode': languageCode,
          'countryCode': countryCode,
          'cursor': (currentCursor?.isNotEmpty ?? false) ? currentCursor : null,
        },
      ));

      if (result.hasException) throw result.exception.toString();

      final list = <Product>[];
      final node = result.data?['node'];

      if (node != null) {
        final edges = node['products']['edges'] as List;
        if (edges.isNotEmpty) {
          _cacheCursorWithCategories['$categoryId'] = edges.last['cursor'];
        }
        for (final item in edges) {
          final product = item['node'] as Map<String, dynamic>;
          product['categoryId'] = categoryId;
          if (kAdvanceConfig.hideOutOfStock &&
              product['availableForSale'] == false) continue;
          list.add(Product.fromShopify(product));
        }
      }

      if (maxPrice != null && minPrice != null) {
        return list
            .where((p) {
          final price = double.tryParse(p.price ?? '') ?? 0.0;
          return price >= minPrice && price <= maxPrice;
        })
            .toList()
          ..sort((a, b) {
            final aPrice = double.tryParse(a.price ?? '') ?? 0.0;
            final bPrice = double.tryParse(b.price ?? '') ?? 0.0;
            return aPrice.compareTo(bPrice);
          });
      }

      return list;
    } catch (e) {
      printError('fetchProductsByCategory error: $e');
      rethrow;
    }
  }

  @override
  Future<PagingResponse<Product>> searchProducts({
    name,
    categoryId = '',
    categoryName = '',
    tag = '',
    attribute = '',
    attributeId = '',
    page,
    lang,
    listingLocation,
    userId,
    String? sortKey,
    bool reverse = false,
  }) async {
    try {
      final result = await client.query(QueryOptions(
        document: gql(ShopifyQuery.getProductByName),
        variables: <String, dynamic>{
          'nRepositories': 50,
          'query': '$name $categoryName',
          if (page != null) 'cursor': page,
          'pageSize': 25,
          'sortKey': getProductSortKey(sortKey),
          'reverse': reverse,
          'langCode': lang?.toString().toUpperCase(),
        },
      ));
      if (result.hasException) throw result.exception.toString();
      final list = <Product>[];
      String? lastCursor;
      for (var item in result.data?['products']['edges']) {
        lastCursor = item['cursor'];
        if (kAdvanceConfig.hideOutOfStock &&
            item['node']?['availableForSale'] == false) continue;
        list.add(Product.fromShopify(item['node']));
      }
      return PagingResponse(data: list, cursor: lastCursor);
    } catch (e) {
      printLog('searchProducts error $e');
      rethrow;
    }
  }

  @override
  Future<PagingResponse<Product>> searchProductsSearchanise({
    name,
    categoryId = '',
    categoryName = '',
    tag = '',
    attribute = '',
    attributeId = '',
    page,
    listingLocation,
    userId,
    String? sortKey,
    bool reverse = false,
  }) async {
    try {
      final dio = Dio(BaseOptions(
        baseUrl: 'https://searchserverapi.com',
        headers: {'Content-Type': 'application/json'},
      ));
      final result = await dio.get('/search', queryParameters: {
        'api_key': '9D0C1B6f1s',
        'q': name,
        'maxResults': 10,
        'startIndex': page == null ? 0 : int.parse(page),
        'items': true,
        'pages': false,
        'facets': false,
        'categories': false,
        'suggestions': false,
        'vendors': false,
        'tags': false,
        'pageStartIndex': 0,
        'pagesMaxResults': 0,
        'categoryStartIndex': 0,
        'categoriesMaxResults': 0,
        'suggestionsMaxResults': 0,
        'output': 'jsonp',
      });
      final dataMap = Map<String, dynamic>.from(jsonDecode(result.data));
      final items = dataMap['items'];
      final list = await Future.wait<Product>(
        (items as List)
            .map<Future<Product>>((item) => getProduct(item['product_id'])),
      );
      final cursor = page == null ? 1 : int.parse(page) + 1;
      return PagingResponse(data: list, cursor: '$cursor');
    } catch (e) {
      printLog('searchProductsSearchanise error $e');
      rethrow;
    }
  }

  @override
  Future<Product> getProduct(id, {lang, cursor}) async {
    if (int.tryParse(id) == null) return getProductByPrivateId(id);
    final result = await client.query(QueryOptions(
      document: gql(ShopifyQuery.getProductById),
      variables: <String, dynamic>{
        'nRepositories': 50,
        'id': id,
        'langCode': languageCode,
        'countryCode': countryCode,
      },
    ));
    if (result.hasException) printLog(result.exception.toString());
    final listData = result.data?['products']?['edges'] as List?;
    if (listData != null && listData.isNotEmpty) {
      return Product.fromShopify(listData.first['node']);
    }
    return Product();
  }

  Future<Product> getProductByPrivateId(id) async {
    final result = await client.query(QueryOptions(
      document: gql(ShopifyQuery.getProductByPrivateId),
      fetchPolicy: FetchPolicy.networkOnly,
      variables: <String, dynamic>{
        'nRepositories': 50,
        'id': id,
        'langCode': languageCode,
        'countryCode': countryCode,
      },
    ));
    if (result.hasException) printLog(result.exception.toString());
    return Product.fromShopify(result.data!['node']);
  }

  @override
  Future<Product?> getProductByPermalink(String productPermalink) async {
    final handle =
    productPermalink.substring(productPermalink.lastIndexOf('/') + 1);
    final result = await client.query(QueryOptions(
      document: gql(ShopifyQuery.getProductByHandle),
      variables: <String, dynamic>{
        'nRepositories': 50,
        'handle': handle,
        'langCode': languageCode,
      },
    ));
    if (result.hasException) printLog(result.exception.toString());
    return Product.fromShopify(result.data?['product']);
  }

  @override
  Future<List<ProductVariation>?> getProductVariations(Product product,
      {String? lang = 'en'}) async {
    try {
      return product.variations;
    } catch (e) {
      rethrow;
    }
  }

  @override
  Future<ProductVariation?> getVariationProduct(
      String productId, String? variationId,
      {String? lang}) async {
    if (variationId == null) return null;
    try {
      final result = await client.mutate(MutationOptions(
        document: gql(ShopifyQuery.getProductVariant),
        fetchPolicy: FetchPolicy.noCache,
        variables: <String, dynamic>{
          'id': variationId,
          'langCode': languageCode,
          'countryCode': countryCode,
        },
      ));
      if (result.hasException) printLog(result.exception.toString());
      return ProductVariation.fromShopifyJson(result.data!['node']);
    } catch (e) {
      return null;
    }
  }

  // ── Tags (Storefront API) ─────────────────────────────────────────────────

  @override
  Future<List<FilterTag>>? getFilterTags({String? lang}) async {
    try {
      final result = await client.query(QueryOptions(
        document: gql(ShopifyQuery.getallTags),
        variables: <String, dynamic>{
          'nRepositories': 50,
          'langCode': lang?.toString().toUpperCase() ?? 'AR',
        },
      ));
      if (result.hasException) return [];
      final edges = result.data?['productTags']?['edges'];
      if (edges == null || edges is! List) return [];
      return edges
          .map<FilterTag?>((item) {
        final node = item['node'];
        if (node == null) return null;
        return FilterTag.fromJson({'name': node});
      })
          .whereType<FilterTag>()
          .toList();
    } catch (e) {
      return [];
    }
  }

  // ── Cart / Checkout (Storefront API) ──────────────────────────────────────

  /// Whether [token] is a Customer Account API token (shcat_)
  /// vs a legacy Storefront customer access token.
  bool _isCaToken(String? token) => token?.startsWith('shcat_') ?? false;

  @override
  Future<CheckoutCart> addItemsToCart(covariant CartModelShopify cartModel) async {
    print('addItemsToCart: existingCartId=${cartModel.checkout?.id}');

    final cookie = cartModel.user?.cookie;
    if (cookie == null) throw Exception('User not authenticated');


    try {
      final lineItems = <Map<String, dynamic>>[];
      for (final entry in cartModel.productVariationInCart.entries) {
        final variant = entry.value;
        final quantity = cartModel.productsInCart[entry.key] ?? 1;
        if (variant == null || (variant.id?.isEmpty ?? true)) continue;
        final rawId = variant.id!;
        final merchandiseId = rawId.startsWith('gid://shopify/ProductVariant/')
            ? rawId
            : 'gid://shopify/ProductVariant/$rawId';
        lineItems.add({'merchandiseId': merchandiseId, 'quantity': quantity});
      }
      if (lineItems.isEmpty) throw Exception('No valid line items');

      final existingCartId = cartModel.checkout?.id;
      final isExistingCart = existingCartId != null &&
          existingCartId.toString().startsWith('gid://shopify/Cart/');

      Map<String, dynamic>? cartData;

      if (isExistingCart) {
        // ── Update existing cart ──────────────────────────────────────────
        printLog('addItemsToCart: updating existing cart $existingCartId');

        // Get current line items from cart to decide add vs update
        final cartResult = await client.query(QueryOptions(
          document: gql(ShopifyQuery.getCart),
          fetchPolicy: FetchPolicy.noCache,
          variables: {
            'cartId': existingCartId,
            'country': countryCode,
            'language': languageCode,
          },
        ));

        final existingLines =
        (cartResult.data?['cart']?['lines']?['edges'] as List? ?? []);

        // Build a map of merchandiseId → existing line node id + quantity
        final existingLineMap = <String, Map<String, dynamic>>{};
        for (final edge in existingLines) {
          final node = edge['node'] as Map<String, dynamic>?;
          if (node == null) continue;
          final merchId =
          node['merchandise']?['id'] as String?;
          if (merchId != null) {
            existingLineMap[merchId] = {
              'id': node['id'],
              'quantity': node['quantity'] ?? 0,
            };
          }
        }

        // Split into lines to add vs lines to update
        final linesToAdd = <Map<String, dynamic>>[];
        final linesToUpdate = <Map<String, dynamic>>[];

        for (final line in lineItems) {
          final merchId = line['merchandiseId'] as String;
          final qty = line['quantity'] as int;
          if (existingLineMap.containsKey(merchId)) {
            linesToUpdate.add({
              'id': existingLineMap[merchId]!['id'],
              'quantity': qty,
            });
          } else {
            linesToAdd.add(line);
          }
        }

        // Apply updates
        if (linesToUpdate.isNotEmpty) {
          final updateResult = await client.mutate(MutationOptions(
            document: gql(ShopifyQuery.cartLinesUpdate),
            variables: {
              'cartId': existingCartId,
              'lines': linesToUpdate,
              'country': countryCode,
              'language': languageCode,
            },
          ));
          if (!updateResult.hasException) {
            cartData = Map<String, dynamic>.from(
                updateResult.data?['cartLinesUpdate']?['cart'] ?? {});
          }
        }

        // Apply additions
        if (linesToAdd.isNotEmpty) {
          final addResult = await client.mutate(MutationOptions(
            document: gql(ShopifyQuery.cartLinesAdd),
            variables: {
              'cartId': existingCartId,
              'lines': linesToAdd,
              'country': countryCode,
              'language': languageCode,
            },
          ));
          if (!addResult.hasException) {
            cartData = Map<String, dynamic>.from(
                addResult.data?['cartLinesAdd']?['cart'] ?? {});
          }
        }

        // If neither ran (no changes), fetch current cart state
        cartData ??= Map<String, dynamic>.from(
            cartResult.data?['cart'] as Map<String, dynamic>? ?? {});

      } else {
        // ── Create new cart ───────────────────────────────────────────────
        printLog('addItemsToCart: creating new cart');

        final createResult = await client.mutate(MutationOptions(
          document: gql(ShopifyQuery.cartCreate),
          variables: {
            'lines': lineItems,
            'country': countryCode,
            'language': languageCode,
            'buyerIdentity': null,
          },
        ));

        if (createResult.hasException) {
          throw Exception(createResult.exception.toString());
        }
        final userErrors =
            createResult.data?['cartCreate']?['userErrors'] as List? ?? [];
        if (userErrors.isNotEmpty) {
          throw Exception(
              userErrors.map((e) => '${e['code']}: ${e['message']}').join(', '));
        }

        cartData = Map<String, dynamic>.from(
            createResult.data?['cartCreate']?['cart'] ?? {});

        // Associate buyer for legacy Storefront tokens only
        final cartId = cartData['id'] as String?;
        if (cartId != null && !_isCaToken(cookie)) {
          try {
            final updated = await _cartBuyerIdentityUpdate(
              cartId: cartId,
              customerAccessToken: cookie,
            );
            if (updated != null) cartData = Map<String, dynamic>.from(updated);
          } catch (e) {
            printLog('cartBuyerIdentityUpdate (legacy) error (non-fatal): $e');
          }
        }
      }

      // Re-apply existing discount if present
      final cartId = cartData?['id'] as String?;
      final existingDiscount = cartModel.checkout?.coupon?.code;
      if (cartId != null &&
          existingDiscount != null &&
          existingDiscount.isNotEmpty) {
        try {
          printLog('addItemsToCart: re-applying discount=$existingDiscount');
          final discountResult = await client.mutate(MutationOptions(
            document: gql(ShopifyQuery.cartDiscountCodesUpdate),
            variables: {
              'cartId': cartId,
              'discountCodes': [existingDiscount],
              'country': countryCode,
              'language': languageCode,
            },
          ));
          final updatedCart =
          discountResult.data?['cartDiscountCodesUpdate']?['cart']
          as Map<String, dynamic>?;
          if (updatedCart != null) {
            cartData = Map<String, dynamic>.from(updatedCart);
            final rawUrl = cartData['checkoutUrl'] as String? ?? '';
            if (rawUrl.isNotEmpty) {
              final uri = Uri.parse(rawUrl);
              cartData['checkoutUrl'] = uri.replace(queryParameters: {
                ...uri.queryParameters,
                'discount': existingDiscount,
              }).toString();
            }
          }
        } catch (e) {
          printLog('addItemsToCart: re-apply discount error (non-fatal): $e');
        }
      }

      if (cartData!.isNotEmpty) {
        return CheckoutCart.fromCartJson(cartData!, langCode: languageCode);
      }

      // Fallback: legacy checkoutCreate
      return await _addItemsViaLegacyCheckout(cartModel, cookie);
    } catch (e, s) {
      printLog('addItemsToCart error: $e\n$s');
      rethrow;
    }
  }

  /// Returns a map of merchandiseId → lineId for all lines in a cart.
  @override
  Future<Map<String, String>?> getCartLines(String cartId) async {
    try {
      final result = await client.query(QueryOptions(
        document: gql(ShopifyQuery.getCart),
        fetchPolicy: FetchPolicy.noCache,
        variables: {
          'cartId': cartId,
          'country': countryCode,
          'language': languageCode,
        },
      ));
      if (result.hasException) return null;
      final edges = result.data?['cart']?['lines']?['edges'] as List? ?? [];
      final map = <String, String>{};
      for (final edge in edges) {
        final node = edge['node'] as Map<String, dynamic>?;
        if (node == null) continue;
        final merchId = node['merchandise']?['id'] as String?;
        final lineId = node['id'] as String?;
        if (merchId != null && lineId != null) {
          map[merchId] = lineId;
        }
      }
      return map;
    } catch (e) {
      printLog('getCartLines error: $e');
      return null;
    }
  }

  @override
  Future<CheckoutCart> updateItemsToCart(
      covariant CartModelShopify cartModel, String? cookie) async {

    final existingCartId = cartModel.checkout?.id;

    print('asdasdsa${existingCartId}');

    // If no existing cart GID, fall back to addItemsToCart (creates new cart)
    if (existingCartId == null ||
        !existingCartId.toString().startsWith('gid://shopify/Cart/')) {
      return addItemsToCart(cartModel);
    }

    try {
      // Fetch current cart lines to get line item GIDs
      final cartResult = await client.query(QueryOptions(
        document: gql(ShopifyQuery.getCart),
        fetchPolicy: FetchPolicy.noCache,
        variables: {
          'cartId': existingCartId,
          'country': countryCode,
          'language': languageCode,
        },
      ));

      final existingLines =
      (cartResult.data?['cart']?['lines']?['edges'] as List? ?? []);

      // Map merchandiseId → line node id
      final existingLineMap = <String, String>{};
      for (final edge in existingLines) {
        final node = edge['node'] as Map<String, dynamic>?;
        if (node == null) continue;
        final merchId = node['merchandise']?['id'] as String?;
        final lineId = node['id'] as String?;
        if (merchId != null && lineId != null) {
          existingLineMap[merchId] = lineId;
        }
      }

      // Build update lines using existing line GIDs
      final linesToUpdate = <Map<String, dynamic>>[];
      final linesToAdd = <Map<String, dynamic>>[];

      for (final entry in cartModel.productVariationInCart.entries) {
        final variant = entry.value;
        final quantity = cartModel.productsInCart[entry.key] ?? 1;
        if (variant == null || (variant.id?.isEmpty ?? true)) continue;

        final rawId = variant.id!;
        final merchandiseId = rawId.startsWith('gid://shopify/ProductVariant/')
            ? rawId
            : 'gid://shopify/ProductVariant/$rawId';

        if (existingLineMap.containsKey(merchandiseId)) {
          // ✅ Line exists → update quantity using its line GID
          linesToUpdate.add({
            'id': existingLineMap[merchandiseId]!,
            'quantity': quantity,
          });
        } else {
          // ➕ New item → add it
          linesToAdd.add({'merchandiseId': merchandiseId, 'quantity': quantity});
        }
      }

      Map<String, dynamic>? cartData;

      // Update existing lines
      if (linesToUpdate.isNotEmpty) {
        printLog('updateItemsToCart: updating ${linesToUpdate.length} lines');
        final updateResult = await client.mutate(MutationOptions(
          document: gql(ShopifyQuery.cartLinesUpdate),
          variables: {
            'cartId': existingCartId,
            'lines': linesToUpdate,
            'country': countryCode,
            'language': languageCode,
          },
        ));
        if (updateResult.hasException) {
          throw Exception(updateResult.exception.toString());
        }
        cartData = Map<String, dynamic>.from(
            updateResult.data?['cartLinesUpdate']?['cart'] ?? {});
      }

      print('asdasdsa');
      // Add new lines
      if (linesToAdd.isNotEmpty) {
        printLog('updateItemsToCart: adding ${linesToAdd.length} new lines');
        final addResult = await client.mutate(MutationOptions(
          document: gql(ShopifyQuery.cartLinesAdd),
          variables: {
            'cartId': existingCartId,
            'lines': linesToAdd,
            'country': countryCode,
            'language': languageCode,
          },
        ));
        if (!addResult.hasException) {
          cartData = Map<String, dynamic>.from(
              addResult.data?['cartLinesAdd']?['cart'] ?? {});
        }
      }
      //

      // Fallback: fetch current cart state if no mutation ran
      cartData ??= Map<String, dynamic>.from(
          cartResult.data?['cart'] as Map<String, dynamic>? ?? {});

      if (cartData.isNotEmpty) {
        return CheckoutCart.fromCartJson(cartData, langCode: languageCode);
      }

      return addItemsToCart(cartModel);
    } catch (e, s) {
      printLog('updateItemsToCart error: $e\n$s');
      rethrow;
    }
  }
  /// Associate a buyer with a cart using [cartBuyerIdentityUpdate].
  /// Works for both shcat_ (CA API) tokens and legacy Storefront tokens.
  Future<Map<String, dynamic>?> _cartBuyerIdentityUpdate({
    required String cartId,
    required String customerAccessToken,
  }) async {
    // shcat_ tokens are rejected by Storefront cartBuyerIdentityUpdate
    if (_isCaToken(customerAccessToken)) {
      printLog('_cartBuyerIdentityUpdate: skipping for shcat_ token');
      return null;
    }

    final result = await client.mutate(MutationOptions(
      document: gql(r'''
      mutation cartBuyerIdentityUpdate(
        $cartId: ID!
        $buyerIdentity: CartBuyerIdentityInput!
        $country: CountryCode
        $language: LanguageCode
      ) @inContext(country: $country, language: $language) {
        cartBuyerIdentityUpdate(cartId: $cartId, buyerIdentity: $buyerIdentity) {
          cart {
            id
            checkoutUrl
            buyerIdentity {
              email
              phone
              customer { id email }
              countryCode
            }
          }
          userErrors { field message code }
        }
      }
    '''),
      variables: {
        'cartId': cartId,
        'buyerIdentity': {
          'customerAccessToken': customerAccessToken,
          'countryCode': countryCode,
        },
        'country': countryCode,
        'language': languageCode,
      },
    ));
    if (result.hasException) throw Exception(result.exception.toString());
    final errors =
        result.data?['cartBuyerIdentityUpdate']?['userErrors'] as List? ?? [];
    if (errors.isNotEmpty) {
      printLog('cartBuyerIdentityUpdate userErrors: $errors');
    }
    return result.data?['cartBuyerIdentityUpdate']?['cart']
    as Map<String, dynamic>?;
  }


  Future<CheckoutCart> _addItemsViaLegacyCheckout(
      CartModelShopify cartModel, String cookie) async {
    final lineItems = cartModel.productVariationInCart.entries
        .where((e) => e.value?.id != null)
        .map((e) => {
      'variantId': e.value!.id,
      'quantity': cartModel.productsInCart[e.key] ?? 1,
    })
        .toList();

    printLog('addItemsToCart: existingCartId=${cartModel.checkout?.id}');

//
    final result = await client.mutate(MutationOptions(
      document: gql(ShopifyQuery.createCheckout),
      variables: {
        'input': {'lineItems': lineItems},
        'langCode': cartModel.langCode?.toUpperCase(),
        'countryCode': countryCode,
      },
    ));
    if (result.hasException) throw Exception(result.exception.toString());
    final checkout = result.data?['checkoutCreate']?['checkout'];
    if (checkout == null) throw Exception('Legacy checkout returned null');
    try {
      // For CA API (shcat_) tokens, skip checkoutLinkUser — it only accepts
      // legacy Storefront customer access tokens.
      if (_isCaToken(cookie)) {
        return CheckoutCart.fromJsonShopify(checkout, langCode: languageCode);
      }
      final linked = await checkoutLinkUser(checkout['id'], cookie);
      return CheckoutCart.fromJsonShopify(
          linked ?? checkout, langCode: languageCode);
    } catch (_) {
      return CheckoutCart.fromJsonShopify(checkout, langCode: languageCode);
    }
  }

  // ── Legacy checkout coupon methods (Storefront checkoutCreate flow) ─────────

  Future<CheckoutCart> applyCoupon(
      CartModel cartModel, String discountCode) async {
    final checkoutId = cartModel.checkout?.id;
    if (checkoutId == null) throw Exception('No checkout/cart ID');

    final isCartGid = checkoutId.startsWith('gid://shopify/Cart/');
    if (isCartGid || _isCaToken(cartModel.user?.cookie)) {
      return applyCartCoupon(checkoutId, discountCode);
    }

    // Legacy Checkout API flow
    final result = await client.mutate(MutationOptions(
      document: gql(ShopifyQuery.applyCoupon),
      variables: {
        'discountCode': discountCode,
        'checkoutId': checkoutId,
      },
    ));
    if (result.hasException) {
      printLog('applyCoupon exception: ${result.exception.toString()}');
      throw Exception(result.exception.toString());
    }
    print('dataxxxx${result.data!['checkoutDiscountCodeApplyV2']['checkout']}');//
    return CheckoutCart.fromJsonShopify(
        result.data!['checkoutDiscountCodeApplyV2']['checkout']);
  }

  Future<CheckoutCart> removeCoupon(String? checkoutId) async {
    if (checkoutId == null) throw Exception('No checkout/cart ID');

    if (checkoutId.startsWith('gid://shopify/Cart/')) {
      return removeCartCoupon(checkoutId);
    }

    final result = await client.mutate(MutationOptions(
      document: gql(ShopifyQuery.removeCoupon),
      variables: {'checkoutId': checkoutId},
    ));
    if (result.hasException) throw Exception(result.exception.toString());
    return CheckoutCart.fromJsonShopify(
        result.data!['checkoutDiscountCodeRemove']['checkout']);
  }

  @override
  Future<List<ShippingMethod>> getShippingMethods({
    CartModel? cartModel,
    String? token,
    String? checkoutId,
    store_model.Store? store,
    FormatAddress? formatAddress,
    String? langCode,
  }) async {
    // Cart API flow: checkoutId is actually a cart GID for shcat_ users
    final isCaFlow = _isCaToken(token) ||
        (checkoutId?.startsWith('gid://shopify/Cart/') ?? false);

    if (isCaFlow && checkoutId != null) {
      return await _getCartShippingRates(
        cartId: checkoutId,
        cartModel: cartModel,
        formatAddress: formatAddress,
      );
    }

    // Legacy checkout flow
    try {
      final newAddress = cartModel!.address!
          .toShopifyJson(formatAddress: formatAddress)['address'];
      final result = await client.mutate(MutationOptions(
        document: gql(ShopifyQuery.updateShippingAddress),
        fetchPolicy: FetchPolicy.noCache,
        variables: {
          'shippingAddress': newAddress,
          'checkoutId': checkoutId,
        },
      ));
      if (result.hasException) {
        throw 'So sorry, We do not support shipping to your address.';
      }
      final checkout = await getCheckout(checkoutId: checkoutId);
      final availableShippingRates = checkout['availableShippingRates'];
      final list = <ShippingMethod>[];
      if (availableShippingRates != null && availableShippingRates['ready']) {
        for (var item in availableShippingRates['shippingRates']) {
          list.add(ShippingMethod.fromShopifyJson(item));
        }
      } else {
        await Future.delayed(const Duration(milliseconds: 500));
        final checkoutData = await getCheckout(checkoutId: checkoutId);
        for (var item
        in checkoutData['availableShippingRates']['shippingRates']) {
          list.add(ShippingMethod.fromShopifyJson(item));
        }
      }
      return list;
    } catch (e) {
      throw 'So sorry, We do not support shipping to your address.';
    }
  }

  /// Fetch available delivery options from the Cart API.
  /// Updates delivery address via cartBuyerIdentityUpdate first.
  Future<List<ShippingMethod>> _getCartShippingRates({
    required String cartId,
    CartModel? cartModel,
    FormatAddress? formatAddress,
  }) async {
    try {
      if (cartModel?.address != null) {
        final addr = cartModel!.address!;
        await client.mutate(MutationOptions(
          document: gql(r'''
            mutation cartBuyerIdentityUpdateAddr(
              $cartId: ID!
              $buyerIdentity: CartBuyerIdentityInput!
            ) {
              cartBuyerIdentityUpdate(cartId: $cartId, buyerIdentity: $buyerIdentity) {
                cart { id }
                userErrors { field message }
              }
            }
          '''),
          variables: {
            'cartId': cartId,
            'buyerIdentity': {
              'countryCode': countryCode,
              'deliveryAddressPreferences': [
                {
                  'deliveryAddress': {
                    'address1': addr.street ?? '',
                    'address2': addr.apartment ?? '',
                    'city': addr.city ?? '',
                    'province': addr.state ?? '',
                    'zip': addr.zipCode ?? '',
                    'countryCode': addr.country ?? countryCode,
                    'firstName': addr.firstName ?? '',
                    'lastName': addr.lastName ?? '',
                    'phone': addr.phoneNumber ?? '',
                  }
                }
              ],
            },
          },
        ));
      }

      final result = await client.query(QueryOptions(
        document: gql(r'''
          query cartDeliveryGroups($cartId: ID!) {
            cart(id: $cartId) {
              deliveryGroups(first: 10) {
                nodes {
                  id
                  deliveryOptions {
                    handle
                    title
                    estimatedCost { amount currencyCode }
                    deliveryMethodType
                  }
                }
              }
            }
          }
        '''),
        fetchPolicy: FetchPolicy.noCache,
        variables: {'cartId': cartId},
      ));

      if (result.hasException) {
        throw 'So sorry, We do not support shipping to your address.';
      }

      final groups =
          result.data?['cart']?['deliveryGroups']?['nodes'] as List? ?? [];
      final list = <ShippingMethod>[];
      for (final group in groups) {
        final options = group['deliveryOptions'] as List? ?? [];
        for (final opt in options) {
          list.add(ShippingMethod.fromJson({
            'id': opt['handle'] ?? '',
            'title': opt['title'] ?? '',
            'cost': opt['estimatedCost']?['amount'] ?? '0',
            'description': opt['deliveryMethodType'] ?? '',
          }));
        }
      }
      return list;
    } catch (e) {
      throw 'So sorry, We do not support shipping to your address.';
    }
  }

  /// Update selected delivery option on a cart (CA API flow).
  Future<CheckoutCart?> updateCartDeliveryOption({
    required String cartId,
    required String deliveryGroupId,
    required String deliveryOptionHandle,
  }) async {
    try {
      final result = await client.mutate(MutationOptions(
        document: gql(r'''
          mutation cartSelectedDeliveryOptionsUpdate(
            $cartId: ID!
            $selectedDeliveryOptions: [CartSelectedDeliveryOptionInput!]!
          ) {
            cartSelectedDeliveryOptionsUpdate(
              cartId: $cartId
              selectedDeliveryOptions: $selectedDeliveryOptions
            ) {
              cart {
                id
                checkoutUrl
                cost { totalAmount { amount currencyCode } }
              }
              userErrors { field message }
            }
          }
        '''),
        variables: {
          'cartId': cartId,
          'selectedDeliveryOptions': [
            {
              'deliveryGroupId': deliveryGroupId,
              'deliveryOptionHandle': deliveryOptionHandle,
            }
          ],
        },
      ));
      if (result.hasException) return null;
      final cart =
      result.data?['cartSelectedDeliveryOptionsUpdate']?['cart'];
      return cart != null
          ? CheckoutCart.fromCartJson(cart, langCode: languageCode)
          : null;
    } catch (e) {
      printLog('updateCartDeliveryOption error: $e');
      return null;
    }
  }

  /// Update quantities for existing line items in a cart.
  Future<CheckoutCart?> updateCartLines({
    required String cartId,
    required List<Map<String, dynamic>> lines, // [{id, quantity}]
  }) async {
    try {
      final result = await client.mutate(MutationOptions(
        document: gql(ShopifyQuery.cartLinesUpdate),
        variables: {
          'cartId': cartId,
          'lines': lines,
          'country': countryCode,
          'language': languageCode,
        },
      ));
      if (result.hasException) throw Exception(result.exception.toString());
      final cart = result.data?['cartLinesUpdate']?['cart'];
      return cart != null
          ? CheckoutCart.fromCartJson(cart, langCode: languageCode)
          : null;
    } catch (e) {
      printLog('updateCartLines error: $e');
      return null;
    }
  }

  /// Remove line items from a cart by their line GIDs.
  ///
  @override
  Future<CheckoutCart?> removeCartLines({
    required String cartId,
    required List<String> lineIds,
    String? discountCode,
  }) async {
    try {
      final result = await client.mutate(MutationOptions(
        document: gql(ShopifyQuery.cartLinesRemove),
        variables: {
          'cartId': cartId,
          'lineIds': lineIds,
          'country': countryCode,
          'language': languageCode,
        },
      ));
      if (result.hasException) throw Exception(result.exception.toString());

      var cartData = Map<String, dynamic>.from(
          result.data?['cartLinesRemove']?['cart'] as Map<String, dynamic>? ?? {});

      // Re-apply discount if one was active
      if (discountCode != null && discountCode.isNotEmpty && cartData['id'] != null) {
        try {
          final discountResult = await client.mutate(MutationOptions(
            document: gql(ShopifyQuery.cartDiscountCodesUpdate),
            variables: {
              'cartId': cartData['id'],
              'discountCodes': [discountCode],
              'country': countryCode,
              'language': languageCode,
            },
          ));
          final updatedCart = discountResult.data?['cartDiscountCodesUpdate']?['cart']
          as Map<String, dynamic>?;
          if (updatedCart != null) {
            cartData = Map<String, dynamic>.from(updatedCart);
            final rawUrl = cartData['checkoutUrl'] as String? ?? '';
            if (rawUrl.isNotEmpty) {
              final uri = Uri.parse(rawUrl);
              cartData['checkoutUrl'] = uri.replace(queryParameters: {
                ...uri.queryParameters,
                'discount': discountCode,
              }).toString();
            }
          }
        } catch (e) {
          printLog('removeCartLines: re-apply discount error (non-fatal): $e');
        }
      }

      return cartData.isNotEmpty
          ? CheckoutCart.fromCartJson(cartData, langCode: languageCode)
          : null;
    } catch (e) {
      printLog('removeCartLines error: $e');
      return null;
    }
  }
  /// Apply a discount code to a cart (Cart API) or legacy checkout.

  Future<CheckoutCart> applyCartCoupon(
      String cartId, String discountCode)

  async {
    final result = await client.mutate(MutationOptions(
      document: gql(ShopifyQuery.cartDiscountCodesUpdate),
      variables: {
        'cartId': cartId,
        'discountCodes': [discountCode],
        'country': countryCode,
        'language': languageCode,
      },
    ));
    if (result.hasException) throw Exception(result.exception.toString());

    final rawCart = result.data?['cartDiscountCodesUpdate']?['cart']
    as Map<String, dynamic>?;
    if (rawCart == null) throw Exception('Cart data is null');

    // Must deep-copy — GraphQL returns unmodifiable maps
    final cartData = Map<String, dynamic>.from(rawCart);

    final rawUrl = cartData['checkoutUrl'] as String? ?? '';
    log('applyCartCoupondiscount: rawUrl=$cartData');
    printLog('applyCartCoupon: rawUrl=$rawUrl');

    if (rawUrl.isNotEmpty && discountCode.isNotEmpty) {
      final uri = Uri.parse(rawUrl);
      final newUrl = uri.replace(queryParameters: {
        ...uri.queryParameters,
        'discount': discountCode,
      }).toString();
      cartData['checkoutUrl'] = newUrl;
      printLog('applyCartCoupon: updatedUrl=$newUrl');
    }

    return CheckoutCart.fromCartJson(cartData, langCode: languageCode);
  }

  @override
  Future<Category?> getProductCategoryByPermalink(
      String productCategoryPermalink) async {
    try {
      // Extract handle from URL
      // e.g. https://fawaah.com/collections/honey → honey
      final handle = productCategoryPermalink
          .split('/')
          .lastWhere((e) => e.isNotEmpty, orElse: () => '');

      if (handle.isEmpty) return null;

      final result = await client.query(QueryOptions(
        document: gql(r'''
        query getCollectionByHandle($handle: String!) {
          collection(handle: $handle) {
            id
            title
            handle
            description
            image {
              url
              altText
            }
            onlineStoreUrl
          }
        }
      '''),
        variables: {'handle': handle},
        fetchPolicy: FetchPolicy.networkOnly,
      ));

      if (result.hasException || result.data?['collection'] == null) {
        printLog('getProductCategoryByPermalink: not found for handle=$handle');
        return null;
      }

      return Category.fromJsonShopify(result.data!['collection']);
    } catch (e) {
      printLog('getProductCategoryByPermalink error: $e');
      return null;
    }
  }

  Future<CheckoutCart> removeCartCoupon(String cartId) async {
    final result = await client.mutate(MutationOptions(
      document: gql(ShopifyQuery.cartDiscountCodesUpdate),
      variables: {
        'cartId': cartId,
        'discountCodes': <String>[],
        'country': countryCode,
        'language': languageCode,
      },
    ));
    if (result.hasException) throw Exception(result.exception.toString());
    return CheckoutCart.fromCartJson(
        result.data?['cartDiscountCodesUpdate']?['cart'],
        langCode: languageCode);
  }

  Future<Map<String, dynamic>> getCheckout({String? checkoutId}) async {

    final result = await client.query(QueryOptions(
      document: gql(ShopifyQuery.getCheckout),
      fetchPolicy: FetchPolicy.noCache,
      variables: {'checkoutId': checkoutId},
    ));
    if (result.hasException) throw Exception(result.exception.toString());
    return result.data?['node'];
  }

  @override
  Future<List<PaymentMethod>> getPaymentMethods({
    CartModel? cartModel,
    ShippingMethod? shippingMethod,
    String? token,
    String? langCode,
  }) async {
    final list = <PaymentMethod>[];
    list.add(PaymentMethod.fromJson({
      'id': '0',
      'title': 'Checkout Free',
      'description': '',
      'enabled': true,
    }));
    if (kShopifyPaymentConfig.paymentCardConfig.enable) {
      list.add(PaymentMethod.fromJson({
        'id': PaymentMethod.stripeCard,
        'title': 'Checkout Credit card',
        'description': '',
        'enabled': true,
      }));
    }
    if (kShopifyPaymentConfig.applePayConfig.enable && isIos) {
      list.add(PaymentMethod.fromJson({
        'id': PaymentMethod.stripeApplePay,
        'title': 'Checkout with ApplePay',
        'description': '',
        'enabled': true,
      }));
    }
    if (kShopifyPaymentConfig.googlePayConfig.enable && isAndroid) {
      list.add(PaymentMethod.fromJson({
        'id': PaymentMethod.stripeGooglePay,
        'title': 'Checkout with GooglePay',
        'description': '',
        'enabled': true,
      }));
    }
    return list;
  }

  @override
  Future<PaymentSettings> getPaymentSettings() async {
    final result = await client.query(QueryOptions(
      document: gql(ShopifyQuery.getPaymentSettings),
      variables: const <String, dynamic>{'nRepositories': 50},
    ));
    if (result.hasException) throw Exception(result.exception.toString());
    return PaymentSettings.fromShopifyJson(
        result.data!['shop']['paymentSettings']);
  }

  @override
  Future checkoutWithCreditCard(
      String? vaultId,
      CartModel cartModel,
      Address address,
      PaymentSettingsModel paymentSettingsModel,
      ) async {
    final result = await client.mutate(MutationOptions(
      document: gql(ShopifyQuery.checkoutWithCreditCard),
      variables: {
        'checkoutId': cartModel.checkout!.id,
        'payment': {
          'paymentAmount': {
            'amount': cartModel.getTotal(),
            'currencyCode': cartModel.getCurrency(),
          },
          'idempotencyKey': const Uuid().v1(),
          'billingAddress': address.toShopifyJson()['address'],
          'vaultId': vaultId,
          'test': true,
        },
      },
    ));
    if (result.hasException) throw Exception(result.exception.toString());
    return CheckoutCart.fromJsonShopify(
        result.data!['checkoutCompleteWithCreditCardV2']['checkout']);
  }

  Future<PaymentShopify?> checkoutCompleteWithTokenizedPayment({
    required String checkoutId,
    required Map paymentData,
  }) async {
    try {
      final result = await client.mutate(MutationOptions(
        document: gql(ShopifyQuery.checkoutCompleteWithTokenizedPayment),
        variables: <String, dynamic>{
          'checkoutId': checkoutId,
          'payment': paymentData,
        },
      ));
      if (result.hasException) throw result.exception.toString();
      return PaymentShopify.fromJson(
          result.data!['checkoutCompleteWithTokenizedPaymentV3']['payment']);
    } catch (e) {
      return null;
    }
  }

  Future<PaymentShopify?> fetchPayment({required String paymentId}) async {
    try {
      final result = await client.mutate(MutationOptions(
        document: gql(ShopifyQuery.fetchPayment),
        variables: <String, dynamic>{'paymentId': paymentId},
      ));
      if (result.hasException) throw result.exception.toString();
      return PaymentShopify.fromJson(result.data?['node']);
    } catch (e) {
      return null;
    }
  }

  @override
  Future<CheckoutCart?> updateShippingRate({
    required String checkoutId,
    required String shippingRateHandle,
  }) async {
    try {
      final result = await client.mutate(MutationOptions(
        document: gql(ShopifyQuery.updateShippingRate),
        variables: <String, dynamic>{
          'checkoutId': checkoutId,
          'shippingRateHandle': shippingRateHandle,
        },
      ));
      if (result.hasException) printLog(result.exception.toString());
      return CheckoutCart.fromJsonShopify(
          result.data!['checkoutShippingLineUpdate']['checkout']);
    } catch (e) {
      return null;
    }
  }

  Future updateCheckout({
    String? checkoutId,
    String? note,
    DateTime? deliveryDate,
  }) async {
    var deliveryInfo = [];
    if (deliveryDate != null) {
      final dateFormat = DateFormat(DateTimeFormatConstants.ddMMMMyyyy);
      final dayFormat = DateFormat(DateTimeFormatConstants.weekday);
      final timeFormat = DateFormat(DateTimeFormatConstants.timeHHmmFormatEN);
      deliveryInfo = [
        {'key': 'Delivery Date', 'value': dateFormat.format(deliveryDate)},
        {'key': 'Delivery Day', 'value': dayFormat.format(deliveryDate)},
        {'key': 'Delivery Time', 'value': timeFormat.format(deliveryDate)},
      ];
    }
    final result = await client.mutate(MutationOptions(
      document: gql(ShopifyQuery.updateCheckoutAttribute),
      variables: <String, dynamic>{
        'checkoutId': checkoutId,
        'input': {
          'note': note,
          if (deliveryDate != null) 'customAttributes': deliveryInfo,
        },
      },
    ));
    if (result.hasException) throw Exception(result.exception.toString());
  }

  @override
  Future<void> updateCheckoutEmail({
    required String checkoutId,
    required String email,
  }) async {
    final result = await client.mutate(MutationOptions(
      document: gql(ShopifyQuery.updateCheckoutEmail),
      variables: <String, dynamic>{
        'checkoutId': checkoutId,
        'email': email,
      },
    ));
    if (result.hasException) throw result.exception.toString();
  }

  Future<Map<String, dynamic>?> checkoutLinkUser(
      String? checkoutId, String? token) async {
    final result = await client.mutate(MutationOptions(
      document: gql(ShopifyQuery.checkoutLinkUser),
      variables: {
        'checkoutId': checkoutId,
        'customerAccessToken': token,
      },
    ));
    if (result.hasException) throw result.exception.toString();
    return result.data?['checkoutCustomerAssociateV2']?['checkout'];
  }

  // ── Blogs (Storefront API) ────────────────────────────────────────────────

  @override
  Future<PagingResponse<Blog>>? getBlogs(dynamic cursor) async {
    if (super.blogApi.url != domain) {
      return (await super.getBlogs(cursor)) ?? const PagingResponse();
    }
    try {
      final response = await client.query(QueryOptions(
        document: gql(ShopifyQuery.getArticle),
        fetchPolicy: FetchPolicy.networkOnly,
        variables: {
          'nRepositories': 50,
          'pageSize': 12,
          'langCode': languageCode,
          if (cursor != null && cursor is! num) 'cursor': cursor,
        },
      ));
      if (response.hasException) return const PagingResponse();
      final edges = response.data?['articles']?['edges'];
      if (edges == null || edges is! List) return const PagingResponse();
      final data = <Blog>[];
      String? lastCursor;
      for (var item in edges) {
        final node = item['node'];
        if (node == null) continue;
        lastCursor = item['cursor'] as String?;
        data.add(Blog.fromShopifyJson(node));
      }
      return PagingResponse(data: data, cursor: lastCursor);
    } catch (e) {
      return const PagingResponse();
    }
  }

  @override
  Future<Blog?> getBlogByPermalink(String blogPermaLink) async {
    final uri = Uri.parse(blogPermaLink);
    final articleHandle = uri.pathSegments.last;
    final blogHandle = uri.pathSegments[uri.pathSegments.length - 2];
    try {
      final result = await client.query(QueryOptions(
        document: gql(ShopifyQuery.getArticleByHandle),
        variables: <String, dynamic>{
          'blogHandle': blogHandle,
          'articleHandle': articleHandle,
        },
      ));
      if (result.hasException) return null;
      final article =
      result.data?['blog']?['articleByHandle'] as Map<String, dynamic>?;
      if (article == null) return null;
      return Blog.fromShopifyJson(article);
    } catch (e) {
      return null;
    }
  }
}