import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:nsd/nsd.dart' as nsd;

import 'config.dart';

/// An alarm found on the phone's current WiFi.
class FoundDevice {
  const FoundDevice(this.id, this.ip);
  final String id; // e.g. TALM-A1B2C3
  final String ip;
}

/// Looks for alarms on the local WiFi: mDNS (_templealarm._tcp, advertised by
/// the firmware once it is on the home WiFi) plus the device's own hotspot
/// address, where mDNS is not running.
class DeviceFinder extends ChangeNotifier {
  static const _hotspotIp = '192.168.4.1';

  final List<FoundDevice> devices = [];
  bool searching = false;
  nsd.Discovery? _discovery;
  Timer? _stopTimer;

  Future<void> search() async {
    await stop();
    devices.clear();
    searching = true;
    notifyListeners();

    unawaited(_probe(_hotspotIp));
    try {
      final d = await nsd.startDiscovery('_templealarm._tcp', ipLookupType: nsd.IpLookupType.v4);
      _discovery = d;
      d.addServiceListener((s, status) {
        if (status != nsd.ServiceStatus.found) return;
        final ip = s.addresses?.firstOrNull?.address;
        final id = s.txt?['id'];
        if (ip == null) return;
        id != null ? _add(FoundDevice(utf8.decode(id), ip)) : _probe(ip);
      });
    } catch (_) {
      // No multicast on this network: the hotspot probe and manual IP still work
    }
    _stopTimer = Timer(const Duration(seconds: 15), stop);
  }

  Future<void> stop() async {
    _stopTimer?.cancel();
    final d = _discovery;
    _discovery = null;
    if (d != null) {
      try {
        await nsd.stopDiscovery(d);
      } catch (_) {}
    }
    if (searching) {
      searching = false;
      notifyListeners();
    }
  }

  /// Asks an address for its device info; adds it to the list if it is an alarm.
  Future<FoundDevice?> _probe(String ip) async {
    final dev = await probe(ip);
    if (dev != null) _add(dev);
    return dev;
  }

  static Future<FoundDevice?> probe(String ip) async {
    try {
      final r = await http.get(Uri.http(ip, '/api/info')).timeout(const Duration(seconds: 4));
      final id = (jsonDecode(r.body) as Map<String, dynamic>)['deviceID'] as String?;
      return id == null || id.isEmpty ? null : FoundDevice(id, ip);
    } catch (_) {
      return null;
    }
  }

  void _add(FoundDevice dev) {
    if (devices.any((d) => d.id == dev.id)) return;
    devices.add(dev);
    notifyListeners();
  }

  @override
  void dispose() {
    stop();
    super.dispose();
  }
}

/// Logs in to the device web login over the local network and, on success,
/// saves the Device ID + broker details the device hands back.
/// Returns null on success, otherwise a message for the user.
Future<String?> setupFromDevice(String ip, String user, String pass) async {
  final http.Response r;
  try {
    r = await http
        .post(Uri.http(ip, '/api/applogin'), body: {'username': user, 'password': pass})
        .timeout(const Duration(seconds: 10));
  } on TimeoutException {
    return 'No reply from the device at $ip';
  } on SocketException {
    return 'Cannot reach the device at $ip – is the phone on the same WiFi?';
  } catch (e) {
    return 'Connection failed: $e';
  }
  final Map<String, dynamic> d;
  try {
    d = jsonDecode(r.body) as Map<String, dynamic>;
  } catch (_) {
    return 'Unexpected reply (HTTP ${r.statusCode}) – update the device firmware';
  }
  if (d['ok'] != true) return d['msg']?.toString() ?? 'Login failed';
  final mq = d['mqtt'] as Map<String, dynamic>;
  final cfg = AppConfig(
    host: mq['host'] as String,
    port: mq['port'] as int,
    user: mq['user'] as String? ?? '',
    pass: mq['pass'] as String? ?? '',
    deviceId: d['deviceID'] as String,
  );
  await cfg.save();
  await AppConfig.setLoggedIn(cfg.deviceId.trim().toUpperCase());
  return null;
}
