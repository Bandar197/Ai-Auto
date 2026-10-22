import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/storage/scan_report.dart';
import '../obd/obd.dart';
import '../state/clear_controller.dart';
import '../state/connection_controller.dart';
import '../state/providers.dart';
import '../ui/l10n_helpers.dart';
import '../ui/widgets.dart';

/// Clear DTCs (service 04) and start "clear and verify":
/// scan saved as a session → server approval → engine off + speed 0 →
/// explicit confirmation → clear → immediate re-check → verdict.
class ClearDtcsScreen extends ConsumerStatefulWidget {
  const ClearDtcsScreen({super.key, this.reportId});
  final String? reportId;
  @override
  ConsumerState<ClearDtcsScreen> createState() => _ClearDtcsScreenState();
}

class _ClearDtcsScreenState extends ConsumerState<ClearDtcsScreen> {
  double? _rpm;
  double? _speed;
  String? _message;
  ScanReport? _report;
  Recording? _recording;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _load();
      await _readConditions();
    });
  }

  Future<void> _load() async {
    final store = ref.read(localStoreProvider);
    ScanReport? r;
    if (widget.reportId != null) {
      r = await store.loadReport(widget.reportId!);
    } else {
      final mode = ref.read(connectionProvider).mode?.apiValue;
      for (final x in await store.listReports()) {
        if (x.dataMode == mode) {
          r = x;
          break;
        }
      }
    }
    final rec = r?.recordingId == null ? null : await store.loadRecording(r!.recordingId!);
    if (mounted) {
      setState(() {
        _report = r;
        _recording = rec;
        _loaded = true;
      });
    }
  }

  Future<void> _readConditions() async {
    final c = ref.read(connectionProvider).client;
    if (c == null || !c.isReady) return;
    if (c.supported == null) await c.readSupportedPids();
    Future<double?> read(int pid, String key) async {
      if (!c.supported!.supports(pid)) return null;
      final r = await c.readPid(pid);
      return r.isEmpty ? null : r.first.values[key];
    }

    final rpm = await read(0x0C, 'engine_rpm');
    final speed = await read(0x0D, 'vehicle_speed');
    if (mounted) {
      setState(() {
        _rpm = rpm;
        _speed = speed;
      });
    }
  }

  String _failureText(ClearResult r) {
    final l = context.l10n;
    return switch (r.failure!) {
      ClearFailure.notConnected => l.notConnected,
      ClearFailure.replay => l.clearFailReplay,
      ClearFailure.conditionsUnreadable => l.clearFailUnreadable,
      ClearFailure.engineRunning => l.clearFailEngine(r.detail ?? ''),
      ClearFailure.moving => l.clearFailMoving(r.detail ?? ''),
      ClearFailure.needsServer => l.clearRequiresServer,
      ClearFailure.uploadFailed => l.clearFailUpload(r.detail ?? ''),
      ClearFailure.rejected => l.clearRejected(r.detail ?? ''),
      ClearFailure.policy => l.clearConditionsFailed(r.detail ?? ''),
      ClearFailure.carDidNotConfirm => l.clearFailed,
    };
  }

  Future<void> _run() async {
    final l = context.l10n;
    final report = _report;
    if (report == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.clearDtcsTitle),
        content: Text('${l.clearDtcsWarning}\n\n${l.verifyHowItWorks}\n\n${l.clearDtcsChecklist}'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(l.cancel)),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l.clearDtcsConfirm),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _message = null);
    final r = await ref.read(clearProvider.notifier).clearAndVerify(report, consentText: l.clearDtcsWarning);
    if (!mounted) return;
    await ref.read(reportsProvider.notifier).refresh();
    if (!mounted) return;
    if (r.ok) {
      showSnack(context, l.clearSuccess);
      context.pushReplacement('/verify/${r.entry!.id}');
    } else {
      setState(() => _message = _failureText(r));
      await _readConditions();
    }
  }

  String _phaseText(ClearPhase p) {
    final l = context.l10n;
    return switch (p) {
      ClearPhase.checking => l.clearPhase_checking,
      ClearPhase.uploading => l.clearPhase_uploading,
      ClearPhase.requesting => l.clearPhase_requesting,
      ClearPhase.clearing => l.clearPhase_clearing,
      ClearPhase.waiting => l.clearPhase_waiting,
      ClearPhase.rechecking => l.clearPhase_rechecking,
      _ => '',
    };
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final lang = context.lang;
    final conn = ref.watch(connectionProvider);
    final phase = ref.watch(clearProvider);
    final busy = phase != ClearPhase.idle && phase != ClearPhase.done;
    final report = _report;
    final canRun = conn.client != null && conn.ecuReady && conn.mode != DataMode.replay && report != null && report.dtcs.isNotEmpty;
    final readiness = _recording?.readiness;
    final monitors = (readiness?['monitors'] as Map?) ?? const {};
    final user = ref.watch(authProvider).value;
    return Scaffold(
      appBar: AppBar(title: Text(l.clearDtcsTitle)),
      body: ListView(padding: const EdgeInsets.only(bottom: 24), children: [
        if (conn.mode != null) ModeBanner(mode: conn.mode!.apiValue, simulator: conn.isSimulator),
        if (conn.isDemo) Padding(padding: const EdgeInsets.all(12), child: Text(l.clearDemoNote)),
        Container(
          margin: const EdgeInsets.all(12),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: Colors.blue.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(10)),
          child: Text(l.verifyHowItWorks, style: const TextStyle(fontWeight: FontWeight.w600)),
        ),
        if (_loaded && report == null) Padding(padding: const EdgeInsets.all(16), child: Text(l.clearNoReport)),
        if (report != null) ...[
          SectionCard(
            title: l.dtcsTitle,
            icon: Icons.error_outline,
            child: Text(report.dtcs.isEmpty ? l.noDtcs : report.dtcs.map((d) => '${d['code']} (${d['status']})').join(' · '),
                textDirection: TextDirection.ltr),
          ),
          SectionCard(
            title: l.clearErases,
            icon: Icons.delete_sweep_outlined,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('• ${l.clearErasesFreeze}'),
              if (report.freezeFrames.isNotEmpty)
                Padding(
                  padding: const EdgeInsetsDirectional.only(start: 12, top: 2, bottom: 6),
                  child: Text(
                    '${report.freezeFrames.first['dtc'] ?? ''}: ${((report.freezeFrames.first['values'] as Map?) ?? const {}).entries.map((e) => '${e.key}=${e.value}').join(', ')}',
                    style: Theme.of(context).textTheme.bodySmall,
                    textDirection: TextDirection.ltr,
                  ),
                ),
              Text('• ${l.clearErasesReadiness}'),
              if (monitors.isNotEmpty)
                Padding(
                  padding: const EdgeInsetsDirectional.only(start: 12, top: 4),
                  child: Wrap(spacing: 6, runSpacing: 4, children: [
                    for (final e in monitors.entries)
                      Chip(
                        visualDensity: VisualDensity.compact,
                        avatar: Icon((e.value as Map)['complete'] == true ? Icons.check_circle : Icons.timelapse,
                            size: 16, color: (e.value as Map)['complete'] == true ? Colors.green : Colors.orange),
                        label: Text(lang == 'ar' ? (monitorNames[e.key]?.$2 ?? '${e.key}') : (monitorNames[e.key]?.$1 ?? '${e.key}')),
                      ),
                  ]),
                ),
              const SizedBox(height: 6),
              Text(l.clearDtcsWarning, style: Theme.of(context).textTheme.bodySmall),
            ]),
          ),
          ListTile(
            leading: Icon(report.serverSessionId != null ? Icons.cloud_done : Icons.cloud_upload_outlined,
                color: report.serverSessionId != null ? Colors.green : Colors.orange),
            title: Text(report.serverSessionId != null ? l.clearScanSaved : l.clearScanNotSaved),
          ),
        ],
        SectionCard(
          title: l.clearDtcsChecklist,
          icon: Icons.checklist,
          child: Column(children: [
            _cond('rpm', _rpm, _rpm == 0),
            _cond('km/h', _speed, _speed == 0),
            Align(alignment: AlignmentDirectional.centerEnd, child: TextButton(onPressed: _readConditions, child: Text(l.retry))),
          ]),
        ),
        if (conn.demo != null) ...[
          SwitchListTile(
            title: Text(l.simulateEngineOff),
            value: !conn.demo!.emulator.engineRunning,
            onChanged: (v) {
              ref.read(connectionProvider.notifier).setEngineRunning(!v);
              _readConditions();
            },
          ),
          SwitchListTile(
            title: Text(l.autoStartAfterClear),
            value: ref.read(connectionProvider.notifier).autoStartAfterClear,
            onChanged: (v) => ref.read(connectionProvider.notifier).setAutoStartAfterClear(v),
          ),
        ],
        if (busy)
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(children: [
              const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2)),
              const SizedBox(width: 12),
              Expanded(child: Text(_phaseText(phase))),
            ]),
          ),
        if (_message != null)
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(_message!, style: const TextStyle(color: Colors.red, fontWeight: FontWeight.w700)),
          ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: FilledButton.icon(
            key: const Key('clear-run'),
            style: FilledButton.styleFrom(backgroundColor: Colors.red, minimumSize: const Size.fromHeight(48)),
            icon: const Icon(Icons.delete_sweep),
            label: Text(l.clearDtcsConfirm),
            onPressed: !canRun || busy ? null : _run,
          ),
        ),
        if (user != null) _Procedures(vehicleId: report?.vehicleId),
      ]),
    );
  }

  Widget _cond(String unit, double? v, bool ok) => ListTile(
        dense: true,
        leading: Icon(ok ? Icons.check_circle : Icons.cancel, color: ok ? Colors.green : Colors.red),
        title: Text(v == null ? '— $unit' : '${v.toStringAsFixed(0)} $unit', textDirection: TextDirection.ltr, textAlign: TextAlign.start),
      );
}

/// Control procedures as the server reports them. Unavailable ones (e.g.
/// `clear_srs_dtcs`, safety category airbag) show the server's reason; the
/// app never sends any SRS command.
class _Procedures extends ConsumerWidget {
  const _Procedures({this.vehicleId});
  final String? vehicleId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final lang = context.lang;
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: ref.read(apiProvider).controlProcedures(vehicleId: vehicleId),
      builder: (context, snap) {
        final list = snap.data ?? const [];
        if (list.isEmpty) return const SizedBox.shrink();
        return SectionCard(
          title: l.otherProcedures,
          icon: Icons.build_circle_outlined,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            for (final p in list.where((p) => p['key'] != 'clear_dtcs'))
              ListTile(
                key: Key('procedure-${p['key']}'),
                contentPadding: EdgeInsets.zero,
                enabled: false,
                leading: Icon(p['safety_category'] == 'airbag' ? Icons.airline_seat_recline_extra : Icons.lock_outline),
                title: Text(pickLang(p, 'name', lang)),
                subtitle: Text([
                  if (p['available'] != true) l.procedureUnavailable,
                  pickLang(p, 'reason', lang),
                ].where((x) => x.isNotEmpty).join(' — ')),
              ),
            Text(l.srsNote, style: Theme.of(context).textTheme.bodySmall),
          ]),
        );
      },
    );
  }
}
