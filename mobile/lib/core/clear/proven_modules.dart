import '../../obd/obd.dart';
import '../storage/local_store.dart';

/// A module address confirmed on ONE specific car: it answered a UDS read (0x59)
/// during a LIVE scan of that car. Only such an address can be used to clear that
/// module's stored codes (with the user's consent) — never a registry guess, never
/// from a demo/simulator, never for another car.
class ProvenModule {
  const ProvenModule({
    required this.vehicleKey,
    required this.key,
    required this.requestId,
    required this.responseId,
    required this.idBits,
    required this.category,
    required this.nameEn,
    required this.nameAr,
    required this.provenAt,
  });

  factory ProvenModule.fromJson(Map<String, dynamic> j) => ProvenModule(
        vehicleKey: j['vehicle_key'] as String,
        key: j['key'] as String,
        requestId: (j['request_id'] as num).toInt(),
        responseId: (j['response_id'] as num).toInt(),
        idBits: (j['id_bits'] as num?)?.toInt() ?? 11,
        category: j['category'] as String? ?? 'other',
        nameEn: j['name_en'] as String? ?? '',
        nameAr: j['name_ar'] as String? ?? '',
        provenAt: DateTime.tryParse(j['proven_at'] as String? ?? '') ?? DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      );

  /// VIN-based (`vin:<VIN>`) or the server vehicle id — never empty / generic.
  final String vehicleKey;
  final String key;
  final int requestId;
  final int responseId;
  final int idBits;
  final String category;
  final String nameEn;
  final String nameAr;
  final DateTime provenAt;

  String get address => requestId.toRadixString(16).toUpperCase().padLeft(idBits == 29 ? 8 : 3, '0');

  /// As a module the clear path accepts: verified for this car, standard UDS 0x14.
  UdsModule toUdsModule() => UdsModule(
        key: key,
        nameEn: nameEn,
        nameAr: nameAr,
        requestId: requestId,
        responseId: responseId,
        idBits: idBits,
        category: switch (category) {
          'airbag' => ModuleCategory.airbag,
          'abs' => ModuleCategory.abs,
          _ => ModuleCategory.other,
        },
        verified: true,
        clearService: 'uds14',
      );

  Map<String, dynamic> toJson() => {
        'vehicle_key': vehicleKey,
        'key': key,
        'request_id': requestId,
        'response_id': responseId,
        'id_bits': idBits,
        'category': category,
        'name_en': nameEn,
        'name_ar': nameAr,
        'proven_at': provenAt.toUtc().toIso8601String(),
      };
}

/// A vehicle identity usable for "proven" addresses: VIN first, else a server vehicle
/// id. Returns null when the car can't be identified (then nothing is ever proven).
String? provenVehicleKey({String? vin, String? vehicleId}) {
  final v = vin?.trim().toUpperCase();
  if (v != null && RegExp(r'^[A-HJ-NPR-Z0-9]{17}$').hasMatch(v)) return 'vin:$v';
  if (vehicleId != null && vehicleId.isNotEmpty && !vehicleId.startsWith('local-')) return 'vehicle:$vehicleId';
  return null;
}

class ProvenModulesStore {
  ProvenModulesStore(this.store);
  final LocalStore store;
  static const String _file = 'proven_modules';

  Future<List<ProvenModule>> all() async {
    final raw = await store.readJson(_file);
    final out = <ProvenModule>[];
    for (final x in (raw as List? ?? const [])) {
      try {
        out.add(ProvenModule.fromJson((x as Map).cast<String, dynamic>()));
      } on Object catch (_) {}
    }
    return out;
  }

  Future<List<ProvenModule>> forVehicle(String? vehicleKey) async =>
      vehicleKey == null ? const [] : [for (final p in await all()) if (p.vehicleKey == vehicleKey) p];

  /// Records every module that answered a UDS read in a LIVE scan of [vehicleKey].
  /// A module that only refused or stayed silent proves nothing.
  Future<int> recordFromScan(String? vehicleKey, List<ModuleScan> scans, {required DataMode mode, DateTime? at}) async {
    if (vehicleKey == null || mode != DataMode.live) return 0;
    final list = await all();
    var n = 0;
    for (final s in scans.where((s) => s.readOk)) {
      list.removeWhere((p) => p.vehicleKey == vehicleKey && p.key == s.module.key);
      list.add(ProvenModule(
        vehicleKey: vehicleKey,
        key: s.module.key,
        requestId: s.module.requestId,
        responseId: s.module.responseId,
        idBits: s.module.idBits,
        category: s.inferredCategory.value,
        nameEn: s.module.nameEn,
        nameAr: s.module.nameAr,
        provenAt: (at ?? DateTime.now()).toUtc(),
      ));
      n++;
    }
    if (n > 0) await store.writeJson(_file, [for (final p in list) p.toJson()]);
    return n;
  }
}
