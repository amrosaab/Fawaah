import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_facebook_auth/flutter_facebook_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:random_string/random_string.dart';
import 'package:the_apple_sign_in/the_apple_sign_in.dart' as apple;

import '../common/config.dart';
import '../common/constants.dart';
import '../data/boxes.dart';
import '../generated/l10n.dart';
import '../services/index.dart';
import 'entities/user.dart';

abstract class UserModelDelegate {
  void onLoaded(User? user);
  void onLoggedIn(User user);
  void onLogout(User? user);
}

class UserModel with ChangeNotifier {
  UserModel() {
    _wireShopifyCallbacks();
  }

  final Services _service = Services();
  User? user;
  bool loggedIn = false;
  bool loading = false;
  UserModelDelegate? delegate;

  // ─────────────────────────────────────────────────────────────────────────
  // Shopify token callbacks
  // Wire up once at construction so both getUser() and any later CA API
  // call can trigger refresh/logout without needing a BuildContext.
  // ─────────────────────────────────────────────────────────────────────────

  void _wireShopifyCallbacks() {
    try {
      final shopify = _service.api as dynamic;

      // Silent refresh succeeded — update cookie in memory + Hive
      shopify.onTokenRefreshed = (String newToken) async {
        if (user != null) {
          user!.cookie = newToken;
          await saveUser(user);
          printLog('UserModel: shcat_ token refreshed and saved');
        }
      };

      // Token dead, refresh failed — log the user out immediately
      shopify.onTokenExpired = () async {
        printLog('UserModel: token expired and refresh failed — logging out');
        await logout();
      };
    } catch (_) {
      // Service is not ShopifyService — no-op for other store types
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Core helpers
  // ─────────────────────────────────────────────────────────────────────────

  void updateUser(User newUser) {
    user = newUser;
    notifyListeners();
  }

  Future<String?> submitForgotPassword(
      {String? forgotPwLink, Map<String, dynamic>? data}) async {
    return await _service.api
        .submitForgotPassword(forgotPwLink: forgotPwLink, data: data);
  }

  Future<void> saveUser(User? user) async {
    try {
      if (Services().firebase.isEnabled && ServerConfig().isVendorType()) {
        Services().firebase.saveUserToFirestore(user: user);
      }
      UserBox().isLoggedIn = true;
      loggedIn = true;
      UserBox().userInfo = user;
      this.user = user;
      delegate?.onLoaded(user);

      if (kAdvanceConfig.enableWooCommerceWholesalePrices &&
          ServerConfig().isWooPluginSupported) {
        eventBus.fire(const EventLoadedAppConfig());
      }
    } catch (err) {
      printLog(err);
    }
  }

  void setLoading(bool isLoading) {
    loading = isLoading;
    notifyListeners();
  }

  Future<void> setUser(User? user) async {
    if (user != null) {
      this.user = user;
      await saveUser(user);
      notifyListeners();
    }
  }

  String _getGenerateCookie() {
    var cookie = UserBox().userCookie;
    cookie ??= 'OCSESSID=${randomNumeric(30)}; PHPSESSID=${randomNumeric(30)}';
    UserBox().userCookie = cookie;
    return cookie;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Load user on app start
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> getUser() async {
    try {
      final localUser = UserBox().userInfo;
      if (localUser != null) {
        user = localUser;
        loggedIn = true;

        // getUserInfo will internally call _validCaToken for shcat_ tokens.
        // If the token is expired and refresh fails, onTokenExpired fires
        // which calls logout() — so userInfo will be null here.
        final userInfo = await _service.api.getUserInfo(user!.cookie);

        if (userInfo == null) {
          // Token was invalid and logout has already been triggered by
          // onTokenExpired. Nothing more to do — UI rebuilds via notifyListeners
          // inside logout().
          printLog('UserModel.getUser: userInfo null — session cleared');
          return;
        }

        userInfo.isSocial = user!.isSocial;
        user = userInfo;
        await saveUser(user);
        notifyListeners();
      } else {
        if (kPaymentConfig.guestCheckout) {
          delegate?.onLoaded(User()..cookie = _getGenerateCookie());
        }
        notifyListeners();
      }
    } catch (err) {
      printLog(err);
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Email + password login
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> login({
    required String username,
    required String password,
    required Function(User user) success,
    required Function(String message) fail,
  }) async {
    try {
      loading = true;
      notifyListeners();

      user = await _service.api.login(username: username, password: password);

      final userEmail =
      (user?.email?.isNotEmpty ?? false) ? user?.email : username;
      Services().firebase.loginFirebaseEmail(
        email: userEmail,
        password: password,
      );

      if (user == null) throw 'Something went wrong!!!';

      await saveUser(user);
      success(user!);
      loading = false;
      notifyListeners();
    } catch (err) {
      loading = false;
      fail(err.toString());
      notifyListeners();
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // OTP login (email code — Shopify Storefront API)
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> sendCode({
    required String username,
    required Function(bool success) success,
    required Function(String message) fail,
  }) async {
    try {
      loading = true;
      notifyListeners();

      final bool? sent = await _service.api.sendVerificationCode(username);

      loading = false;
      notifyListeners();

      if (sent == true) {
        success(true);
      } else {
        fail('Failed to send verification code. Please check your email.');
      }
    } catch (err) {
      loading = false;
      notifyListeners();
      fail(err.toString());
    }
  }

  Future<void> loginWithCode({
    required String username,
    required String code,
    required Function(User user) success,
    required Function(String message) fail,
  }) async {
    try {
      loading = true;
      notifyListeners();

      final String? accessToken =
      await _service.api.loginWithCode(username, code);

      if (accessToken == null || accessToken.isEmpty) {
        loading = false;
        notifyListeners();
        fail('Invalid or expired verification code. Please try again.');
        return;
      }

      final userInfo = await _service.api.getUserInfo(accessToken);

      if (userInfo == null) {
        loading = false;
        notifyListeners();
        fail('Could not load user profile. Please try again.');
        return;
      }

      userInfo.cookie = accessToken;
      userInfo.isSocial = false;

      await saveUser(userInfo);
      success(userInfo);

      loading = false;
      notifyListeners();
    } catch (err) {
      loading = false;
      notifyListeners();
      fail(err.toString());
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Shopify Customer Account API login (shcat_ token from WebView OAuth)
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> loginWithShcatToken(String shcatToken) async {
    try {
      loading = true;
      notifyListeners();

      final userInfo = await _service.api.getUserInfo(shcatToken);

      if (userInfo == null) {
        loading = false;
        notifyListeners();
        return;
      }

      userInfo.cookie = shcatToken;
      userInfo.isSocial = false;

      user = userInfo;
      loggedIn = true;

      await saveUser(userInfo);
      delegate?.onLoggedIn(userInfo);

      loading = false;
      notifyListeners();
    } catch (e) {
      loading = false;
      notifyListeners();
      printLog('loginWithShcatToken error: $e');
      rethrow;
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Create account
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> createUser({
    String? username,
    String? password,
    String? firstName,
    String? lastName,
    String? phoneNumber,
    bool? isVendor,
    required Function success,
    Function? fail,
  }) async {
    try {
      loading = true;
      notifyListeners();

      Services().firebase.createUserWithEmailAndPassword(
          email: username!, password: password!);

      user = await _service.api.createUser(
        firstName: firstName,
        lastName: lastName,
        username: username,
        password: password,
        phoneNumber: phoneNumber,
        isVendor: isVendor ?? false,
      );
      await saveUser(user);
      success(user);

      loading = false;
      notifyListeners();
    } catch (err) {
      fail!(err.toString());
      loading = false;
      notifyListeners();
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Logout
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> logout() async {
    loggedIn = false;
    try {
      unawaited(Services().firebase.signOut());
      unawaited(FacebookAuth.instance.logOut());
    } catch (err) {
      printLog(err);
    }

    delegate?.onLogout(user);
    unawaited(_service.api.logout(user?.cookie)); // also clears ShopifyTokenStore
    user = null;

    if (kPaymentConfig.guestCheckout) {
      delegate?.onLoaded(User()..cookie = _getGenerateCookie());
    }

    AddressBox().cleanUpForLogout();
    UserBox().cleanUpForLogout();
    notifyListeners();

    if (kAdvanceConfig.enableWooCommerceWholesalePrices &&
        ServerConfig().isWooPluginSupported) {
      eventBus.fire(const EventLoadedAppConfig());
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Social logins
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> loginApple({Function? success, Function? fail, context}) async {
    try {
      final result = await apple.TheAppleSignIn.performRequests([
        const apple.AppleIdRequest(
            requestedScopes: [apple.Scope.email, apple.Scope.fullName])
      ]);

      switch (result.status) {
        case apple.AuthorizationStatus.authorized:
          final userdat = await Services().firebase.loginFirebaseApple(
            authorizationCode: result.credential!.authorizationCode!,
            identityToken: result.credential!.identityToken!,
          );

          await login(
            username: userdat!.user!.email!,
            password: userdat.user!.email!,
            success: (sucUser) async {
              user = sucUser..isSocial = true;
              await saveUser(user);
              success!(user);
              notifyListeners();
            },
            fail: (failed) async {
              await createUser(
                username: userdat.user!.email!,
                password: userdat.user!.email!,
                success: (successuser) async {
                  user = successuser..isSocial = true;
                  await saveUser(user);
                  success!(user);
                  notifyListeners();
                },
                fail: (failed) {
                  fail!(S
                      .of(context)
                      .loginErrorServiceProvider(failed.toString()));
                  notifyListeners();
                },
              );
            },
          );
          notifyListeners();
          break;

        case apple.AuthorizationStatus.error:
          fail!(S.of(context).error(result.error!));
          break;
        case apple.AuthorizationStatus.cancelled:
          fail!(S.of(context).loginCanceled);
          break;
      }
    } catch (err) {
      fail!(S.of(context).loginErrorServiceProvider(err.toString()));
    }
  }

  Future<void> loginFirebaseSMS({
    String? phoneNumber,
    required Function success,
    Function? fail,
    context,
  }) async {
    try {
      await login(
        username: '${phoneNumber!}@fawaah.com',
        password: '$phoneNumber@fawaah.com',
        success: (sucUser) async {
          user = sucUser..isSocial = true;
          await saveUser(user);
          success(user);
          notifyListeners();
        },
        fail: (f) async {
          await createUser(
            username: '$phoneNumber@fawaah.com',
            password: '$phoneNumber@fawaah.com',
            success: (successuser) async {
              user = successuser..isSocial = true;
              await saveUser(user);
              success(user);
              notifyListeners();
            },
            fail: (failed) =>
                printLog('loginFirebaseSMS createUser failed: $failed'),
          );
        },
      );
    } catch (err) {
      fail?.call(S.of(context).loginErrorServiceProvider(err.toString()));
    }
  }

  Future<void> loginFB({Function? success, Function? fail, context}) async {
    try {
      final result = await FacebookAuth.instance.login();
      switch (result.status) {
        case LoginStatus.success:
          final accessToken = await FacebookAuth.instance.accessToken;
          Services()
              .firebase
              .loginFirebaseFacebook(token: accessToken?.tokenString);

          final fakeEmail = '${accessToken!.tokenString}@fawaah.com';
          await login(
            username: fakeEmail,
            password: fakeEmail,
            success: (sucUser) async {
              user = sucUser..isSocial = true;
              await saveUser(user);
              success!(user);
              notifyListeners();
            },
            fail: (f) async {
              await createUser(
                username: fakeEmail,
                password: fakeEmail,
                success: (successuser) async {
                  user = successuser..isSocial = true;
                  await saveUser(user);
                  success!(user);
                  notifyListeners();
                },
                fail: (failed) =>
                    printLog('loginFB createUser failed: $failed'),
              );
            },
          );
          break;
        case LoginStatus.cancelled:
          fail!(S.of(context).loginCanceled);
          break;
        default:
          fail!(result.message);
          break;
      }
      notifyListeners();
    } catch (err) {
      fail!(S.of(context).loginErrorServiceProvider(err.toString()));
    }
  }

  Future<void> loginGoogle(
      {Function? success, Function? fail, context}) async {
    try {
      final googleSignIn = GoogleSignIn(scopes: ['email']);
      try {
        await googleSignIn.disconnect();
      } catch (_) {}

      final res = await googleSignIn.signIn();
      if (res == null) {
        fail!(S.of(context).loginCanceled);
        return;
      }

      final auth = await res.authentication;
      Services().firebase.loginFirebaseGoogle(token: auth.idToken);

      await login(
        username: res.email,
        password: res.email,
        success: (sucUser) async {
          user = sucUser..isSocial = true;
          await saveUser(user);
          success!(user);
          notifyListeners();
        },
        fail: (failed) async {
          await createUser(
            username: res.email,
            password: res.email,
            success: (successuser) async {
              user = successuser..isSocial = true;
              await saveUser(user);
              success!(user);
              notifyListeners();
            },
            fail: (failed) {
              fail!(S
                  .of(context)
                  .loginErrorServiceProvider(failed.toString()));
              notifyListeners();
            },
          );
        },
      );
    } catch (err, trace) {
      printError(err, trace);
      fail!(S.of(context).loginErrorServiceProvider(err.toString()));
    }
  }
}