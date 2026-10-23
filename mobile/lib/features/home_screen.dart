import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart' show DateFormat;

import '../core/storage/scan_report.dart';
import '../state/connection_controller.dart';
import '../state/providers.dart';
import '../state/verification_controller.dart';
import 'verify_screen.dart';
import '../ui/l10n_helpers.dart';
import '../ui/widgets.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final conn = ref.watch(connectionProvider);
    final vehicle = ref.watch(selectedVehicleProvider);
    final reports = ref.watch(reportsProvider).value ?? const <ScanReport>[];
    final latest = reports.isEmpty ? null : reports.first;
    final pending = ref.watch(pendingUploadsProvider).value ?? 0;
    final kb = ref.watch(appAssetsProvider).kb;
    final verify = ref.watch(openVerificationProvider);

    final alerts = <(String, String?)>[];
    final findings = (latest?.diagnosis?['findings'] as List?) ?? const [];
    for (final f in findings.cast<Map<String, dynamic>>()) {
      if (const ['high', 'critical'].contains(f['severity'])) alerts.add((pickLang(f, 'title', context.lang), f['severity'] as String?));
    }
    if (latest != null && latest.diagnosis == null) {
      for (final d in latest.dtcs) {
        final code = d['code'] as String;
        alerts.add(('$code — ${kb.lookup(code)?.description(context.lang) ?? l.kbUnknownCode}', kb.lookup(code)?.severity));
      }
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(l.appTitle),
        actions: [
          IconButton(icon: const Icon(Icons.directions_car), tooltip: l.vehiclesTitle, onPressed: () => context.push('/vehicles')),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          await ref.read(pendingUploadsProvider.notifier).sync();
          await ref.read(reportsProvider.notifier).refresh();
        },
        child: ListView(children: [
          if (conn.mode != null) ModeBanner(mode: conn.mode!.apiValue, simulator: conn.isSimulator),
          if (pending > 0)
            MaterialBanner(
              content: Text(l.pendingUploads(pending)),
              leading: const Icon(Icons.cloud_upload_outlined),
              actions: [TextButton(onPressed: () => ref.read(pendingUploadsProvider.notifier).sync(), child: Text(l.uploadNow))],
            ),
          Card(
            margin: const EdgeInsets.all(12),
            child: ListTile(
              leading: const Icon(Icons.directions_car_filled, size: 36),
              title: Text(vehicle == null
                  ? l.vehicleNone
                  : (vehicle['nickname'] as String?)?.isNotEmpty == true
                      ? vehicle['nickname'] as String
                      : '${vehicle['make'] ?? ''} ${vehicle['model'] ?? ''} ${vehicle['model_year'] ?? ''}'.trim()),
              subtitle: vehicle == null ? null : Text('${vehicle['vin_masked'] ?? vehicle['vin'] ?? ''}', textDirection: TextDirection.ltr),
              trailing: vehicle == null ? TextButton(onPressed: () => context.push('/vehicles/edit'), child: Text(l.addVehicle)) : null,
              onTap: () => context.push('/vehicles'),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: StatusChips(status: conn.status, simulator: conn.isSimulator),
          ),
          if (verify != null)
            Card(
              key: const Key('home-verify-card'),
              margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              color: overallColor(verify.overall),
              child: ListTile(
                leading: Icon(overallIcon(verify.overall), color: Colors.white, size: 32),
                title: Text('${l.verifyTitle} · ${overallText(context, verify.overall)}',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
                subtitle: Text(
                  '${verify.record.before.dtcs.map((d) => d.code).toSet().join(', ')} · ${l.verifyChecks(verify.checks.length)}'
                  '${verify.dataMode != 'live' ? ' · ${modeText(l, verify.dataMode).toUpperCase()}' : ''}',
                  style: const TextStyle(color: Colors.white70),
                ),
                trailing: const Icon(Icons.chevron_right, color: Colors.white),
                onTap: () => context.push('/verify/${verify.id}'),
              ),
            ),
          SectionCard(
            title: l.healthScore,
            icon: Icons.favorite_outline,
            child: Row(children: [
              HealthGauge(score: latest?.healthScore),
              const SizedBox(width: 16),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(healthBandText(l, latest?.healthBand), style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 4),
                  Text(l.dtcCount(latest?.dtcs.map((d) => d['code']).toSet().length ?? 0)),
                  const SizedBox(height: 4),
                  Text(l.lastScan(latest == null ? l.never : DateFormat.yMMMd(context.lang).add_Hm().format(latest.createdAt.toLocal()))),
                  if (latest != null && latest.dataMode != 'live')
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(modeText(l, latest.dataMode).toUpperCase(),
                          style: TextStyle(color: latest.isReplay ? replayColor : demoColor, fontWeight: FontWeight.w700)),
                    ),
                ]),
              ),
            ]),
          ),
          SectionCard(
            title: l.importantAlerts,
            icon: Icons.warning_amber_outlined,
            child: alerts.isEmpty
                ? Text(l.noAlerts)
                : Column(children: [
                    for (final (text, sev) in alerts.take(5))
                      ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(Icons.circle, size: 12, color: severityColor(sev)),
                        title: Text(text),
                        onTap: latest == null ? null : () => context.push('/report/${latest.id}'),
                      ),
                  ]),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: FilledButton.icon(
              key: const Key('start-scan'),
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(64), textStyle: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
              icon: const Icon(Icons.play_circle_outline, size: 30),
              label: Text(l.startScan),
              onPressed: () => context.push(conn.ecuReady || conn.replay != null ? '/scan' : '/connect?next=scan'),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(children: [
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.show_chart),
                  label: Text(l.liveData),
                  onPressed: () => context.go('/live'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.build_outlined),
                  label: Text(l.maintenanceHistory),
                  onPressed: vehicle == null ? () => context.push('/vehicles/edit') : () => context.push('/maintenance/${vehicle['id']}'),
                ),
              ),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: OutlinedButton.icon(
              icon: const Icon(Icons.radar),
              label: Text(l.extendedModulesTitle),
              onPressed: () => context.push(conn.ecuReady ? '/extended-modules' : '/connect?next=extended-modules'),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(children: [
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.history),
                  label: Text(l.sessionsHistory),
                  onPressed: () => context.go('/history'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.link),
                  label: Text(l.connect),
                  onPressed: () => context.push('/connect'),
                ),
              ),
            ]),
          ),
          const SizedBox(height: 24),
        ]),
      ),
    );
  }
}
