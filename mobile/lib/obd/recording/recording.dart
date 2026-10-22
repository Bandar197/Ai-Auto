import 'dart:convert';

import '../decode/dtc.dart';
import '../services/obd_models.dart';

const String recordingFormat = 'automind.recording.v1';

class RecordingSample {
  RecordingSample({required this.tMs, required this.pid, required this.values, this.ecu, this.raw});

  factory RecordingSample.fromJson(Map<String, dynamic> j) => RecordingSample(
        tMs: (j['t_ms'] as num).toInt(),
        pid: j['pid'] as String,
        ecu: j['ecu'] as String?,
        raw: j['raw'] as String?,
        values: {
          for (final e in (j['values'] as Map<String, dynamic>).entries) e.key: (e.value as num?)?.toDouble(),
        },
      );

  final int tMs;

  /// service + pid, e.g. `010C`.
  final String pid;
  final String? ecu;
  final String? raw;
  final Map<String, double?> values;

  Map<String, dynamic> toJson() => {'t_ms': tMs, 'pid': pid, 'ecu': ecu, 'raw': raw, 'values': values};
}

class RecordingEvent {
  RecordingEvent({required this.tMs, required this.type, this.detail});
  factory RecordingEvent.fromJson(Map<String, dynamic> j) =>
      RecordingEvent(tMs: (j['t_ms'] as num).toInt(), type: j['type'] as String, detail: j['detail'] as String?);

  final int tMs;

  /// connection_lost | reconnected | ecu_no_response | note
  final String type;
  final String? detail;

  Map<String, dynamic> toJson() => {'t_ms': tMs, 'type': type, 'detail': detail};
}

class RecordingSignal {
  RecordingSignal({required this.key, required this.pid, this.unit});
  factory RecordingSignal.fromJson(Map<String, dynamic> j) =>
      RecordingSignal(key: j['key'] as String, pid: j['pid'] as String, unit: j['unit'] as String?);
  final String key;
  final String pid;
  final String? unit;
  Map<String, dynamic> toJson() => {'key': key, 'pid': pid, 'unit': unit};
}

/// Recording v1 (`shared/schemas/recording.v1.schema.json`). [dataMode] is
/// `live` or `demo` and is never relabelled — a replay keeps it.
class Recording {
  Recording({
    required this.recordingId,
    required this.createdAt,
    required this.dataMode,
    required this.source,
    required this.durationMs,
    required this.signals,
    required this.samples,
    this.vehicle = const {},
    this.supportedPids = const {},
    this.ecus = const [],
    this.dtcs = const [],
    this.freezeFrames = const [],
    this.events = const [],
  });

  factory Recording.fromJsonString(String s) => Recording.fromJson(jsonDecode(s) as Map<String, dynamic>);

  factory Recording.fromJson(Map<String, dynamic> j) {
    if (j['format'] != recordingFormat) throw FormatException('not an AutoMind v1 recording: ${j['format']}');
    return Recording(
      recordingId: j['recording_id'] as String,
      createdAt: DateTime.parse(j['created_at'] as String),
      dataMode: j['data_mode'] as String,
      source: Map<String, dynamic>.from(j['source'] as Map),
      vehicle: Map<String, dynamic>.from((j['vehicle'] as Map?) ?? const {}),
      supportedPids: {
        for (final e in ((j['supported_pids'] as Map?) ?? const {}).entries)
          e.key as String: [for (final p in e.value as List) p as String],
      },
      ecus: [for (final e in (j['ecus'] as List? ?? const [])) e as String],
      dtcs: [for (final d in (j['dtcs'] as List? ?? const [])) Dtc.fromJson(d as Map<String, dynamic>)],
      freezeFrames: [
        for (final f in (j['freeze_frames'] as List? ?? const []))
          FreezeFrame(
            dtc: (f as Map<String, dynamic>)['dtc'] as String?,
            frame: (f['frame'] as num?)?.toInt() ?? 0,
            values: {for (final e in ((f['values'] as Map?) ?? const {}).entries) e.key as String: (e.value as num?)?.toDouble()},
          ),
      ],
      durationMs: (j['duration_ms'] as num).toInt(),
      signals: [for (final s in j['signals'] as List) RecordingSignal.fromJson(s as Map<String, dynamic>)],
      samples: [for (final s in j['samples'] as List) RecordingSample.fromJson(s as Map<String, dynamic>)],
      events: [for (final e in (j['events'] as List? ?? const [])) RecordingEvent.fromJson(e as Map<String, dynamic>)],
    );
  }

  final String recordingId;
  final DateTime createdAt;
  final String dataMode;
  final Map<String, dynamic> source;
  final Map<String, dynamic> vehicle;
  final Map<String, List<String>> supportedPids;
  final List<String> ecus;
  final List<Dtc> dtcs;
  final List<FreezeFrame> freezeFrames;
  final int durationMs;
  final List<RecordingSignal> signals;
  final List<RecordingSample> samples;
  final List<RecordingEvent> events;

  String? get demoScenario => source['demo_scenario'] as String?;

  Map<String, dynamic> toJson() => {
        'format': recordingFormat,
        'recording_id': recordingId,
        'created_at': createdAt.toUtc().toIso8601String(),
        'data_mode': dataMode,
        'source': source,
        'vehicle': vehicle,
        'supported_pids': supportedPids,
        'ecus': ecus,
        'dtcs': [for (final d in dtcs) d.toJson()],
        'freeze_frames': [for (final f in freezeFrames) f.toJson()],
        'duration_ms': durationMs,
        'signals': [for (final s in signals) s.toJson()],
        'samples': [for (final s in samples) s.toJson()],
        'events': [for (final e in events) e.toJson()],
      };

  String toJsonString({bool pretty = false}) =>
      pretty ? const JsonEncoder.withIndent(' ').convert(toJson()) : jsonEncode(toJson());

  /// Per-signal time series {key: [(t_ms, value)]}.
  Map<String, List<(int, double)>> series() {
    final out = <String, List<(int, double)>>{};
    for (final s in samples) {
      for (final e in s.values.entries) {
        final v = e.value;
        if (v != null) out.putIfAbsent(e.key, () => []).add((s.tMs, v));
      }
    }
    return out;
  }

  /// Copy without the VIN (privacy default for uploads).
  Recording redactVin() => Recording(
        recordingId: recordingId,
        createdAt: createdAt,
        dataMode: dataMode,
        source: source,
        vehicle: {...vehicle, 'vin': null},
        supportedPids: supportedPids,
        ecus: ecus,
        dtcs: dtcs,
        freezeFrames: freezeFrames,
        durationMs: durationMs,
        signals: signals,
        samples: samples,
        events: events,
      );

  /// Required top-level fields per the JSON schema; returns problems found.
  static List<String> validateJson(Map<String, dynamic> j) {
    final problems = <String>[];
    for (final k in const ['format', 'recording_id', 'created_at', 'data_mode', 'source', 'duration_ms', 'signals', 'samples']) {
      if (!j.containsKey(k)) problems.add('missing $k');
    }
    if (j['format'] != recordingFormat) problems.add('bad format');
    if (!const ['live', 'demo'].contains(j['data_mode'])) problems.add('bad data_mode');
    final src = j['source'];
    if (src is! Map || !const ['elm327_wifi', 'elm327_ble', 'elm327_serial', 'simulator'].contains(src['kind'])) {
      problems.add('bad source.kind');
    }
    if (j['duration_ms'] is! int || (j['duration_ms'] as int) < 0) problems.add('bad duration_ms');
    if (!RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$').hasMatch('${j['recording_id']}')) {
      problems.add('recording_id not a uuid');
    }
    for (final s in (j['samples'] as List? ?? const [])) {
      final m = s as Map;
      if (m['t_ms'] is! int || m['pid'] is! String || m['values'] is! Map) {
        problems.add('bad sample $m');
        break;
      }
    }
    for (final s in (j['signals'] as List? ?? const [])) {
      if (s is! Map || s['key'] is! String || s['pid'] is! String) {
        problems.add('bad signal $s');
        break;
      }
    }
    for (final d in (j['dtcs'] as List? ?? const [])) {
      if (!RegExp(r'^[PCBU][0-9A-F]{4}$').hasMatch('${(d as Map)['code']}')) problems.add('bad dtc $d');
    }
    return problems;
  }
}
