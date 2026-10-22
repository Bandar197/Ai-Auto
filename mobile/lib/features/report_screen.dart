import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';

import '../core/api/api_client.dart';
import '../core/kb/local_kb.dart';
import '../core/storage/scan_report.dart';
import '../state/connection_controller.dart';
import '../state/providers.dart';
import '../ui/l10n_helpers.dart';
import '../ui/widgets.dart';

class ReportScreen extends ConsumerWidget {
  const ReportScreen({super.key, required this.reportId});
  final String reportId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final async = ref.watch(reportProvider(reportId));
    return Scaffold(
      appBar: AppBar(
        title: Text(l.reportTitle),
        actions: [
          if (async.value != null)
            IconButton(
              icon: const Icon(Icons.ios_share),
              tooltip: l.exportJson,
              onPressed: () => _share(context, ref, async.value!),
            ),
        ],
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text(l.errorGeneric('$e'))),
        data: (r) => r == null
            ? Center(child: Text(l.notAvailable))
            : ReportView(
                report: r,
                kb: ref.watch(appAssetsProvider).kb,
                onAnalyze: r.diagnosis != null
                    ? null
                    : () async {
                        try {
                          await ref.read(uploadQueueProvider).uploadOne(r);
                          final pending = await ref.read(localStoreProvider).readQueue();
                          await ref.read(localStoreProvider).writeQueue(pending.where((x) => x != r.id).toList());
                          ref.invalidate(reportProvider(reportId));
                          await ref.read(reportsProvider.notifier).refresh();
                          await ref.read(pendingUploadsProvider.notifier).refresh();
                        } on ApiException catch (e) {
                          if (context.mounted) showSnack(context, e.isOffline ? l.scanQueued : e.message);
                        }
                      },
                onClearDtcs: r.dataMode == 'replay' || r.dtcs.isEmpty || ref.watch(connectionProvider).client == null
                    ? null
                    : () => context.push('/clear-dtcs'),
              ),
      ),
    );
  }

  Future<void> _share(BuildContext context, WidgetRef ref, ScanReport r) async {
    final json = const JsonEncoder.withIndent(' ').convert({
      'report': r.toJson(),
      'labels': {'data_mode': r.dataMode, 'original_mode': r.originalMode, 'is_demo': r.isDemo},
    });
    final f = await ref.read(localStoreProvider).writeExport('automind_report_${r.id}${r.isDemo ? '_DEMO' : ''}.json', json);
    await SharePlus.instance.share(ShareParams(files: [XFile(f.path, mimeType: 'application/json')], subject: 'AutoMind report'));
  }
}

/// Pure presentation of a report (server diagnosis or offline KB view).
class ReportView extends StatelessWidget {
  const ReportView({super.key, required this.report, required this.kb, this.onAnalyze, this.onClearDtcs});

  final ScanReport report;
  final LocalKb kb;
  final VoidCallback? onAnalyze;
  final VoidCallback? onClearDtcs;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final lang = context.lang;
    final d = report.diagnosis;
    final watermark = report.isReplay ? l.replayWatermark : (report.isDemo ? l.demoWatermark : null);
    final findings = ((d?['findings'] as List?) ?? const []).cast<Map<String, dynamic>>();
    final serverDtcs = ((d?['dtcs'] as List?) ?? const []).cast<Map<String, dynamic>>();

    return Watermark(
      text: watermark,
      child: ListView(padding: const EdgeInsets.only(bottom: 32), children: [
        ModeBanner(mode: report.dataMode, originalMode: report.originalMode, simulator: report.simulator),
        if (report.isReplay && report.originalMode == 'demo') const ModeBanner(mode: 'demo'),
        if (d == null)
          Container(
            key: const Key('offline-note'),
            margin: const EdgeInsets.all(12),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: Colors.amber.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(8)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(l.offlineReportNote),
              if (report.lastError != null) Text(report.lastError!, style: Theme.of(context).textTheme.bodySmall, textDirection: TextDirection.ltr),
              if (onAnalyze != null) TextButton.icon(onPressed: onAnalyze, icon: const Icon(Icons.cloud_upload_outlined), label: Text(l.analyzeNow)),
            ]),
          ),
        SectionCard(
          title: l.summary,
          icon: Icons.summarize_outlined,
          child: Row(children: [
            HealthGauge(score: report.healthScore, size: 80),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(healthBandText(l, report.healthBand), style: Theme.of(context).textTheme.titleMedium),
                if (d != null) Text(pickBi(d['summary'], lang)),
                if (report.vin != null) Text('${l.vinLabel}: ${report.vin}', textDirection: TextDirection.ltr),
                if (report.protocolName != null) Text(report.protocolName!, style: Theme.of(context).textTheme.bodySmall),
              ]),
            ),
          ]),
        ),
        if (d != null && d['technician_summary'] != null)
          SectionCard(title: l.technicianSummary, icon: Icons.engineering_outlined, child: Text(pickBi(d['technician_summary'], lang))),
        SectionCard(
          title: l.dtcsTitle,
          icon: Icons.error_outline,
          trailing: onClearDtcs == null ? null : TextButton(onPressed: onClearDtcs, child: Text(l.clearDtcsTitle)),
          child: _dtcs(context, serverDtcs),
        ),
        if (findings.isNotEmpty) ...[
          Padding(padding: const EdgeInsets.fromLTRB(16, 12, 16, 0), child: Text(l.findings, style: Theme.of(context).textTheme.titleLarge)),
          for (final f in findings) _FindingCard(f: f),
        ],
        if (d != null && (d['system_status'] as List?)?.isNotEmpty == true)
          SectionCard(
            title: l.systemStatus,
            icon: Icons.dashboard_outlined,
            child: Wrap(spacing: 6, runSpacing: 6, children: [
              for (final s in (d['system_status'] as List).cast<Map<String, dynamic>>())
                Tooltip(
                  message: pickLang(s, 'note', lang),
                  child: Chip(
                    avatar: Icon(Icons.circle, size: 12, color: switch (s['status']) {
                      'ok' => Colors.green,
                      'warning' => Colors.orange,
                      'fault' => Colors.red,
                      _ => Colors.grey,
                    }),
                    label: Text('${s['system']}'),
                  ),
                ),
            ]),
          ),
        if (report.freezeFrames.isNotEmpty)
          SectionCard(
            title: '${l.freezeFrame} ${report.freezeFrames.first['dtc'] ?? ''}',
            icon: Icons.ac_unit,
            child: Column(children: [
              for (final e in ((report.freezeFrames.first['values'] as Map?) ?? const {}).entries)
                Row(children: [Expanded(child: Text('${e.key}')), Text('${e.value}', textDirection: TextDirection.ltr)]),
            ]),
          ),
        if (d != null && d['data_quality'] is Map)
          SectionCard(
            title: l.dataQuality,
            icon: Icons.analytics_outlined,
            child: Text(
              '${(d['data_quality'] as Map)['sample_count'] ?? ''} · ${(d['data_quality'] as Map)['duration_s'] ?? ''} ${l.seconds} · '
              '${((d['data_quality'] as Map)['conditions_seen'] as List?)?.join(', ') ?? ''}',
              textDirection: TextDirection.ltr,
            ),
          ),
        if (d != null && (d['disclaimers'] as List?)?.isNotEmpty == true)
          SectionCard(
            title: l.disclaimers,
            icon: Icons.info_outline,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              for (final x in d['disclaimers'] as List) Padding(padding: const EdgeInsets.only(bottom: 4), child: Text('• ${pickBi(x, lang)}')),
            ]),
          ),
      ]),
    );
  }

  Widget _dtcs(BuildContext context, List<Map<String, dynamic>> serverDtcs) {
    final l = context.l10n;
    final lang = context.lang;
    final rows = <Widget>[];
    if (serverDtcs.isNotEmpty) {
      for (final x in serverDtcs) {
        final known = x['known'] != false;
        rows.add(ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(Icons.circle, size: 14, color: severityColor(x['severity'] as String?)),
          title: Text('${x['code']} · ${x['status'] ?? ''}', textDirection: TextDirection.ltr, textAlign: TextAlign.start),
          subtitle: Text(known ? pickLang(x, 'description', lang) : l.kbUnknownCode),
        ));
      }
    } else {
      for (final x in report.dtcs) {
        final code = x['code'] as String;
        final e = kb.lookup(code);
        rows.add(ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(Icons.circle, size: 14, color: severityColor(e?.severity)),
          title: Text('$code · ${x['status']}${x['ecu'] != null ? ' · ${x['ecu']}' : ''}', textDirection: TextDirection.ltr, textAlign: TextAlign.start),
          subtitle: Text(e?.description(lang) ?? l.kbUnknownCode),
        ));
      }
    }
    return rows.isEmpty ? Text(l.noDtcs) : Column(children: rows);
  }
}

class _FindingCard extends StatelessWidget {
  const _FindingCard({required this.f});
  final Map<String, dynamic> f;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final lang = context.lang;
    final causes = ((f['causes'] as List?) ?? const []).cast<Map<String, dynamic>>();
    final evidence = ((f['evidence'] as List?) ?? const []).cast<Map<String, dynamic>>();
    final tests = ((f['tests'] as List?) ?? const []).cast<Map<String, dynamic>>();
    final actions = ((f['actions'] as List?) ?? const []).cast<Map<String, dynamic>>();
    final parts = ((f['parts_candidates'] as List?) ?? const []).cast<Map<String, dynamic>>();
    final missing = ((f['missing_data'] as List?) ?? const []).cast<Map<String, dynamic>>();
    final conf = ((f['confidence'] as num? ?? 0) * 100).round();
    final sev = f['severity'] as String?;
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      shape: RoundedRectangleBorder(
        side: BorderSide(color: severityColor(sev), width: 1.5),
        borderRadius: BorderRadius.circular(12),
      ),
      child: ExpansionTile(
        initiallyExpanded: true,
        leading: Icon(Icons.report_problem_outlined, color: severityColor(sev)),
        title: Text(pickLang(f, 'title', lang), style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text('${severityText(l, sev)} · ${l.confidence(conf)}${(f['related_dtcs'] as List?)?.isNotEmpty == true ? ' · ${(f['related_dtcs'] as List).join(', ')}' : ''}'),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        expandedCrossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (causes.isNotEmpty) ...[
            _h(context, l.probableCauses),
            for (final c in causes)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(children: [
                  Expanded(child: Text('${c['rank'] ?? ''}. ${pickLang(c, 'title', lang)}')),
                  SizedBox(width: 80, child: LinearProgressIndicator(value: (c['likelihood'] as num? ?? 0).toDouble())),
                  const SizedBox(width: 6),
                  Text(l.likelihood(((c['likelihood'] as num? ?? 0) * 100).round())),
                ]),
              ),
          ],
          if (evidence.isNotEmpty) ...[
            _h(context, l.evidence),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                key: const Key('evidence-table'),
                headingRowHeight: 32,
                dataRowMinHeight: 32,
                columns: [
                  DataColumn(label: Text(l.measured)),
                  DataColumn(label: Text(l.observed)),
                  DataColumn(label: Text(l.expected)),
                  const DataColumn(label: Text('')),
                ],
                rows: [
                  for (final e in evidence)
                    DataRow(
                      color: WidgetStatePropertyAll(
                        e['is_measured'] == true ? Colors.blue.withValues(alpha: 0.06) : Colors.purple.withValues(alpha: 0.06),
                      ),
                      cells: [
                        DataCell(Row(children: [
                          Icon(e['is_measured'] == true ? Icons.straighten : Icons.psychology_alt_outlined, size: 16),
                          const SizedBox(width: 4),
                          Text(e['is_measured'] == true ? l.measured : l.inferred),
                          const SizedBox(width: 6),
                          Text('${e['signal'] ?? e['kind'] ?? ''}', textDirection: TextDirection.ltr),
                        ])),
                        DataCell(Text('${e['observed_value'] ?? ''} ${e['unit'] ?? ''}', textDirection: TextDirection.ltr)),
                        DataCell(Text(
                          e['expected_min'] == null && e['expected_max'] == null
                              ? ''
                              : '${e['expected_min'] ?? ''}–${e['expected_max'] ?? ''} ${e['expected_context'] ?? ''}',
                          textDirection: TextDirection.ltr,
                        )),
                        DataCell(Text(pickLang(e, 'note', lang))),
                      ],
                    ),
                ],
              ),
            ),
          ],
          if (tests.isNotEmpty) ...[
            _h(context, l.tests),
            for (final t in tests)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.science_outlined),
                title: Text(pickLang(t, 'title', lang)),
                subtitle: Text('${l.howTo}: ${pickLang(t, 'how', lang)}\n${l.expectedResult}: ${pickLang(t, 'expected', lang)}'),
              ),
          ],
          if (actions.isNotEmpty) ...[
            _h(context, l.actions),
            for (final a in actions) Text('• ${pickLang(a, 'title', lang)}'),
          ],
          if (parts.isNotEmpty) ...[
            _h(context, l.partsToConfirm),
            for (final p in parts)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.inventory_2_outlined),
                title: Text(pickLang(p, 'name', lang)),
                subtitle: Text([if (p['requires_confirmation'] == true) l.requiresConfirmation, pickLang(p, 'condition', lang)].where((x) => x.isNotEmpty).join(' — ')),
              ),
          ],
          if (missing.isNotEmpty) ...[
            _h(context, l.missingData),
            for (final m in missing) Text('• ${m['signal'] ?? ''}: ${pickLang(m, 'description', lang)}'),
          ],
        ],
      ),
    );
  }

  Widget _h(BuildContext context, String t) => Padding(
        padding: const EdgeInsets.only(top: 10, bottom: 4),
        child: Text(t, style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
      );
}
