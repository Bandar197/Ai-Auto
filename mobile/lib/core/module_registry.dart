import 'dart:convert';

import '../obd/obd.dart';

/// Per-manufacturer registry of non-powertrain module CAN addresses
/// (airbag/SRS, ABS, body), loaded from `assets/shared/obd/modules.json`.
///
/// Addresses are per make/model/year and must be verified on a real car; entries
/// marked `verified: false` are discovery starting points. The `generic` profile
/// is appended for every vehicle. Unknown make → generic candidates only.
class ModuleProfile {
  const ModuleProfile({required this.make, this.aliases = const [], this.protocol, this.modules = const []});
  final String make;
  final List<String> aliases;
  final String? protocol; // ELM ATSP code hint (e.g. "7" for 29-bit)
  final List<UdsModule> modules;

  bool matches(String make) {
    final m = make.toLowerCase();
    return this.make.toLowerCase() == m || aliases.any((a) => a.toLowerCase() == m);
  }
}

class ModuleRegistry {
  ModuleRegistry(this.profiles, {this.version});
  factory ModuleRegistry.empty() => ModuleRegistry(const []);

  final List<ModuleProfile> profiles;
  final String? version;

  ModuleProfile? get generic {
    for (final p in profiles) {
      if (p.make.toLowerCase() == 'generic') return p;
    }
    return null;
  }

  /// Candidate modules to probe for [make]: the make's own profile first, then the
  /// generic profile, de-duped by address. Empty make → generic only.
  List<UdsModule> candidatesFor(String? make) {
    final out = <UdsModule>[];
    final seen = <String>{};
    void add(Iterable<UdsModule> mods) {
      for (final m in mods) {
        final k = '${m.requestId}:${m.responseId}:${m.idBits}';
        if (seen.add(k)) out.add(m);
      }
    }

    if (make != null && make.trim().isNotEmpty) {
      for (final p in profiles) {
        if (p.make.toLowerCase() != 'generic' && p.matches(make.trim())) add(p.modules);
      }
    }
    final g = generic;
    if (g != null) add(g.modules);
    return out;
  }

  static ModuleRegistry fromJsonString(String source) {
    final data = jsonDecode(source);
    if (data is! Map<String, dynamic>) return ModuleRegistry.empty();
    final profiles = <ModuleProfile>[];
    for (final p in (data['profiles'] as List? ?? const [])) {
      if (p is! Map<String, dynamic>) continue;
      final make = p['make']?.toString();
      if (make == null || make.isEmpty) continue;
      final mods = <UdsModule>[];
      for (final m in (p['modules'] as List? ?? const [])) {
        if (m is! Map<String, dynamic>) continue;
        final req = int.tryParse('${m['request']}', radix: 16);
        final resp = int.tryParse('${m['response']}', radix: 16);
        final bits = m['id_bits'] is int ? m['id_bits'] as int : 11;
        if (req == null || resp == null) continue;
        mods.add(UdsModule(
          key: '${m['key'] ?? make}',
          nameEn: '${m['name_en'] ?? m['key'] ?? ''}',
          nameAr: '${m['name_ar'] ?? m['name_en'] ?? m['key'] ?? ''}',
          requestId: req,
          responseId: resp,
          idBits: bits == 29 ? 29 : 11,
          category: switch ('${m['category']}') {
            'airbag' => ModuleCategory.airbag,
            'abs' => ModuleCategory.abs,
            _ => ModuleCategory.other,
          },
          verified: m['verified'] == true,
          clearService: m['clear'] == 'uds14' ? 'uds14' : null,
        ));
      }
      profiles.add(ModuleProfile(
        make: make,
        aliases: [for (final a in (p['aliases'] as List? ?? const [])) '$a'],
        protocol: p['protocol']?.toString(),
        modules: mods,
      ));
    }
    return ModuleRegistry(profiles, version: data['version']?.toString());
  }
}
