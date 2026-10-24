import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../obd/obd.dart';
import 'connection_controller.dart';

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
  final bool deep; // a broad address sweep (slower, finds unverified modules)
  final int progress;
  final int total;
}

class ExtendedScanController extends Notifier<ExtendedScanState> {
  @override
  ExtendedScanState build() => const ExtendedScanState();

  /// [deep] = true probes every common 11-bit address (slower) to find modules whose
  /// exact address is not yet known for this make — e.g. a Hyundai airbag module.
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
    final candidates = deep ? deepSweep11() : kDiscoveryCandidates;
    state = ExtendedScanState(running: true, deep: deep, total: candidates.length);
    try {
      final results = await scanModules(
        client.elm,
        candidates: candidates,
        perModuleTimeout: Duration(milliseconds: deep ? 450 : 700),
        onProgress: (d, t) {
          if (state.running) state = ExtendedScanState(running: true, deep: deep, progress: d, total: t, results: state.results);
        },
      );
      state = ExtendedScanState(results: results, done: true, deep: deep, total: candidates.length, progress: candidates.length);
    } on Object catch (e) {
      state = ExtendedScanState(error: e.toString(), done: true, deep: deep);
    }
  }
}

final extendedScanProvider =
    NotifierProvider<ExtendedScanController, ExtendedScanState>(ExtendedScanController.new);
