import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../obd/obd.dart';
import '../platform/ble_transport.dart';
import 'providers.dart';

class ConnState {
  const ConnState({
    this.mode,
    this.client,
    this.status = const LinkStatus(),
    this.scenarioKey,
    this.demo,
    this.replay,
    this.replayServerId,
    this.log,
    this.busy = false,
    this.sourceKind = 'elm327_wifi',
  });

  /// null = nothing selected yet.
  final DataMode? mode;
  final ObdClient? client;
  final LinkStatus status;
  final String? scenarioKey;
  final DemoTransport? demo;
  final Recording? replay;
  final String? replayServerId;
  final ConnectionLog? log;
  final bool busy;

  /// recording source.kind: elm327_wifi | elm327_ble | simulator
  final String sourceKind;

  bool get isConnected => client != null && status.adapter == AdapterState.connected;
  bool get ecuReady => isConnected && status.ecu == EcuState.connected;
  bool get isSimulator => client?.info.isSimulator ?? false;
  bool get isDemo => mode == DataMode.demo;

  ConnState copyWith({LinkStatus? status, bool? busy, ConnectionLog? log}) => ConnState(
        mode: mode,
        client: client,
        status: status ?? this.status,
        scenarioKey: scenarioKey,
        demo: demo,
        replay: replay,
        replayServerId: replayServerId,
        log: log ?? this.log,
        busy: busy ?? this.busy,
        sourceKind: sourceKind,
      );
}

/// Owns the single OBD connection of the app (live adapter, in-process demo
/// or a replay source).
class ConnectionController extends Notifier<ConnState> {
  StreamSubscription<LinkStatus>? _sub;
  ObdClient? _client;

  @override
  ConnState build() {
    ref.onDispose(() {
      _sub?.cancel();
      _client?.dispose();
    });
    return const ConnState();
  }

  ObdClientConfig _config() {
    final s = ref.read(settingsProvider);
    return ObdClientConfig(
      protocol: s.protocol,
      commandTimeout: Duration(milliseconds: s.commandTimeoutMs),
      searchTimeout: Duration(milliseconds: s.searchTimeoutMs),
      appPlatform: Platform.isIOS ? 'ios' : (Platform.isAndroid ? 'android' : Platform.operatingSystem),
      appVersion: appVersion,
    );
  }

  Future<void> _reset() async {
    await _sub?.cancel();
    _sub = null;
    final old = _client;
    _client = null;
    if (old != null) await old.dispose();
  }

  Future<ConnectResult> _connect(ObdTransport t, {String? scenarioKey, DemoTransport? demo, required String kind}) async {
    await _reset();
    final client = ObdClient(transport: t, table: ref.read(appAssetsProvider).table, config: _config());
    _client = client;
    state = ConnState(
      mode: demo != null ? DataMode.demo : DataMode.live,
      client: client,
      scenarioKey: scenarioKey,
      demo: demo,
      busy: true,
      sourceKind: kind,
      status: const LinkStatus(adapter: AdapterState.connecting, message: LinkMessage.connectingAdapter),
    );
    _sub = client.status.listen((s) => state = state.copyWith(status: s));
    final vehicleId = ref.read(settingsProvider).selectedVehicleId;
    final r = await client.connect(vehicleId: vehicleId != null && !vehicleId.startsWith('local-') ? vehicleId : null);
    // The simulator answering AT@1 is always demo, never live.
    state = ConnState(
      mode: r.dataMode,
      client: client,
      scenarioKey: scenarioKey,
      demo: demo,
      log: r.log,
      sourceKind: client.info.isSimulator ? 'simulator' : kind,
      status: client.currentStatus,
    );
    return r;
  }

  Future<ConnectResult> connectWifi(String host, int port) =>
      _connect(TcpTransport(host: host, port: port), kind: 'elm327_wifi');

  Future<ConnectResult> connectBle(BluetoothDevice device) {
    final s = ref.read(settingsProvider);
    final override = s.bleService.isNotEmpty && s.bleNotify.isNotEmpty && s.bleWrite.isNotEmpty
        ? BleUartProfile(name: 'manual', service: s.bleService, notify: s.bleNotify, write: s.bleWrite)
        : null;
    return _connect(BleTransport(device, uuidOverride: override), kind: 'elm327_ble');
  }

  Future<ConnectResult> connectDemo(Scenario scenario) {
    final emu = Elm327Emulator(scenario, ref.read(appAssetsProvider).table);
    final t = DemoTransport(emu);
    return _connect(t, scenarioKey: scenario.key, demo: t, kind: 'simulator');
  }

  /// Re-runs the connect sequence on the existing transport.
  Future<ConnectResult?> reconnect() async {
    final c = state.client;
    if (c == null) return null;
    state = state.copyWith(busy: true);
    final r = await c.connect();
    state = ConnState(
      mode: r.dataMode,
      client: c,
      scenarioKey: state.scenarioKey,
      demo: state.demo,
      log: r.log,
      sourceKind: state.sourceKind,
      status: c.currentStatus,
    );
    return r;
  }

  Future<void> useReplay(Recording recording, {String? serverId}) async {
    await _reset();
    state = ConnState(mode: DataMode.replay, replay: recording, replayServerId: serverId);
  }

  void setEngineRunning(bool running) {
    final d = state.demo;
    if (d == null) return;
    d.emulator.engineRunning = running;
    state = state.copyWith();
  }

  Future<void> disconnect() async {
    await _reset();
    state = const ConnState(status: LinkStatus(message: LinkMessage.disconnected));
  }
}

final connectionProvider = NotifierProvider<ConnectionController, ConnState>(ConnectionController.new);
