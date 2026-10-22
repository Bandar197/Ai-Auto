import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart' show DateFormat;

import '../core/storage/clear_entry.dart';
import '../obd/obd.dart';
import '../state/connection_controller.dart';
import '../state/verification_controller.dart';
import '../ui/l10n_helpers.dart';
import '../ui/widgets.dart';

Color overallColor(String overall) => switch (overall) {
      'problem_confirmed' => Colors.red.shade700,
      'likely_resolved' => Colors.green.shade700,
      'verifying' => Colors.amber.shade800,
      _ => Colors.blueGrey,
    };

IconData overallIcon(String overall) => switch (overall) {
      'problem_confirmed' => Icons.report,
      'likely_resolved' => Icons.verified,
      'verifying' => Icons.hourglass_top,
      _ => Icons.info_outline,
    };

Color verdictColor(CodeVerdict v) => v.isRealProblem == true
    ? Colors.red.shade700
    : v.isRealProblem == false
        ? Colors.green.shade700
        : Colors.amber.shade800;

String overallText(BuildContext context, String overall) {
  final l = context.l10n;
  return switch (overall) {
    'problem_confirmed' => l.verifyOverall_problem_confirmed,
    'likely_resolved' => l.verifyOverall_likely_resolved,
    'verifying' => l.verifyOverall_verifying,
    _ => l.verifyOverall_nothing_cleared,
  };
}

class VerifyScreen extends ConsumerStatefulWidget {
  const VerifyScreen({super.key, this.entryId});
  final String? entryId;
  @override
  ConsumerState<VerifyScreen> createState() => _VerifyScreenState();
}

class _VerifyScreenState extends ConsumerState<VerifyScreen> {
  bool _busy = false;

  Future<void> _checkNow(ClearEntry e) async {
    final client = ref.read(connectionProvider).client;
    if (client == null) return;
    setState(() => _busy = true);
    try {
      final snap = await client.snapshot();
      await ref.read(verificationProvider.notifier).addCheck(e.id, snap);
    } on Object catch (x) {
      if (mounted) showSnack(context, context.l10n.errorGeneric('$x'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final entries = ref.watch(verificationProvider).value ?? const <ClearEntry>[];
    ClearEntry? entry;
    if (widget.entryId != null) {
      for (final e in entries) {
        if (e.id == widget.entryId) entry = e;
      }
    } else {
      entry = ref.watch(openVerificationProvider) ?? (entries.isEmpty ? null : entries.first);
    }
    final conn = ref.watch(connectionProvider);
    final canCheck = entry != null && entry.open && conn.ecuReady && conn.mode?.apiValue == entry.dataMode;
    return Scaffold(
      appBar: AppBar(title: Text(l.verifyTitle)),
      body: entry == null
          ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(l.verifyNone, textAlign: TextAlign.center)))
          : VerificationView(
              entry: entry,
              busy: _busy,
              onCheckNow: canCheck ? () => _checkNow(entry!) : null,
              onFullScan: entry.open && conn.ecuReady ? () => context.push('/scan') : null,
              onClose: entry.open
                  ? () async {
                      await ref.read(verificationProvider.notifier).close(entry!.id);
                    }
                  : null,
            ),
    );
  }
}

/// Pure presentation of a clear-and-verify entry.
class VerificationView extends StatelessWidget {
  const VerificationView({super.key, required this.entry, this.onCheckNow, this.onFullScan, this.onClose, this.busy = false});

  final ClearEntry entry;
  final VoidCallback? onCheckNow;
  final VoidCallback? onFullScan;
  final VoidCallback? onClose;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final lang = context.lang;
    final v = entry.verification ?? assessAfterClear(entry.record, entry.checks);
    final color = overallColor(v.overall);
    final fmt = DateFormat.yMMMd(lang).add_Hm();
    return ListView(padding: const EdgeInsets.only(bottom: 32), children: [
      ModeBanner(mode: entry.dataMode, simulator: entry.dataMode == 'demo'),
      Container(
        key: Key('verify-overall-${v.overall}'),
        margin: const EdgeInsets.all(12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(14)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(overallIcon(v.overall), color: Colors.white, size: 32),
            const SizedBox(width: 10),
            Expanded(
              child: Text(overallText(context, v.overall),
                  style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800)),
            ),
          ]),
          const SizedBox(height: 8),
          Text(v.summary(lang), style: const TextStyle(color: Colors.white, fontSize: 15)),
          const SizedBox(height: 8),
          Text('${l.verifyClearedAt(fmt.format(entry.record.clearedAt.toLocal()))} · ${l.verifyChecks(v.checksAfterClear)}',
              style: const TextStyle(color: Colors.white70)),
        ]),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Text(entry.verificationSource == 'server' ? l.verifySourceServer : l.verifySourceLocal,
            style: Theme.of(context).textTheme.bodySmall),
      ),
      for (final c in v.codes) _CodeCard(c: c),
      if (entry.open)
        Padding(
          padding: const EdgeInsets.all(12),
          child: Wrap(spacing: 8, runSpacing: 8, children: [
            FilledButton.icon(
              key: const Key('verify-check-now'),
              onPressed: busy ? null : onCheckNow,
              icon: busy ? const SizedBox.square(dimension: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.refresh),
              label: Text(l.verifyCheckNow),
            ),
            OutlinedButton.icon(onPressed: onFullScan, icon: const Icon(Icons.play_circle_outline), label: Text(l.verifyRunScan)),
            TextButton(onPressed: onClose, child: Text(l.verifyClose)),
          ]),
        ),
      SectionCard(
        title: l.verifyBeforeCodes,
        icon: Icons.save_outlined,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(
            entry.record.before.dtcs.isEmpty ? l.noCodesInCheck : entry.record.before.dtcs.map((d) => '${d.code} (${d.status})').join(' · '),
            textDirection: TextDirection.ltr,
          ),
          if (entry.freezeFrame != null)
            Text('${l.freezeFrame}: ${(entry.freezeFrame!['values'] as Map? ?? const {}).entries.map((e) => '${e.key}=${e.value}').join(', ')}',
                style: Theme.of(context).textTheme.bodySmall, textDirection: TextDirection.ltr),
        ]),
      ),
      if (entry.checks.isNotEmpty)
        SectionCard(
          title: l.verifyChecks(entry.checks.length),
          icon: Icons.timeline,
          child: Column(children: [
            for (var i = 0; i < entry.checks.length; i++)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: CircleAvatar(radius: 12, child: Text('${i + 1}', style: const TextStyle(fontSize: 12))),
                title: Text(l.checkLabel(i + 1)),
                subtitle: Text(
                  '${fmt.format(entry.checks[i].takenAt.toLocal())} · '
                  '${entry.checks[i].dtcs.isEmpty ? l.noCodesInCheck : entry.checks[i].dtcs.map((d) => '${d.code}/${d.status}').join(', ')}'
                  '${entry.checks[i].warmupsSinceClear != null ? ' · warm-ups ${entry.checks[i].warmupsSinceClear!.toStringAsFixed(0)}' : ''}'
                  '${incompleteMonitors(entry.checks[i].readiness).isEmpty ? '' : ' · ${l.monitorIncomplete}: ${incompleteMonitors(entry.checks[i].readiness).join(', ')}'}',
                  textDirection: TextDirection.ltr,
                ),
              ),
          ]),
        ),
      Padding(padding: const EdgeInsets.all(16), child: Text(l.verifyHowItWorks, style: Theme.of(context).textTheme.bodySmall)),
    ]);
  }
}

class _CodeCard extends StatelessWidget {
  const _CodeCard({required this.c});
  final CodeVerdict c;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final lang = context.lang;
    final color = verdictColor(c);
    return Card(
      key: Key('verdict-${c.code}'),
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      shape: RoundedRectangleBorder(side: BorderSide(color: color, width: 2), borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(c.isRealProblem == true ? Icons.error : (c.isRealProblem == false ? Icons.check_circle : Icons.schedule), color: color),
            const SizedBox(width: 8),
            Expanded(child: Text(c.title(lang), style: TextStyle(fontWeight: FontWeight.w800, color: color))),
          ]),
          const SizedBox(height: 6),
          Text(c.explanation(lang)),
          const SizedBox(height: 6),
          Text(l.verifyNextStep, style: const TextStyle(fontWeight: FontWeight.w700)),
          Text(c.nextStep(lang)),
          if (c.monitor != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                '${lang == 'ar' ? (monitorNames[c.monitor]?.$2 ?? c.monitor) : (monitorNames[c.monitor]?.$1 ?? c.monitor)}'
                '${c.monitorComplete == null ? '' : ': ${c.monitorComplete! ? l.monitorComplete : l.monitorIncomplete}'}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
        ]),
      ),
    );
  }
}
