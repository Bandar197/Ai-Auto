import '../client/states.dart';
import '../decode/dtc.dart';
import '../decode/pid_table.dart';
import '../services/obd_models.dart';
import 'recording.dart';

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

  int get sampleCount => _samples.length;
  int elapsedMs([DateTime? at]) => (at ?? _now()).difference(_startedAt).inMilliseconds.clamp(0, 1 << 31);

  void setSupported(SupportedPids s) {
    supportedPids = s.toRecordingJson();
    ecus = s.ecus;
  }

  void addReading(PidReading r) {
    final pidHex = r.requestId;
    final def = table[r.pid];
    for (final e in r.values.keys) {
      _signals.putIfAbsent(
          e, () => RecordingSignal(key: e, pid: pidHex, unit: def?.outputs.where((o) => o.key == e).firstOrNull?.unit));
    }
    _samples.add(RecordingSample(tMs: elapsedMs(r.at), pid: pidHex, ecu: r.ecu, raw: r.raw, values: r.values));
  }

  void addEvent(String type, [String? detail, DateTime? at]) =>
      _events.add(RecordingEvent(tMs: elapsedMs(at), type: type, detail: detail));

  Recording build() {
    final duration = _samples.isEmpty ? elapsedMs() : _samples.last.tMs;
    return Recording(
      recordingId: _id,
      createdAt: _startedAt,
      dataMode: dataMode.apiValue,
      source: {
        'kind': sourceKind,
        'adapter_firmware': adapterFirmware,
        'protocol_code': protocolCode,
        'protocol_name': protocolName,
        'demo_scenario': demoScenario,
        'app': app,
      },
      vehicle: vehicle,
      supportedPids: supportedPids,
      ecus: ecus,
      dtcs: dtcs,
      freezeFrames: freezeFrames,
      durationMs: duration,
      signals: _signals.values.toList(),
      samples: List.unmodifiable(_samples),
      events: List.unmodifiable(_events),
    );
  }
}
