import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../obd/obd.dart';
import '../state/connection_controller.dart';
import '../ui/l10n_helpers.dart';
import '../ui/widgets.dart';

/// Service 06 on-board monitor test results: pass/fail per test from the raw values
/// and the limits the engine computer reports. Read-only.
class MonitorTestsScreen extends ConsumerStatefulWidget {
  const MonitorTestsScreen({super.key});
  @override
  ConsumerState<MonitorTestsScreen> createState() => _MonitorTestsScreenState();
}

class _MonitorTestsScreenState extends ConsumerState<MonitorTestsScreen> {
  MonitorTestReport? _report;
  bool _busy = false;
  String? _error;

  Future<void> _read() async {
    final c = ref.read(connectionProvider).client;
    if (c == null || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final r = await c.readMonitorTests();
      if (mounted) setState(() => _report = r);
    } on Object catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final lang = context.lang;
    final conn = ref.watch(connectionProvider);
    final r = _report;
    final byMid = <int, List<MonitorTest>>{};
    for (final t in r?.tests ?? const <MonitorTest>[]) {
      byMid.putIfAbsent(t.mid, () => []).add(t);
    }
    return Scaffold(
      appBar: AppBar(title: Text(l.monitorTestsTitle)),
      body: ListView(padding: const EdgeInsets.only(bottom: 24), children: [
        if (conn.mode != null) ModeBanner(mode: conn.mode!.apiValue, simulator: conn.isSimulator),
        Container(
          margin: const EdgeInsets.all(12),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: Colors.blue.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(10)),
          child: Text(l.monitorTestsIntro),
        ),
        if (!conn.ecuReady) Padding(padding: const EdgeInsets.all(16), child: Text(l.monitorTestsNeedConnection)),
        if (_busy) const Padding(padding: EdgeInsets.all(16), child: LinearProgressIndicator()),
        if (_error != null) Padding(padding: const EdgeInsets.all(16), child: Text(_error!, style: const TextStyle(color: Colors.red))),
        if (r?.unsupportedReason != null)
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(r!.unsupportedReason == 'not_can' ? l.monitorTestsNotCan : l.monitorTestsNotSupported),
          ),
        if (r != null && r.tests.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(l.monitorTestsSummary(r.tests.length, r.failed), style: const TextStyle(fontWeight: FontWeight.w700)),
          ),
        for (final e in byMid.entries)
          Card(
            key: Key('mid-${e.key}'),
            margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(midName(e.key, lang), style: const TextStyle(fontWeight: FontWeight.w700)),
                for (final t in e.value)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Row(children: [
                      Expanded(
                        child: Text(
                          'TID \$${t.tid.toRadixString(16).padLeft(2, '0').toUpperCase()} · '
                          '${l.monitorValues('${t.value}', '${t.min}', '${t.max}', '\$${t.uasid.toRadixString(16).padLeft(2, '0').toUpperCase()}')}',
                          style: Theme.of(context).textTheme.bodySmall,
                          textDirection: TextDirection.ltr,
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: (t.passed ? Colors.green : Colors.red).withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(t.passed ? l.monitorPass : l.monitorFail,
                            style: TextStyle(color: t.passed ? Colors.green.shade800 : Colors.red.shade800, fontWeight: FontWeight.w700, fontSize: 12)),
                      ),
                    ]),
                  ),
              ]),
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: FilledButton.icon(
            key: const Key('monitor-read'),
            icon: const Icon(Icons.fact_check_outlined),
            label: Text(l.monitorTestsRead),
            onPressed: conn.ecuReady && !_busy && conn.mode != DataMode.replay ? _read : null,
          ),
        ),
      ]),
    );
  }
}
