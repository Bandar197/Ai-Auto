import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/kb/local_kb.dart';
import '../obd/obd.dart';
import '../state/connection_controller.dart';
import '../state/extended_scan_controller.dart';
import '../state/providers.dart';
import '../ui/l10n_helpers.dart';
import '../ui/widgets.dart';

/// Reads airbag (SRS) / ABS / body modules over UDS and shows their fault codes,
/// alongside the engine codes read elsewhere. Read-only discovery: clearing SRS
/// stays a separate, gated step.
class ExtendedModulesScreen extends ConsumerStatefulWidget {
  const ExtendedModulesScreen({super.key});

  @override
  ConsumerState<ExtendedModulesScreen> createState() => _ExtendedModulesScreenState();
}

class _ExtendedModulesScreenState extends ConsumerState<ExtendedModulesScreen> {
  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final lang = context.lang;
    final conn = ref.watch(connectionProvider);
    final scan = ref.watch(extendedScanProvider);
    final kb = ref.watch(appAssetsProvider).kb;
    final canRun = conn.client != null && conn.ecuReady && conn.mode != DataMode.replay && !scan.running;

    return Scaffold(
      appBar: AppBar(title: Text(l.extendedModulesTitle)),
      body: ListView(padding: const EdgeInsets.only(bottom: 24), children: [
        if (conn.mode != null) ModeBanner(mode: conn.mode!.apiValue, simulator: conn.isSimulator),
        Container(
          margin: const EdgeInsets.all(12),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: Colors.blue.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(10)),
          child: Text(l.extendedModulesIntro),
        ),
        if (scan.running)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Row(children: [
              SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2)),
              SizedBox(width: 12),
              Expanded(child: Text('…')),
            ]),
          ),
        if (scan.error == 'replay') Padding(padding: const EdgeInsets.all(16), child: Text(l.extendedNeedsLive)),
        if (scan.error == 'not_connected') Padding(padding: const EdgeInsets.all(16), child: Text(l.notConnected)),
        if (scan.error != null && scan.error != 'replay' && scan.error != 'not_connected')
          Padding(padding: const EdgeInsets.all(16), child: Text(scan.error!, style: const TextStyle(color: Colors.red))),
        if (scan.done && scan.error == null && scan.results.isEmpty)
          Padding(padding: const EdgeInsets.all(16), child: Text(l.extendedNoModules)),
        for (final m in scan.results) _moduleCard(context, lang, kb, m),
        if (scan.done && scan.results.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
            child: Text(l.extendedDisclaimer, style: Theme.of(context).textTheme.bodySmall),
          ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: FilledButton.icon(
            icon: const Icon(Icons.radar),
            label: Text(scan.done ? l.retry : l.extendedScanCta),
            onPressed: canRun ? () => ref.read(extendedScanProvider.notifier).run() : null,
          ),
        ),
      ]),
    );
  }

  Widget _moduleCard(BuildContext context, String lang, LocalKb kb, ModuleScan m) {
    final l = context.l10n;
    final airbag = m.module.category == ModuleCategory.airbag;
    final icon = airbag ? Icons.airline_seat_legroom_extra : (m.module.category == ModuleCategory.abs ? Icons.disc_full : Icons.memory);
    return SectionCard(
      title: m.module.name(lang),
      icon: icon,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (m.refused)
          Text(l.extendedRefused, style: const TextStyle(fontWeight: FontWeight.w600))
        else if (m.dtcs.isEmpty)
          Text(l.extendedNoFaults, style: const TextStyle(color: Colors.green, fontWeight: FontWeight.w600))
        else
          for (final d in m.dtcs) _dtcRow(context, lang, kb, d),
        if (airbag && m.dtcs.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(l.extendedAirbagClearNote, style: Theme.of(context).textTheme.bodySmall),
          ),
      ]),
    );
  }

  Widget _dtcRow(BuildContext context, String lang, LocalKb kb, UdsDtc d) {
    final entry = kb.lookup(d.code);
    final desc = entry?.description(lang) ?? '';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text(d.display, style: const TextStyle(fontWeight: FontWeight.w700), textDirection: TextDirection.ltr),
          const SizedBox(width: 8),
          if (d.active)
            const _Tag('active', Colors.red)
          else if (d.confirmed)
            const _Tag('stored', Colors.orange),
        ]),
        if (desc.isNotEmpty) Text(desc, style: Theme.of(context).textTheme.bodySmall),
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
