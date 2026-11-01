import 'dart:io';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Local notifications for alarm events received over MQTT.
class Notifier {
  static final _plugin = FlutterLocalNotificationsPlugin();
  static bool _ready = false;

  static const alarmChannel = AndroidNotificationChannel(
    'alarm', 'Alarm alerts',
    description: 'A sensor or panic button triggered the alarm',
    importance: Importance.max,
  );
  static const infoChannel = AndroidNotificationChannel(
    'info', 'Status changes',
    description: 'Armed, disarmed, alarm stopped, sensor paired',
    importance: Importance.defaultImportance,
  );
  static const serviceChannel = AndroidNotificationChannel(
    'service', 'Background connection',
    description: 'Keeps the alarm connection open while the app is closed',
    importance: Importance.low,
  );

  static const _darwinInit = DarwinInitializationSettings(
    requestAlertPermission: false,
    requestBadgePermission: false,
    requestSoundPermission: false,
  );

  static Future<void> init() async {
    if (_ready) return;
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: _darwinInit,
        macOS: _darwinInit,
      ),
    );
    final android = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    for (final ch in [alarmChannel, infoChannel, serviceChannel]) {
      await android?.createNotificationChannel(ch);
    }
    _ready = true;
  }

  /// Ask once, from the UI (Android 13+, iOS and macOS need the user's consent).
  static Future<void> requestPermission() async {
    if (Platform.isAndroid) {
      await _plugin
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
          ?.requestNotificationsPermission();
    } else if (Platform.isMacOS) {
      await _plugin
          .resolvePlatformSpecificImplementation<MacOSFlutterLocalNotificationsPlugin>()
          ?.requestPermissions(alert: true, badge: true, sound: true);
    } else if (Platform.isIOS) {
      await _plugin
          .resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>()
          ?.requestPermissions(alert: true, badge: true, sound: true);
    }
  }

  /// Shows a notification for an event the phone has not seen yet.
  /// The device keeps its last event retained, so the same event arrives again
  /// after every reconnect; the stored id filters those repeats.
  static Future<void> handleEvent(Map<String, dynamic> e) async {
    final id = e['id']?.toString();
    if (id == null) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    final last = prefs.getString('lastEventId');
    if (last == id) return;
    await prefs.setString('lastEventId', id);
    if (last == null) return; // first connection: don't replay an old event

    final isAlarm = e['type'] == 'alarm';
    final ch = isAlarm ? alarmChannel : infoChannel;
    await init();
    final darwin = DarwinNotificationDetails(
      presentSound: true,
      interruptionLevel: isAlarm ? InterruptionLevel.timeSensitive : InterruptionLevel.active,
    );
    await _plugin.show(
      id: id.hashCode & 0x7fffffff,
      title: isAlarm ? 'ALARM – Temple Alarm' : 'Temple Alarm',
      body: e['msg']?.toString() ?? e['type'].toString(),
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          ch.id, ch.name,
          channelDescription: ch.description,
          importance: ch.importance,
          priority: isAlarm ? Priority.max : Priority.defaultPriority,
          category: isAlarm ? AndroidNotificationCategory.alarm : AndroidNotificationCategory.status,
          ticker: e['msg']?.toString(),
        ),
        iOS: darwin,
        macOS: darwin,
      ),
    );
  }
}
