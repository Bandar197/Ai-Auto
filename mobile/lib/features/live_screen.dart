import 'dart:async';
import 'dart:convert';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';
import 'package:uuid/uuid.dart';

import '../obd/obd.dart';
import '../state/connection_controller.dart';
import '../state/providers.dart';
import '../ui/l10n_helpers.dart';
import '../ui/plausible.dart';
import '../ui/widgets.dart';

class LiveScreen extends ConsumerStatefulWidget {
  const LiveScreen({super.key});
  @override
  ConsumerState<LiveScreen> createState() => _LiveScreenState();
}

class _LiveScreenState extends ConsumerState<LiveScreen> {
  static const double windowS = 120;
  static const List<int> defaultPids = [0x0C, 0x0D, 0x05, 0x0B];

  LivePoller? _poller;
  ReplaySource? _replay;
  StreamSubscription<PidReading>? _sub;
  StreamSubscription<RecordingSample>? _replaySub;
  Timer? _ticker;
  final Map<String, List<FlSpot>> _series = {};
  final Map<String, List<FlSpot>> _compare = {};
  final Stopwatch _clock = Stopwatch();
  Set<int> _selected = {};
  Recorder? _recorder;
  ObdClient? _boundClient;
  Recording? _boundReplay;
  String? _compareName;

  @override
  void dispose() {
    _teardown();
    super.dispose();
  }

  void _teardown() {
    _sub?.cancel();
    _replaySub?.cancel();
    _ticker?.cancel();
    _poller?.dispose();
    _replay?.dispose();
    _poller = null;
    _replay = null;
    _boundClient = null;
    _boundReplay = null;
  }

  void _add(String key, double t, double? v) {
    if (v == null) return;
    final list = _series.putIfAbsent(key, () => []);
    list.add(FlSpot(t, v));
    while (list.isNotEmpty && list.first.x < t - windowS) {
      list.removeAt(0);
    }
  }

  Future<void> _bindClient(ObdClient client) async {
    _teardown();
    _boundClient = client;
    _series.clear();
    if (client.supported == null) await client.readSupportedPids();
    final sup = client.supported!.all;
    _selected = {for (final p in defaultPids) if (sup.contains(p)) p};
    final poller = LivePoller(client, pids: _selected);
    _poller = poller;
    _clock
      ..reset()
      ..start();
    _sub = poller.readings.listen((r) {
      final t = _clock.elapsedMilliseconds / 1000;
      r.values.forEach((k, v) => _add(k, t, v));
      _recorder?.addReading(r);
    });
    unawaited(poller.start());
    _ticker = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (mounted) setState(() {});
    });
    if (mounted) setState(() {});
  }

  void _bindReplay(Recording rec) {
    _teardown();
    _boundReplay = rec;
    _series.clear();
    final table = ref.read(appAssetsProvider).table;
    final replay = ReplaySource(rec, table: table);
    _replay = replay;
    _selected = {for (final s in rec.signals) int.tryParse(s.pid.substring(2), radix: 16) ?? 0}..remove(0);
    _replaySub = replay.samples.listen((s) {
      s.values.forEach((k, v) => _add(k, s.tMs / 1000, v));
    });
    _ticker = Timer.periodic(const Duration(milliseconds: 300), (_) {
      if (mounted) setState(() {});
    });
  }

  void _toggleRecord(ConnState conn) {
    final l = context.l10n;
    final client = conn.client;
    if (client == null) return;
    if (_recorder == null) {
      final r = Recorder(
        dataMode: client.dataMode,
        sourceKind: conn.sourceKind,
        table: ref.read(appAssetsProvider).table,
        newId: const Uuid().v4,
        adapterFirmware: client.info.firmware,
        protocolCode: client.info.protocolCode,
        protocolName: client.info.protocolName,
        demoScenario: conn.scenarioKey,
        app: 'automind-mobile/$appVersion',
      );
      final s = client.supported;
      if (s != null) r.setSupported(s);
      setState(() => _recorder = r);
    } else {
      final rec = _recorder!.build();
      setState(() => _recorder = null);
      ref.read(localStoreProvider).saveRecording(rec).then((_) {
        if (mounted) showSnack(context, l.recordingSaved);
      });
    }
  }

  Future<void> _pickCompare() async {
    final list = await ref.read(localStoreProvider).listRecordings();
    if (!mounted) return;
    final l = context.l10n;
    final rec = await showModalBottomSheet<Recording>(
      context: context,
      builder: (ctx) => list.isEmpty
          ? Padding(padding: const EdgeInsets.all(24), child: Text(l.noRecordings))
          : ListView(children: [
              for (final r in list)
                ListTile(
                  title: Text('${modeText(l, r.dataMode)} · ${r.demoScenario ?? ''}'),
                  subtitle: Text('${r.createdAt.toLocal()}'),
                  onTap: () => Navigator.pop(ctx, r),
                ),
            ]),
    );
    if (rec == null) return;
    _compare.clear();
    final t0 = rec.samples.isEmpty ? 0 : rec.samples.first.tMs;
    rec.series().forEach((k, pts) {
      _compare[k] = [for (final (t, v) in pts) FlSpot((t - t0) / 1000, v)];
    });
    setState(() => _compareName = '${modeText(l, rec.dataMode)} ${rec.createdAt.toLocal()}');
  }

  Future<void> _export({required bool csv}) async {
    final store = ref.read(localStoreProvider);
    final stamp = DateTime.now().toUtc().toIso8601String().replaceAll(':', '-');
    final mode = ref.read(connectionProvider).mode?.apiValue ?? 'live';
    String content;
    if (csv) {
      final b = StringBuffer('data_mode,t_s,signal,value\n');
      _series.forEach((k, pts) {
        for (final p in pts) {
          b.writeln('$mode,${p.x.toStringAsFixed(3)},$k,${p.y}');
        }
      });
      content = b.toString();
    } else {
      content = const JsonEncoder.withIndent(' ').convert({
        'data_mode': mode,
        'series': {for (final e in _series.entries) e.key: [for (final p in e.value) {'t': p.x, 'v': p.y}]},
      });
    }
    final f = await store.writeExport('automind_live_${mode}_$stamp.${csv ? 'csv' : 'json'}', content);
    await SharePlus.instance.share(ShareParams(files: [XFile(f.path)]));
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final conn = ref.watch(connectionProvider);
    final table = ref.watch(appAssetsProvider).table;

    if (conn.mode == DataMode.replay && conn.replay != null && _boundReplay != conn.replay) {
      _bindReplay(conn.replay!);
    } else if (conn.mode != DataMode.replay && conn.ecuReady && conn.client != null && _boundClient != conn.client) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _bindClient(conn.client!));
    }

    final notReady = !(conn.ecuReady || conn.replay != null);
    final supported = conn.client?.supported?.all ?? const <int>{};
    final choices = conn.replay != null
        ? _selected.toList()
        : [for (final d in table.byPid.values) if (supported.contains(d.pidByte) && d.isLiveSignal) d.pidByte];

    return Scaffold(
      appBar: AppBar(
        title: Text(l.liveTitle),
        actions: [
          PopupMenuButton<String>(
            onSelected: (v) {
              if (v == 'csv') _export(csv: true);
              if (v == 'json') _export(csv: false);
              if (v == 'compare') _pickCompare();
              if (v == 'nocompare') {
                setState(() {
                  _compare.clear();
                  _compareName = null;
                });
              }
            },
            itemBuilder: (_) => [
              PopupMenuItem(value: 'compare', child: Text(l.compareWith)),
              if (_compareName != null) PopupMenuItem(value: 'nocompare', child: Text(l.clearCompare)),
              PopupMenuItem(value: 'csv', child: Text(l.exportCsv)),
              PopupMenuItem(value: 'json', child: Text(l.exportJson)),
            ],
          ),
        ],
      ),
      body: notReady
          ? Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text(l.notConnected),
                const SizedBox(height: 12),
                FilledButton(onPressed: () => context.push('/connect'), child: Text(l.connect)),
              ]),
            )
          : Column(children: [
              if (conn.mode != null) ModeBanner(mode: conn.mode!.apiValue, originalMode: conn.replay?.dataMode, simulator: conn.isSimulator),
              if (conn.client != null)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Row(children: [
                    Expanded(child: StatusChips(status: conn.status, simulator: conn.isSimulator)),
                    Text(l.sampleRate((_poller?.sampleRate ?? 0).toStringAsFixed(1))),
                  ]),
                ),
              if (_replay != null) _replayControls(context),
              if (choices.isEmpty)
                Padding(padding: const EdgeInsets.all(16), child: Text(l.noSupportedSignals))
              else
                SizedBox(
                  height: 48,
                  child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 8), children: [
                    for (final pid in choices)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 3),
                        child: FilterChip(
                          label: Text(table[pid]?.outputs.first.name(context.lang) ?? pid.toRadixString(16)),
                          selected: _selected.contains(pid),
                          onSelected: conn.replay != null
                              ? null
                              : (v) => setState(() {
                                    v ? _selected.add(pid) : _selected.remove(pid);
                                    _poller?.setPids(_selected);
                                  }),
                        ),
                      ),
                  ]),
                ),
              if (_compareName != null)
                Padding(padding: const EdgeInsets.symmetric(horizontal: 12), child: Text('↔ $_compareName', style: Theme.of(context).textTheme.bodySmall)),
              Expanded(
                child: ListView(children: [
                  for (final pid in _selected)
                    for (final o in table[pid]?.outputs ?? const <PidOutput>[])
                      if (o.unit != 'enum' && o.unit != 'bitmask') _chart(context, o),
                ]),
              ),
            ]),
      floatingActionButton: conn.client != null && conn.ecuReady
          ? FloatingActionButton.extended(
              backgroundColor: _recorder != null ? Colors.red : null,
              icon: Icon(_recorder != null ? Icons.stop : Icons.fiber_manual_record),
              label: Text(_recorder != null ? '${l.stopRecording} (${_recorder!.sampleCount})' : l.record),
              onPressed: () => _toggleRecord(conn),
            )
          : null,
    );
  }

  Widget _replayControls(BuildContext context) {
    final r = _replay!;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(children: [
        IconButton(
          icon: Icon(r.isPlaying ? Icons.pause : Icons.play_arrow),
          onPressed: () => setState(() => r.isPlaying ? r.pause() : r.play()),
        ),
        Expanded(
          child: Slider(
            value: r.positionMs.clamp(0, r.durationMs == 0 ? 1 : r.durationMs).toDouble(),
            max: (r.durationMs == 0 ? 1 : r.durationMs).toDouble(),
            onChanged: (v) => setState(() {
              _series.clear();
              r.seek(v.round());
            }),
          ),
        ),
        SegmentedButton<double>(
          showSelectedIcon: false,
          segments: const [
            ButtonSegment(value: 1, label: Text('1x')),
            ButtonSegment(value: 2, label: Text('2x')),
            ButtonSegment(value: 4, label: Text('4x')),
          ],
          selected: {r.speed},
          onSelectionChanged: (s) => setState(() => r.setSpeed(s.first)),
        ),
      ]),
    );
  }

  Widget _chart(BuildContext context, PidOutput o) {
    final l = context.l10n;
    final spots = _series[o.key] ?? const <FlSpot>[];
    final cmp = _compare[o.key];
    final last = spots.isEmpty ? null : spots.last.y;
    final anomalous = last != null && isAnomalous(o.key, last, min: o.min, max: o.max);
    final color = Theme.of(context).colorScheme.primary;
    bool bad(FlSpot s) => isAnomalous(o.key, s.y, min: o.min, max: o.max);
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: anomalous ? Colors.red : Colors.transparent, width: 2),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text(o.name(context.lang), style: const TextStyle(fontWeight: FontWeight.w700))),
            if (anomalous) Chip(label: Text(l.outOfRange), backgroundColor: Colors.red.withValues(alpha: 0.15), visualDensity: VisualDensity.compact),
            const SizedBox(width: 6),
            Text(last == null ? '—' : '${last.toStringAsFixed(last.abs() < 10 ? 2 : 0)} ${o.unit}',
                textDirection: TextDirection.ltr, style: Theme.of(context).textTheme.titleMedium),
          ]),
          SizedBox(
            height: 120,
            child: Directionality(
              textDirection: TextDirection.ltr, // time axis always left → right
              child: LineChart(
                LineChartData(
                  minX: spots.isEmpty ? 0 : (spots.last.x - windowS).clamp(0, double.infinity),
                  maxX: spots.isEmpty ? windowS : spots.last.x.clamp(10, double.infinity),
                  clipData: const FlClipData.all(),
                  gridData: const FlGridData(show: true, drawVerticalLine: false),
                  borderData: FlBorderData(show: false),
                  titlesData: const FlTitlesData(
                    topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 20)),
                    leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 40)),
                  ),
                  lineTouchData: const LineTouchData(enabled: false),
                  lineBarsData: [
                    if (cmp != null && cmp.isNotEmpty)
                      LineChartBarData(spots: cmp, color: Colors.grey, barWidth: 1.5, dashArray: const [4, 4], dotData: const FlDotData(show: false)),
                    LineChartBarData(
                      spots: spots.isEmpty ? const [FlSpot(0, 0)] : spots,
                      color: spots.isEmpty ? Colors.transparent : color,
                      barWidth: 2,
                      dotData: FlDotData(
                        show: true,
                        checkToShowDot: (s, _) => bad(s),
                        getDotPainter: (s, p, b, i) => FlDotCirclePainter(radius: 3, color: Colors.red, strokeWidth: 0),
                      ),
                    ),
                  ],
                ),
                duration: Duration.zero,
              ),
            ),
          ),
        ]),
      ),
    );
  }
}
