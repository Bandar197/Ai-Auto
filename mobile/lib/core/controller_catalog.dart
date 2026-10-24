import 'dart:convert';

/// One controller identifier from the catalogue (UNVERIFIED static identifier).
class ControllerEntry {
  const ControllerEntry({required this.id, required this.make, required this.category});
  final String id;
  final String make;
  final String category;

  /// Human label from the id, e.g. "hyundai_bcm_controller" → "Bcm".
  String get label {
    var s = id;
    if (s.startsWith('${make}_')) s = s.substring(make.length + 1);
    s = s.replaceAll('_controller', '').replaceAll('_', ' ').trim();
    return s.isEmpty ? id : s.split(' ').map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}').join(' ');
  }
}

/// Catalogue of controller identifiers, loaded from
/// `assets/shared/diag/controller_identifiers.json`.
///
/// These are UNVERIFIED static identifiers (module-group names per manufacturer) —
/// not CAN addresses and not proof that a module is readable on a given car. They are
/// shown for reference/filtering; readable modules come from the verified registry.
class ControllerCatalog {
  ControllerCatalog(this.entries, {this.version});
  factory ControllerCatalog.empty() => ControllerCatalog(const []);

  final List<ControllerEntry> entries;
  final String? version;

  List<String> get makes {
    final s = <String>{for (final e in entries) e.make};
    final list = s.toList()..sort();
    return list;
  }

  /// Entries for [make] (all when null), optionally filtered by a free-text [query]
  /// matched against id/label/category.
  List<ControllerEntry> filter({String? make, String query = ''}) {
    final q = query.trim().toLowerCase();
    return [
      for (final e in entries)
        if ((make == null || e.make == make) &&
            (q.isEmpty || e.id.contains(q) || e.label.toLowerCase().contains(q) || e.category.contains(q)))
          e,
    ];
  }

  static ControllerCatalog fromJsonString(String source) {
    final data = jsonDecode(source);
    if (data is! Map<String, dynamic>) return ControllerCatalog.empty();
    final out = <ControllerEntry>[];
    for (final e in (data['identifiers'] as List? ?? const [])) {
      if (e is! Map<String, dynamic>) continue;
      final id = e['id']?.toString();
      if (id == null || id.isEmpty) continue;
      out.add(ControllerEntry(
        id: id,
        make: '${e['make'] ?? ''}',
        category: '${e['category'] ?? 'other'}',
      ));
    }
    return ControllerCatalog(out, version: data['version']?.toString());
  }
}
