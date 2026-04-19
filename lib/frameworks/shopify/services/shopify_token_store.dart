import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// Persists the Shopify Customer Account API OAuth tokens across app restarts.
///
/// Stored keys (all prefixed with `_shopify_ca_`):
///   access_token   — shcat_... token used for CA API calls
///   refresh_token  — opaque refresh token from the token endpoint
///   expires_at     — Unix ms when the access token expires
///
/// Usage:
///   await ShopifyTokenStore.save(accessToken: t, refreshToken: r, expiresIn: 3600);
///   final token = await ShopifyTokenStore.validAccessToken();  // null if expired
///   await ShopifyTokenStore.clear();
class ShopifyTokenStore {
  static const _kAccess  = '_shopify_ca_access_token';
  static const _kRefresh = '_shopify_ca_refresh_token';
  static const _kExpiry  = '_shopify_ca_expires_at';

  /// Persist tokens returned by the CA API token endpoint.
  /// [expiresIn] is seconds from now (the `expires_in` field in the response).
  static Future<void> save({
    required String accessToken,
    String? refreshToken,
    int expiresIn = 7200, // default 2h if server omits the field
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final expiresAt = DateTime.now()
        .add(Duration(seconds: expiresIn - 60)) // 60s buffer
        .millisecondsSinceEpoch;
    await prefs.setString(_kAccess, accessToken);
    await prefs.setInt(_kExpiry, expiresAt);
    if (refreshToken != null) {
      await prefs.setString(_kRefresh, refreshToken);
    }
  }

  /// Returns the stored access token only if it has not yet expired.
  /// Returns null if missing or expired — caller should refresh.
  static Future<String?> validAccessToken() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString(_kAccess);
    if (token == null) return null;
    final expiresAt = prefs.getInt(_kExpiry) ?? 0;
    if (DateTime.now().millisecondsSinceEpoch > expiresAt) return null;
    return token;
  }

  static Future<String?> refreshToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_kRefresh);
  }

  static Future<String?> accessToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_kAccess);
  }

  static Future<bool> isExpired() async {
    final prefs = await SharedPreferences.getInstance();
    final expiresAt = prefs.getInt(_kExpiry) ?? 0;
    return DateTime.now().millisecondsSinceEpoch > expiresAt;
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kAccess);
    await prefs.remove(_kRefresh);
    await prefs.remove(_kExpiry);
  }

  static Future<Map<String, dynamic>> debugInfo() async {
    final prefs = await SharedPreferences.getInstance();
    final expiresAt = prefs.getInt(_kExpiry) ?? 0;
    final token = prefs.getString(_kAccess);
    final hasRefresh = prefs.getString(_kRefresh) != null;
    final expiry = DateTime.fromMillisecondsSinceEpoch(expiresAt);
    final isExpired = DateTime.now().millisecondsSinceEpoch > expiresAt;
    return {
      'hasAccessToken': token != null,
      'tokenPreview': token != null
          ? token.substring(0, token.length.clamp(0, 20)) + '...'
          : null,
      'hasRefreshToken': hasRefresh,
      'expiresAt': expiry.toIso8601String(),
      'isExpired': isExpired,
      'secondsRemaining': (expiresAt - DateTime.now().millisecondsSinceEpoch) ~/ 1000,
    };
  }
}