import '../decode/dtc.dart';

/// Supported service 01 PIDs per ECU (from the 00/20/40… bitmasks).
class SupportedPids {
  SupportedPids(this.byEcu, {this.service09 = const {}});

  final Map<String, Set<int>> byEcu;
  final Set<int> service09;

  Set<int> get all => {for (final s in byEcu.values) ...s};

  bool supports(int pid) => all.contains(pid);

  List<String> get ecus => byEcu.keys.toList();

  /// ECU that reports the most PIDs (normally the engine ECU 7E8).
  String? get primaryEcu {
    String? best;
    var n = -1;
    for (final e in byEcu.entries) {
      if (e.value.length > n) {
        best = e.key;
        n = e.value.length;
      }
    }
    return best;
  }

  /// Recording v1 shape: {"01": ["0C", ...], "09": ["02"]}.
  Map<String, List<String>> toRecordingJson() {
    String h(int p) => p.toRadixString(16).padLeft(2, '0').toUpperCase();
    return {
      '01': (all.toList()..sort()).map(h).toList(),
      if (service09.isNotEmpty) '09': (service09.toList()..sort()).map(h).toList(),
    };
  }
}

/// One mode 01 answer from one ECU.
class PidReading {
  PidReading({required this.pid, required this.ecu, required this.raw, required this.values, this.at});

  final int pid;
  final String ecu;

  /// Data bytes as hex (`41 0C 1A F8`).
  final String raw;
  final Map<String, double?> values;
  final DateTime? at;

  String get requestId => '01${pid.toRadixString(16).padLeft(2, '0').toUpperCase()}';
}

class FreezeFrame {
  FreezeFrame({this.dtc, this.frame = 0, required this.values, this.ecu});
  final String? dtc;
  final int frame;
  final Map<String, double?> values;
  final String? ecu;

  Map<String, dynamic> toJson() => {'dtc': dtc, 'frame': frame, 'values': values};
}

class VinResult {
  VinResult(this.vin, {required this.valid, this.warning});
  final String? vin;
  final bool valid;
  final String? warning;
}

class DtcReadResult {
  DtcReadResult(this.dtcs, {this.error});
  final List<Dtc> dtcs;
  final String? error;
}
