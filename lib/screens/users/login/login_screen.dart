import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../../app.dart';
import '../../../common/constants.dart';
import '../../../common/events.dart';
import '../../../common/tools/flash.dart';
import '../../../models/index.dart';
import '../../../services/index.dart';
import '../../base_screen.dart';
import 'mixins/mixin_animation_button_login.dart';
import 'mixins/mixin_login.dart';
import '../../../frameworks/shopify/services/shopify_token_store.dart';

// ─────────────────────────────────────────────────────────────────────────────
// LoginScreen
// ─────────────────────────────────────────────────────────────────────────────

class LoginScreen extends StatefulWidget {
  const LoginScreen();

  @override
  BaseScreen<LoginScreen> createState() => _LoginPageState();
}

class _LoginPageState extends BaseScreen<LoginScreen>
    with TickerProviderStateMixin, AnimationButtonLoginMixin, LoginMixin {

  @override
  TextEditingController passwordCtrl = TextEditingController();
  @override
  TextEditingController usernameCtrl = TextEditingController();
  @override
  Future<void> beforeCallLogin() async {}
  @override
  Future<void> afterCallLogin(bool isLoginSuccess) async {}

  Future<void> _handleShcatToken(String shcatToken) async {
    try {
      print('asdsadsad');
      if (!mounted) return;




      final userModel = Provider.of<UserModel>(context, listen: false);
      final nav = Navigator.of(context); // capture before async gap

      await userModel.loginWithShcatToken(shcatToken);


      loginDone();

      if (nav.canPop()) {
        nav.pop();
      } else {
        nav.pushReplacementNamed(RouteList.dashboard);
      }
    } catch (e) {
      if (mounted) {
        // FlashHelper.errorMessage(context, message: 'Login failed: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.background,
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.background,
        elevation: 0,
        title: const Text('Sign In'),
        actions: !Services().widget.isRequiredLogin &&
            !(ModalRoute.of(context)?.canPop ?? false)
            ? [IconButton(onPressed: loginDone, icon: const Icon(Icons.close))]
            : null,
      ),
      body: SafeArea(
        child: FawaahAuthWebView(
          onShcatToken: _handleShcatToken,
          onError: (err) {
            // if (mounted) FlashHelper.errorMessage(context, message: err);
          },
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// FawaahAuthWebView
// ─────────────────────────────────────────────────────────────────────────────

class FawaahAuthWebView extends StatefulWidget {
  final Future<void> Function(String shcatToken) onShcatToken;
  final void Function(String error) onError;

  const FawaahAuthWebView({
    Key? key,
    required this.onShcatToken,
    required this.onError,
  }) : super(key: key);

  @override
  State<FawaahAuthWebView> createState() => _FawaahAuthWebViewState();
}

class _FawaahAuthWebViewState extends State<FawaahAuthWebView> {
  late final WebViewController _controller;
  bool _isLoading = true;
  bool _done      = false;

  Future<void> _handleShcatToken(String shcatToken) async {
    try {
      print('asdsadsad');
      if (!mounted) return;




      final userModel = Provider.of<UserModel>(context, listen: false);
      final nav = Navigator.of(context); // capture before async gap

      await userModel.loginWithShcatToken(shcatToken);

      eventBus.fire(const EventLoggedIn());

      if (nav.canPop()) {
        nav.pop();
      } else {
        nav.pushReplacementNamed(RouteList.dashboard);
      }
    } catch (e) {
      if (mounted) {
        // FlashHelper.errorMessage(context, message: 'Login failed: $e');
      }
    }
  }

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..addJavaScriptChannel('FawaahAuth', onMessageReceived: _onJsMessage)
      ..setNavigationDelegate(NavigationDelegate(
        onPageStarted: (_) {
          if (!_done && mounted) setState(() => _isLoading = true);
        },
        onPageFinished: (url) {
          if (!_done && mounted) setState(() => _isLoading = false);
          _onPageFinished(url);
        },
      ))
      ..loadRequest(Uri.parse('https://account.fawaah.com/?mode=app'));
  }

  void _onPageFinished(String url) {
    if (_done) return;
    if (url.contains('account.fawaah.com') &&
        (url.contains('/orders') ||
            url == 'https://account.fawaah.com/' ||
            url.contains('/profile') ||
            url.contains('/account'))) {
      _exchangeToken();
    }
  }

  Future<void> _exchangeToken() async {
    if (_done) return;
    await _controller.runJavaScript(r'''
(async function() {
  try {
    const resp = await fetch('https://account.fawaah.com/oauth/token', {
      method: 'GET',
      credentials: 'include',
      headers: { 'Accept': 'application/json' }
    });
    const data = await resp.json();
    if (data.access_token && data.access_token.startsWith('shcat_')) {
      FawaahAuth.postMessage(JSON.stringify({
        type: 'token',
        access_token: data.access_token,
        refresh_token: data.refresh_token || null,
        expires_in: data.expires_in || 7200
      }));
    } else {
      FawaahAuth.postMessage(JSON.stringify({
        type: 'error',
        message: 'unexpected: ' + JSON.stringify(data)
      }));
    }
  } catch(e) {
    FawaahAuth.postMessage(JSON.stringify({ type: 'error', message: e.toString() }));
  }
})();
''');
  }

  void _onJsMessage(JavaScriptMessage message) {
    if (_done) return;
    try {
      final data = jsonDecode(message.message) as Map<String, dynamic>;
      if (data['type'] == 'token') {
        _done = true;
        final accessToken  = data['access_token']  as String;
        final refreshToken = data['refresh_token']  as String?;
        final expiresIn    = (data['expires_in'] as num?)?.toInt() ?? 7200;

        debugPrint('FawaahAuth: shcat_ received (${accessToken.substring(0, 20)}...) '
            'refresh=${refreshToken != null} expiresIn=${expiresIn}s');

        ShopifyTokenStore.save(
          accessToken:  accessToken,
          refreshToken: refreshToken,
          expiresIn:    expiresIn,
        ).then((_) {

          _handleShcatToken(accessToken);
          // WidgetsBinding.instance.addPostFrameCallback((_) {
          //   widget.onShcatToken(accessToken);
          // });
        });
      } else {
        final err = data['message'] as String? ?? 'Unknown error';
        debugPrint('FawaahAuth: JS error: $err');
        widget.onError(err);
      }
    } catch (e) {
      debugPrint('FawaahAuth: parse error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        WebViewWidget(controller: _controller),
        if (_isLoading) const Center(child: CircularProgressIndicator()),
      ],
    );
  }
}