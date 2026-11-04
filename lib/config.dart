import 'package:shared_preferences/shared_preferences.dart';

/// Broker + device settings, shared by the UI and the Android background service.
class AppConfig {
  AppConfig({
    required this.host,
    required this.port,
    required this.user,
    required this.pass,
    required this.deviceId,
  });

  final String host;
  final int port;
  final String user;
  final String pass;
  final String deviceId; // e.g. TALM-A1B2C3, shown on the device login page

  bool get isValid => host.isNotEmpty && deviceId.isNotEmpty;
  String get topicBase => 'templealarm/$deviceId';

  static Future<AppConfig> load() async {
    final p = await SharedPreferences.getInstance();
    await p.reload(); // the other isolate may have saved new values
    return AppConfig(
      host: p.getString('host') ?? '',
      port: p.getInt('port') ?? 8883,
      user: p.getString('user') ?? '',
      pass: p.getString('pass') ?? '',
      deviceId: p.getString('deviceId') ?? '',
    );
  }

  /// The device ID the user last logged in to (cleared on logout).
  static Future<String?> loggedInDevice() async =>
      (await SharedPreferences.getInstance()).getString('loggedInDevice');

  static Future<void> setLoggedIn(String? deviceId) async {
    final p = await SharedPreferences.getInstance();
    deviceId == null ? await p.remove('loggedInDevice') : await p.setString('loggedInDevice', deviceId);
  }

  Future<void> save() async {
    final p = await SharedPreferences.getInstance();
    await p.setString('host', host.trim());
    await p.setInt('port', port);
    await p.setString('user', user.trim());
    await p.setString('pass', pass);
    await p.setString('deviceId', deviceId.trim().toUpperCase());
  }
}
