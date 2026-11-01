import 'dart:io';
import 'dart:ui';

import 'package:flutter/widgets.dart';
import 'package:flutter_background_service/flutter_background_service.dart';

import 'alarm_link.dart';
import 'config.dart';
import 'notify.dart';

/// Android only: a foreground service keeps its own MQTT connection open so
/// alarm notifications arrive while the app is closed. macOS shows them from
/// the running app instead.
class AlertService {
  static Future<void> configure() async {
    if (!Platform.isAndroid) return;
    await FlutterBackgroundService().configure(
      androidConfiguration: AndroidConfiguration(
        onStart: _serviceMain,
        autoStart: true,
        autoStartOnBoot: true,
        isForegroundMode: true,
        notificationChannelId: Notifier.serviceChannel.id,
        initialNotificationTitle: 'Temple Alarm',
        initialNotificationContent: 'Watching for alerts',
        foregroundServiceNotificationId: 888,
        // specialUse has no daily time limit (dataSync is capped at 6 h/day on Android 15)
        foregroundServiceTypes: [AndroidForegroundType.specialUse],
      ),
      iosConfiguration: IosConfiguration(autoStart: false),
    );
  }

  /// Call after the broker settings change.
  static Future<void> reload() async {
    if (!Platform.isAndroid) return;
    final svc = FlutterBackgroundService();
    if (await svc.isRunning()) {
      svc.invoke('reload');
    } else {
      await svc.startService();
    }
  }
}

@pragma('vm:entry-point')
Future<void> _serviceMain(ServiceInstance service) async {
  DartPluginRegistrant.ensureInitialized();
  WidgetsFlutterBinding.ensureInitialized();
  await Notifier.init();

  AlarmLink? link;
  Future<void> start() async {
    link?.close();
    final cfg = await AppConfig.load();
    if (!cfg.isValid) return;
    final l = AlarmLink(cfg, clientTag: 'svc');
    l.onEvent = Notifier.handleEvent;
    l.addListener(() {
      if (service is AndroidServiceInstance) {
        final s = l.status;
        final state = s['alarm'] == true ? 'ALARM ACTIVE' : s['armed'] == true ? 'Armed' : 'Disarmed';
        service.setForegroundNotificationInfo(
          title: 'Temple Alarm · ${cfg.deviceId}',
          content: l.connected ? state : 'Reconnecting…',
        );
      }
    });
    link = l;
    await l.connect();
  }

  service.on('reload').listen((_) => start());
  service.on('stop').listen((_) async {
    link?.close();
    await service.stopSelf();
  });
  await start();
}
