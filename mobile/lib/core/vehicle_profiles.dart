import 'dart:convert';

/// A vehicle compatibility profile (`assets/shared/obd/vehicle_profiles.json`).
/// Holds only established facts + open questions; `verified: false` until a logged
/// read on the car confirms it. It never adds module addresses.
class VehicleProfile {
  const VehicleProfile({
    required this.key,
    required this.make,
    required this.models,
    required this.years,
    required this.verified,
    required this.titleEn,
    required this.titleAr,
    this.notesEn = const [],
    this.notesAr = const [],
    this.srsUnreachableEn,
    this.srsUnreachableAr,
    this.coolingEn,
    this.coolingAr,
  });

  final String key;
  final String make;
  final List<String> models;
  final List<int> years;
  final bool verified;
  final String titleEn;
  final String titleAr;
  final List<String> notesEn;
  final List<String> notesAr;
  final String? srsUnreachableEn;
  final String? srsUnreachableAr;

  /// Where the radiator fan fuse/relays are and how to check them (owner's manual).
  final String? coolingEn;
  final String? coolingAr;
  String? cooling(String lang) => lang == 'ar' ? coolingAr : coolingEn;

  String title(String lang) => lang == 'ar' ? titleAr : titleEn;
  List<String> notes(String lang) => lang == 'ar' ? notesAr : notesEn;
  String? srsUnreachable(String lang) => lang == 'ar' ? srsUnreachableAr : srsUnreachableEn;
}

class VehicleProfiles {
  VehicleProfiles(this.profiles);
  factory VehicleProfiles.empty() => VehicleProfiles(const []);

  factory VehicleProfiles.fromJsonString(String source) {
    final data = jsonDecode(source);
    List<String> strs(dynamic v) => [for (final x in (v as List? ?? const [])) '$x'];
    return VehicleProfiles([
      for (final p in (data is Map ? (data['profiles'] as List? ?? const []) : const []))
        if (p is Map)
          VehicleProfile(
            key: '${p['key']}',
            make: '${p['make']}'.toLowerCase(),
            models: [for (final m in strs(p['model'])) m.toLowerCase()],
            years: [for (final y in (p['years'] as List? ?? const [])) if (y is int) y],
            verified: p['verified'] == true,
            titleEn: '${p['title_en'] ?? p['key']}',
            titleAr: '${p['title_ar'] ?? p['title_en'] ?? p['key']}',
            notesEn: strs(p['notes_en']),
            notesAr: strs(p['notes_ar']),
            srsUnreachableEn: p['srs_unreachable_en']?.toString(),
            srsUnreachableAr: p['srs_unreachable_ar']?.toString(),
            coolingEn: p['cooling_en']?.toString(),
            coolingAr: p['cooling_ar']?.toString(),
          ),
    ]);
  }

  final List<VehicleProfile> profiles;

  /// The profile for make + model (+ year when known). Make alone is not enough.
  VehicleProfile? match({String? make, String? model, int? year}) {
    final mk = make?.toLowerCase();
    final md = model?.toLowerCase().trim();
    if (mk == null || md == null || md.isEmpty) return null;
    for (final p in profiles) {
      if (p.make != mk) continue;
      if (!p.models.any((m) => md.contains(m))) continue;
      if (year != null && p.years.isNotEmpty && !p.years.contains(year)) continue;
      return p;
    }
    return null;
  }
}
