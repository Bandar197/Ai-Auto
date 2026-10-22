import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/api/api_client.dart';
import '../obd/obd.dart';
import '../platform/ble_transport.dart';
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
  bool _ble = false;
  late final TextEditingController _host;
  late final TextEditingController _port;
  StreamSubscription<List<ScanResult>>? _scanSub;
  List<ScanResult> _bleResults = [];
  bool _scanning = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final s = ref.read(settingsProvider);
    _host = TextEditingController(text: s.wifiHost);
    _port = TextEditingController(text: '${s.wifiPort}');
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
    try {
      if (await FlutterBluePlus.isSupported == false) throw Exception('Bluetooth LE not supported');
      await _scanSub?.cancel();
      _scanSub = BleTransport.scan().listen((r) => setState(() => _bleResults = r));
      await Future<void>.delayed(const Duration(seconds: 8));
    } on Object catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _scanning = false);
    }
  }

  Future<void> _connectBle(BluetoothDevice d) async {
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
    return [
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: SegmentedButton<bool>(
          segments: [
            ButtonSegment(value: false, label: Text(l.transportWifi), icon: const Icon(Icons.wifi)),
            ButtonSegment(value: true, label: Text(l.transportBle), icon: const Icon(Icons.bluetooth)),
          ],
          selected: {_ble},
          onSelectionChanged: (s) => setState(() => _ble = s.first),
        ),
      ),
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
      if (!_ble) ...[
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
            icon: const Icon(Icons.link),
            label: Text(l.connectButton),
            onPressed: conn.busy ? null : _connectWifi,
          ),
        ),
      ] else ...[
        if (Platform.isIOS || Platform.isAndroid)
          Padding(padding: const EdgeInsets.symmetric(horizontal: 12), child: Text(l.bleClassicNote, style: Theme.of(context).textTheme.bodySmall)),
        Padding(
          padding: const EdgeInsets.all(12),
          child: OutlinedButton.icon(
            icon: _scanning ? const SizedBox.square(dimension: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.bluetooth_searching),
            label: Text(_scanning ? l.bleScanning : l.bleScan),
            onPressed: _scanning ? null : _scanBle,
          ),
        ),
        if (_bleResults.isEmpty && !_scanning) Padding(padding: const EdgeInsets.all(12), child: Text(l.bleNoDevices)),
        for (final r in _bleResults.where((r) => r.device.platformName.isNotEmpty || r.advertisementData.advName.isNotEmpty))
          ListTile(
            leading: const Icon(Icons.bluetooth),
            title: Text(r.device.platformName.isNotEmpty ? r.device.platformName : r.advertisementData.advName),
            subtitle: Text('${r.device.remoteId.str} · ${r.rssi} dBm', textDirection: TextDirection.ltr),
            onTap: conn.busy ? null : () => _connectBle(r.device),
          ),
      ],
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
