import 'package:inspireui/widgets/coupon_card.dart';

import '../../common/constants.dart';
import '../entities/address.dart';
import '../order/order.dart';

class CheckoutCart {
  final dynamic id;
  final String? webUrl;
  final double? subtotalPrice;
  final double? totalTax;
  final double? totalPrice;
  final double? paymentDue;
  final Coupon? coupon;
  final Address? shippingAddress;
  final String? currencyCode;
  final ShippingLine? shippingLine;
  final List<ProductItem>? lineItems;
  final Order? order;
  final String? email;

  CheckoutCart({
    this.id,
    this.webUrl,
    this.subtotalPrice,
    this.totalTax,
    this.totalPrice,
    this.paymentDue,
    this.coupon,
    this.shippingAddress,
    this.currencyCode,
    this.shippingLine,
    this.lineItems,
    this.order,
    this.email,
  });

  /// Legacy Checkout API response (subtotalPrice / totalTax / totalPrice / paymentDue nodes)
  factory CheckoutCart.fromJsonShopify(
      Map<String, dynamic> parsedJson, {
        String? langCode,
      }) {
    try {
      final rawUrl =
          parsedJson['checkoutUrl'] ?? parsedJson['webUrl'] ?? '';
      return CheckoutCart(
        id: parsedJson['id'],
        email: parsedJson['email'],
        webUrl: '$rawUrl${rawUrl.toString().contains('?') ? '&' : '?'}locale=${langCode?.toLowerCase()}',
        subtotalPrice: double.tryParse(
            parsedJson['subtotalPrice']?['amount']?.toString() ?? '0.0') ??
            0.0,
        totalTax: double.tryParse(
            parsedJson['totalTax']?['amount']?.toString() ?? '0.0') ??
            0.0,
        totalPrice: double.tryParse(
            parsedJson['totalPrice']?['amount']?.toString() ?? '0.0') ??
            0.0,
        paymentDue: double.tryParse(
            parsedJson['paymentDue']?['amount']?.toString() ?? '0.0') ??
            0.0,
        shippingLine: parsedJson['shippingLine'] != null
            ? ShippingLine.fromJson(parsedJson['shippingLine'])
            : null,
        currencyCode: parsedJson['currencyCode'],
        lineItems: parsedJson['lineItems']?['nodes'] != null
            ? List.from(parsedJson['lineItems']['nodes'])
            .map((x) => ProductItem.fromShopifyJson(x))
            .toList()
            : null,
        shippingAddress: parsedJson['shippingAddress'] != null
            ? Address.fromShopifyJson(parsedJson['shippingAddress'])
            : null,
        coupon: Coupon.fromShopify(parsedJson['discountApplications'] ?? {}),
        order: parsedJson['order'] != null
            ? Order.fromShopify(parsedJson['order'])
            : null,
      );
    } catch (e) {
      printLog('::::: CheckoutCart.fromJsonShopify ERROR $e');
      return CheckoutCart();
    }
  }

  /// Cart API 2025-01 response
  /// Shape:
  /// {
  ///   id, checkoutUrl, totalQuantity,
  ///   cost: { subtotalAmount, totalAmount, totalTaxAmount, totalDutyAmount },
  ///   discountCodes: [{ applicable, code }],
  ///   discountAllocations: [{ discountedAmount: { amount, currencyCode } }],
  ///   lines.edges[].node: {
  ///     id, quantity,
  ///     cost.totalAmount,
  ///     merchandise { id, title, price, compareAtPrice, image,
  ///                   selectedOptions, product { id, title, handle } }
  ///   }
  /// }

  factory CheckoutCart.fromCartJson(
      Map<String, dynamic> cartJson, {
        String? langCode,
      }) {
    try {
      final cost = cartJson['cost'] as Map<String, dynamic>? ?? {};

      final subtotal = double.tryParse(
          cost['subtotalAmount']?['amount']?.toString() ?? '0.0') ?? 0.0;
      final total = double.tryParse(
          cost['totalAmount']?['amount']?.toString() ?? '0.0') ?? 0.0;
      final tax = double.tryParse(
          cost['totalTaxAmount']?['amount']?.toString() ?? '0.0') ?? 0.0;

      final currencyCode =
          (cost['totalAmount']?['currencyCode'] as String?) ??
              _currencyFromCartLines(cartJson);

      // ✅ Sum all discount allocations
      final discountAllocations =
          cartJson['discountAllocations'] as List<dynamic>? ?? [];
      final discountAmount = discountAllocations.fold<double>(0.0, (sum, alloc) {
        return sum +
            (double.tryParse(
                alloc['discountedAmount']?['amount']?.toString() ?? '0') ?? 0.0);
      });

      final discountCodes = cartJson['discountCodes'] as List<dynamic>? ?? [];
      // ✅ Pass discountAmount so the coupon carries the real value
      final coupon = _couponFromCartDiscountCodes(discountCodes, discountAmount);

      final lineEdges = cartJson['lines']?['edges'] as List<dynamic>? ?? [];
      final lineItems = lineEdges
          .map<ProductItem?>((edge) {
        final node = edge['node'] as Map<String, dynamic>?;
        if (node == null) return null;
        return ProductItem.fromCartLineJson(node);
      })
          .whereType<ProductItem>()
          .toList();

      final checkoutUrl = cartJson['checkoutUrl'] as String? ?? '';
      printLog('checkoutUrl: $checkoutUrl');
      final webUrl = langCode != null && langCode.isNotEmpty
          ? '$checkoutUrl${checkoutUrl.contains('?') ? '&' : '?'}locale=${langCode.toLowerCase()}'
          : checkoutUrl;

      return CheckoutCart(
        id: cartJson['id'],
        email: null,
        webUrl: webUrl,
        subtotalPrice: subtotal,
        totalTax: tax,
        totalPrice: total,
        paymentDue: total,
        currencyCode: currencyCode,
        coupon: coupon,
        lineItems: lineItems.isEmpty ? null : lineItems,
        shippingAddress: null,
        shippingLine: null,
        order: null,
      );
    } catch (e) {
      printLog('::::: CheckoutCart.fromCartJson ERROR $e');
      return CheckoutCart();
    }
  }

  // ─── helpers ────────────────────────────────

  static String? _currencyFromCartLines(Map<String, dynamic> cartJson) {
    try {
      final edges = cartJson['lines']?['edges'] as List<dynamic>?;
      if (edges == null || edges.isEmpty) return null;
      final node = edges.first['node'] as Map<String, dynamic>?;
      return node?['merchandise']?['price']?['currencyCode'] as String?;
    } catch (_) {
      return null;
    }
  }

  static Coupon? _couponFromCartDiscountCodes(
      List<dynamic> codes,
      double discountAmount, {
        String currencyCode = 'KWD', // ✅ pass from cart
      }) {
    try {
      if (codes.isEmpty) return null;
      final applicable =
      codes.firstWhere((c) => c['applicable'] == true, orElse: () => null);
      if (applicable == null) return null;

      return Coupon.fromShopify({
        'edges': [
          {
            'node': {
              '__typename': 'DiscountCodeApplication',
              'applicable': true,
              'code': applicable['code'],
              'allocationMethod': 'ACROSS',
              'targetSelection': 'ALL',
              'targetType': 'LINE_ITEM',
              'value': {
                '__typename': 'MoneyV2',
                'amount': discountAmount.toString(),
                'currencyCode': currencyCode, // ✅ dynamic
              },
            }
          }
        ]
      });
    } catch (_) {
      return null;
    }
  }
  // ─── serialisation ──────────────────────────

  Map toJson() => {
    'id': id,
    'email': email,
    'webUrl': webUrl,
    'subtotalPrice': subtotalPrice,
    'totalTax': totalTax,
    'totalPrice': totalPrice,
    'paymentDue': paymentDue,
    'coupon': coupon,
    'shippingAddress': shippingAddress,
    'currencyCode': currencyCode,
    'shippingLine': shippingLine,
    'needsShipping': true,
    'lineItems': lineItems?.map((e) => e.toJson()).toList(),
  };

  @override
  String toString() => 'Checkout { id: $id }';
}

// ─────────────────────────────────────────────────────────────────────────────
// ShippingLine
// ─────────────────────────────────────────────────────────────────────────────

class ShippingLine {
  final String handle;
  final String title;
  final double price;

  ShippingLine({
    required this.handle,
    required this.title,
    required this.price,
  });

  factory ShippingLine.fromJson(Map json) {
    return ShippingLine(
      handle: json['handle']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      price: double.tryParse(
          json['price']?['amount']?.toString() ?? '0.0') ??
          0.0,
    );
  }

  Map toJson() => {
    'handle': handle,
    'title': title,
    'price': price,
  };

  @override
  String toString() =>
      'ShippingLine { handle: $handle, title: $title, price: $price }';
}