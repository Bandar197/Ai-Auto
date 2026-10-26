import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app.dart';
import '../l10n/app_localizations.dart';
import '../obd/obd.dart';
import '../state/adapter_caps_controller.dart';
import '../state/connection_controller.dart';
import '../ui/l10n_helpers.dart';
import '../ui/widgets.dart';

/// Adapter Manager: shows what the connected adapter PROVED it supports
/// (passed / failed / not tested, and how it was established) plus the raw
/// probe log. Nothing here writes to the vehicle.
class AdapterScreen extends ConsumerWidget {
  const AdapterScreen({super.key});

  static String capLabel(AppLocalizations l, Capability c) => switch (c) {
    Capability.headers => l.capHeaders,
    Capability.filters => l.capFilters,
    Capability.canFormatting => l.capCanFormatting,
    Capability.isoTp => l.capIsoTp,
    Capability.multiFrame => l.capMultiFrame,
    Capability.flowControl => l.capFlowControl,
    Capability.protocolSwitching => l.capProtocolSwitching,
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final conn = ref.watch(connectionProvider);
    final caps = ref.watch(adapterCapabilitiesProvider);
    final result = caps.value;

    String? blocked;
    if (conn.mode == DataMode.replay) {
      blocked = l.adapterCapsReplay;
    } else if (conn.client == null || !conn.isConnected) {
      blocked = l.adapterCapsNeedConnection;
    } else if (conn.busy) {
      blocked = l.adapterCapsBusy;
    }

    Future<void> run() async {
      try {
        await ref.read(adapterCapabilitiesProvider.notifier).probe();
      } on ProbeBlockedException {
        // The button is disabled in these states; nothing to do.
      }
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(l.adapterCapsTitle),
        actions: [
          if (result != null)
            IconButton(
              tooltip: l.adapterCapsCopy,
              icon: const Icon(Icons.copy_all_outlined),
              onPressed: () async {
                final messenger = ScaffoldMessenger.of(context);
                await Clipboard.setData(ClipboardData(text: const JsonEncoder.withIndent('  ').convert(result.toJson())));
                messenger.showSnackBar(SnackBar(content: Text(l.adapterCapsCopied)));
              },
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
        children: [
          if (conn.mode != null && conn.mode != DataMode.replay) ModeBanner(mode: conn.mode!.apiValue, simulator: conn.isSimulator),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.memory, color: brandBlue),
                      const SizedBox(width: 8),
                      Expanded(child: Text(l.adapterCapsTitle, style: Theme.of(context).textTheme.titleMedium)),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(l.adapterCapsIntro),
                  const SizedBox(height: 4),
                  Text(l.adapterCapsIdleNote, style: Theme.of(context).textTheme.bodySmall),
                  if (conn.isConnected && !conn.ecuReady && conn.mode != DataMode.replay) ...[
                    const SizedBox(height: 6),
                    Text(l.adapterCapsNoVehicle, style: const TextStyle(color: brandOrange)),
                  ],
                  if (conn.isSimulator || conn.isDemo) ...[
                    const SizedBox(height: 6),
                    Text(l.adapterCapsSimulator, style: const TextStyle(color: brandOrange)),
                  ],
                  if (blocked != null) ...[
                    const SizedBox(height: 6),
                    Text(blocked, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                  ],
                  const SizedBox(height: 10),
                  if (caps.isLoading) const LinearProgressIndicator(),
                  Align(
                    alignment: AlignmentDirectional.centerEnd,
                    child: FilledButton.icon(
                      key: const Key('adapter-probe'),
                      onPressed: blocked != null || caps.isLoading ? null : run,
                      icon: const Icon(Icons.play_arrow),
                      label: Text(result == null ? l.adapterCapsRun : l.adapterCapsRerun),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (caps.hasError)
            Padding(
              padding: const EdgeInsets.all(8),
              child: Text(l.adapterCapsError('${caps.error}'), style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ),
          if (result == null && !caps.isLoading && !caps.hasError)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(l.adapterCapsNotRun, textAlign: TextAlign.center),
            ),
          if (result != null) ...[
            _identity(context, l, result),
            Card(child: Column(children: [for (final c in Capability.values) _capRow(context, l, result, c)])),
            _rawLog(context, l, result),
          ],
        ],
      ),
    );
  }

  Widget _identity(BuildContext context, AppLocalizations l, AdapterCapabilities r) {
    Widget row(String k, String? v) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 120, child: Text(k, style: Theme.of(context).textTheme.bodySmall)),
          Expanded(child: Text(v == null || v.isEmpty ? '—' : v, textDirection: TextDirection.ltr)),
        ],
      ),
    );
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          children: [
            row(l.adapterCapsName, r.name),
            row(l.adapterCapsFirmware, r.firmware),
            row(l.adapterCapsVoltage, r.voltage == null ? null : '${r.voltage!.toStringAsFixed(1)} V'),
            row(l.adapterCapsProtocol, r.protocol),
            row(l.adapterCapsConnection, r.connection),
          ],
        ),
      ),
    );
  }

  Widget _capRow(BuildContext context, AppLocalizations l, AdapterCapabilities r, Capability c) {
    final v = r.capabilities[c];
    final ev = r.evidence[c] ?? Evidence.notTested;
    final (icon, color, label) = switch (v) {
      true => (Icons.check_circle, Colors.green.shade700, l.adapterCapsPass),
      false => (Icons.cancel, Theme.of(context).colorScheme.error, l.adapterCapsFail),
      null => (Icons.help_outline, Colors.grey, l.adapterCapsUntested),
    };
    final how = switch (ev) {
      Evidence.behavioral => l.adapterCapsBehavioral,
      Evidence.acceptedOnly => l.adapterCapsAcceptedOnly,
      Evidence.notTested => null,
    };
    final note = r.notes[c];
    return ListTile(
      key: Key('cap-${c.wire}'),
      leading: Icon(icon, color: color),
      title: Text(capLabel(l, c)),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text([label, ?how].join(' · ')),
          if (note != null) Text(note, style: Theme.of(context).textTheme.bodySmall, textDirection: TextDirection.ltr),
        ],
      ),
    );
  }

  Widget _rawLog(BuildContext context, AppLocalizations l, AdapterCapabilities r) {
    final mono = Theme.of(context).textTheme.bodySmall?.copyWith(fontFamily: 'monospace');
    return Card(
      child: ExpansionTile(
        title: Text(l.adapterCapsRawLog),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        children: [
          for (final s in r.probe)
            Directionality(
              textDirection: TextDirection.ltr,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(s.ok ? Icons.check : Icons.close, size: 14, color: s.ok ? Colors.green.shade700 : Colors.grey),
                    const SizedBox(width: 6),
                    SizedBox(width: 90, child: Text('> ${s.cmd}', style: mono)),
                    Expanded(child: Text(s.response.replaceAll('\r', ' | '), style: mono)),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
