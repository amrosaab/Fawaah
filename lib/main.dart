import 'dart:async';
import 'dart:io' show HttpClient, SecurityContext;

import 'package:flutter/foundation.dart' as foundation;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';

import 'package:flux_firebase/index.dart';
import 'package:provider/provider.dart';
import 'package:responsive_builder/responsive_builder.dart';
import 'package:universal_platform/universal_platform.dart';

import 'app.dart';
import 'common/config.dart';
import 'common/constants.dart';
import 'common/tools.dart';
import 'common/tools/biometrics_tools.dart';
import 'data/boxes.dart';
import 'env.dart';
import 'modules/webview/index.dart';
import 'services/dependency_injection.dart';
import 'services/locale_service.dart';
import 'services/services.dart';

Future<void> _firebaseMessagingBackgroundHandler(dynamic message) async {

}

Future<void> _setupApplication() async {
  Configurations().setConfigurationValues(environment);

  /// Fix issue android sdk version 22 can not run the app.
  if (UniversalPlatform.isAndroid) {
    SecurityContext.defaultContext
        .setTrustedCertificatesBytes(Uint8List.fromList(isrgRootX1.codeUnits));
  }

  /// Support Webview (iframe) for Flutter Web. Requires this below header.
  /// Content-Security-Policy: frame-ancestors 'self' *.yourdomain.com
  registerWebViewWebImplementation();

  /// Hide status bar for splash screen
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.leanBack);

  Provider.debugCheckInvalidValueType = null;

  LicenseRegistry.addLicense(() async* {
    final license = await rootBundle.loadString('google_fonts/OFL.txt');
    yield LicenseEntryWithLineBreaks(['google_fonts'], license);
  });

  var app=  await Firebase.initializeApp();
  printLog('Handling a background message ${app.options}');

  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
}

void main() {
  printLog('[main] ===== START main.dart =======');

  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();

    /// Call the setup for the application.
    _setupApplication();

    /// get language code default
    var languageCode = kAdvanceConfig.defaultLanguage;

    try{
      await initBoxes();

    }catch(e){
      print("messagrr${e}");
    }


    if (!foundation.kIsWeb) {
      /// Enable network traffic logging.
      HttpClient.enableTimelineLogging = !foundation.kReleaseMode;

      /// Lock portrait mode.
      unawaited(SystemChrome.setPreferredOrientations(
          [DeviceOrientation.portraitUp]));
    }

    await GmsCheck().checkGmsAvailability(enableLog: foundation.kDebugMode);
    const fatalError = true;

    try {
      if (isMobile) {
        /// Init Firebase settings due to version 0.5.0+ requires to.
        /// Use await to prevent any usage until the initialization is completed.
        await Services().firebase.init();
        await Configurations().loadRemoteConfig();
        await BiometricsTools.instance.init();

        FlutterError.onError = (errorDetails) {
          if (fatalError) {
            // If you want to record a "fatal" exception
            FirebaseCrashlytics.instance.recordFlutterFatalError(errorDetails);
            // ignore: dead_code
          } else {
            // If you want to record a "non-fatal" exception
            FirebaseCrashlytics.instance.recordFlutterError(errorDetails);
          }
        };
        // Async exceptions
        PlatformDispatcher.instance.onError = (error, stack) {
          if (fatalError) {
            // If you want to record a "fatal" exception
            FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
            // ignore: dead_code
          } else {
            // If you want to record a "non-fatal" exception
            FirebaseCrashlytics.instance.recordError(error, stack);
          }
          return true;
        };
      }
    } catch (e) {
      printLog(e);
      printLog('🔴 Firebase init issue');
    }

    await DependencyInjection.inject();
    Services().setAppConfig(serverConfig);

    if (isMobile && kAdvanceConfig.autoDetectLanguage) {
      final lang = SettingsBox().languageCode;

      if (lang?.isEmpty ?? true) {
        languageCode = await LocaleService().getDeviceLanguage();
      } else {
        languageCode = lang.toString();
      }
    }

    if (serverConfig['type'] == 'vendorAdmin') {
      return runApp(Services()
          .getVendorAdminApp(languageCode: languageCode, isFromMV: false));
    }

    if (serverConfig['type'] == 'delivery') {
      return runApp(Services()
          .getDeliveryApp(languageCode: languageCode, isFromMV: false));
    }

    ResponsiveSizingConfig.instance.setCustomBreakpoints(
        const ScreenBreakpoints(desktop: 900, tablet: 600, watch: 100));
    runApp(App(languageCode: languageCode));
  }, printError);
}
