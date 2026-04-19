import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';
import 'package:fstore/common/config.dart';
import 'package:fstore/common/constants.dart' show RouteList;
import 'package:fstore/generated/l10n.dart';
import 'package:fstore/models/entities/back_drop_arguments.dart';
import 'package:fstore/models/entities/store_arguments.dart';
import 'package:fstore/routes/flux_navigate.dart';
import 'package:fstore/screens/blog/views/blog_detail_screen.dart';
import 'package:fstore/services/firebase/dynamic_link_service.dart';
import 'package:fstore/services/service_config.dart';
import 'package:fstore/services/services.dart';
import 'package:fstore/widgets/common/webview.dart';
import 'package:share_plus/share_plus.dart';

final _appLinks = AppLinks();

class DynamicLinkServiceImpl extends DynamicLinkService {
  final _service = Services();

  Future<void> initUniLinks(context) async {
    _appLinks.uriLinkStream.listen((uri) async {
      await handleDynamicLink(uri, context);
    });
  }

  @override
  void initDynamicLinks(BuildContext context) async {
    await initUniLinks(context);
  }

  @override
  void shareProductLink({
    required String productUrl,
  }) async {
    await SharePlus.instance.share(
      ShareParams(uri: Uri.parse(productUrl)),
    );
  }

  @override
  Future<String> generateProductCategoryUrl(dynamic productCategoryId) async {
    try {
      // Decode base64 GID if needed
      if (productCategoryId is String &&
          !productCategoryId.startsWith('gid://')) {
        try {
          final decoded = String.fromCharCodes(
              Uri.parse('data:text/plain;base64,$productCategoryId')
                  .data!
                  .contentAsBytes());
          productCategoryId = decoded;
        } catch (_) {}
      }

      if (ServerConfig().isShopify) {
        final categories = await _service.api.getCategories();
        if (categories != null) {
          final category = categories.firstWhere(
                (element) => element.id == productCategoryId,
            orElse: () => throw Exception('Category not found'),
          );
          return category.onlineStoreUrl ?? '';
        }
      } else {
        final category = await _service.api
            .getProductCategoryById(categoryId: productCategoryId);
        if (category != null) {
          return '${ServerConfig().url}/product-category/${category.slug}';
        }
      }
    } catch (e) {
      debugPrint('generateProductCategoryUrl error: $e');
    }
    return '';
  }

  @override
  Future<String> generateProductTagUrl(dynamic productTagId) async {
    try {
      final tag =
      await _service.api.getTagById(tagId: productTagId.toString());
      if (tag != null) {
        return '${ServerConfig().url}/product-tag/${tag.slug}';
      }
    } catch (e) {
      debugPrint('generateProductTagUrl error: $e');
    }
    return '';
  }

  @override
  Future<String> generateProductBrandUrl(dynamic brandCategoryId) async {
    try {
      final brand = await _service.api.getBrandById(brandCategoryId);
      if (brand != null) {
        return '${serverConfig['url']}/brand/${brand.slug}';
      }
    } catch (e) {
      debugPrint('generateProductBrandUrl error: $e');
    }
    return '';
  }

  @override
  Future<void> handleDynamicLink(Uri uri, BuildContext context) async {
    try {
      var url = Uri.parse(uri.path).toString();

      /// PRODUCT CASE
      if (url.contains('/product/') ||
          url.contains('/shop/') ||
          url.contains('/products/')) {
        print("sasasasascx${url}");
        final product = await Services().api.getProductByPermalink(url);
        if (product != null) {
          await FluxNavigate.pushNamed(
            RouteList.productDetail,
            arguments: product,
          );
        }

        /// PRODUCT CATEGORY CASE
      } else if (url.contains('/product-category/') ||
          url.contains('/collections/')) {
        final category = await Services().api.getProductCategoryByPermalink(url);

        if (category != null) {
          await FluxNavigate.pushNamed(
            RouteList.backdrop,
            arguments: BackDropArguments(
              cateId: category.id,
              cateName: category.name,
            ),
          );
        }

        /// PRODUCT TAGS CASE
      } else if (url.contains('/product-tag/')) {
        final slug = Uri.tryParse(url)?.pathSegments.last;
        if (slug == null) throw '';
        final tag = await Services().api.getTagBySlug(slug);
        if (tag != null) {
          await FluxNavigate.pushNamed(
            RouteList.backdrop,
            arguments: BackDropArguments(
              tag: tag.id.toString(),
            ),
          );
        }

        /// VENDOR CASE
      } else if (url.contains('/store/')) {
        final vendor = await Services().api.getStoreByPermalink(url);
        if (vendor != null) {
          await FluxNavigate.pushNamed(
            RouteList.storeDetail,
            arguments: StoreDetailArgument(store: vendor),
          );
        }

        /// BRAND CASE
      } else if (url.contains('/brand/')) {
        final slug = Uri.tryParse(url)?.pathSegments.last;
        if (slug == null) throw '';
        final brand = await Services().api.getBrandBySlug(slug);
        if (brand != null) {
          await FluxNavigate.pushNamed(
            RouteList.backdrop,
            arguments: BackDropArguments(
              brandId: brand.id,
              brandName: brand.name,
              brandImg: brand.image,
            ),
          );
        }

        /// LISTING CASE
      } else if (url.contains('/listing/')) {
        var blog = await Services().api.getBlogByPermalink(url);
        var product = await Services().api.getProduct(blog?.id);
        if (product != null) {
          await FluxNavigate.pushNamed(
            RouteList.productDetail,
            arguments: product,
          );
        }

        /// BLOG / FALLBACK CASE
      } else {
        var blog = await Services().api.getBlogByPermalink(url);
        if (blog != null) {
          await FluxNavigate.pushNamed(
            RouteList.detailBlog,
            arguments: BlogDetailArguments(blog: blog),
          );
        } else {
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => WebView(
                enableBackward: false,
                enableForward: false,
                url: uri.toString(),
              ),
            ),
          );
        }
      }
    } catch (err) {
      _showErrorMessage(context);
    }
  }

  static void _showErrorMessage(context) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(S.current.canNotLoadThisLink),
        duration: const Duration(seconds: 2),
        action: SnackBarAction(
          label: 'DISMISS',
          onPressed: () {
            ScaffoldMessenger.of(context).hideCurrentSnackBar();
          },
        ),
      ),
    );
  }
}