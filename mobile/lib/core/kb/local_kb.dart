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
  });
  final String code;
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

/// Offline DTC lookup from `assets/shared/kb/dtc_definitions.json`. The file
/// is maintained by the backend team; the loader accepts a list of objects,
/// a `{code: {...}}` map, or either nested under `dtcs` / `codes` / `items`.
/// Unknown codes return null — meanings are never invented.
class LocalKb {
  LocalKb(this.entries, {this.version});

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

  bool get isEmpty => entries.isEmpty;

  KbEntry? lookup(String code) => entries[code.toUpperCase()];
}
