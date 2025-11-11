// import 'dart:async';
//
// import 'package:flutter/material.dart';
// import 'package:inspireui/inspireui.dart';
// import 'package:provider/provider.dart';
//
// import '../../../common/config.dart';
// import '../../../common/tools.dart';
// import '../../../common/tools/biometrics_tools.dart';
// import '../../../data/boxes.dart';
// import '../../../generated/l10n.dart';
// import '../../../models/index.dart';
// import '../../../services/index.dart';
// import '../../../widgets/auth/social_login_button_row.dart';
// import '../../../widgets/common/custom_text_field.dart';
// import '../../../widgets/common/flux_image.dart';
// import '../../../widgets/common/login_animation.dart';
// import '../../base_screen.dart';
// import 'mixins/mixin_animation_button_login.dart';
// import 'mixins/mixin_login.dart';
//
// class LoginScreen extends StatefulWidget {
//   const LoginScreen();
//
//   @override
//   BaseScreen<LoginScreen> createState() => _LoginPageState();
// }
//
// class _LoginPageState extends BaseScreen<LoginScreen>
//     with TickerProviderStateMixin, AnimationButtonLoginMixin, LoginMixin {
//   late BuildContext _parentContext;
//
//   final _usernameFocusNode = FocusNode();
//   final _passwordFocusNode = FocusNode();
//
//   Future _biometricsLogin(BuildContext context) async {
//     var didAuth = await BiometricsTools.instance.localAuth(context);
//     if (didAuth) {
//       usernameCtrl.text = BiometricsBox().username ?? '';
//       passwordCtrl.text = BiometricsBox().password ?? '';
//       _onTapLogin();
//     }
//   }
//
//   void _onTapLogin() {
//     final currentFocus = FocusScope.of(context);
//     if (!currentFocus.hasPrimaryFocus) {
//       currentFocus.unfocus();
//     }
//
//     runLogin(context);
//   }
//
//   @override
//   TextEditingController passwordCtrl = TextEditingController();
//
//   @override
//   TextEditingController usernameCtrl = TextEditingController();
//
//   @override
//   Future<void> beforeCallLogin() => playAnimation();
//
//   @override
//   Future<void> afterCallLogin(bool isLoginSuccess) => stopAnimation();
//
//   @override
//   void dispose() {
//     _usernameFocusNode.dispose();
//     _passwordFocusNode.dispose();
//     super.dispose();
//   }
//
//   @override
//   Widget build(BuildContext context) {
//     _parentContext = context;
//     final appModel = Provider.of<AppModel>(context);
//     final screenSize = MediaQuery.of(context).size;
//     final themeConfig = appModel.themeConfig;
//     var forgetPasswordUrl = ServerConfig().forgetPassword;
//
//     return Scaffold(
//       backgroundColor: Theme.of(context).colorScheme.background,
//       appBar: AppBar(
//         backgroundColor: Theme.of(context).colorScheme.background,
//         elevation: 0.0,
//         actions: !Services().widget.isRequiredLogin &&
//                 !ModalRoute.of(context)!.canPop
//             ? [
//                 IconButton(
//                   onPressed: loginDone,
//                   icon: const Icon(Icons.close, size: 25),
//                 )
//               ]
//             : null,
//       ),
//       body: SafeArea(
//         child: AutoHideKeyboard(
//           child: IgnorePointer(
//             ignoring: isLoading,
//             child: Center(
//               child: Consumer<UserModel>(
//                 builder: (context, model, child) {
//                   return Container(
//                     padding: const EdgeInsets.symmetric(horizontal: 24.0),
//                     alignment: Alignment.center,
//                     width: screenSize.width /
//                         (2 / (screenSize.height / screenSize.width)),
//                     constraints: const BoxConstraints(maxWidth: 700),
//                     child: AutofillGroup(
//                       child: Column(
//                         children: <Widget>[
//                           Expanded(
//                             flex: 1,
//                             child: FractionallySizedBox(
//                               widthFactor: 0.8,
//                               child: FluxImage(
//                                 imageUrl: themeConfig.logo,
//                                 fit: BoxFit.contain,
//                               ),
//                             ),
//                           ),
//                           Expanded(
//                             flex: 3,
//                             child: SingleChildScrollView(
//                               physics: const NeverScrollableScrollPhysics(),
//                               child: Column(
//                                 mainAxisSize: MainAxisSize.min,
//                                 children: [
//                                   const SizedBox(height: 20.0),
//                                   CustomTextField(
//                                     key: const Key('loginEmailField'),
//                                     controller: usernameCtrl,
//                                     autofillHints: const [AutofillHints.email],
//                                     showCancelIcon: true,
//                                     autocorrect: false,
//                                     enableSuggestions: false,
//                                     textInputAction: TextInputAction.next,
//                                     keyboardType: TextInputType.emailAddress,
//                                     nextNode: _usernameFocusNode,
//                                     decoration: InputDecoration(
//                                       labelText: S.of(_parentContext).username,
//                                       hintText: S
//                                           .of(_parentContext)
//                                           .enterYourEmailOrUsername,
//                                     ),
//                                     onSubmitted: (value) {
//                                       FocusScope.of(context).requestFocus(_passwordFocusNode);
//
//                                     },
//
//                                   ),
//                                   CustomTextField(
//                                     key: const Key('loginPasswordField'),
//                                     autofillHints: const [
//                                       AutofillHints.password
//                                     ],
//                                     obscureText: true,
//                                     showEyeIcon: true,
//                                     textInputAction: TextInputAction.done,
//                                     controller: passwordCtrl,
//                                     focusNode: _passwordFocusNode,
//                                     decoration: InputDecoration(
//                                       labelText: S.of(_parentContext).password,
//                                       hintText: S
//                                           .of(_parentContext)
//                                           .enterYourPassword,
//                                     ),
//                                   ),
//                                   if (kLoginSetting.isResetPasswordSupported)
//                                     Padding(
//                                       padding: const EdgeInsets.symmetric(
//                                           vertical: 12.0),
//                                       child: GestureDetector(
//                                         onTap: () {
//                                           launchForgetPasswordURL(
//                                               forgetPasswordUrl);
//                                         },
//                                         behavior: HitTestBehavior.opaque,
//                                         child: Padding(
//                                           padding: const EdgeInsets.all(12.0),
//                                           child: Text(
//                                             S.of(context).resetPassword,
//                                             style: TextStyle(
//                                               color: Theme.of(context)
//                                                   .primaryColor,
//                                               // decoration:
//                                               //     TextDecoration.underline,
//                                             ),
//                                           ),
//                                         ),
//                                       ),
//                                     ),
//                                   if (!kLoginSetting.isResetPasswordSupported)
//                                     const SizedBox(height: 50.0),
//                                   StaggerAnimation(
//                                     key: const Key('loginSubmitButton'),
//                                     titleButton: S.of(context).signInWithEmail,
//                                     buttonController: loginButtonController.view
//                                         as AnimationController,
//                                     onTap: () =>
//                                         isLoading ? null : _onTapLogin(),
//                                   ),
//                                   if (BiometricsTools.instance.isLoginSupported)
//                                     Padding(
//                                       padding: const EdgeInsets.only(top: 10),
//                                       child: IconButton(
//                                         iconSize: 50,
//                                         onPressed: () =>
//                                             _biometricsLogin(context),
//                                         icon: const Icon(
//                                             Icons.fingerprint_outlined),
//                                       ),
//                                     ),
//                                   Stack(
//                                     alignment: AlignmentDirectional.center,
//                                     children: <Widget>[
//
//                                       Container(
//                                           height: 30,
//                                           width: 40,
//                                           color: Theme.of(context)
//                                               .colorScheme
//                                               .background),
//                                       if (kLoginSetting.showFacebook ||
//                                           kLoginSetting.showSMSLogin ||
//                                           kLoginSetting.showGoogleLogin ||
//                                           kLoginSetting.showAppleLogin)
//                                         Text(
//                                           S.of(context).or,
//                                           style: TextStyle(
//                                               fontSize: 12,
//                                               color: Colors.grey.shade400),
//                                         )
//                                     ],
//                                   ),
//                                   SocialLoginButtonRow(
//                                     onApplePressed: () =>
//                                         loginWithApple(context),
//                                     onFacebookPressed: () =>
//                                         loginWithFacebook(context),
//                                     onGooglePressed: () =>
//                                         loginWithGoogle(context),
//                                     onSmsPressed: () => loginWithSMS(context),
//                                   ),
//                                   const SizedBox(height: 30.0),
//                                   Column(
//                                     children: <Widget>[
//                                       Row(
//                                         mainAxisAlignment:
//                                             MainAxisAlignment.center,
//                                         children: <Widget>[
//                                           Text(S.of(context).dontHaveAccount),
//                                           GestureDetector(
//                                             onTap: () {
//                                               NavigateTools.navigateRegister(
//                                                   context);
//                                             },
//                                             child: Text(
//                                               ' ${S.of(context).signup}',
//                                               style: TextStyle(
//                                                 fontWeight: FontWeight.bold,
//                                                 color: Theme.of(context)
//                                                     .primaryColor,
//                                               ),
//                                             ),
//                                           ),
//                                         ],
//                                       ),
//                                     ],
//                                   ),
//                                   const SizedBox(height: 30.0),
//                                 ],
//                               ),
//                             ),
//                           ),
//                         ],
//                       ),
//                     ),
//                   );
//                 },
//               ),
//             ),
//           ),
//         ),
//       ),
//     );
//   }
// }

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:inspireui/inspireui.dart';
import 'package:provider/provider.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../../common/config.dart';
import '../../../common/tools.dart';
import '../../../common/tools/biometrics_tools.dart';
import '../../../common/tools/flash.dart';
import '../../../data/boxes.dart';
import '../../../generated/l10n.dart';
import '../../../models/index.dart';
import '../../../services/index.dart';
import '../../../widgets/auth/social_login_button_row.dart';
import '../../../widgets/common/custom_text_field.dart';
import '../../../widgets/common/flux_image.dart';
import '../../../widgets/common/login_animation.dart';
import '../../base_screen.dart';
import 'mixins/mixin_animation_button_login.dart';
import 'mixins/mixin_login.dart';

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
  Future<void> beforeCallLogin() async {
    // Empty implementation
  }

  @override
  Future<void> afterCallLogin(bool isLoginSuccess) async {
    // Empty implementation
  }

  Future<void> _handleAuthSuccess(String accessToken, Map<String, dynamic> userData) async {
    try {
      // Create user with access token
      final user = User();
      user.email = userData['email'] ?? '';
      user.cookie = accessToken;
      user.isSocial = false;

      print("Access token received: $accessToken");

      // Save user to your app
      final userModel = Provider.of<UserModel>(context, listen: false);
      await userModel.getUserfromacsses(accessToken);

      // Navigate to home/dashboard
      loginDone();
    } catch (e) {
      FlashHelper.errorMessage(context, message: 'Login failed: $e');
    }
  }

  void _handleAuthError(String error) {
    FlashHelper.errorMessage(context, message: error);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.background,
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.background,
        elevation: 0.0,
        title: const Text('Sign In'),
        actions: !Services().widget.isRequiredLogin &&
            !ModalRoute.of(context)!.canPop
            ? [
          IconButton(
            onPressed: loginDone,
            icon: const Icon(Icons.close, size: 25),
          )
        ]
            : null,
      ),
      body: SafeArea(
        child: FawaahAuthWebView(
          onSuccess: _handleAuthSuccess,
          onError: _handleAuthError,
          onCancel: () {
            // Handle cancel if needed
          },
        ),
      ),
    );
  }
}

// WebView Authentication Screen
class FawaahAuthWebView extends StatefulWidget {
  final Function(String accessToken, Map<String, dynamic> userData) onSuccess;
  final Function(String error) onError;
  final VoidCallback? onCancel;

  const FawaahAuthWebView({
    Key? key,
    required this.onSuccess,
    required this.onError,
    this.onCancel,
  }) : super(key: key);

  @override
  State<FawaahAuthWebView> createState() => _FawaahAuthWebViewState();
}

class _FawaahAuthWebViewState extends State<FawaahAuthWebView> {
  late WebViewController _controller;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _initializeWebView();
  }

  void _initializeWebView() {
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (String url) {
            setState(() => _isLoading = true);
          },
          onPageFinished: (String url) {
            setState(() => _isLoading = false);
            _checkForAuthResult(url);
          },
        ),
      )
      ..addJavaScriptChannel(
        'FawaahAuth',
        onMessageReceived: (JavaScriptMessage message) {
          _handleMessage(message.message);
        },
      );

    // Load your authentication page directly
    final authUrl = 'https://account.fawaah.com/?mode=app';
    _controller.loadRequest(Uri.parse(authUrl));
  }

  void _checkForAuthResult(String url) async {
    // Check if redirected to orders page (successful verification)
    if (url.contains('/orders') || url.contains('account.fawaah.com/orders')) {
      try {
        // Make GET request to token endpoint to get access token
        await _getAccessToken();
      } catch (e) {
        widget.onError('Failed to get access token: $e');
      }
    } else if (url.contains('error=') || url.contains('cancelled=true')) {
      final uri = Uri.parse(url);
      final error = uri.queryParameters['error'] ?? 'Authentication failed';
      widget.onError(error);
    }
  }

  Future<void> _getAccessToken() async {
    try {
      // Inject JavaScript to make GET request to token endpoint
      await _controller.runJavaScript('''
        fetch('https://account.fawaah.com/oauth/token', {
          method: 'GET',
          credentials: 'include', // Include cookies from the session
          headers: {
            'Accept': 'application/json',
            'Content-Type': 'application/json'
          }
        })
        .then(response => response.json())
        .then(data => {
          if (data.access_token) {
            if (window.FawaahAuth) {
              window.FawaahAuth.postMessage(JSON.stringify({
                type: 'auth_success',
                access_token: data.access_token,
                expires_in: data.expires_in || 3600,
                user_data: {
                  email: ''
                }
              }));
            }
          } else {
            if (window.FawaahAuth) {
              window.FawaahAuth.postMessage(JSON.stringify({
                type: 'auth_error',
                message: 'No access token received'
              }));
            }
          }
        })
        .catch(error => {
          if (window.FawaahAuth) {
            window.FawaahAuth.postMessage(JSON.stringify({
              type: 'auth_error',
              message: 'Failed to get token: ' + error.message
            }));
          }
        });
      ''');
    } catch (e) {
      widget.onError('JavaScript execution failed: $e');
    }
  }

  void _handleMessage(String message) {
    try {
      print("WebView message received: $message");
      final data = json.decode(message);


      switch (data['type']) {
        case 'auth_success':
          widget.onSuccess(data['access_token'], data['user_data'] ?? {});

          break;
        case 'auth_error':
          widget.onError(data['message'] ?? 'Authentication failed');
          break;
        case 'auth_cancel':
          widget.onCancel?.call();
          break;
      }
    } catch (e) {
      print('Error parsing message: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        WebViewWidget(controller: _controller),
        if (_isLoading)
          const Center(child: CircularProgressIndicator()),
      ],
    );
  }
}