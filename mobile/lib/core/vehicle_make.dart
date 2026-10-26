import 'dart:convert';

/// VIN → brand from the WMI table (`assets/shared/obd/wmi.json`). Longest prefix
/// wins; an unknown WMI returns null ("make unknown") — never a guess.
class WmiTable {
  WmiTable(this.prefixes);
  factory WmiTable.empty() => WmiTable(const {});

  factory WmiTable.fromJsonString(String source) {
    final data = jsonDecode(source);
    final p = data is Map ? (data['prefixes'] as Map?) ?? const {} : const {};
    return WmiTable({for (final e in p.entries) '${e.key}'.toUpperCase(): '${e.value}'.toLowerCase()});
  }

  final Map<String, String> prefixes;

  /// Brand for a VIN, or null. Needs a plausible 17-character VIN (no I/O/Q).
  String? makeFromVin(String? vin) {
    final v = (vin ?? '').trim().toUpperCase();
    if (!RegExp(r'^[A-HJ-NPR-Z0-9]{17}$').hasMatch(v)) return null;
    for (final n in const [3, 2]) {
      final m = prefixes[v.substring(0, n)];
      if (m != null) return m;
    }
    return null;
  }
}
