import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../obd/obd.dart';
import 'connection_controller.dart';

/// Read-only discovery scan of non-powertrain modules (SRS/ABS/BCM) over UDS.
class ExtendedScanState {
  const ExtendedScanState({this.running = false, this.results = const [], this.error, this.done = false});

  final bool running;
  final List<ModuleScan> results;
  final String? error; // 'not_connected' | 'replay' | other
  final bool done;
}

class ExtendedScanController extends Notifier<ExtendedScanState> {
  @override
  ExtendedScanState build() => const ExtendedScanState();

  Future<void> run() async {
    if (state.running) return;
    final conn = ref.read(connectionProvider);
    final client = conn.client;
    if (conn.mode == DataMode.replay) {
      state = const ExtendedScanState(error: 'replay', done: true);
      return;
    }
    if (client == null || !conn.ecuReady) {
      state = const ExtendedScanState(error: 'not_connected', done: true);
      return;
    }
    state = const ExtendedScanState(running: true);
    try {
      final results = await scanModules(client.elm);
      state = ExtendedScanState(results: results, done: true);
    } on Object catch (e) {
      state = ExtendedScanState(error: e.toString(), done: true);
    }
  }
}

final extendedScanProvider =
    NotifierProvider<ExtendedScanController, ExtendedScanState>(ExtendedScanController.new);
