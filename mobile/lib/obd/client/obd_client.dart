import 'dart:async';

import '../decode/dtc.dart';
import '../decode/pid_table.dart';
import '../elm327/elm327.dart';
import '../errors.dart';
import '../protocol/protocol.dart';
import '../services/obd_services.dart';
import '../transport/obd_transport.dart';
import 'connection_log.dart';
import 'states.dart';

export 'connection_log.dart';
export 'states.dart';

class ObdClientConfig {
  const ObdClientConfig({
    this.protocol = '0',
    this.commandTimeout = const Duration(milliseconds: 2500),
    this.searchTimeout = const Duration(seconds: 10),
    this.resetTimeout = const Duration(seconds: 2),
    this.maxAttempts = 3,
    this.backoff = const Duration(seconds: 1),
    this.timeoutStreakForLoss = 3,
    this.appPlatform,
    this.appVersion,
  });

  /// `0` = automatic search, `1`..`9` = forced ELM protocol.
  final String protocol;
  final Duration commandTimeout;
  final Duration searchTimeout;
  final Duration resetTimeout;
  final int maxAttempts;
  final Duration backoff;
  final int timeoutStreakForLoss;
  final String? appPlatform;
  final String? appVersion;
}

/// Outcome of [ObdClient.connect].
class ConnectResult {
  ConnectResult({required this.adapterOk, required this.ecuOk, required this.info, required this.log, required this.dataMode});
  final bool adapterOk;
  final bool ecuOk;
  final AdapterInfo info;
  final ConnectionLog log;
  final DataMode dataMode;
}

/// Engine/client events that end up in recordings (`events`).
class ClientEvent {
  ClientEvent(this.type, [this.detail]);

  /// connection_lost | reconnected | ecu_no_response | note
  final String type;
  final String? detail;
  final DateTime at = DateTime.now().toUtc();
}

/// Server approval for clearing DTCs (`POST /control/operations` response).
class ClearDtcApproval {
  const ClearDtcApproval({required this.operationId, required this.status, required this.commands});
  final String operationId;
  final String status;
  final List<String> commands;

  bool get approvesClear => status == 'approved' && commands.contains('04');
}

class ClearDtcOutcome {
  ClearDtcOutcome({required this.success, required this.requestFrames, required this.responseFrames, this.error});
  final bool success;
  final List<String> requestFrames;
  final List<String> responseFrames;
  final String? error;
}

/// High-level OBD client: connects (with retry/backoff), initialises the
/// ELM327, detects the protocol/ECUs, exposes read-only services, detects
/// link loss and reconnects. Holds no Flutter dependency.
class ObdClient {
  ObdClient({required this.transport, required this.table, this.config = const ObdClientConfig()})
      : elm = Elm327(transport, defaultTimeout: config.commandTimeout, searchTimeout: config.searchTimeout);

  final ObdTransport transport;
  final PidTable table;
  final ObdClientConfig config;
  final Elm327 elm;

  late final ObdServices services = ObdServices(elm, table);

  AdapterInfo info = AdapterInfo();
  DataMode dataMode = DataMode.live;
  SupportedPids? supported;

  final StreamController<LinkStatus> _status = StreamController<LinkStatus>.broadcast();
  final StreamController<ClientEvent> _events = StreamController<ClientEvent>.broadcast();
  LinkStatus _current = const LinkStatus();
  StreamSubscription<void>? _lostSub;
  bool _closing = false;
  bool _reconnecting = false;
  Completer<void>? _reconnectDone;

  /// When true, a lost link triggers automatic reconnection (live view).
  bool autoReconnect = false;

  Stream<LinkStatus> get status => _status.stream;
  LinkStatus get currentStatus => _current;
  Stream<AdapterState> get adapterState => status.map((s) => s.adapter).distinct();
  Stream<EcuState> get ecuState => status.map((s) => s.ecu).distinct();
  Stream<ClientEvent> get events => _events.stream;

  bool get isReady => _current.adapter == AdapterState.connected && _current.ecu == EcuState.connected;

  void _set(LinkStatus s) {
    _current = s;
    if (!_status.isClosed) _status.add(s);
  }

  void _event(String type, [String? detail]) {
    if (!_events.isClosed) _events.add(ClientEvent(type, detail));
  }

  /// Connects with up to [ObdClientConfig.maxAttempts] attempts and
  /// exponential backoff. Never throws for link problems: inspect the result.
  Future<ConnectResult> connect({String? deviceId, String? vehicleId}) async {
    _closing = false;
    final log = ConnectionLog(
      dataMode: transport.kind == TransportKind.demo ? DataMode.demo.apiValue : DataMode.live.apiValue,
      transport: transport.kind.apiValue,
      startedAt: DateTime.now().toUtc(),
      appPlatform: config.appPlatform,
      appVersion: config.appVersion,
      deviceId: deviceId,
      vehicleId: vehicleId,
    );
    final sw = Stopwatch()..start();
    var adapterOk = false;
    var ecuOk = false;
    for (var attempt = 1; attempt <= config.maxAttempts; attempt++) {
      log.attempts = attempt;
      final r = await _connectOnce(log);
      adapterOk = r.$1;
      ecuOk = r.$2;
      if (adapterOk) break;
      if (attempt < config.maxAttempts) {
        await Future<void>.delayed(config.backoff * (1 << (attempt - 1)));
      }
    }
    log.latencyMs = sw.elapsedMilliseconds;
    log.endedAt = DateTime.now().toUtc();
    log.dataMode = dataMode.apiValue;
    log.adapterFirmware = info.firmware;
    log.protocolCode = info.protocolCode;
    log.protocolName = info.protocolName;
    if (adapterOk) {
      log.adapterStatus = 'connected';
      _lostSub?.cancel();
      _lostSub = elm.onTransportLost.listen((_) => _onLinkLost('transport closed'));
    }
    return ConnectResult(adapterOk: adapterOk, ecuOk: ecuOk, info: info, log: log, dataMode: dataMode);
  }

  /// One full attempt. Returns (adapterOk, ecuOk).
  Future<(bool, bool)> _connectOnce(ConnectionLog log) async {
    _set(const LinkStatus(adapter: AdapterState.connecting, message: LinkMessage.connectingAdapter));
    try {
      await transport.connect();
    } on TransportException catch (e) {
      log.adapterStatus = e.code == 'timeout' ? 'timeout' : 'unreachable';
      log.errorCode = e.code;
      log.errorMessage = e.message;
      _set(LinkStatus(
        adapter: AdapterState.error,
        message: e.code == 'timeout' ? LinkMessage.adapterTimeout : LinkMessage.adapterUnreachable,
        detail: e.message,
      ));
      return (false, false);
    }
    elm.attach();
    final adapterOk = await _initAdapter(log);
    if (!adapterOk) {
      await transport.close();
      return (false, false);
    }
    final ecuOk = await _detectEcu(log);
    return (true, ecuOk);
  }

  Future<bool> _initAdapter(ConnectionLog log) async {
    _set(_current.copyWith(message: LinkMessage.initializing));
    info = AdapterInfo();
    // ATZ: reset; firmware banner e.g. "ELM327 v1.5".
    var z = await elm.send('ATZ', timeout: config.resetTimeout);
    if (!z.ok && z.error == ElmErrorKind.timeout) {
      z = await elm.send('ATZ', timeout: config.resetTimeout);
    }
    if (!z.ok) {
      final timeout = z.error == ElmErrorKind.timeout;
      log.adapterStatus = timeout ? 'timeout' : 'rejected';
      log.errorCode = z.error?.code;
      log.errorMessage = 'adapter did not answer ATZ';
      _set(LinkStatus(
        adapter: AdapterState.error,
        message: timeout ? LinkMessage.adapterTimeout : LinkMessage.adapterNotElm,
        detail: z.errorLine ?? z.error?.code ?? '',
      ));
      return false;
    }
    info.firmware = z.lines.firstWhere((l) => l.toUpperCase().contains('ELM'), orElse: () => z.lines.isEmpty ? '' : z.lines.last);
    if (info.firmware!.isEmpty) info.firmware = null;

    final unsupported = <String>[];
    for (final cmd in const ['ATE0', 'ATL0', 'ATS1', 'ATH1', 'ATAT1']) {
      final r = await elm.send(cmd);
      if (r.error == ElmErrorKind.timeout || r.error == ElmErrorKind.transportClosed) {
        log.adapterStatus = 'timeout';
        log.errorCode = r.error!.code;
        log.errorMessage = 'adapter stopped answering during init ($cmd)';
        _set(LinkStatus(adapter: AdapterState.error, message: LinkMessage.adapterTimeout, detail: cmd));
        return false;
      }
      // Clones answer "?" to some AT commands (e.g. ATAT1): continue.
      if (!r.ok) unsupported.add(cmd);
      if (cmd == 'ATH1' && !r.ok) info.headersOn = false;
    }
    final sp = config.protocol == '0' ? 'ATSP0' : 'ATSP${config.protocol}';
    final spr = await elm.send(sp);
    if (!spr.ok) unsupported.add(sp);
    final d = await elm.send('AT@1');
    if (d.ok) info.description = d.text;
    info.isSimulator = (info.description ?? '').toUpperCase().contains('AUTOMIND SIMULATOR');
    // The team's PC simulator is never live data.
    dataMode = (info.isSimulator || transport.kind == TransportKind.demo) ? DataMode.demo : DataMode.live;
    info.voltage = await services.readAdapterVoltage();
    info.unsupportedAtCommands = unsupported;
    services.headersOn = info.headersOn;
    _set(_current.copyWith(adapter: AdapterState.connected, message: LinkMessage.initializing));
    return true;
  }

  Future<bool> _detectEcu(ConnectionLog log) async {
    _set(_current.copyWith(ecu: EcuState.searching, message: LinkMessage.searchingProtocol));
    ElmResponse? last;
    var found = false;
    for (var i = 0; i < 2 && !found; i++) {
      final r = await elm.send('0100', timeout: config.searchTimeout);
      last = r;
      if (r.ok) {
        final msgs = ObdServices.positive(services.parser.parse(r.lines), 0x01, 0x00);
        found = msgs.isNotEmpty;
      }
      if (r.error == ElmErrorKind.transportClosed) break;
    }
    if (!found) {
      final err = last?.error;
      final bus = err == ElmErrorKind.busError ||
          err == ElmErrorKind.canError ||
          err == ElmErrorKind.busInitError ||
          err == ElmErrorKind.dataError;
      log.ecuStatus = bus ? 'bus_error' : (err == null || err.isVehicleSide ? 'no_response' : 'error');
      log.errorCode = err?.code ?? 'no_positive_response';
      log.errorMessage = last?.errorLine ?? 'no ECU answered 0100';
      _set(_current.copyWith(
        ecu: bus ? EcuState.busError : EcuState.noResponse,
        message: bus ? LinkMessage.ecuBusError : LinkMessage.ecuNoResponse,
        detail: last?.errorLine ?? err?.code ?? '',
      ));
      _event('ecu_no_response', last?.errorLine);
      return false;
    }
    final dpn = await elm.send('ATDPN');
    if (dpn.ok) {
      final p = ObdProtocol.fromDpn(dpn.text);
      info.protocolCode = p?.code ?? dpn.text;
      info.protocolAuto = ObdProtocol.isAutoDpn(dpn.text);
      services.family = p?.family ?? ProtocolFamily.unknown;
    }
    final dp = await elm.send('ATDP');
    if (dp.ok) info.protocolName = dp.text;
    log.ecuStatus = 'connected';
    log.errorCode = null;
    log.errorMessage = null;
    _set(_current.copyWith(ecu: EcuState.connected, message: LinkMessage.ecuConnected, detail: info.protocolName ?? ''));
    return true;
  }

  // ------------------------------------------------------------ link loss

  void _onLinkLost(String why) {
    if (_closing) return;
    unawaited(_lostSub?.cancel());
    _lostSub = null;
    _set(_current.copyWith(adapter: AdapterState.disconnected, ecu: EcuState.unknown, message: LinkMessage.linkLost, detail: why));
    _event('connection_lost', why);
    if (autoReconnect) unawaited(_reconnectLoop());
  }

  void _checkTimeoutStreak() {
    if (elm.consecutiveTimeouts >= config.timeoutStreakForLoss && !_reconnecting && !_closing) {
      elm.consecutiveTimeouts = 0;
      unawaited(transport.close());
      _onLinkLost('timeout streak');
    }
  }

  Future<void> _reconnectLoop() async {
    if (_reconnecting) return;
    _reconnecting = true;
    _reconnectDone = Completer<void>();
    try {
      for (var attempt = 1; attempt <= config.maxAttempts && !_closing; attempt++) {
        _set(_current.copyWith(message: LinkMessage.reconnecting, detail: 'attempt $attempt'));
        final log = ConnectionLog(dataMode: dataMode.apiValue, transport: transport.kind.apiValue, startedAt: DateTime.now().toUtc());
        final (a, e) = await _connectOnce(log);
        if (a) {
          _lostSub?.cancel();
          _lostSub = elm.onTransportLost.listen((_) => _onLinkLost('transport closed'));
          _event('reconnected', 'attempt $attempt${e ? '' : ' (ECU not responding)'}');
          _set(_current.copyWith(message: LinkMessage.reconnected));
          return;
        }
        await Future<void>.delayed(config.backoff * (1 << (attempt - 1)));
      }
      _set(_current.copyWith(adapter: AdapterState.error, message: LinkMessage.adapterUnreachable));
    } finally {
      _reconnecting = false;
      _reconnectDone?.complete();
    }
  }

  /// Waits for a running reconnection (used by pollers).
  Future<void> waitReconnect() => _reconnectDone?.future ?? Future<void>.value();

  bool get isReconnecting => _reconnecting;

  // ------------------------------------------------------------ services

  Future<SupportedPids> readSupportedPids() async {
    final s = await services.supportedPids();
    supported = s;
    return s;
  }

  /// Reads a supported PID; throws [NotSupportedException] otherwise.
  Future<List<PidReading>> readPid(int pid) async {
    final s = supported;
    if (s == null || !s.supports(pid)) throw NotSupportedException('PID ${pid.toRadixString(16)} not reported as supported');
    final r = await services.readPid(pid);
    _checkTimeoutStreak();
    return r;
  }

  Future<DtcReadResult> readDtcs(DtcStatus status) => services.readDtcs(status);

  Future<FreezeFrame?> readFreezeFrame() => services.readFreezeFrame(
        interesting: supported?.all,
      );

  Future<VinResult> readVin() async {
    final s = supported;
    if (s != null && s.service09.isNotEmpty && !s.service09.contains(0x02)) {
      return VinResult(null, valid: false, warning: 'not_supported');
    }
    return services.readVin();
  }

  Future<double?> readVoltage() => services.readAdapterVoltage();

  /// Clears DTCs (service 04) only when the server approved the operation
  /// and live data shows engine off (0 rpm) and vehicle stopped (0 km/h).
  Future<ClearDtcOutcome> clearDtcs(ClearDtcApproval approval) async {
    if (!approval.approvesClear) {
      throw PolicyViolationException('server did not approve clearing DTCs');
    }
    final rpm = await _readFirst(0x0C, 'engine_rpm');
    final speed = await _readFirst(0x0D, 'vehicle_speed');
    if (rpm == null || speed == null) {
      throw PolicyViolationException('cannot verify engine off / vehicle stopped (rpm=$rpm, speed=$speed)');
    }
    if (rpm > 0) throw PolicyViolationException('engine is running ($rpm rpm)');
    if (speed > 0) throw PolicyViolationException('vehicle is moving ($speed km/h)');
    final r = await elm.sendClearDtcs();
    final ok = r.ok && r.lines.any((l) => l.replaceAll(' ', '').toUpperCase().contains('44'));
    return ClearDtcOutcome(success: ok, requestFrames: const ['04'], responseFrames: r.ok ? r.lines : [r.errorLine ?? r.error?.code ?? 'error'], error: r.error?.code);
  }

  Future<double?> _readFirst(int pid, String key) async {
    final s = supported;
    if (s == null || !s.supports(pid)) return null;
    final r = await services.readPid(pid);
    return r.isEmpty ? null : r.first.values[key];
  }

  Future<void> disconnect() async {
    _closing = true;
    await _lostSub?.cancel();
    _lostSub = null;
    await elm.close();
    await transport.close();
    _set(const LinkStatus(message: LinkMessage.disconnected));
  }

  Future<void> dispose() async {
    await disconnect();
    await _status.close();
    await _events.close();
  }
}
