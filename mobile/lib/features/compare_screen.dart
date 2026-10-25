import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' show DateFormat;

import '../core/recording/session_compare.dart';
import '../core/storage/scan_report.dart';
import '../l10n/app_localizations.dart';
import '../state/providers.dart';
import '../ui/l10n_helpers.dart';

/// Side-by-side comparison of two saved sessions: new / gone / persisting codes and
/// module read changes. A code is "gone" only when the later session really read it.
class CompareScreen extends ConsumerStatefulWidget {
  const CompareScreen({super.key, this.beforeId, this.afterId});
  final String? beforeId;
  final String? afterId;

  @override
  ConsumerState<CompareScreen> createState() => _CompareScreenState();
}

class _CompareScreenState extends ConsumerState<CompareScreen> {
  String? _before;
  String? _after;
  Future<SessionDiff?>? _diff;
  String? _computedFor;

  @override
  void initState() {
    super.initState();
    _before = widget.beforeId;
    _after = widget.afterId;
  }

  void _recompute(List<ScanReport> reports) {
    final key = '$_before|$_after|${reports.length}';
    if (key == _computedFor) return; // only when the selection changes
    _computedFor = key;
    final a = reports.where((r) => r.id == _before).firstOrNull;
    final b = reports.where((r) => r.id == _after).firstOrNull;
    if (a?.recordingId == null || b?.recordingId == null || a!.id == b!.id) {
      _diff = null;
      return;
    }
    final store = ref.read(localStoreProvider);
    _diff = () async {
      final ra = await store.loadRecording(a.recordingId!);
      final rb = await store.loadRecording(b.recordingId!);
      return ra == null || rb == null ? null : compareSessions(ra, rb);
    }();
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final reports = (ref.watch(reportsProvider).value ?? const <ScanReport>[]).where((r) => r.recordingId != null).toList()
      ..sort((x, y) => x.createdAt.compareTo(y.createdAt));
    if (reports.length >= 2 && _before == null && _after == null) {
      _before = reports[reports.length - 2].id;
      _after = reports.last.id;
    }
    _recompute(reports);
    String label(ScanReport r) =>
        '${DateFormat.yMMMd(context.lang).add_Hm().format(r.createdAt.toLocal())}${r.dataMode == 'live' ? '' : ' · ${modeText(l, r.dataMode).toUpperCase()}'}';

    Widget picker(String title, String? value, void Function(String?) onChanged, Key key) => Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          child: DropdownButtonFormField<String>(
            key: key,
            initialValue: value,
            isExpanded: true,
            decoration: InputDecoration(labelText: title),
            items: [for (final r in reports) DropdownMenuItem(value: r.id, child: Text(label(r)))],
            onChanged: onChanged,
          ),
        );

    return Scaffold(
      appBar: AppBar(title: Text(l.compareTitle)),
      body: reports.length < 2
          ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(l.compareNeedTwo, textAlign: TextAlign.center)))
          : ListView(padding: const EdgeInsets.only(bottom: 24), children: [
              picker(l.compareBefore, _before, (v) => setState(() => _before = v), const Key('compare-before')),
              picker(l.compareAfter, _after, (v) => setState(() => _after = v), const Key('compare-after')),
              const SizedBox(height: 8),
              FutureBuilder<SessionDiff?>(
                future: _diff,
                builder: (context, snap) {
                  if (snap.connectionState != ConnectionState.done) {
                    return const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()));
                  }
                  final d = snap.data;
                  if (d == null) return const SizedBox.shrink();
                  return _DiffView(diff: d);
                },
              ),
            ]),
    );
  }
}

class _DiffView extends StatelessWidget {
  const _DiffView({required this.diff});
  final SessionDiff diff;

  static String outcomeText(AppLocalizations l, String? o) => switch (o) {
        'read_codes' => l.moduleReadCodes,
        'read_no_codes' => l.moduleNoCodes,
        'refused' => l.moduleRefused,
        'no_response' => l.moduleNoResponse,
        _ => l.compareNotRead,
      };

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    Widget section(String title, Color color, IconData icon, Iterable<CodeDiff> items, Key key) {
      final list = items.toList();
      if (list.isEmpty) return const SizedBox.shrink();
      return Card(
        key: key,
        margin: const EdgeInsets.fromLTRB(12, 6, 12, 6),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(icon, color: color),
              const SizedBox(width: 8),
              Expanded(child: Text('$title (${list.length})', style: const TextStyle(fontWeight: FontWeight.w700))),
            ]),
            const SizedBox(height: 6),
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (final c in list)
                Chip(
                  label: Text(c.module == null ? c.code : '${c.code} · ${c.module}', textDirection: TextDirection.ltr),
                  visualDensity: VisualDensity.compact,
                ),
            ]),
          ]),
        ),
      );
    }

    final none = diff.codes.isEmpty && diff.unverified.isEmpty;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (diff.mixedModes)
        Container(
          margin: const EdgeInsets.fromLTRB(12, 4, 12, 4),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: Colors.orange.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(8)),
          child: Text(l.compareMixedModes),
        ),
      if (none) Padding(padding: const EdgeInsets.all(16), child: Text(l.compareNoChanges, textAlign: TextAlign.center)),
      section(l.compareNew, Colors.red.shade700, Icons.add_alert_outlined, diff.of(CodeChange.newCode), const Key('diff-new')),
      section(l.comparePersisting, Colors.orange.shade800, Icons.history, diff.of(CodeChange.persisting), const Key('diff-persisting')),
      section(l.compareResolved, Colors.green.shade700, Icons.check_circle_outline, diff.of(CodeChange.resolved), const Key('diff-resolved')),
      section(l.compareUnverified, Colors.blueGrey, Icons.help_outline, diff.unverified, const Key('diff-unverified')),
      if (diff.modules.isNotEmpty)
        Card(
          margin: const EdgeInsets.fromLTRB(12, 6, 12, 6),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(l.compareModules, style: const TextStyle(fontWeight: FontWeight.w700)),
              for (final m in diff.modules)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text('${m.key}: ${outcomeText(l, m.before)} → ${outcomeText(l, m.after)}'),
                ),
            ]),
          ),
        ),
    ]);
  }
}
