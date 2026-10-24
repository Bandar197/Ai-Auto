import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/systems.dart';
import '../obd/obd.dart';
import 'connection_controller.dart';
import 'providers.dart';

/// One fault code found during a full scan, ready for display + "explain".
class ScanCode {
  const ScanCode({required this.code, this.description, this.active = false, this.confirmed = true, this.ecu});
  final String code;
  final String? description;
  final bool active; // module reported it failing now (UDS) — treated as high attention
  final bool confirmed; // stored/confirmed vs pending
  final String? ecu;
}

/// Codes grouped under one vehicle system, with how the read actually went.
class SystemGroup {
  const SystemGroup({
    required this.system,
    this.codes = const [],
    this.checked = false,
    this.refused = false,
    this.readOk = false,
  });
  final VehicleSystem system;
  final List<ScanCode> codes;
  final bool checked; // a read for this system was attempted
  final bool refused; // a module answered but refused (e.g. security gateway)
  final bool readOk; // a genuine, interpretable read happened (the only case "no faults" is honest)

  SystemGroup copy({List<ScanCode>? codes, bool? checked, bool? refused, bool? readOk}) => SystemGroup(
        system: system,
        codes: codes ?? this.codes,
        checked: checked ?? this.checked,
        refused: refused ?? this.refused,
        readOk: readOk ?? this.readOk,
      );
}

class FullScanState {
  const FullScanState({
    this.running = false,
    this.done = false,
    this.error,
    this.stage = '',
    this.groups = const {},
  });

  final bool running;
  final bool done;
  final String? error; // 'not_connected' | other
  final String stage; // current stage label key (system id or '')
  final Map<String, SystemGroup> groups;

  int get totalCodes => groups.values.fold(0, (n, g) => n + g.codes.length);

  FullScanState copy({bool? running, bool? done, String? error, String? stage, Map<String, SystemGroup>? groups}) =>
      FullScanState(
        running: running ?? this.running,
        done: done ?? this.done,
        error: error ?? this.error,
        stage: stage ?? this.stage,
        groups: groups ?? this.groups,
      );
}

class FullScanController extends Notifier<FullScanState> {
  @override
  FullScanState build() => const FullScanState();

  Map<String, SystemGroup> _empty() => {for (final s in kVehicleSystems) s.id: SystemGroup(system: s)};

  void _addCode(Map<String, SystemGroup> groups, String systemId, ScanCode c) {
    final g = groups[systemId] ?? SystemGroup(system: systemById(systemId));
    if (g.codes.any((x) => x.code == c.code && x.ecu == c.ecu)) return; // de-dupe
    groups[systemId] = g.copy(codes: [...g.codes, c]);
  }

  Future<void> run() async {
    if (state.running) return;
    final conn = ref.read(connectionProvider);
    final client = conn.client;
    if (client == null || !conn.ecuReady) {
      state = const FullScanState(done: true, error: 'not_connected');
      return;
    }
    final kb = ref.read(appAssetsProvider).kb;
    final lang = ref.read(settingsProvider).locale;
    final groups = _empty();
    state = FullScanState(running: true, groups: groups, stage: 'engine');

    // --- Stage 1: standard OBD codes (engine / emissions / transmission / electrical / network) ---
    try {
      var anyReadOk = false;
      for (final status in DtcStatus.values) {
        final res = await client.readDtcs(status);
        if (res.error == null) anyReadOk = true; // a successful, interpretable read happened
        for (final d in res.dtcs) {
          final entry = kb.lookup(d.code);
          final sysId = systemIdForDtc(d.code, subsystem: entry?.subsystem);
          _addCode(groups, sysId, ScanCode(
            code: d.code,
            description: entry?.description(lang),
            confirmed: status != DtcStatus.pending,
            ecu: d.ecu,
          ));
        }
      }
      // Mark OBD systems checked; "no faults" is only honest where a read actually succeeded.
      for (final s in kVehicleSystems) {
        if (s.source == ScanSource.obd) groups[s.id] = groups[s.id]!.copy(checked: true, readOk: anyReadOk);
      }
      state = state.copy(groups: {...groups});
    } on Object catch (e) {
      state = state.copy(error: e.toString());
    }

    // --- Stage 2: non-powertrain modules via UDS (SRS / ABS / body) — live only ---
    if (conn.mode != DataMode.replay) {
      state = state.copy(stage: 'modules');
      try {
        final make = ref.read(selectedVehicleProvider)?['make']?.toString();
        final registry = ref.read(appAssetsProvider).modules;
        final candidates = registry.candidatesFor(make);
        final found = await scanModules(
          client.elm,
          candidates: candidates.isNotEmpty ? candidates : kDiscoveryCandidates,
          includeNoResponse: true, // so a module that didn't answer is shown honestly, not as "no faults"
        );
        for (final m in found) {
          final sysId = systemIdForModuleCategory(m.module.category);
          final g = groups[sysId] ?? SystemGroup(system: systemById(sysId));
          groups[sysId] = g.copy(checked: true, refused: g.refused || m.refused, readOk: g.readOk || m.readOk);
          for (final d in m.dtcs) {
            final entry = kb.lookup(d.code);
            _addCode(groups, sysId, ScanCode(
              code: d.code,
              description: entry?.description(lang) ?? (lang == 'ar' ? d.code : d.code),
              active: d.active,
              confirmed: d.confirmed,
            ));
          }
        }
        state = state.copy(groups: {...groups});
      } on Object catch (_) {
        // modules are best-effort; engine results already stand.
      }
    }

    state = state.copy(running: false, done: true, stage: '');
  }
}

final fullScanProvider = NotifierProvider<FullScanController, FullScanState>(FullScanController.new);
