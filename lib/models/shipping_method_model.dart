import 'package:flutter/material.dart';
import 'package:fstore/common/typesdef.dart';
import '../common/config.dart';

import '../models/cart/cart_model.dart';
import '../services/index.dart';
import 'entities/order_delivery_date.dart';
import 'entities/shipping_method.dart';

class ShippingMethodModel extends ChangeNotifier {
  final Services _service = Services();
  List<ShippingMethod>? shippingMethods;
  bool isLoading = true;
  String? message;

  List<OrderDeliveryDate>? _deliveryDates;
  List<OrderDeliveryDate>? get deliveryDates => _deliveryDates;

  Future<void> getShippingMethods(
      {CartModel? cartModel,
      String? token,
      String? checkoutId,
        FormatAddress? formatAddress,

        required String langCode}) async {
    try {
      isLoading = true;
      if (ServerConfig().isOpencart && (shippingMethods?.isNotEmpty ?? false)) {
        shippingMethods = [];
      }
      notifyListeners();
      shippingMethods = await _service.api.getShippingMethods(
          formatAddress: formatAddress ?? DefaultConfig.formatAddress,
          cartModel: cartModel,
          token: token,
          checkoutId: checkoutId,
          langCode: langCode);


      if (kAdvanceConfig.enableDeliveryDateOnCheckout) {
        _deliveryDates = await getDelivery();
      }
      isLoading = false;
      message = null;
      notifyListeners();
    } catch (err) {
      isLoading = false;
      message = '⚠️ $err';
      notifyListeners();
    }
  }

  Future<List<OrderDeliveryDate>> getDelivery() async {
    return await _service.api.getListDeliveryDates();
  }
}
