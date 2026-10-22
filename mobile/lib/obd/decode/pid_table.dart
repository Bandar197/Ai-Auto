import 'dart:convert';

import '../hex.dart';

/// One decoded output of a PID (e.g. `engine_rpm`).
class PidOutput {
  PidOutput({
    required this.key,
    required this.nameEn,
    required this.nameAr,
    required this.unit,
    required this.start,
    required this.length,
    required this.scale,
    required this.offset,
    required this.signed,
    required this.min,
    required this.max,
  });

  factory PidOutput.fromJson(Map<String, dynamic> j) => PidOutput(
        key: j['key'] as String,
        nameEn: j['name_en'] as String? ?? j['key'] as String,
        nameAr: j['name_ar'] as String? ?? j['key'] as String,
        unit: j['unit'] as String? ?? '',
        start: (j['start'] as num?)?.toInt() ?? 0,
        length: (j['length'] as num?)?.toInt() ?? 1,
        scale: (j['scale'] as num?)?.toDouble() ?? 1,
        offset: (j['offset'] as num?)?.toDouble() ?? 0,
        signed: j['signed'] as bool? ?? false,
        min: (j['min'] as num?)?.toDouble(),
        max: (j['max'] as num?)?.toDouble(),
      );

  final String key;
  final String nameEn;
  final String nameAr;
  final String unit;
  final int start;
  final int length;
  final double scale;
  final double offset;
  final bool signed;
  final double? min;
  final double? max;

  String name(String lang) => lang == 'ar' ? nameAr : nameEn;
}

class PidDefinition {
  PidDefinition({
    required this.pid,
    required this.service,
    required this.nameEn,
    required this.nameAr,
    required this.bytes,
    required this.kind,
    required this.category,
    required this.outputs,
  });

  factory PidDefinition.fromJson(Map<String, dynamic> j) => PidDefinition(
        pid: (j['pid'] as String).toUpperCase(),
        service: j['service'] as String? ?? '01',
        nameEn: j['name_en'] as String? ?? '',
        nameAr: j['name_ar'] as String? ?? '',
        bytes: (j['bytes'] as num?)?.toInt() ?? 1,
        kind: j['kind'] as String? ?? 'linear',
        category: j['category'] as String? ?? 'other',
        outputs: [
          for (final o in (j['outputs'] as List? ?? const [])) PidOutput.fromJson(o as Map<String, dynamic>),
        ],
      );

  final String pid;
  final String service;
  final String nameEn;
  final String nameAr;
  final int bytes;
  final String kind;
  final String category;
  final List<PidOutput> outputs;

  int get pidByte => int.parse(pid, radix: 16);

  /// `010C` style identifier used in recordings.
  String get requestId => '$service$pid';

  bool get isMeta => kind == 'supported_bitmask' || kind == 'dtc' || (outputs.isEmpty);

  /// Pollable in live view: has numeric outputs and is not a bitmask/meta PID.
  bool get isLiveSignal => outputs.isNotEmpty && kind != 'supported_bitmask' && kind != 'bitmask_raw';

  String name(String lang) => lang == 'ar' ? nameAr : nameEn;
}

/// The shared SAE J1979 table (`shared/obd/pids.json`) and decoder.
class PidTable {
  PidTable._(this.version, this.byPid, this.enums);

  factory PidTable.fromJsonString(String source) =>
      PidTable.fromJson(jsonDecode(source) as Map<String, dynamic>);

  factory PidTable.fromJson(Map<String, dynamic> j) {
    final by = <int, PidDefinition>{};
    for (final p in (j['pids'] as List)) {
      final d = PidDefinition.fromJson(p as Map<String, dynamic>);
      if (d.service == '01') by[d.pidByte] = d;
    }
    final enums = <String, Map<String, dynamic>>{};
    final e = j['enums'];
    if (e is Map<String, dynamic>) {
      for (final entry in e.entries) {
        if (entry.value is Map<String, dynamic>) enums[entry.key] = entry.value as Map<String, dynamic>;
      }
    }
    return PidTable._(j['version'] as String? ?? '0', by, enums);
  }

  final String version;
  final Map<int, PidDefinition> byPid;
  final Map<String, Map<String, dynamic>> enums;

  PidDefinition? operator [](int pid) => byPid[pid];

  /// Finds the PID that produces [key] (e.g. `map_kpa` → 0x0B).
  PidDefinition? pidForKey(String key) {
    for (final d in byPid.values) {
      if (d.outputs.any((o) => o.key == key)) return d;
    }
    return null;
  }

  PidOutput? outputForKey(String key) {
    for (final d in byPid.values) {
      for (final o in d.outputs) {
        if (o.key == key) return o;
      }
    }
    return null;
  }

  /// Decodes the data bytes that follow the PID byte (A = data[0]).
  /// Output keys are exactly those of pids.json. Values are numbers (enums
  /// stay numeric codes; use [enumLabel] to display them) or null when the
  /// standard defines the value as not applicable.
  Map<String, double?> decode(int pid, List<int> data) {
    final def = byPid[pid];
    if (def == null) return const {};
    final out = <String, double?>{};
    switch (def.kind) {
      case 'monitor_status':
        if (data.isEmpty) return const {};
        for (final o in def.outputs) {
          if (o.key == 'mil_on') out[o.key] = ((data[0] >> 7) & 1).toDouble();
          if (o.key == 'dtc_count') out[o.key] = (data[0] & 0x7F).toDouble();
        }
        return out;
      case 'supported_bitmask':
      case 'dtc':
        return const {};
      default:
        for (final o in def.outputs) {
          if (o.start + o.length > data.length) {
            out[o.key] = null;
            continue;
          }
          // O2 sensor trim (PIDs 14..1B byte B) is not applicable when 0xFF.
          if (pid >= 0x14 && pid <= 0x1B && o.start == 1 && data[1] == 0xFF) {
            out[o.key] = null;
            continue;
          }
          var raw = 0;
          for (var i = 0; i < o.length; i++) {
            raw = (raw << 8) | (data[o.start + i] & 0xFF);
          }
          if (o.signed && (raw & (1 << (8 * o.length - 1))) != 0) raw -= 1 << (8 * o.length);
          out[o.key] = roundValue(raw * o.scale + o.offset);
        }
        return out;
    }
  }

  /// Decodes a full positive response (`41 0C 1A F8` → {engine_rpm: 1726}).
  Map<String, double?> decodeResponse(List<int> response) {
    if (response.length < 2 || (response[0] != 0x41 && response[0] != 0x42)) return const {};
    final skip = response[0] == 0x42 ? 3 : 2; // mode 02 carries a frame number
    if (response.length < skip) return const {};
    return decode(response[1], response.sublist(skip));
  }

  Map<String, double?> decodeHex(String hex) {
    final b = parseHexBytes(hex);
    return b == null ? const {} : decodeResponse(b);
  }

  /// Human label for enum outputs (fuel system status, OBD standard, fuel type).
  String? enumLabel(String key, num? value, {String lang = 'en'}) {
    if (value == null) return null;
    final code = value.toInt().toString();
    if (key.startsWith('fuel_system_')) {
      final name = enums['fuel_system_status']?[code] as String?;
      if (name == null) return null;
      final label = enums['fuel_system_status_labels']?[name];
      if (label is Map) return (label[lang] ?? label['en']) as String?;
      return name;
    }
    if (key == 'obd_standard') return enums['obd_standard']?[code] as String?;
    if (key == 'fuel_type') return enums['fuel_type']?[code] as String?;
    return null;
  }

  /// Inverse of [decode] for linear outputs (used by the demo emulator).
  List<int> encode(int pid, Map<String, double> values) {
    final def = byPid[pid];
    if (def == null) return const [];
    final data = List<int>.filled(def.bytes, 0);
    for (final o in def.outputs) {
      final v = values[o.key];
      if (v == null) continue;
      var raw = ((v - o.offset) / o.scale).round();
      final bits = 8 * o.length;
      if (o.signed) {
        final lo = -(1 << (bits - 1));
        final hi = (1 << (bits - 1)) - 1;
        raw = raw.clamp(lo, hi);
        if (raw < 0) raw += 1 << bits;
      } else {
        raw = raw.clamp(0, (1 << bits) - 1);
      }
      for (var i = 0; i < o.length; i++) {
        final shift = 8 * (o.length - 1 - i);
        if (o.start + i < data.length) data[o.start + i] = (raw >> shift) & 0xFF;
      }
    }
    return data;
  }
}

/// Rounds to 6 decimals so JSON stays clean (14.094 not 14.094000000000001).
double roundValue(double v) => (v * 1e6).roundToDouble() / 1e6;

/// Decodes a 4-byte "PIDs supported" bitmask relative to [base]
/// (0x00 → PIDs 0x01..0x20).
List<int> decodeSupportedBitmask(int base, List<int> mask) {
  final out = <int>[];
  for (var i = 0; i < 32 && i ~/ 8 < mask.length; i++) {
    final byte = mask[i ~/ 8];
    if ((byte >> (7 - (i % 8))) & 1 == 1) out.add(base + i + 1);
  }
  return out;
}

List<int> encodeSupportedBitmask(int base, Iterable<int> pids) {
  final mask = [0, 0, 0, 0];
  for (final p in pids) {
    final i = p - base - 1;
    if (i < 0 || i > 31) continue;
    mask[i ~/ 8] |= 1 << (7 - (i % 8));
  }
  return mask;
}
