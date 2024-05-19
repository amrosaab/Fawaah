import 'dart:convert';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:onesignal_flutter/onesignal_flutter.dart';

import '../../models/entities/fstore_notification_item.dart';
import '../../services/notification/notification_service.dart';

class OneSignalNotificationService extends NotificationService {
  // final _instance = OneSignal;
  final String appID;

  OneSignalNotificationService({required this.appID}) {
    OneSignal.initialize(appID);
  }

  @override
  void disableNotification() {
    OneSignal.Notifications.requestPermission(false);
  }

  @override
  void enableNotification() {
    OneSignal.Notifications.requestPermission(true);
  }

  @override
  void init({
    String? externalUserId,
    required NotificationDelegate notificationDelegate,
  }) {
    OneSignal.login(externalUserId ?? '');
    delegate = notificationDelegate;
    _setupOnMessageOpenedApp();
    _setupOnMessage();
  }

  void _setupOnMessageOpenedApp() {
    OneSignal.Notifications.addClickListener(( result) {
      final data = result.notification;
      delegate.onMessageOpenedApp(FStoreNotificationItem(
        id: data.notificationId,
        title: data.title ?? '',
        body: data.body ?? '',
        additionalData: data.additionalData,
        date: DateTime.now(),
      ));
    });
  }

  void _setupOnMessage() {
    OneSignal.Notifications.addForegroundWillDisplayListener((
        ( result) {
      final data = result.notification;
      //
      // _instance.completeNotification(
      //   result.notification.notificationId,
      //   false,
      // );

      flutterLocalNotificationsPlugin.show(
        data.hashCode,
        data.title,
        data.body,
        payload: jsonEncode(data.additionalData),
        NotificationDetails(
          android: AndroidNotificationDetails(
            channel.id,
            channel.name,
            channelDescription: channel.description,
            icon:
                data.largeIcon ?? data.smallIcon ?? 'ic_stat_onesignal_default',
          ),
          iOS: const DarwinNotificationDetails(),
        ),
      );
    }));
  }

  @override
  void setExternalId(String? userId) async {
    if (userId != null) {
      await OneSignal.login(userId);
    }
  }

  @override
  void removeExternalId() async {
    OneSignal.logout();
  }
}
