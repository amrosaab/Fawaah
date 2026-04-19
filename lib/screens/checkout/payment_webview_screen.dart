import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../common/config.dart';
import '../../services/index.dart';
import '../base_screen.dart';

class PaymentWebview extends StatefulWidget {
  final String? url;
  final Function? onFinish;
  final Function? onClose;
  final String? token;

  const PaymentWebview({this.onFinish, this.onClose, this.url, this.token});

  @override
  State<StatefulWidget> createState() => PaymentWebviewState();
}

class PaymentWebviewState extends BaseScreen<PaymentWebview> {
  late final WebViewController _controller;
  Timer? _pollTimer;
  bool _finished = false;
  String? _orderId;

  // Injected on every poll tick via runJavaScript.
  // Posts JSON { url, orderId } back via CheckoutPoll channel.
  // Works for:
  //   New Shopify checkout (SPA)  → scans <p> for "Confirmation #XXXXX"
  //   Legacy Shopify theme        → .os-order-number element
  //   Other patterns              → handled in Dart via URL matching
  static const _kPollScript = r'''
(function() {
  var result = { url: location.href, orderId: null };
  var isThankYou = result.url.indexOf('thank_you') > -1
                || result.url.indexOf('thank-you') > -1;

  if (isThankYou) {
    // New Shopify checkout: look for "Confirmation #XXXXX" in any <p>
    var ps = document.querySelectorAll('p');
    for (var i = 0; i < ps.length; i++) {
      var t = (ps[i].innerText || ps[i].textContent || '').trim();
      if (t.indexOf('Confirmation #') === 0) {
        result.orderId = t.replace('Confirmation #', '').trim();
        break;
      }
    }
    // Legacy theme fallback
    if (!result.orderId) {
      var el = document.querySelector('.os-order-number');
      if (el) result.orderId = (el.innerText || el.textContent || '').replace(/\D/g, '') || null;
    }
  }
  window.CheckoutPoll.postMessage(JSON.stringify(result));
})();
''';

  @override
  void initState() {
    super.initState();
    _buildController();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  void _buildController() {
    var url = '';
    var headers = <String, String>{};

    if (widget.url != null) {
      url = widget.url!;
    } else {
      final info = Services().widget.getPaymentUrl(context)!;
      url = info['url'] as String? ?? '';
      if (info['headers'] != null) {
        headers = Map<String, String>.from(info['headers']);
      }
    }
    if (widget.token != null) {
      headers['X-Shopify-Customer-Access-Token'] = widget.token!;
    }

    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..addJavaScriptChannel('CheckoutPoll', onMessageReceived: _onPollMessage)
      ..setNavigationDelegate(NavigationDelegate(
        onPageFinished: (u) {
          if (!_finished) _startPolling();
        },
      ))
      ..loadRequest(Uri.parse(url), headers: headers);
  }

  void _startPolling() {
    _pollTimer?.cancel();
    // 800 ms is fast enough to feel instant on a SPA transition
    _pollTimer = Timer.periodic(const Duration(milliseconds: 800), (_) {
      if (_finished) { _pollTimer?.cancel(); return; }
      _controller.runJavaScript(_kPollScript);
    });
  }

  void _onPollMessage(JavaScriptMessage msg) {
    if (_finished) return;
    try {
      final data = jsonDecode(msg.message) as Map<String, dynamic>;
      final url     = (data['url']     as String?) ?? '';
      final orderId = (data['orderId'] as String?);

      debugPrint('[PaymentWebview] poll url=$url orderId=$orderId');

      // Dart-side URL pattern checks (WooCommerce, PrestaShop, etc.)
      _checkUrlPatterns(url);

      // New Shopify SPA / legacy theme: JS already extracted the ID
      if (orderId != null && orderId.isNotEmpty) {
        _resolve(orderId);
      }
    } catch (e) {
      debugPrint('[PaymentWebview] poll parse error: $e');
    }
  }

  void _checkUrlPatterns(String url) {
    if (_finished) return;

    if (url.contains('/order-received/')) {
      final parts = url.split('/order-received/');
      if (parts.length > 1) { _resolve(parts[1].split('/')[0]); return; }
    }
    if (url.contains('checkout/success')) { _resolve('0'); return; }
    if (url.contains('/checkout/order-confirmation')) { _resolve('0'); return; }
    if (url.contains('/order-confirmation')) {
      final id = Uri.tryParse(url)?.queryParameters['id_order'] ?? '0';
      _resolve(id);
      return;
    }
    if (url.contains('/member-login/')) {
      _resolve('0');
      Navigator.of(context).pop();
      return;
    }
    if (url.contains('common/home')) {
      Navigator.of(context).pop();
      return;
    }
  }

  void _resolve(String orderId) {
    if (_finished) return;
    _finished = true;
    _orderId  = orderId;
    _pollTimer?.cancel();
    debugPrint('[PaymentWebview] ✓ resolved orderId=$orderId');
    widget.onFinish?.call(orderId);
    if (kPaymentConfig.showWebviewCheckoutSuccessScreen) {
      if (mounted) Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        widget.onFinish?.call(_orderId);
        widget.onClose?.call();
        return true;
      },
      child: WebViewWidget(controller: _controller),
    );
  }
}