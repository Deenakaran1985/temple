import 'dart:io';

import 'package:flutter/material.dart';

import 'alarm_link.dart';
import 'background.dart';
import 'config.dart';
import 'notify.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Notifier.init();
  await AlertService.configure();
  runApp(const TempleAlarmApp());
}

class TempleAlarmApp extends StatelessWidget {
  const TempleAlarmApp({super.key});

  @override
  Widget build(BuildContext context) {
    ThemeData theme(Brightness b) => ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFFD97706), brightness: b),
          useMaterial3: true,
        );
    return MaterialApp(
      title: 'Temple Alarm',
      theme: theme(Brightness.light),
      darkTheme: theme(Brightness.dark),
      home: const RootPage(),
    );
  }
}

/// Loads the saved settings; first run goes straight to the settings form.
class RootPage extends StatefulWidget {
  const RootPage({super.key});
  @override
  State<RootPage> createState() => _RootPageState();
}

class _RootPageState extends State<RootPage> {
  AlarmLink? _link;
  bool _loading = true;
  bool _loggedIn = false;

  @override
  void initState() {
    super.initState();
    _start();
    Notifier.requestPermission();
  }

  Future<void> _start() async {
    _link?.dispose();
    final cfg = await AppConfig.load();
    AlarmLink? link;
    if (cfg.isValid) {
      link = AlarmLink(cfg);
      // Android: the background service notifies. iOS / macOS: the app itself does.
      if (Platform.isMacOS || Platform.isIOS) link.onEvent = Notifier.handleEvent;
      link.connect();
    }
    // A login only counts for the device it was made to
    final loggedIn = cfg.isValid && await AppConfig.loggedInDevice() == cfg.deviceId;
    setState(() {
      _link = link;
      _loggedIn = loggedIn;
      _loading = false;
    });
  }

  Future<void> _onLoggedIn() async {
    await AppConfig.setLoggedIn(_link!.cfg.deviceId);
    setState(() => _loggedIn = true);
  }

  Future<void> _logout() async {
    await AppConfig.setLoggedIn(null);
    setState(() => _loggedIn = false);
  }

  Future<void> _openSettings() async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const SettingsPage()),
    );
    if (saved == true) {
      await AlertService.reload();
      await _start();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(body: Center(child: Image.asset('assets/logo.png', width: 120, height: 120)));
    }
    final link = _link;
    if (link == null) return SettingsPage(firstRun: true, onSaved: _start);
    if (!_loggedIn) return LoginPage(link: link, onLoggedIn: _onLoggedIn, onSettings: _openSettings);
    return HomePage(link: link, onSettings: _openSettings, onLogout: _logout);
  }
}

// ─────────────────────────────────────────────────────────────
//  Login: same username / password as the device web page,
//  checked by the device itself once it is reachable
// ─────────────────────────────────────────────────────────────
class LoginPage extends StatefulWidget {
  const LoginPage({super.key, required this.link, required this.onLoggedIn, required this.onSettings});
  final AlarmLink link;
  final VoidCallback onLoggedIn;
  final VoidCallback onSettings;
  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _form = GlobalKey<FormState>();
  final _user = TextEditingController(text: 'admin');
  final _pass = TextEditingController();
  bool _busy = false, _hide = true;
  String? _error;

  Future<void> _login() async {
    if (!_form.currentState!.validate()) return;
    setState(() { _busy = true; _error = null; });
    final ok = await widget.link.login(_user.text.trim(), _pass.text);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = switch (ok) {
        true => null,
        false => 'Wrong username or password',
        null => 'No reply from the device – check it is online and try again',
      };
    });
    if (ok == true) widget.onLoggedIn();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.link,
      builder: (context, _) {
        final link = widget.link;
        final ready = link.connected && link.deviceOnline;
        return Scaffold(
          appBar: AppBar(
            title: const Text('Login'),
            actions: [
              _ConnChip(link: link),
              IconButton(icon: const Icon(Icons.settings), tooltip: 'Settings', onPressed: widget.onSettings),
            ],
          ),
          body: Form(
            key: _form,
            child: ListView(padding: const EdgeInsets.all(24), children: [
              Center(child: Image.asset('assets/logo.png', width: 96, height: 96)),
              const SizedBox(height: 8),
              Center(child: Text('Temple Alarm', style: Theme.of(context).textTheme.titleLarge)),
              Center(child: Text(link.cfg.deviceId, style: Theme.of(context).textTheme.bodySmall)),
              const SizedBox(height: 24),
              TextFormField(
                controller: _user,
                autocorrect: false,
                textInputAction: TextInputAction.next,
                validator: (v) => (v ?? '').trim().isEmpty ? 'Required' : null,
                decoration: const InputDecoration(labelText: 'Username', prefixIcon: Icon(Icons.person)),
              ),
              TextFormField(
                controller: _pass,
                obscureText: _hide,
                textInputAction: TextInputAction.done,
                onFieldSubmitted: (_) => _busy || !ready ? null : _login(),
                validator: (v) => (v ?? '').isEmpty ? 'Required' : null,
                decoration: InputDecoration(
                  labelText: 'Password',
                  prefixIcon: const Icon(Icons.lock),
                  suffixIcon: IconButton(
                    icon: Icon(_hide ? Icons.visibility : Icons.visibility_off),
                    onPressed: () => setState(() => _hide = !_hide),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text('Use the login of the device web page (default: admin / admin123).',
                  style: Theme.of(context).textTheme.bodySmall),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
              ],
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: _busy || !ready ? null : _login,
                icon: _busy
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.login),
                label: Text(ready ? 'Login' : 'Waiting for device…'),
              ),
            ]),
          ),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────
//  Home: status, controls, zones, remote, audio, events
// ─────────────────────────────────────────────────────────────
class HomePage extends StatelessWidget {
  const HomePage({super.key, required this.link, required this.onSettings, required this.onLogout});
  final AlarmLink link;
  final VoidCallback onSettings;
  final VoidCallback onLogout;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: link,
      builder: (context, _) {
        final s = link.status;
        return Scaffold(
          appBar: AppBar(
            leading: Padding(
              padding: const EdgeInsets.all(10),
              child: Image.asset('assets/logo.png'),
            ),
            title: Text(link.cfg.deviceId),
            actions: [
              _ConnChip(link: link),
              IconButton(icon: const Icon(Icons.settings), tooltip: 'Settings', onPressed: onSettings),
              IconButton(icon: const Icon(Icons.logout), tooltip: 'Logout', onPressed: onLogout),
            ],
          ),
          body: RefreshIndicator(
            onRefresh: () async => link.send('status'),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _StatusCard(link: link),
                const SizedBox(height: 12),
                _Controls(link: link),
                const SizedBox(height: 12),
                if (s['pairing'] == true) _PairingBanner(zone: s['pairZone']),
                _ZonesCard(link: link),
                const SizedBox(height: 12),
                _RemoteCard(link: link),
                const SizedBox(height: 12),
                _AudioCard(link: link),
                const SizedBox(height: 12),
                _EventsCard(link: link),
                const SizedBox(height: 12),
                _NetworkCard(status: s),
              ],
            ),
          ),
        );
      },
    );
  }
}

void _sendOrWarn(BuildContext context, AlarmLink link, String cmd, [int? value]) {
  if (!link.send(cmd, value)) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Not connected to the cloud – check Settings or your internet')),
    );
  }
}

class _ConnChip extends StatelessWidget {
  const _ConnChip({required this.link});
  final AlarmLink link;
  @override
  Widget build(BuildContext context) {
    final ok = link.connected && link.deviceOnline;
    final label = !link.connected ? 'Cloud offline' : link.deviceOnline ? 'Online' : 'Device offline';
    return Padding(
      padding: const EdgeInsets.only(right: 4),
      child: Chip(
        avatar: Icon(Icons.circle, size: 12, color: ok ? Colors.green : Colors.orange),
        label: Text(label),
        visualDensity: VisualDensity.compact,
      ),
    );
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.link});
  final AlarmLink link;
  @override
  Widget build(BuildContext context) {
    final s = link.status;
    final alarm = s['alarm'] == true, armed = s['armed'] == true;
    final zones = (s['zones'] as List?) ?? const [];
    final az = s['alarmZone'];
    final (color, icon, title, sub) = s.isEmpty
        ? (Colors.grey, Icons.hourglass_empty, 'Waiting for device', link.connection)
        : alarm
            ? (Colors.red, Icons.notifications_active, 'ALARM ACTIVE',
                az is int && az >= 0 && az < zones.length ? 'Zone ${az + 1}: ${zones[az]['name']}' : 'Panic / manual alarm')
            : armed
                ? (Colors.deepOrange, Icons.lock, 'ARMED', 'Sensors will trigger the alarm')
                : (Colors.green, Icons.lock_open, 'DISARMED', 'System is not active');
    return Card(
      color: color.withValues(alpha: 0.15),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(children: [
          Icon(icon, size: 48, color: color),
          const SizedBox(width: 16),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: Theme.of(context).textTheme.headlineSmall?.copyWith(color: color, fontWeight: FontWeight.bold)),
              Text(sub),
              if (link.statusAt != null)
                Text('Device time ${s['date'] ?? ''} ${s['time'] ?? ''}', style: Theme.of(context).textTheme.bodySmall),
            ]),
          ),
        ]),
      ),
    );
  }
}

class _Controls extends StatelessWidget {
  const _Controls({required this.link});
  final AlarmLink link;
  @override
  Widget build(BuildContext context) {
    final alarm = link.status['alarm'] == true;
    return Wrap(spacing: 8, runSpacing: 8, children: [
      FilledButton.icon(
        style: FilledButton.styleFrom(backgroundColor: Colors.deepOrange),
        onPressed: () => _sendOrWarn(context, link, 'arm'),
        icon: const Icon(Icons.lock), label: const Text('ARM'),
      ),
      FilledButton.icon(
        style: FilledButton.styleFrom(backgroundColor: Colors.green),
        onPressed: () => _sendOrWarn(context, link, 'disarm'),
        icon: const Icon(Icons.lock_open), label: const Text('DISARM'),
      ),
      FilledButton.icon(
        style: FilledButton.styleFrom(backgroundColor: Colors.red),
        onPressed: () async {
          final ok = await showDialog<bool>(
            context: context,
            builder: (c) => AlertDialog(
              title: const Text('Trigger panic alarm?'),
              content: const Text('The hooter, buzzer and siren will sound.'),
              actions: [
                TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
                FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Sound alarm')),
              ],
            ),
          );
          if (ok == true && context.mounted) _sendOrWarn(context, link, 'panic');
        },
        icon: const Icon(Icons.campaign), label: const Text('PANIC'),
      ),
      if (alarm)
        OutlinedButton.icon(
          onPressed: () => _sendOrWarn(context, link, 'stop_alarm'),
          icon: const Icon(Icons.stop_circle), label: const Text('Stop alarm'),
        ),
      OutlinedButton.icon(
        onPressed: () => _sendOrWarn(context, link, 'mute'),
        icon: const Icon(Icons.volume_off), label: const Text('Mute'),
      ),
    ]);
  }
}

class _PairingBanner extends StatelessWidget {
  const _PairingBanner({required this.zone});
  final Object? zone;
  @override
  Widget build(BuildContext context) {
    final z = zone is int && (zone as int) >= 0 ? 'zone ${(zone as int) + 1}' : 'the remote';
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Card(
        color: Theme.of(context).colorScheme.tertiaryContainer,
        child: ListTile(
          leading: const Icon(Icons.sensors),
          title: Text('Pairing $z'),
          subtitle: const Text('Trigger the sensor or press the remote button within 30 s'),
        ),
      ),
    );
  }
}

class _ZonesCard extends StatelessWidget {
  const _ZonesCard({required this.link});
  final AlarmLink link;
  @override
  Widget build(BuildContext context) {
    final zones = (link.status['zones'] as List?) ?? const [];
    return Card(
      child: Column(children: [
        ListTile(
          title: const Text('Sensor zones', style: TextStyle(fontWeight: FontWeight.bold)),
          trailing: TextButton.icon(
            onPressed: () => _sendOrWarn(context, link, 'pair_next'),
            icon: const Icon(Icons.add_link), label: const Text('Pair next'),
          ),
        ),
        for (final z in zones)
          ListTile(
            leading: Icon(z['paired'] == true ? Icons.sensors : Icons.sensors_off,
                color: z['paired'] == true ? Colors.green : null),
            title: Text('Z${(z['id'] as int) + 1}: ${z['name']}'),
            subtitle: Text(z['paired'] == true ? 'Paired' : 'Not paired'),
            trailing: z['paired'] == true
                ? IconButton(
                    tooltip: 'Unpair',
                    icon: const Icon(Icons.link_off),
                    onPressed: () => _sendOrWarn(context, link, 'unpair_zone', z['id'] as int),
                  )
                : TextButton(
                    onPressed: () => _sendOrWarn(context, link, 'pair_zone', z['id'] as int),
                    child: const Text('Pair'),
                  ),
          ),
      ]),
    );
  }
}

class _RemoteCard extends StatelessWidget {
  const _RemoteCard({required this.link});
  final AlarmLink link;
  static const _labels = ['ARM', 'DISARM', 'PANIC', 'MUTE'];
  @override
  Widget build(BuildContext context) {
    final remote = (link.status['remote'] as List?) ?? const [];
    return Card(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        ListTile(
          title: const Text('HC-12 remote', style: TextStyle(fontWeight: FontWeight.bold)),
          subtitle: const Text('Pair all: press ARM, DISARM, PANIC, MUTE in order'),
          trailing: TextButton(onPressed: () => _sendOrWarn(context, link, 'pair_remote'), child: const Text('Pair all')),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Wrap(spacing: 8, runSpacing: 8, children: [
            for (var i = 0; i < 4; i++)
              Chip(
                avatar: Icon(
                  i < remote.length && remote[i]['paired'] == true ? Icons.check_circle : Icons.radio_button_unchecked,
                  size: 18,
                ),
                label: Text(_labels[i]),
              ),
          ]),
        ),
      ]),
    );
  }
}

class _AudioCard extends StatefulWidget {
  const _AudioCard({required this.link});
  final AlarmLink link;
  @override
  State<_AudioCard> createState() => _AudioCardState();
}

class _AudioCardState extends State<_AudioCard> {
  double? _dragging;
  @override
  Widget build(BuildContext context) {
    final vol = (widget.link.status['volume'] as num?)?.toDouble() ?? 0;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Volume ${(_dragging ?? vol).round()} / 30', style: const TextStyle(fontWeight: FontWeight.bold)),
          Slider(
            value: (_dragging ?? vol).clamp(0, 30),
            max: 30,
            divisions: 30,
            onChanged: (v) => setState(() => _dragging = v),
            onChangeEnd: (v) {
              _sendOrWarn(context, widget.link, 'volume', v.round());
              setState(() => _dragging = null);
            },
          ),
          Wrap(spacing: 8, children: [
            OutlinedButton.icon(
              onPressed: () => _sendOrWarn(context, widget.link, 'stop_music'),
              icon: const Icon(Icons.stop), label: const Text('Stop music'),
            ),
            OutlinedButton.icon(
              onPressed: () => _sendOrWarn(context, widget.link, 'play', 99),
              icon: const Icon(Icons.volume_up), label: const Text('Test siren'),
            ),
            OutlinedButton.icon(
              onPressed: () => _sendOrWarn(context, widget.link, 'say_time'),
              icon: const Icon(Icons.schedule), label: const Text('Say time'),
            ),
          ]),
        ]),
      ),
    );
  }
}

class _EventsCard extends StatelessWidget {
  const _EventsCard({required this.link});
  final AlarmLink link;
  @override
  Widget build(BuildContext context) {
    return Card(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const ListTile(title: Text('Recent events', style: TextStyle(fontWeight: FontWeight.bold))),
        if (link.events.isEmpty)
          const Padding(padding: EdgeInsets.fromLTRB(16, 0, 16, 16), child: Text('No events since the app opened.')),
        for (final e in link.events.take(20))
          ListTile(
            dense: true,
            leading: Icon(e['type'] == 'alarm' ? Icons.warning_amber : Icons.info_outline,
                color: e['type'] == 'alarm' ? Colors.red : null),
            title: Text('${e['msg']}'),
            subtitle: Text('${e['time']}'),
          ),
      ]),
    );
  }
}

class _NetworkCard extends StatelessWidget {
  const _NetworkCard({required this.status});
  final Map<String, dynamic> status;
  @override
  Widget build(BuildContext context) {
    final net = (status['net'] as Map?) ?? const {};
    final mdns = (net['mdns'] ?? '').toString();
    return Card(
      child: ListTile(
        leading: const Icon(Icons.wifi),
        title: Text('${net['ssid'] ?? '--'}  ·  ${status['ip'] ?? '--'}'),
        subtitle: Text('Signal ${net['rssi'] ?? '--'} dBm · ${net['static'] == true ? 'Static IP' : 'DHCP'}'
            '${mdns.isNotEmpty ? ' · $mdns' : ''}'),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
//  Settings: broker + device ID (same values as the device web page)
// ─────────────────────────────────────────────────────────────
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key, this.firstRun = false, this.onSaved});
  final bool firstRun;
  final VoidCallback? onSaved;
  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final _form = GlobalKey<FormState>();
  final _host = TextEditingController();
  final _port = TextEditingController(text: '8883');
  final _user = TextEditingController();
  final _pass = TextEditingController();
  final _dev = TextEditingController();

  @override
  void initState() {
    super.initState();
    AppConfig.load().then((c) {
      _host.text = c.host;
      _port.text = '${c.port}';
      _user.text = c.user;
      _pass.text = c.pass;
      _dev.text = c.deviceId;
    });
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    await AppConfig(
      host: _host.text,
      port: int.parse(_port.text),
      user: _user.text,
      pass: _pass.text,
      deviceId: _dev.text,
    ).save();
    if (!mounted) return;
    if (widget.firstRun) {
      await AlertService.reload();
      widget.onSaved?.call();
    } else {
      Navigator.pop(context, true);
    }
  }

  @override
  Widget build(BuildContext context) {
    String? req(String? v) => (v == null || v.trim().isEmpty) ? 'Required' : null;
    return Scaffold(
      appBar: AppBar(title: Text(widget.firstRun ? 'Connect to your alarm' : 'Settings')),
      body: Form(
        key: _form,
        child: ListView(padding: const EdgeInsets.all(16), children: [
          if (widget.firstRun) ...[
            Center(child: Image.asset('assets/logo.png', width: 96, height: 96)),
            const SizedBox(height: 8),
            Center(child: Text('Temple Alarm', style: Theme.of(context).textTheme.titleLarge)),
            const SizedBox(height: 16),
          ],
          const Text('Use the same broker details you entered on the device web page '
              '(Settings → Mobile App). The Device ID is shown on the device login page.'),
          const SizedBox(height: 16),
          TextFormField(controller: _dev, validator: req,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(labelText: 'Device ID', hintText: 'TALM-A1B2C3')),
          TextFormField(controller: _host, validator: req, keyboardType: TextInputType.url,
              decoration: const InputDecoration(labelText: 'Broker host', hintText: 'xxxx.s1.eu.hivemq.cloud')),
          TextFormField(controller: _port, keyboardType: TextInputType.number,
              validator: (v) => int.tryParse(v ?? '') == null ? 'Number' : null,
              decoration: const InputDecoration(labelText: 'Port (8883 = TLS)')),
          TextFormField(controller: _user, decoration: const InputDecoration(labelText: 'Broker username')),
          TextFormField(controller: _pass, obscureText: true, decoration: const InputDecoration(labelText: 'Broker password')),
          const SizedBox(height: 24),
          FilledButton(onPressed: _save, child: const Text('Save & connect')),
        ]),
      ),
    );
  }
}
