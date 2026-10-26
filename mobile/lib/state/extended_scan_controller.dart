import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../obd/obd.dart';
import '../core/clear/proven_modules.dart';
import 'connection_controller.dart';
import 'providers.dart';

/// Read-only discovery scan of non-powertrain modules (SRS/ABS/BCM) over UDS.
class ExtendedScanState {
  const ExtendedScanState({
    this.running = false,
    this.results = const [],
    this.error,
    this.done = false,
    this.deep = false,
    this.progress = 0,
    this.total = 0,
  });

  final bool running;
  final List<ModuleScan> results;
  final String? error; // 'not_connected' | 'replay' | other
  final bool done;
  final bool deep; // every approved address for this car's make (registry), not a blind sweep
  final int progress;
  final int total;
}

class ExtendedScanController extends Notifier<ExtendedScanState> {
  @override
  ExtendedScanState build() => const ExtendedScanState();

  /// [deep] = true probes every APPROVED address for the selected car's make from the
  /// curated registry (shared/obd/modules.json) plus the generic list. There is no blind
  /// sweep of the 0x700–0x7EF band (developer prompt rule 1.5).
  Future<void> run({bool deep = false}) async {
    if (state.running) return;
    final conn = ref.read(connectionProvider);
    final client = conn.client;
    if (conn.mode == DataMode.replay) {
      state = ExtendedScanState(error: 'replay', done: true, deep: deep);
      return;
    }
    if (client == null || !conn.ecuReady) {
      state = ExtendedScanState(error: 'not_connected', done: true, deep: deep);
      return;
    }
    final candidates = deep ? approvedCandidates() : kDiscoveryCandidates;
    state = ExtendedScanState(running: true, deep: deep, total: candidates.length);
    try {
      final results = await scanModules(
        client.elm,
        candidates: candidates,
        // Show modules that didn't answer too (honest, never "healthy").
        includeNoResponse: true,
        onProgress: (d, t) {
          if (state.running) state = ExtendedScanState(running: true, deep: deep, progress: d, total: t, results: state.results);
        },
      );
      state = ExtendedScanState(results: results, done: true, deep: deep, total: candidates.length, progress: candidates.length);
      try {
        await ProvenModulesStore(ref.read(localStoreProvider)).recordFromScan(
          provenVehicleKey(vehicleId: ref.read(settingsProvider).selectedVehicleId),
          results,
          mode: conn.mode ?? DataMode.demo,
        );
      } on Object catch (_) {}
    } on Object catch (e) {
      state = ExtendedScanState(error: e.toString(), done: true, deep: deep);
    }
  }

  /// Approved addresses for the selected vehicle's make (registry make profile + generic).
  List<UdsModule> approvedCandidates() {
    final make = ref.read(selectedVehicleProvider)?['make']?.toString();
    final list = ref.read(appAssetsProvider).modules.candidatesFor(make);
    return list.isNotEmpty ? list : kDiscoveryCandidates;
  }
}

final extendedScanProvider =
    NotifierProvider<ExtendedScanController, ExtendedScanState>(ExtendedScanController.new);
