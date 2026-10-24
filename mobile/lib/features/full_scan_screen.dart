import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/systems.dart';
import '../state/connection_controller.dart';
import '../state/full_scan_controller.dart';
import '../ui/l10n_helpers.dart';
import '../ui/widgets.dart';

/// Staged, categorized full scan: standard OBD codes (engine / emissions /
/// transmission / electrical / network) then the airbag / ABS / body modules
/// over UDS, grouped by system with an "explain" action on every code.
class FullScanScreen extends ConsumerWidget {
  const FullScanScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final lang = context.lang;
    final conn = ref.watch(connectionProvider);
    final scan = ref.watch(fullScanProvider);
    final canRun = conn.client != null && conn.ecuReady && !scan.running;

    // Show a system section when it was checked or has codes, in catalogue order.
    final sections = [
      for (final s in kVehicleSystems)
        if (scan.groups[s.id] != null && (scan.groups[s.id]!.checked || scan.groups[s.id]!.codes.isNotEmpty))
          scan.groups[s.id]!,
    ];

    return Scaffold(
      appBar: AppBar(title: Text(l.fullScanTitle)),
      body: ListView(padding: const EdgeInsets.only(bottom: 24), children: [
        if (conn.mode != null) ModeBanner(mode: conn.mode!.apiValue, simulator: conn.isSimulator),
        if (scan.done && scan.error == null)
          Container(
            margin: const EdgeInsets.all(12),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: (scan.totalCodes == 0 ? Colors.green : Colors.orange).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(children: [
              Icon(scan.totalCodes == 0 ? Icons.check_circle : Icons.report_problem,
                  color: scan.totalCodes == 0 ? Colors.green : Colors.orange),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  scan.totalCodes == 0 ? l.fullScanAllClear : l.fullScanSummary(scan.totalCodes),
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ]),
          ),
        if (scan.running)
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(children: [
              const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2)),
              const SizedBox(width: 12),
              Expanded(child: Text(scan.stage.isEmpty ? l.fullScanChecking : '${l.fullScanChecking}  ${systemById(scan.stage).name(lang)}')),
            ]),
          ),
        if (scan.error == 'not_connected') Padding(padding: const EdgeInsets.all(16), child: Text(l.notConnected)),
        for (final g in sections) _systemCard(context, lang, g),
        if (scan.done)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
            child: Text(l.fullScanCoverageNote, style: Theme.of(context).textTheme.bodySmall),
          ),
        if (scan.done)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: OutlinedButton.icon(
              icon: const Icon(Icons.travel_explore),
              label: Text(l.fullScanFindMore),
              onPressed: () => context.push('/extended-modules'),
            ),
          ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: FilledButton.icon(
            icon: const Icon(Icons.radar),
            label: Text(scan.done ? l.retry : l.fullScanCta),
            onPressed: canRun ? () => ref.read(fullScanProvider.notifier).run() : null,
          ),
        ),
      ]),
    );
  }

  Widget _systemCard(BuildContext context, String lang, SystemGroup g) {
    final l = context.l10n;
    return SectionCard(
      title: '${g.system.name(lang)}  (${g.codes.length})',
      icon: g.system.icon,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (g.codes.isEmpty && g.refused)
          Text(l.extendedRefused, style: const TextStyle(fontWeight: FontWeight.w600))
        else if (g.codes.isEmpty)
          Text(l.extendedNoFaults, style: const TextStyle(color: Colors.green, fontWeight: FontWeight.w600))
        else
          for (final c in g.codes) _codeRow(context, c),
      ]),
    );
  }

  Widget _codeRow(BuildContext context, ScanCode c) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text(c.code, style: const TextStyle(fontWeight: FontWeight.w700), textDirection: TextDirection.ltr),
          const SizedBox(width: 8),
          if (c.active)
            const _Tag('active', Colors.red)
          else if (!c.confirmed)
            const _Tag('pending', Colors.orange),
          const Spacer(),
          TextButton.icon(
            icon: const Icon(Icons.help_outline, size: 18),
            label: Text(context.l10n.explainCta),
            onPressed: () => context.push('/explain/${c.code}'),
          ),
        ]),
        if ((c.description ?? '').isNotEmpty) Text(c.description!, style: Theme.of(context).textTheme.bodySmall),
      ]),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag(this.text, this.color);
  final String text;
  final Color color;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
        decoration: BoxDecoration(color: color.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(6)),
        child: Text(text, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w700)),
      );
}
