import '../../obd/obd.dart';

/// The eight clear contexts of the developer prompt (recording.v2 `clear_operations.context`).
enum ClearContext {
  allowed('allowed'),
  unsupportedByHardware('unsupported_by_hardware'),
  unsupportedByVehicle('unsupported_by_vehicle'),
  requiresOemAuthorization('requires_oem_authorization'),
  activeFaultNotClearable('active_fault_not_clearable'),
  crashDataSpecialist('crash_data_specialist'),
  commFailed('comm_failed'),
  clearedAndVerified('cleared_and_verified');

  const ClearContext(this.wire);
  final String wire;
}

/// The precise reason behind a context (shown to the user, kept in the audit log).
enum ClearReason {
  notConnected('not_connected'),
  replay('replay'),
  moduleNotRead('module_not_read'),
  moduleRefused('module_refused'),
  addressUnverified('address_unverified'),
  clearNotDocumented('clear_not_documented'),
  adapterNoHeaders('adapter_no_headers'),
  activeFault('active_fault'),
  crashData('crash_data'),
  safetyPolicy('safety_policy');

  const ClearReason(this.wire);
  final String wire;
}

/// One thing that could be cleared: the engine/OBD memory (service 04) or one module (UDS 0x14).
class ClearTarget {
  const ClearTarget({
    required this.key,
    required this.nameEn,
    required this.nameAr,
    required this.service,
    required this.codes,
    required this.context,
    this.reason,
    this.category = 'other',
    this.module,
    this.permanentCodes = const [],
    this.flaggedCodes = const [],
    this.proven = false,
  });

  /// 'engine' for OBD-II; otherwise the module key (srs, abs, bcm, …).
  final String key;
  final String nameEn;
  final String nameAr;

  /// '04' (OBD-II ClearDiagnosticInformation) or '14' (UDS).
  final String service;
  final List<String> codes;
  final ClearContext context;
  final ClearReason? reason;
  final String category;

  /// Registry module (address, verification) for UDS targets.
  final UdsModule? module;

  /// Engine: permanent codes (service 0A) are NOT erased by 04 — they clear themselves
  /// after the related monitor passes.
  final List<String> permanentCodes;

  /// Codes that caused the block (active / crash-data codes).
  final List<String> flaggedCodes;

  /// The module address was confirmed by a successful read on THIS car.
  final bool proven;

  bool get clearable => context == ClearContext.allowed;
  String name(String lang) => lang == 'ar' ? nameAr : nameEn;
}

class ClearPlan {
  const ClearPlan(this.targets);
  final List<ClearTarget> targets;

  Iterable<ClearTarget> get clearable => targets.where((t) => t.clearable);
  Iterable<ClearTarget> get blocked => targets.where((t) => !t.clearable);
}

/// Words in a code description that mark crash/deployment data (never cleared here; the
/// user is sent to a specialist).
const List<String> kCrashDataKeywords = ['crash', 'deploy', 'collision', 'impact data', 'event data'];

/// Server procedure that must be available (per-vehicle allowlist) before a safety
/// module (airbag / ABS) may be cleared.
const Map<String, String> kSafetyClearProcedure = {'airbag': 'clear_srs_dtcs', 'abs': 'clear_abs_dtcs'};

/// Server procedure for clearing any other module over UDS 0x14.
const String kModuleClearProcedure = 'clear_module_dtcs';

/// Builds the honest clear plan for the last scan: which targets can be cleared and,
/// for every other one, the context + reason. Nothing is sent from here.
///
/// A module is clearable only when ALL hold: it was read successfully with codes, no
/// code is active or crash-related, the adapter did not fail the header test, and
/// EITHER its address was proven by a successful read on this very car ([proven] —
/// standard UDS 0x14, the user's consent and the on-device audit are the record), OR
/// it is registry-verified with a documented clear and allowlisted by the server.
ClearPlan planClear({
  required Recording? recording,
  List<Map<String, dynamic>> reportDtcs = const [],
  required bool connected,
  required bool replay,
  AdapterCapabilities? adapter,
  List<UdsModule> registry = const [],
  Set<String>? serverProcedures,
  String? Function(String code)? describeEn,
  List<UdsModule> proven = const [],
}) {
  final targets = <ClearTarget>[];
  ClearReason? linkReason;
  if (replay) {
    linkReason = ClearReason.replay;
  } else if (!connected) {
    linkReason = ClearReason.notConnected;
  }

  // --- Engine / OBD-II (service 04) ---
  final obd = recording != null
      ? [for (final d in recording.dtcs) (d.code, d.status.apiValue)]
      : [for (final d in reportDtcs) ('${d['code']}', '${d['status'] ?? 'stored'}')];
  if (obd.isNotEmpty) {
    final codes = {for (final (c, _) in obd) c}.toList();
    final permanent = {for (final (c, s) in obd) if (s == 'permanent') c}.toList();
    targets.add(ClearTarget(
      key: 'engine',
      nameEn: 'Engine / emissions (OBD-II)',
      nameAr: 'المحرك / الانبعاثات (OBD-II)',
      service: '04',
      codes: codes,
      permanentCodes: permanent,
      context: linkReason == null ? ClearContext.allowed : ClearContext.commFailed,
      reason: linkReason,
      category: 'engine',
    ));
  }

  // --- Other modules (UDS 0x14) ---
  for (final m in recording?.moduleScans ?? const <RecordingModuleScan>[]) {
    if (m.outcome == 'read_no_codes') continue; // nothing to clear
    final codes = [for (final d in m.codes) d.code];
    final addr = (m.address ?? '').toUpperCase();
    final provenMod = proven.where((p) => p.key == m.key && _addr(p) == addr).firstOrNull;
    final reg = provenMod ??
        registry.where((r) => r.key == m.key && _addr(r) == addr).firstOrNull ??
        registry.where((r) => _addr(r) == addr).firstOrNull;

    ClearTarget t(ClearContext c, ClearReason? r, {List<String> flagged = const []}) => ClearTarget(
          key: m.key,
          nameEn: m.nameEn,
          nameAr: m.nameAr,
          service: '14',
          codes: codes,
          context: c,
          reason: r,
          category: m.category,
          module: reg,
          flaggedCodes: flagged,
          proven: provenMod != null,
        );

    if (linkReason != null) {
      targets.add(t(ClearContext.commFailed, linkReason));
      continue;
    }
    if (m.outcome == 'no_response') {
      targets.add(t(ClearContext.commFailed, ClearReason.moduleNotRead));
      continue;
    }
    if (m.outcome == 'refused') {
      targets.add(t(ClearContext.requiresOemAuthorization, ClearReason.moduleRefused));
      continue;
    }
    final crash = [
      for (final c in codes)
        if (kCrashDataKeywords.any((k) => (describeEn?.call(c) ?? '').toLowerCase().contains(k))) c,
    ];
    if (crash.isNotEmpty) {
      targets.add(t(ClearContext.crashDataSpecialist, ClearReason.crashData, flagged: crash));
      continue;
    }
    if (m.activeCodes.isNotEmpty) {
      targets.add(t(ClearContext.activeFaultNotClearable, ClearReason.activeFault, flagged: m.activeCodes));
      continue;
    }
    if (reg == null || !reg.verified) {
      targets.add(t(ClearContext.unsupportedByVehicle, ClearReason.addressUnverified));
      continue;
    }
    if (reg.clearService != 'uds14') {
      targets.add(t(ClearContext.unsupportedByVehicle, ClearReason.clearNotDocumented));
      continue;
    }
    if (adapter?.capabilities[Capability.headers] == false) {
      targets.add(t(ClearContext.unsupportedByHardware, ClearReason.adapterNoHeaders));
      continue;
    }
    final proc = kSafetyClearProcedure[m.category] ?? kModuleClearProcedure;
    if (provenMod == null && !(serverProcedures?.contains(proc) ?? false)) {
      targets.add(t(ClearContext.requiresOemAuthorization, ClearReason.safetyPolicy));
      continue;
    }
    targets.add(t(ClearContext.allowed, null));
  }
  return ClearPlan(targets);
}

String _addr(UdsModule m) => m.requestId.toRadixString(16).toUpperCase().padLeft(m.idBits == 29 ? 8 : 3, '0');
