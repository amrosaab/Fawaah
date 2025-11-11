import 'dart:convert';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart' as ph;

import '../../common/constants.dart';
import '../../models/entities/fstore_notification_item.dart';

abstract class NotificationService {
  bool _isInitialized = false;

  bool get isInitialized => _isInitialized;

  void setIsInitialized() {
    _isInitialized = true;
  }

  NotificationService() {
    _initializeLocalNotifications();
  }

  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
  FlutterLocalNotificationsPlugin();

  final AndroidNotificationChannel channel = const AndroidNotificationChannel(
    'high_importance_channel', // ID
    'High Importance Notifications', // Name
    description: 'This channel is used for important notifications.',
    importance: Importance.max,
  );

  late final NotificationDelegate delegate;

  void init({
    String? externalUserId,
    required NotificationDelegate notificationDelegate,
  });

  Future<void> _initializeLocalNotifications() async {
    const initSettings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: DarwinInitializationSettings(),
    );

    await flutterLocalNotificationsPlugin.initialize(
      initSettings,
      onDidReceiveNotificationResponse: (notificationResponse) {
        final payload = notificationResponse.payload ?? '{}';
        delegate.onMessageOpenedApp(
          FStoreNotificationItem(
            id: notificationResponse.id?.toString() ?? '',
            title: '',
            body: '',
            additionalData: jsonDecode(payload),
            date: DateTime.now(),
          ),
        );
      },
    );

    await flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);
  }

  Future<bool> requestPermission() async {
    if (kIsWeb) return false;

    // Handles both Android & iOS
    final status = await ph.Permission.notification.request();
    return status.isGranted;
  }

  Future<bool> isGranted() async {
    if (kIsWeb) return false;
    return await ph.Permission.notification.isGranted;
  }

  void disableNotification();

  void enableNotification();

  void setExternalId(String? userId);

  void removeExternalId();
}
mixin NotificationDelegate {
  void onMessage(FStoreNotificationItem notification);

  void onMessageOpenedApp(FStoreNotificationItem notification);
}
