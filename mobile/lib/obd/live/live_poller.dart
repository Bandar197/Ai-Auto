import 'dart:async';
import 'dart:collection';

import '../client/obd_client.dart';
import '../errors.dart';
import '../services/obd_models.dart';

/// Round-robin poller over user-selected PIDs (only those reported as
/// supported). Measures the effective sample rate.
class LivePoller {
  LivePoller(this.client, {Iterable<int> pids = const [], this.interRequestDelay = Duration.zero}) {
    setPids(pids);
  }

  final ObdClient client;
  final Duration interRequestDelay;

  final StreamController<PidReading> _out = StreamController<PidReading>.broadcast();
  Stream<PidReading> get readings => _out.stream;

  List<int> _pids = [];
  List<int> get pids => List.unmodifiable(_pids);
  List<int> rejected = [];
  bool _running = false;
  int _cursor = 0;
  final Queue<DateTime> _times = Queue<DateTime>();
  int noDataCount = 0;

  bool get isRunning => _running;

  /// Keeps only supported PIDs; the rest are listed in [rejected].
  void setPids(Iterable<int> pids) {
    final sup = client.supported?.all ?? const <int>{};
    _pids = [for (final p in pids) if (sup.contains(p)) p];
    rejected = [for (final p in pids) if (!sup.contains(p)) p];
    _cursor = 0;
  }

  /// Samples per second over the last 5 s.
  double get sampleRate {
    final now = DateTime.now();
    while (_times.isNotEmpty && now.difference(_times.first) > const Duration(seconds: 5)) {
      _times.removeFirst();
    }
    if (_times.length < 2) return 0;
    final span = _times.last.difference(_times.first).inMicroseconds / 1e6;
    return span <= 0 ? 0 : (_times.length - 1) / span;
  }

  Future<void> start() async {
    if (_running) return;
    _running = true;
    client.autoReconnect = true;
    while (_running) {
      if (_pids.isEmpty) {
        await Future<void>.delayed(const Duration(milliseconds: 200));
        continue;
      }
      if (client.isReconnecting) {
        await client.waitReconnect();
        continue;
      }
      if (client.currentStatus.adapter != AdapterState.connected) {
        await Future<void>.delayed(const Duration(milliseconds: 300));
        continue;
      }
      final pid = _pids[_cursor % _pids.length];
      _cursor++;
      try {
        final r = await client.readPid(pid);
        if (r.isEmpty) {
          noDataCount++;
        } else {
          _times.add(DateTime.now());
          for (final x in r) {
            if (!_out.isClosed) _out.add(x);
          }
        }
      } on NotSupportedException {
        _pids.remove(pid);
      }
      if (interRequestDelay > Duration.zero) await Future<void>.delayed(interRequestDelay);
    }
  }

  void stop() {
    _running = false;
    client.autoReconnect = false;
  }

  Future<void> dispose() async {
    stop();
    await _out.close();
  }
}
