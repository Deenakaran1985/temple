import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';

import 'config.dart';

/// MQTT connection to one alarm device.
///
/// Topics under templealarm/DEVICE-ID (see the firmware): status (retained
/// JSON), event (retained last event), online ("1"/"0"), cmd (we publish),
/// ack (command replies).
class AlarmLink extends ChangeNotifier {
  AlarmLink(this.cfg, {this.clientTag = 'app'});

  final AppConfig cfg;
  final String clientTag;

  MqttServerClient? _client;
  Timer? _retry;
  bool _closed = false;

  String connection = 'disconnected'; // connecting | connected | disconnected | error text
  bool deviceOnline = false;
  Map<String, dynamic> status = {};
  DateTime? statusAt;
  final List<Map<String, dynamic>> events = [];

  /// Called for every event message (new or retained); the notifier de-duplicates.
  void Function(Map<String, dynamic> event)? onEvent;

  bool get connected => connection == 'connected';
  String get _base => cfg.topicBase;

  Future<void> connect() async {
    _closed = false;
    _retry?.cancel();
    final id = '$clientTag-${cfg.deviceId}-${DateTime.now().millisecondsSinceEpoch}';
    final c = MqttServerClient.withPort(cfg.host, id, cfg.port)
      ..secure = cfg.port != 1883
      ..keepAlivePeriod = 30
      ..autoReconnect = true
      ..logging(on: false);
    c.connectionMessage =
        MqttConnectMessage().withClientIdentifier(id).authenticateAs(cfg.user, cfg.pass).startClean();
    c.onDisconnected = () => _set('disconnected');
    c.onAutoReconnect = () => _set('connecting');
    c.onAutoReconnected = () => _set('connected');
    _client = c;
    _set('connecting');

    try {
      await c.connect();
    } catch (e) {
      c.disconnect();
      _set('error: ${_short(e)}');
      _scheduleRetry();
      return;
    }
    if (c.connectionStatus?.state != MqttConnectionState.connected) {
      _set('error: ${c.connectionStatus?.returnCode}');
      _scheduleRetry();
      return;
    }
    for (final t in ['status', 'event', 'online', 'ack']) {
      c.subscribe('$_base/$t', MqttQos.atLeastOnce);
    }
    c.updates?.listen(_onMessages);
    _set('connected');
  }

  void _scheduleRetry() {
    if (_closed) return;
    _retry = Timer(const Duration(seconds: 15), connect);
  }

  void _onMessages(List<MqttReceivedMessage<MqttMessage>> msgs) {
    for (final m in msgs) {
      final pub = m.payload as MqttPublishMessage;
      final text = MqttPublishPayload.bytesToStringAsString(pub.payload.message);
      final topic = m.topic.substring(_base.length + 1);
      if (topic == 'online') {
        deviceOnline = text == '1';
      } else if (topic == 'status') {
        try {
          status = jsonDecode(text) as Map<String, dynamic>;
          statusAt = DateTime.now();
          deviceOnline = true;
        } catch (_) {}
      } else if (topic == 'event') {
        try {
          final e = jsonDecode(text) as Map<String, dynamic>;
          if (events.isEmpty || events.first['id'] != e['id']) {
            events.insert(0, e);
            if (events.length > 50) events.removeLast();
          }
          onEvent?.call(e);
        } catch (_) {}
      }
    }
    notifyListeners();
  }

  /// Sends a command such as arm, disarm, panic, stop_alarm, mute,
  /// volume(value), play(value), pair_zone(value), pair_next, unpair_zone(value), pair_remote.
  bool send(String cmd, [int? value]) {
    final c = _client;
    if (c == null || !connected) return false;
    final b = MqttClientPayloadBuilder()
      ..addString(jsonEncode({'cmd': cmd, 'value': ?value}));
    c.publishMessage('$_base/cmd', MqttQos.atLeastOnce, b.payload!);
    return true;
  }

  void close() {
    _closed = true;
    _retry?.cancel();
    final c = _client;
    if (c != null) {
      c.autoReconnect = false;
      c.disconnect();
    }
    _client = null;
  }

  void _set(String s) {
    connection = s;
    notifyListeners();
  }

  static String _short(Object e) {
    final s = e.toString();
    return s.length > 80 ? '${s.substring(0, 80)}…' : s;
  }

  @override
  void dispose() {
    close();
    super.dispose();
  }
}
