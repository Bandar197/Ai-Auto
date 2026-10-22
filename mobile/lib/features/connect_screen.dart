import 'dart:async';
import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:universal_ble/universal_ble.dart' show BleDevice;

import '../core/api/api_client.dart';
import '../obd/obd.dart';
import '../platform/ble_transport.dart';
import '../platform/host_platform.dart';
import '../platform/serial_transport.dart';
import '../state/adapter_providers.dart';
import '../state/connection_controller.dart';
import '../state/providers.dart';
import '../ui/l10n_helpers.dart';
import '../ui/widgets.dart';

class ConnectScreen extends ConsumerStatefulWidget {
  const ConnectScreen({super.key, this.next});
  final String? next;
  @override
  ConsumerState<ConnectScreen> createState() => _ConnectScreenState();
}

class _ConnectScreenState extends ConsumerState<ConnectScreen> {
  DataMode _mode = DataMode.live;
  late AdapterLink _link;
  late final TextEditingController _host;
  late final TextEditingController _port;
  StreamSubscription<List<BleDevice>>? _scanSub;
  List<BleDevice> _bleResults = [];
  bool _scanning = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final s = ref.read(settingsProvider);
    _host = TextEditingController(text: s.wifiHost);
    _port = TextEditingController(text: '${s.wifiPort}');
    final host = ref.read(hostPlatformProvider);
    final last = AdapterLink.values.firstWhere((l) => l.name == s.lastLink, orElse: () => AdapterLink.wifi);
    _link = host.supports(last) ? last : AdapterLink.wifi;
  }

  @override
  void dispose() {
    _scanSub?.cancel();
    if (_scanning) BleTransport.stopScan();
    super.dispose();
  }

  void _afterConnect(ConnectResult? r) {
    if (!mounted) return;
    if (r != null && r.adapterOk && r.ecuOk) {
      if (widget.next == 'scan') {
        context.pushReplacement('/scan');
      } else {
        context.pop();
      }
    }
  }

  Future<void> _connectWifi() async {
    final port = int.tryParse(_port.text.trim()) ?? 35000;
    await ref.read(settingsProvider.notifier).change((s) => s.copyWith(wifiHost: _host.text.trim(), wifiPort: port));
    final r = await ref.read(connectionProvider.notifier).connectWifi(_host.text.trim(), port);
    _afterConnect(r);
  }

  Future<void> _scanBle() async {
    setState(() {
      _error = null;
      _bleResults = [];
      _scanning = true;
    });
    await _scanSub?.cancel();
    _scanSub = BleTransport.scan().listen(
      (r) {
        if (mounted) setState(() => _bleResults = r);
      },
      onError: (Object e) {
        if (mounted) setState(() => _error = e.toString());
      },
      onDone: () {
        if (mounted) setState(() => _scanning = false);
      },
    );
  }

  Future<void> _connectClassic(ClassicTarget t) async {
    final host = ref.read(hostPlatformProvider);
    final ctrl = ref.read(connectionProvider.notifier);
    final r = host == HostPlatform.android ? await ctrl.connectBtClassic(t.id, name: t.title) : await ctrl.connectSerial(t.id);
    _afterConnect(r);
  }

  Future<void> _connectBle(BleDevice d) async {
    await BleTransport.stopScan();
    final r = await ref.read(connectionProvider.notifier).connectBle(d);
    _afterConnect(r);
  }

  Future<void> _connectDemo(Scenario s) async {
    final r = await ref.read(connectionProvider.notifier).connectDemo(s);
    _afterConnect(r);
  }

  Future<void> _useRecording(Recording rec, {String? serverId}) async {
    await ref.read(connectionProvider.notifier).useReplay(rec, serverId: serverId);
    if (!mounted) return;
    if (widget.next == 'scan') {
      context.pushReplacement('/scan');
    } else {
      context.go('/live');
    }
  }

  Future<void> _pickFile() async {
    try {
      final files = await FilePicker.pickFiles(type: FileType.custom, allowedExtensions: ['json']);
      if (files.isEmpty) return;
      final text = utf8.decode(await files.first.readAsBytes());
      await _useRecording(Recording.fromJsonString(text));
    } on Object catch (e) {
      setState(() => _error = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final conn = ref.watch(connectionProvider);
    final settings = ref.watch(settingsProvider);
    return Scaffold(
      appBar: AppBar(title: Text(l.connectTitle)),
      body: ListView(padding: const EdgeInsets.only(bottom: 24), children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: SegmentedButton<DataMode>(
            segments: [
              ButtonSegment(value: DataMode.live, label: Text(l.modeLive), icon: const Icon(Icons.sensors)),
              ButtonSegment(value: DataMode.demo, label: Text(l.modeDemo), icon: const Icon(Icons.science_outlined)),
              ButtonSegment(value: DataMode.replay, label: Text(l.modeReplay), icon: const Icon(Icons.replay)),
            ],
            selected: {_mode},
            onSelectionChanged: (s) => setState(() => _mode = s.first),
          ),
        ),
        if (conn.client != null || conn.status.message != LinkMessage.idle)
          Card(
            margin: const EdgeInsets.symmetric(horizontal: 12),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                if (conn.mode != null) ModeBanner(mode: conn.mode!.apiValue, simulator: conn.isSimulator),
                StatusChips(status: conn.status, simulator: conn.isSimulator),
                Text(linkMessageText(l, conn.status.message)),
                if (conn.status.detail.isNotEmpty)
                  Text(conn.status.detail, style: Theme.of(context).textTheme.bodySmall, textDirection: TextDirection.ltr),
                if (conn.busy) const LinearProgressIndicator(),
                if (conn.client != null && !conn.busy)
                  Align(
                    alignment: AlignmentDirectional.centerEnd,
                    child: TextButton(onPressed: () => ref.read(connectionProvider.notifier).disconnect(), child: Text(l.disconnect)),
                  ),
              ]),
            ),
          ),
        if (_error != null) Padding(padding: const EdgeInsets.all(12), child: Text(_error!, style: const TextStyle(color: Colors.red))),
        ...switch (_mode) {
          DataMode.live => _live(context, conn, settings.protocol),
          DataMode.demo => _demo(context, conn),
          DataMode.replay => _replay(context),
        },
      ]),
    );
  }

  List<Widget> _live(BuildContext context, ConnState conn, String protocol) {
    final l = context.l10n;
    final host = ref.watch(hostPlatformProvider);
    final small = Theme.of(context).textTheme.bodySmall;
    return [
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: SegmentedButton<AdapterLink>(
          key: const Key('link-selector'),
          segments: [
            ButtonSegment(value: AdapterLink.wifi, label: Text(l.transportWifi), icon: const Icon(Icons.wifi)),
            ButtonSegment(value: AdapterLink.ble, label: Text(l.transportBle), icon: const Icon(Icons.bluetooth), enabled: host.supportsBle),
            ButtonSegment(
              value: AdapterLink.classic,
              label: Text(l.transportClassic),
              icon: Icon(host.isDesktop ? Icons.usb : Icons.bluetooth_connected),
              enabled: host.supportsClassic,
            ),
          ],
          selected: {_link},
          onSelectionChanged: (sel) => setState(() => _link = sel.first),
        ),
      ),
      if (host == HostPlatform.ios)
        Padding(padding: const EdgeInsets.symmetric(horizontal: 12), child: Text(l.classicIosNote, key: const Key('classic-ios-note'), style: small)),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: DropdownButtonFormField<String>(
          initialValue: protocol,
          decoration: InputDecoration(labelText: l.protocol),
          items: [
            DropdownMenuItem(value: '0', child: Text(l.protocolAuto)),
            for (final p in ObdProtocol.all) DropdownMenuItem(value: p.code, child: Text('${p.code} — ${p.name}', overflow: TextOverflow.ellipsis)),
          ],
          onChanged: (v) => ref.read(settingsProvider.notifier).change((s) => s.copyWith(protocol: v ?? '0')),
        ),
      ),
      ...switch (_link) {
        AdapterLink.wifi => _wifi(context, conn),
        AdapterLink.ble => _bleSection(context, conn),
        AdapterLink.classic => _classic(context, conn, host),
      },
    ];
  }

  List<Widget> _wifi(BuildContext context, ConnState conn) {
    final l = context.l10n;
    return [
      Padding(
        padding: const EdgeInsets.all(12),
        child: Row(children: [
          Expanded(
            flex: 3,
            child: TextField(
              controller: _host,
              textDirection: TextDirection.ltr,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(labelText: l.wifiHost),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: _port,
              textDirection: TextDirection.ltr,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(labelText: l.wifiPort),
            ),
          ),
        ]),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Text(l.wifiInternetNote, style: Theme.of(context).textTheme.bodySmall),
      ),
      Padding(
        padding: const EdgeInsets.all(12),
        child: FilledButton.icon(
          key: const Key('wifi-connect'),
          icon: const Icon(Icons.link),
          label: Text(l.connectButton),
          onPressed: conn.busy ? null : _connectWifi,
        ),
      ),
    ];
  }

  List<Widget> _bleSection(BuildContext context, ConnState conn) {
    final l = context.l10n;
    final last = ref.watch(settingsProvider).lastBleDevice;
    final list = [..._bleResults]..sort((a, b) => ((b.name ?? '').isNotEmpty ? 1 : 0).compareTo((a.name ?? '').isNotEmpty ? 1 : 0));
    return [
      Padding(padding: const EdgeInsets.symmetric(horizontal: 12), child: Text(l.bleNote, style: Theme.of(context).textTheme.bodySmall)),
      Padding(
        padding: const EdgeInsets.all(12),
        child: OutlinedButton.icon(
          key: const Key('ble-scan'),
          icon: _scanning ? const SizedBox.square(dimension: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.bluetooth_searching),
          label: Text(_scanning ? l.bleScanning : l.bleScan),
          onPressed: _scanning ? null : _scanBle,
        ),
      ),
      if (list.isEmpty && !_scanning) Padding(padding: const EdgeInsets.all(12), child: Text(l.bleNoDevices)),
      for (final d in list)
        ListTile(
          leading: Icon(Icons.bluetooth, color: d.deviceId == last ? Theme.of(context).colorScheme.primary : null),
          title: Text(BleTransport.displayName(d)),
          subtitle: Text('${d.deviceId}${d.rssi != null ? ' · ${d.rssi} dBm' : ''}${d.deviceId == last ? ' · ${l.lastUsed}' : ''}',
              textDirection: TextDirection.ltr),
          onTap: conn.busy ? null : () => _connectBle(d),
        ),
    ];
  }

  List<Widget> _classic(BuildContext context, ConnState conn, HostPlatform host) {
    final l = context.l10n;
    final settings = ref.watch(settingsProvider);
    final targets = ref.watch(classicTargetsProvider);
    return [
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Text(host.isDesktop ? '${l.transportSerial}\n${l.classicDesktopNote}' : l.classicAndroidNote,
            key: const Key('classic-note'), style: Theme.of(context).textTheme.bodySmall),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(children: [
          if (host.isDesktop)
            Expanded(
              child: DropdownButtonFormField<int>(
                key: const Key('baud-rate'),
                initialValue: SerialTransport.baudRates.contains(settings.serialBaud) ? settings.serialBaud : SerialTransport.defaultBaud,
                decoration: InputDecoration(labelText: l.baudRate),
                items: [for (final b in SerialTransport.baudRates) DropdownMenuItem(value: b, child: Text('$b'))],
                onChanged: (v) => ref.read(settingsProvider.notifier).change((s) => s.copyWith(serialBaud: v ?? SerialTransport.defaultBaud)),
              ),
            )
          else
            const Spacer(),
          TextButton.icon(onPressed: () => ref.invalidate(classicTargetsProvider), icon: const Icon(Icons.refresh), label: Text(l.refresh)),
        ]),
      ),
      ...targets.when(
        loading: () => [const LinearProgressIndicator()],
        error: (e, _) => [
          Padding(padding: const EdgeInsets.all(12), child: Text(e is StateError ? l.classicBluetoothOff : '$e', style: const TextStyle(color: Colors.red))),
        ],
        data: (list) => list.isEmpty
            ? [Padding(padding: const EdgeInsets.all(12), child: Text(l.classicNoDevices))]
            : [
                for (final t in list)
                  ListTile(
                    key: Key('classic-${t.id}'),
                    leading: Icon(host.isDesktop ? Icons.usb : Icons.bluetooth_connected,
                        color: t.id == settings.lastClassicDevice ? Theme.of(context).colorScheme.primary : null),
                    title: Text(t.title, textDirection: TextDirection.ltr),
                    subtitle: Text([t.subtitle, if (t.id == settings.lastClassicDevice) l.lastUsed].where((x) => x.isNotEmpty).join(' · ')),
                    onTap: conn.busy ? null : () => _connectClassic(t),
                  ),
              ],
      ),
    ];
  }

  List<Widget> _demo(BuildContext context, ConnState conn) {
    final l = context.l10n;
    final scenarios = ref.watch(appAssetsProvider).scenarios;
    return [
      Padding(padding: const EdgeInsets.all(12), child: Text(l.demoExplain)),
      for (final s in scenarios)
        Card(
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: ListTile(
            leading: const Icon(Icons.science_outlined, color: demoColor),
            title: Text(s.name(context.lang)),
            subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(s.description(context.lang), maxLines: 3, overflow: TextOverflow.ellipsis),
              Wrap(spacing: 4, children: [for (final d in s.dtcs) Chip(label: Text(d.code), visualDensity: VisualDensity.compact)]),
            ]),
            onTap: conn.busy ? null : () => _connectDemo(s),
          ),
        ),
      if (conn.demo != null)
        SwitchListTile(
          title: Text(l.simulateEngineOff),
          value: !conn.demo!.emulator.engineRunning,
          onChanged: (v) => ref.read(connectionProvider.notifier).setEngineRunning(!v),
        ),
    ];
  }

  List<Widget> _replay(BuildContext context) {
    final l = context.l10n;
    final store = ref.watch(localStoreProvider);
    final user = ref.watch(authProvider).value;
    return [
      Padding(
        padding: const EdgeInsets.all(12),
        child: OutlinedButton.icon(icon: const Icon(Icons.file_open_outlined), label: Text(l.replayFromFile), onPressed: _pickFile),
      ),
      ListTile(title: Text(l.replayLocal, style: Theme.of(context).textTheme.titleMedium)),
      FutureBuilder<List<Recording>>(
        future: store.listRecordings(),
        builder: (context, snap) {
          final list = snap.data ?? const <Recording>[];
          if (snap.connectionState != ConnectionState.done) return const LinearProgressIndicator();
          if (list.isEmpty) return Padding(padding: const EdgeInsets.all(12), child: Text(l.noRecordings));
          return Column(children: [
            for (final r in list.take(30))
              ListTile(
                leading: Icon(r.dataMode == 'demo' ? Icons.science_outlined : Icons.sensors, color: r.dataMode == 'demo' ? demoColor : null),
                title: Text('${modeText(l, r.dataMode)} · ${r.demoScenario ?? r.source['protocol_name'] ?? ''}'),
                subtitle: Text('${r.createdAt.toLocal()} · ${(r.durationMs / 1000).toStringAsFixed(0)} ${l.seconds} · ${r.samples.length}'),
                onTap: () => _useRecording(r),
              ),
          ]);
        },
      ),
      if (user != null) ...[
        ListTile(title: Text(l.replayFromServer, style: Theme.of(context).textTheme.titleMedium)),
        FutureBuilder<List<Map<String, dynamic>>>(
          future: ref.read(apiProvider).recordings(),
          builder: (context, snap) {
            if (snap.hasError) {
              return Padding(padding: const EdgeInsets.all(12), child: Text(ApiException.from(snap.error!).message));
            }
            if (!snap.hasData) return const LinearProgressIndicator();
            final list = snap.data!;
            if (list.isEmpty) return Padding(padding: const EdgeInsets.all(12), child: Text(l.noRecordings));
            return Column(children: [
              for (final m in list)
                ListTile(
                  leading: const Icon(Icons.cloud_outlined),
                  title: Text('${modeText(l, '${m['data_mode']}')} · ${m['created_at'] ?? ''}'),
                  subtitle: Text('${((m['duration_ms'] as num? ?? 0) / 1000).toStringAsFixed(0)} ${l.seconds} · ${m['sample_count'] ?? ''}'),
                  onTap: () async {
                    try {
                      final full = await ref.read(apiProvider).recording(m['id'] as String);
                      await _useRecording(Recording.fromJson(full), serverId: m['id'] as String);
                    } on Object catch (e) {
                      setState(() => _error = e.toString());
                    }
                  },
                ),
            ]);
          },
        ),
      ],
    ];
  }
}
