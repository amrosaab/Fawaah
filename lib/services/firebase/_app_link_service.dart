import 'package:app_links/app_links.dart';
import 'package:share_plus/share_plus.dart';
import 'package:flutter/material.dart';

class AppLinkService {
  final _appLinks = AppLinks();

  Future<void> initDynamicLinks(BuildContext context) async {
    // Handle link when app is cold started
    try {
      final initialLink = await _appLinks.getInitialLink();
      if (initialLink != null) {
        _handleLink(initialLink, context);
      }
    } catch (e) {
      debugPrint('AppLinkService: getInitialLink error: $e');
    }

    // Handle link when app is already running
    _appLinks.uriLinkStream.listen(
          (uri) => _handleLink(uri, context),
      onError: (e) => debugPrint('AppLinkService: stream error: $e'),
    );
  }

  void _handleLink(Uri uri, BuildContext context) {
    debugPrint('AppLinkService: received link: $uri');
    // Handle your deep link routing here
    // e.g. /product/123 → navigate to product detail
    final path = uri.path;
    if (path.contains('/product/')) {
      final productId = path.split('/product/').last;
      Navigator.pushNamed(context, '/product-detail', arguments: productId);
    }
    // add more routes as needed
  }

  void shareProductLink({String? productUrl}) {
    if (productUrl == null || productUrl.isEmpty) return;
    Share.share(productUrl);
  }
}