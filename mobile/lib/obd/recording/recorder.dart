import '../client/capability_probe.dart';
import '../client/states.dart';
import '../decode/dtc.dart';
import '../decode/pid_table.dart';
import '../decode/readiness.dart';
import '../hex.dart';
import '../services/obd_models.dart';
import '../elm327/elm327.dart';
import 'recording.dart';
import 'traffic.dart';

/// Collects a session into a [Recording]. Times are relative to [start].
class Recorder {
  Recorder({
    required this.dataMode,
    required this.sourceKind,
    required this.table,
    required String Function() newId,
    this.adapterFirmware,
    this.protocolCode,
    this.protocolName,
    this.demoScenario,
    this.app,
    DateTime Function()? now,
  })  : _now = now ?? (() => DateTime.now().toUtc()),
        _id = newId() {
    if (dataMode == DataMode.replay) throw ArgumentError('a replay is never re-recorded as new data');
    _startedAt = _now();
  }

  final DataMode dataMode;

  /// elm327_wifi | elm327_ble | elm327_serial | simulator
  final String sourceKind;
  final PidTable table;
  final String? adapterFirmware;
  final String? protocolCode;
  final String? protocolName;
  final String? demoScenario;
  final String? app;
  final DateTime Function() _now;
  final String _id;
  late final DateTime _startedAt;

  final List<RecordingSample> _samples = [];
  final List<RecordingEvent> _events = [];
  final Map<String, RecordingSignal> _signals = {};
  Map<String, dynamic> vehicle = {};
  Map<String, List<String>> supportedPids = {};
  List<String> ecus = [];
  List<Dtc> dtcs = [];
  List<FreezeFrame> freezeFrames = [];

  /// Latest service 01 PID 01 readiness (filled automatically from readings).
  Map<String, dynamic>? readiness;

  /// Proven adapter capabilities for this session, when a probe ran.
  AdapterCapabilities? adapterCapabilities;

  TrafficTap? _traffic;

  /// Receives every sample, event and TX/RX frame as it happens, plus [checkpoint]
  /// snapshots — wire it to a durable journal so an interrupted session survives.
  void Function(Map<String, dynamic> entry)? onEntry;

  /// Start capturing every adapter command/reply (TX/RX) into this recording. Calling
  /// it again (e.g. after a reconnect) follows the new link and keeps earlier frames.
  TrafficTap attachTraffic(Stream<ElmResponse> log) {
    final existing = _traffic;
    if (existing != null) return existing..attach(log);
    return _traffic = TrafficTap(
      startedAt: _startedAt,
      now: _now,
      onFrame: (f) => onEntry?.call({'type': 'frame', 'f': f.toJson()}),
    )..attach(log);
  }

  Map<String, dynamic> _source() => {
        'kind': sourceKind,
        'adapter_firmware': adapterFirmware,
        'protocol_code': protocolCode,
        'protocol_name': protocolName,
        'demo_scenario': demoScenario,
        'app': app,
      };

  /// Header for a journal `start` line (identity of this recording).
  Map<String, dynamic> journalHeader() => {
        'recording_id': _id,
        'created_at': _startedAt.toUtc().toIso8601String(),
        'data_mode': dataMode.apiValue,
        'source': _source(),
      };

  /// Writes the current vehicle/DTC/freeze-frame/readiness state to [onEntry].
  void checkpoint() => onEntry?.call({
        'type': 'snapshot',
        'r': {
          'vehicle': vehicle,
          'supported_pids': supportedPids,
          'ecus': ecus,
          'dtcs': [for (final d in dtcs) d.toJson()],
          'freeze_frames': [for (final f in freezeFrames) f.toJson()],
          'readiness': ?readiness,
          'signals': [for (final s in _signals.values) s.toJson()],
          if (adapterCapabilities != null) 'adapter_capabilities': adapterCapabilities!.toJson(),
        },
      });

  Future<void> detachTraffic() async => _traffic?.detach();

  int get sampleCount => _samples.length;
  int elapsedMs([DateTime? at]) => (at ?? _now()).difference(_startedAt).inMilliseconds.clamp(0, 1 << 31);

  void setSupported(SupportedPids s) {
    supportedPids = s.toRecordingJson();
    ecus = s.ecus;
  }

  void addReading(PidReading r) {
    if (r.pid == 0x01) {
      final b = parseHexBytes(r.raw);
      if (b != null && b.length >= 6) readiness = decodeMonitorStatus(b.sublist(2)) ?? readiness;
    }
    final pidHex = r.requestId;
    final def = table[r.pid];
    for (final e in r.values.keys) {
      _signals.putIfAbsent(
          e, () => RecordingSignal(key: e, pid: pidHex, unit: def?.outputs.where((o) => o.key == e).firstOrNull?.unit));
    }
    final sample = RecordingSample(tMs: elapsedMs(r.at), pid: pidHex, ecu: r.ecu, raw: r.raw, values: r.values);
    _samples.add(sample);
    onEntry?.call({'type': 'sample', 's': sample.toJson()});
  }

  void addEvent(String type, [String? detail, DateTime? at]) {
    final e = RecordingEvent(tMs: elapsedMs(at), type: type, detail: detail);
    _events.add(e);
    onEntry?.call({'type': 'event', 'e': e.toJson()});
  }

  Recording build() {
    final duration = _samples.isEmpty ? elapsedMs() : _samples.last.tMs;
    return Recording(
      recordingId: _id,
      createdAt: _startedAt,
      dataMode: dataMode.apiValue,
      source: _source(),
      vehicle: vehicle,
      supportedPids: supportedPids,
      ecus: ecus,
      dtcs: dtcs,
      freezeFrames: freezeFrames,
      durationMs: duration,
      signals: _signals.values.toList(),
      samples: List.unmodifiable(_samples),
      events: List.unmodifiable([
        ..._events,
        if (_traffic?.truncated ?? false)
          RecordingEvent(tMs: elapsedMs(), type: 'traffic_truncated', detail: 'TX/RX log reached ${_traffic!.maxFrames} frames'),
      ]),
      readiness: readiness,
      adapterCapabilities: adapterCapabilities,
      txRxFrames: _traffic?.frames ?? const [],
    );
  }
}
