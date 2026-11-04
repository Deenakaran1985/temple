import 'dart:io';

import 'package:flutter/material.dart';

import 'alarm_link.dart';
import 'background.dart';
import 'config.dart';
import 'discovery.dart';
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

  Future<void> _setupDone() async {
    await AlertService.reload();
    await _start();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(body: Center(child: Image.asset('assets/logo.png', width: 120, height: 120)));
    }
    final link = _link;
    if (link == null) return SetupPage(onDone: _setupDone);
    if (!_loggedIn) return LoginPage(link: link, onLoggedIn: _onLoggedIn, onSettings: _openSettings);
    return HomePage(link: link, onSettings: _openSettings, onLogout: _logout);
  }
}

// ─────────────────────────────────────────────────────────────
//  Login form shared by the WiFi setup and the remote login.
//  Same username / password as the device web page.
// ─────────────────────────────────────────────────────────────
class _LoginForm extends StatefulWidget {
  const _LoginForm({required this.subtitle, required this.ready, required this.notReadyLabel, required this.onLogin});
  final String subtitle;
  final bool ready;
  final String notReadyLabel;
  /// Returns null on success, otherwise the error to show.
  final Future<String?> Function(String user, String pass) onLogin;
  @override
  State<_LoginForm> createState() => _LoginFormState();
}

class _LoginFormState extends State<_LoginForm> {
  final _form = GlobalKey<FormState>();
  final _user = TextEditingController(text: 'admin');
  final _pass = TextEditingController();
  bool _busy = false, _hide = true;
  String? _error;

  Future<void> _login() async {
    if (_busy || !widget.ready || !_form.currentState!.validate()) return;
    setState(() { _busy = true; _error = null; });
    final err = await widget.onLogin(_user.text.trim(), _pass.text);
    if (mounted) setState(() { _busy = false; _error = err; });
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Form(
      key: _form,
      child: ListView(padding: const EdgeInsets.all(24), children: [
        Center(child: Image.asset('assets/logo.png', width: 96, height: 96)),
        const SizedBox(height: 8),
        Center(child: Text('Temple Alarm', style: t.titleLarge)),
        Center(child: Text(widget.subtitle, style: t.bodySmall)),
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
          onFieldSubmitted: (_) => _login(),
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
        Text('Use the login of the device web page (default: admin / admin123).', style: t.bodySmall),
        if (_error != null) ...[
          const SizedBox(height: 12),
          Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
        ],
        const SizedBox(height: 24),
        FilledButton.icon(
          onPressed: _busy || !widget.ready ? null : _login,
          icon: _busy
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.login),
          label: Text(widget.ready ? 'Login' : widget.notReadyLabel),
        ),
      ]),
    );
  }
}

/// Remote login over MQTT, once the app already knows the device.
class LoginPage extends StatelessWidget {
  const LoginPage({super.key, required this.link, required this.onLoggedIn, required this.onSettings});
  final AlarmLink link;
  final VoidCallback onLoggedIn;
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: link,
      builder: (context, _) => Scaffold(
        appBar: AppBar(
          title: const Text('Login'),
          actions: [
            _ConnChip(link: link),
            IconButton(icon: const Icon(Icons.settings), tooltip: 'Settings', onPressed: onSettings),
          ],
        ),
        body: _LoginForm(
          subtitle: link.cfg.deviceId,
          ready: link.connected && link.deviceOnline,
          notReadyLabel: 'Waiting for device…',
          onLogin: (user, pass) async {
            final ok = await link.login(user, pass);
            if (ok == true) onLoggedIn();
            return switch (ok) {
              true => null,
              false => 'Wrong username or password',
              null => 'No reply from the device – check it is online and try again',
            };
          },
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
//  Setup: find the alarm on the phone's WiFi, log in, and fetch
//  the Device ID + cloud (broker) details from the device itself
// ─────────────────────────────────────────────────────────────
class SetupPage extends StatefulWidget {
  /// Called after a successful setup; when null the page pops with true.
  const SetupPage({super.key, this.onDone});
  final VoidCallback? onDone;
  @override
  State<SetupPage> createState() => _SetupPageState();
}

class _SetupPageState extends State<SetupPage> {
  final _finder = DeviceFinder();

  @override
  void initState() {
    super.initState();
    _finder.search();
  }

  @override
  void dispose() {
    _finder.dispose();
    super.dispose();
  }

  void _finish() {
    if (widget.onDone != null) {
      widget.onDone!();
    } else {
      Navigator.pop(context, true);
    }
  }

  Future<void> _open(FoundDevice dev) async {
    await _finder.stop();
    if (!mounted) return;
    final ok = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => DeviceLoginPage(device: dev)),
    );
    if (ok == true) _finish();
  }

  Future<void> _enterIp() async {
    final ctl = TextEditingController(text: '192.168.');
    final ip = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Device IP address'),
        content: TextField(
          controller: ctl,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(helperText: "Shown on the alarm's LCD screen"),
          onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, ctl.text.trim()), child: const Text('Connect')),
        ],
      ),
    );
    if (ip == null || ip.isEmpty || !mounted) return;
    final dev = await DeviceFinder.probe(ip);
    if (!mounted) return;
    if (dev == null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('No Temple Alarm found at $ip')));
    } else {
      _open(dev);
    }
  }

  Future<void> _manual() async {
    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const SettingsPage(fromSetup: true)),
    );
    if (saved == true) _finish();
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Find your alarm')),
      body: ListenableBuilder(
        listenable: _finder,
        builder: (context, _) => ListView(padding: const EdgeInsets.all(16), children: [
          Center(child: Image.asset('assets/logo.png', width: 80, height: 80)),
          const SizedBox(height: 12),
          const Text('Connect this phone to the same WiFi as the alarm. '
              'If the alarm is not on a WiFi yet, connect to its own hotspot '
              '(named like TALM-XXXXXX, password 12345678) and turn off mobile data.'),
          const SizedBox(height: 16),
          Row(children: [
            Text('Alarms found', style: t.titleMedium),
            const Spacer(),
            if (_finder.searching)
              const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
            else
              TextButton.icon(onPressed: _finder.search, icon: const Icon(Icons.refresh), label: const Text('Search again')),
          ]),
          if (_finder.devices.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: Text(_finder.searching ? 'Searching the WiFi…' : 'No alarm found on this WiFi',
                    style: t.bodyMedium),
              ),
            ),
          for (final d in _finder.devices)
            Card(
              child: ListTile(
                leading: Image.asset('assets/logo.png', width: 40, height: 40),
                title: Text(d.id),
                subtitle: Text(d.ip),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _open(d),
              ),
            ),
          const SizedBox(height: 16),
          OutlinedButton.icon(onPressed: _enterIp, icon: const Icon(Icons.edit), label: const Text('Enter IP address')),
          TextButton(onPressed: _manual, child: const Text('Advanced: enter cloud details manually')),
        ]),
      ),
    );
  }
}

/// Logs in to a device found on the WiFi; pops with true once set up.
class DeviceLoginPage extends StatelessWidget {
  const DeviceLoginPage({super.key, required this.device});
  final FoundDevice device;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Login')),
      body: _LoginForm(
        subtitle: '${device.id} · ${device.ip}',
        ready: true,
        notReadyLabel: '',
        onLogin: (user, pass) async {
          final err = await setupFromDevice(device.ip, user, pass);
          if (err == null && context.mounted) Navigator.pop(context, true);
          return err;
        },
      ),
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
  const SettingsPage({super.key, this.fromSetup = false});
  /// Opened from the WiFi search page, so don't offer the search again.
  final bool fromSetup;
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
    if (mounted) Navigator.pop(context, true);
  }

  Future<void> _search() async {
    final found = await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => const SetupPage()));
    if (found == true && mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    String? req(String? v) => (v == null || v.trim().isEmpty) ? 'Required' : null;
    return Scaffold(
      appBar: AppBar(title: Text(widget.fromSetup ? 'Cloud details' : 'Settings')),
      body: Form(
        key: _form,
        child: ListView(padding: const EdgeInsets.all(16), children: [
          if (!widget.fromSetup) ...[
            FilledButton.icon(
              onPressed: _search,
              icon: const Icon(Icons.wifi_find),
              label: const Text('Search WiFi for my alarm'),
            ),
            const SizedBox(height: 8),
            const Text('Easiest: the app finds the alarm on your WiFi and copies these details from it.'),
            const Divider(height: 32),
          ],
          const Text('Advanced: the same broker details as on the device web page '
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
