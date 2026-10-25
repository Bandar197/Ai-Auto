import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/ecu_states.dart';
import '../core/storage/scan_report.dart';
import '../core/vehicle_profiles.dart';
import '../l10n/app_localizations.dart';
import '../obd/obd.dart';
import '../state/connection_controller.dart';
import '../state/providers.dart';
import '../ui/l10n_helpers.dart';
import '../ui/widgets.dart';

/// ECU map: every module the last scan tried, with one of the ten honest states,
/// its CAN ids, 11/29-bit, the address source and whether it is verified on a car.
class EcuMapScreen extends ConsumerStatefulWidget {
  const EcuMapScreen({super.key});
  @override
  ConsumerState<EcuMapScreen> createState() => _EcuMapScreenState();
}

class _EcuMapScreenState extends ConsumerState<EcuMapScreen> {
  ScanReport? _report;
  Recording? _rec;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final store = ref.read(localStoreProvider);
    ScanReport? pick;
    Recording? rec;
    for (final r in await store.listReports()) {
      if (r.recordingId == null) continue;
      final x = await store.loadRecording(r.recordingId!);
      if (x != null && (x.moduleScans.isNotEmpty || x.ecus.isNotEmpty)) {
        pick = r;
        rec = x;
        break;
      }
    }
    if (mounted) {
      setState(() {
        _report = pick;
        _rec = rec;
        _loaded = true;
      });
    }
  }

  static String stateText(AppLocalizations l, EcuState10 s) => switch (s) {
        EcuState10.discovered => l.ecu_discovered,
        EcuState10.reachable => l.ecu_reachable,
        EcuState10.dtcReadSupported => l.ecu_dtc_read_supported,
        EcuState10.clearSupported => l.ecu_clear_supported,
        EcuState10.notSupported => l.ecu_not_supported,
        EcuState10.timedOut => l.ecu_timed_out,
        EcuState10.gatewayBlocked => l.ecu_gateway_blocked,
        EcuState10.refused => l.ecu_refused,
        EcuState10.passed => l.ecu_passed,
        EcuState10.faultsPresent => l.ecu_faults_present,
      };

  static Color stateColor(EcuState10 s) => switch (s) {
        EcuState10.passed => Colors.green.shade700,
        EcuState10.faultsPresent => Colors.red.shade700,
        EcuState10.reachable || EcuState10.discovered || EcuState10.dtcReadSupported || EcuState10.clearSupported => Colors.blue.shade700,
        _ => Colors.orange.shade800,
      };

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final lang = context.lang;
    final assets = ref.watch(appAssetsProvider);
    final rec = _rec;
    final make = effectiveMake(ref.watch(selectedVehicleProvider), rec?.vehicle['vin'] as String? ?? _report?.vin, assets);
    final entries = rec == null ? const <EcuEntry>[] : buildEcuMap(rec, registry: assets.modules.candidatesFor(make));
    final vehicle = ref.watch(selectedVehicleProvider);
    final profile = assets.profiles.match(
      make: make,
      model: vehicle?['model']?.toString(),
      year: int.tryParse('${vehicle?['model_year'] ?? ''}'),
    );
    final srsNotRead = entries.any((e) => e.key.startsWith('srs') && (e.state == EcuState10.timedOut || e.state == EcuState10.refused || e.state == EcuState10.gatewayBlocked));
    return Scaffold(
      appBar: AppBar(title: Text(l.ecuMapTitle)),
      body: ListView(padding: const EdgeInsets.only(bottom: 24), children: [
        if (rec != null && rec.dataMode != 'live') ModeBanner(mode: rec.dataMode),
        if (_loaded && rec == null) Padding(padding: const EdgeInsets.all(16), child: Text(l.ecuMapNoScan)),
        if (profile != null) _profileCard(context, l, lang, profile, srsNotRead),
        for (final e in entries) _row(context, l, lang, e),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: OutlinedButton.icon(
            icon: const Icon(Icons.radar),
            label: Text(l.fullScanTitle),
            onPressed: () => context.push(ref.read(connectionProvider).ecuReady ? '/full-scan' : '/connect?next=full-scan'),
          ),
        ),
      ]),
    );
  }

  Widget _profileCard(BuildContext context, AppLocalizations l, String lang, VehicleProfile p, bool srsNotRead) => Card(
        key: const Key('vehicle-profile'),
        margin: const EdgeInsets.all(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const Icon(Icons.directions_car_filled_outlined),
              const SizedBox(width: 8),
              Expanded(child: Text(p.title(lang), style: const TextStyle(fontWeight: FontWeight.w700))),
              if (!p.verified)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(color: Colors.orange.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(6)),
                  child: Text(l.ecuAddrUnverified, style: TextStyle(color: Colors.orange.shade800, fontSize: 11)),
                ),
            ]),
            for (final n in p.notes(lang)) Padding(padding: const EdgeInsets.only(top: 4), child: Text('• $n')),
            if (srsNotRead && p.srsUnreachable(lang) != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(p.srsUnreachable(lang)!, style: TextStyle(color: Colors.orange.shade800, fontWeight: FontWeight.w600)),
              ),
          ]),
        ),
      );

  Widget _row(BuildContext context, AppLocalizations l, String lang, EcuEntry e) {
    final color = stateColor(e.state);
    final small = Theme.of(context).textTheme.bodySmall;
    return Card(
      key: Key('ecu-${e.key}'),
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text(e.name(lang), style: const TextStyle(fontWeight: FontWeight.w700))),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(color: color.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(8)),
              child: Text(stateText(l, e.state), key: Key('ecu-state-${e.key}'), style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 12)),
            ),
          ]),
          const SizedBox(height: 4),
          Text(
            [
              if (e.requestId != null) 'TX ${e.requestId}',
              if (e.responseId != null) 'RX ${e.responseId}',
              if (e.idBits != null) '${e.idBits}-bit',
            ].join(' · '),
            textDirection: TextDirection.ltr,
            style: small,
          ),
          Wrap(spacing: 6, runSpacing: 4, children: [
            for (final f in e.flags.where((f) => f != e.state))
              Chip(visualDensity: VisualDensity.compact, label: Text(stateText(l, f), style: const TextStyle(fontSize: 11))),
          ]),
          if (e.source != null)
            Text(
              '${l.ecuSource(e.source!)}${e.verified == null ? '' : ' · ${e.verified! ? l.ecuAddrVerified : l.ecuAddrUnverified}'}',
              style: small,
            ),
          if (e.nrc != null) Text(l.ecuNrc('0x${e.nrc!.toRadixString(16).padLeft(2, '0').toUpperCase()}'), style: small),
          if (e.codes.isNotEmpty) Text(e.codes.join(' · '), textDirection: TextDirection.ltr),
        ]),
      ),
    );
  }
}
