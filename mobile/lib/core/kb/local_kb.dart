import 'dart:convert';

/// One DTC definition from the bundled knowledge base.
class KbEntry {
  KbEntry({
    required this.code,
    this.descriptionEn,
    this.descriptionAr,
    this.severity,
    this.system,
    this.subsystem,
    this.drivable,
    this.causesEn = const [],
    this.causesAr = const [],
    this.oemMake,
    this.oemSource,
    this.oemVerified = false,
  });
  final String code;

  /// Set when the description is manufacturer-specific (from `dtc_oem.json`).
  final String? oemMake;
  final String? oemSource;

  /// Confirmed against manufacturer service information (false = community data).
  final bool oemVerified;
  final String? descriptionEn;
  final String? descriptionAr;
  final String? severity;
  final String? system;
  final String? subsystem;
  final bool? drivable;
  final List<String> causesEn;
  final List<String> causesAr;

  String? description(String lang) => lang == 'ar' ? (descriptionAr ?? descriptionEn) : (descriptionEn ?? descriptionAr);
  List<String> causes(String lang) => lang == 'ar' && causesAr.isNotEmpty ? causesAr : causesEn;
}

/// SAE J2012: true when the code's meaning is defined by each manufacturer
/// (P1xxx, P3000–P33FF, B1/B2, C1/C2, U1/U2) — the same code means different things
/// on different makes, so a generic description must never be shown for it.
bool isManufacturerSpecific(String code) {
  final c = code.toUpperCase();
  if (!RegExp(r'^[PCBU][0-9A-F]{4}$').hasMatch(c)) return false;
  final d1 = c[1];
  if (c[0] == 'P') return d1 == '1' || (d1 == '3' && '0123'.contains(c[2]));
  return d1 == '1' || d1 == '2';
}

/// Offline DTC lookup from `assets/shared/kb/dtc_definitions.json`. The file
/// is maintained by the backend team; the loader accepts a list of objects,
/// a `{code: {...}}` map, or either nested under `dtcs` / `codes` / `items`.
/// Unknown codes return null — meanings are never invented.
class LocalKb {
  LocalKb(this.entries, {this.version, Map<String, Map<String, KbEntry>>? oem, Map<String, String>? oemAliases})
      : oem = oem ?? const {},
        oemAliases = oemAliases ?? const {};

  factory LocalKb.empty() => LocalKb(const {});

  factory LocalKb.fromJsonString(String source) {
    final data = jsonDecode(source);
    String? version;
    dynamic body = data;
    if (data is Map<String, dynamic>) {
      version = (data['version'] ?? data['kb_version'])?.toString();
      body = data['dtcs'] ?? data['codes'] ?? data['items'] ?? data['definitions'] ?? data;
    }
    final out = <String, KbEntry>{};
    void add(String? code, Map<String, dynamic> m) {
      final c = (code ?? m['code'] as String?)?.toUpperCase();
      if (c == null || !RegExp(r'^[PCBU][0-9A-F]{4}$').hasMatch(c)) return;
      List<String> list(dynamic v) => v is List ? [for (final x in v) x is Map ? '${x['en'] ?? x['title_en'] ?? x}' : '$x'] : const [];
      List<String> listAr(dynamic v) => v is List ? [for (final x in v) x is Map ? '${x['ar'] ?? x['title_ar'] ?? x}' : '$x'] : const [];
      out[c] = KbEntry(
        code: c,
        descriptionEn: (m['description_en'] ?? m['en'] ?? m['description'])?.toString(),
        descriptionAr: (m['description_ar'] ?? m['ar'])?.toString(),
        severity: m['severity']?.toString(),
        system: m['system']?.toString(),
        subsystem: m['subsystem']?.toString(),
        drivable: m['drivable'] is bool ? m['drivable'] as bool : null,
        causesEn: list(m['common_causes'] ?? m['causes_en']),
        causesAr: listAr(m['common_causes_ar'] ?? m['common_causes'] ?? m['causes_ar']),
      );
    }

    if (body is List) {
      for (final x in body) {
        if (x is Map<String, dynamic>) add(null, x);
      }
    } else if (body is Map<String, dynamic>) {
      for (final e in body.entries) {
        if (e.value is Map<String, dynamic>) add(e.key, e.value as Map<String, dynamic>);
      }
    }
    return LocalKb(out, version: version);
  }

  final Map<String, KbEntry> entries;
  final String? version;

  /// make → code → manufacturer-specific entry (from `dtc_oem.json`).
  final Map<String, Map<String, KbEntry>> oem;

  /// alias → make (e.g. kia → hyundai when a profile lists it).
  final Map<String, String> oemAliases;

  bool get isEmpty => entries.isEmpty;

  /// Generic lookup (SAE-defined meanings only).
  KbEntry? lookup(String code) => entries[code.toUpperCase()];

  /// Make-aware lookup: the make's own entry first; a generic entry only for a
  /// generic code. A manufacturer-specific code with no entry for [make] → null.
  KbEntry? lookupFor(String code, {String? make}) {
    final c = code.toUpperCase();
    final m = make?.toLowerCase();
    if (m != null) {
      final hit = oem[m]?[c] ?? oem[oemAliases[m]]?[c];
      if (hit != null) return hit;
    }
    if (isManufacturerSpecific(c)) return null;
    return entries[c];
  }

  /// A copy with the manufacturer overlay (`dtc_oem.json`) merged in.
  LocalKb withOem(String source) {
    final data = jsonDecode(source);
    final out = <String, Map<String, KbEntry>>{};
    final aliases = <String, String>{};
    for (final p in (data is Map ? (data['profiles'] as List? ?? const []) : const [])) {
      if (p is! Map) continue;
      final make = '${p['make'] ?? ''}'.toLowerCase();
      if (make.isEmpty) continue;
      for (final a in (p['aliases'] as List? ?? const [])) {
        aliases['$a'.toLowerCase()] = make;
      }
      final codes = (p['codes'] as Map?) ?? const {};
      final m = out.putIfAbsent(make, () => {});
      for (final e in codes.entries) {
        final c = '${e.key}'.toUpperCase();
        final v = e.value;
        if (v is! Map || !RegExp(r'^[PCBU][0-9A-F]{4}$').hasMatch(c)) continue;
        m[c] = KbEntry(
          code: c,
          descriptionEn: v['en']?.toString(),
          descriptionAr: (v['ar']?.toString().isEmpty ?? true) ? null : v['ar'].toString(),
          severity: v['severity']?.toString(),
          system: v['system']?.toString(),
          oemMake: make,
          oemSource: (v['source'] ?? p['source'])?.toString(),
          oemVerified: (v['verified'] ?? p['verified']) == true,
        );
      }
    }
    return LocalKb(entries, version: version, oem: out, oemAliases: aliases);
  }
}
