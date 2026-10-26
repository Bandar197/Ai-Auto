import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/clear/clear_planner.dart';
import '../core/clear/proven_modules.dart';
import '../core/storage/clear_entry.dart';
import '../core/storage/scan_report.dart';
import '../l10n/app_localizations.dart';
import '../obd/obd.dart';
import '../state/adapter_caps_controller.dart';
import '../state/clear_controller.dart';
import '../state/connection_controller.dart';
import '../state/providers.dart';
import '../ui/l10n_helpers.dart';
import '../ui/widgets.dart';

/// Clear fault codes — honestly:
/// * two lists: what CAN be cleared now, and what cannot (with the exact context and
///   reason — never a promise to erase every module);
/// * the user picks the targets; conditions (ignition, engine off, stopped, battery)
///   are shown; explicit consent;
/// * a permanent snapshot is saved first; after the clear every code is re-read and
///   shown as cleared / still present / re-read failed / pending;
/// * "code cleared" is kept apart from "lamp actually off".
class ClearDtcsScreen extends ConsumerStatefulWidget {
  const ClearDtcsScreen({super.key, this.reportId});
  final String? reportId;
  @override
  ConsumerState<ClearDtcsScreen> createState() => _ClearDtcsScreenState();
}

class _ClearDtcsScreenState extends ConsumerState<ClearDtcsScreen> {
  double? _rpm;
  double? _speed;
  double? _volts;
  String? _message;
  ScanReport? _report;
  Recording? _recording;
  Set<String>? _serverProcedures;
  List<UdsModule> _proven = const [];
  final Set<String> _selected = {};
  bool _loaded = false;
  ClearResult? _result;

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
    Set<String>? procs;
    if (ref.read(authProvider).value != null) {
      try {
        final list = await ref.read(apiProvider).controlProcedures(vehicleId: r?.vehicleId);
        procs = {for (final p in list) if (p['available'] == true) '${p['key']}'};
      } on Object catch (_) {
        procs = null; // offline → module clears stay blocked
      }
    }
    final provenKey = provenVehicleKey(
      vin: r?.vin ?? rec?.vehicle['vin'] as String?,
      vehicleId: r?.vehicleId ?? ref.read(settingsProvider).selectedVehicleId,
    );
    final proven = r?.dataMode == 'live'
        ? [for (final p in await ProvenModulesStore(store).forVehicle(provenKey)) p.toUdsModule()]
        : const <UdsModule>[];
    if (!mounted) return;
    setState(() {
      _report = r;
      _recording = rec;
      _serverProcedures = procs;
      _proven = proven;
      _loaded = true;
      _selected
        ..clear()
        ..addAll(_plan().clearable.map((t) => t.key));
    });
  }

  ClearPlan _plan() {
    final conn = ref.read(connectionProvider);
    final make = ref.read(selectedVehicleProvider)?['make']?.toString();
    final assets = ref.read(appAssetsProvider);
    return planClear(
      recording: _recording,
      reportDtcs: _report?.dtcs ?? const [],
      connected: conn.client != null && conn.ecuReady,
      replay: conn.mode == DataMode.replay,
      adapter: ref.read(adapterCapabilitiesProvider).value,
      registry: assets.modules.candidatesFor(make),
      serverProcedures: _serverProcedures,
      proven: _proven,
      describeEn: (c) => assets.kb.lookupFor(c, make: effectiveMake(ref.read(selectedVehicleProvider), _report?.vin, assets))?.description('en'),
    );
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
    double? volts;
    try {
      final rv = await c.elm.send('ATRV');
      final m = RegExp(r'(\d+(?:\.\d+)?)').firstMatch(rv.ok ? rv.text : '');
      volts = m == null ? null : double.tryParse(m.group(1)!);
    } on Object catch (_) {}
    if (mounted) {
      setState(() {
        _rpm = rpm;
        _speed = speed;
        _volts = volts ?? c.info.voltage;
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
      ClearFailure.snapshotFailed => '${l.clearFailed} (${r.detail ?? ''})',
      ClearFailure.nothingClearable => l.clearNoneClearable,
    };
  }

  Future<void> _run(List<ClearTarget> targets) async {
    final l = context.l10n;
    final lang = context.lang;
    final report = _report;
    if (report == null || targets.isEmpty) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.clearDtcsTitle),
        content: SingleChildScrollView(
          child: Text([
            l.clearConsentTargets,
            for (final t in targets) '• ${t.name(lang)}: ${t.codes.join(', ')}',
            '',
            l.clearDtcsWarning,
            '',
            l.clearDtcsChecklist,
          ].join('\n')),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(l.cancel)),
          FilledButton(
            key: const Key('clear-consent'),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l.clearDtcsConfirm),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      _message = null;
      _result = null;
    });
    final r = await ref.read(clearProvider.notifier).clearTargets(report, targets, consentText: l.clearDtcsWarning);
    if (!mounted) return;
    await ref.read(reportsProvider.notifier).refresh();
    if (!mounted) return;
    setState(() {
      _result = r.ok || r.results.isNotEmpty ? r : null;
      _message = r.ok ? null : _failureText(r);
    });
    if (r.ok) showSnack(context, l.clearSuccess);
    await _readConditions();
  }

  String _phaseText(ClearPhase p) {
    final l = context.l10n;
    return switch (p) {
      ClearPhase.checking => l.clearPhase_checking,
      ClearPhase.snapshot => l.clearSnapshotKept,
      ClearPhase.uploading => l.clearPhase_uploading,
      ClearPhase.requesting => l.clearPhase_requesting,
      ClearPhase.clearing => l.clearPhase_clearing,
      ClearPhase.waiting => l.clearPhase_waiting,
      ClearPhase.rechecking => l.clearPhase_rechecking,
      _ => '',
    };
  }

  static String contextText(AppLocalizations l, ClearContext c) => switch (c) {
        ClearContext.allowed => l.ctx_allowed,
        ClearContext.unsupportedByHardware => l.ctx_unsupported_by_hardware,
        ClearContext.unsupportedByVehicle => l.ctx_unsupported_by_vehicle,
        ClearContext.requiresOemAuthorization => l.ctx_requires_oem_authorization,
        ClearContext.activeFaultNotClearable => l.ctx_active_fault_not_clearable,
        ClearContext.crashDataSpecialist => l.ctx_crash_data_specialist,
        ClearContext.commFailed => l.ctx_comm_failed,
        ClearContext.clearedAndVerified => l.ctx_cleared_and_verified,
      };

  static String reasonText(AppLocalizations l, ClearReason r) => switch (r) {
        ClearReason.notConnected => l.reason_not_connected,
        ClearReason.replay => l.reason_replay,
        ClearReason.moduleNotRead => l.reason_module_not_read,
        ClearReason.moduleRefused => l.reason_module_refused,
        ClearReason.addressUnverified => l.reason_address_unverified,
        ClearReason.clearNotDocumented => l.reason_clear_not_documented,
        ClearReason.adapterNoHeaders => l.reason_adapter_no_headers,
        ClearReason.activeFault => l.reason_active_fault,
        ClearReason.crashData => l.reason_crash_data,
        ClearReason.safetyPolicy => l.reason_safety_policy,
      };

  static String resultText(AppLocalizations l, String r) => switch (r) {
        'cleared' => l.res_cleared,
        'still_active' => l.res_still_active,
        'read_failed' => l.res_read_failed,
        'verification_pending' => l.res_verification_pending,
        'refused' => l.res_refused,
        'comm_failed' => l.res_comm_failed,
        _ => l.res_blocked,
      };

  static Color resultColor(String r) => switch (r) {
        'cleared' => Colors.green.shade700,
        'still_active' => Colors.red.shade700,
        'verification_pending' => Colors.blue.shade700,
        _ => Colors.orange.shade800,
      };

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final lang = context.lang;
    final conn = ref.watch(connectionProvider);
    final phase = ref.watch(clearProvider);
    final busy = phase != ClearPhase.idle && phase != ClearPhase.done;
    final report = _report;
    final user = ref.watch(authProvider).value;
    final plan = _loaded ? _plan() : const ClearPlan([]);
    final chosen = plan.clearable.where((t) => _selected.contains(t.key)).toList();
    final readiness = _recording?.readiness;
    final monitors = (readiness?['monitors'] as Map?) ?? const {};

    return Scaffold(
      appBar: AppBar(title: Text(l.clearDtcsTitle)),
      body: ListView(padding: const EdgeInsets.only(bottom: 24), children: [
        if (conn.mode != null) ModeBanner(mode: conn.mode!.apiValue, simulator: conn.isSimulator),
        if (conn.isDemo) Padding(padding: const EdgeInsets.all(12), child: Text(l.clearDemoNote)),
        if (_loaded && report == null) Padding(padding: const EdgeInsets.all(16), child: Text(l.clearNoReport)),
        if (_result != null) _results(context, l, _result!),
        if (report != null && _result == null) ...[
          // ---- can be cleared ----
          SectionCard(
            title: l.clearCanTitle,
            icon: Icons.check_circle_outline,
            child: plan.clearable.isEmpty
                ? Text(l.clearNoneClearable)
                : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    for (final t in plan.clearable)
                      CheckboxListTile(
                        key: Key('target-${t.key}'),
                        contentPadding: EdgeInsets.zero,
                        value: _selected.contains(t.key),
                        onChanged: busy ? null : (v) => setState(() => v == true ? _selected.add(t.key) : _selected.remove(t.key)),
                        title: Text(t.name(lang), style: const TextStyle(fontWeight: FontWeight.w700)),
                        subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(t.codes.join(' · '), textDirection: TextDirection.ltr),
                          if (t.proven)
                            Text(l.clearProvenNote, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.green.shade800)),
                          if (t.permanentCodes.isNotEmpty)
                            Text(l.clearPermanentNote(t.permanentCodes.join(', ')), style: Theme.of(context).textTheme.bodySmall),
                        ]),
                      ),
                  ]),
          ),
          // ---- cannot be cleared here ----
          if (plan.blocked.isNotEmpty)
            SectionCard(
              title: l.clearCannotTitle,
              icon: Icons.block,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                for (final t in plan.blocked)
                  ListTile(
                    key: Key('blocked-${t.key}'),
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      t.context == ClearContext.crashDataSpecialist ? Icons.medical_services_outlined : Icons.lock_outline,
                      color: Colors.orange.shade800,
                    ),
                    title: Text('${t.name(lang)} — ${contextText(l, t.context)}'),
                    subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      if (t.codes.isNotEmpty) Text(t.codes.join(' · '), textDirection: TextDirection.ltr),
                      if (t.reason != null) Text(reasonText(l, t.reason!)),
                    ]),
                  ),
              ]),
            ),
          // ---- what clearing erases ----
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
              Text(l.clearSnapshotKept, style: Theme.of(context).textTheme.bodySmall),
            ]),
          ),
          if (user == null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
              child: Text(l.clearOfflineNote, style: Theme.of(context).textTheme.bodySmall),
            ),
        ],
        // ---- conditions ----
        if (_result == null)
          SectionCard(
            title: l.clearDtcsChecklist,
            icon: Icons.checklist,
            child: Column(children: [
              _cond(l.clearIgnitionOn, conn.ecuReady),
              _cond(_rpm == null ? '— rpm' : '${_rpm!.toStringAsFixed(0)} rpm', _rpm == 0),
              _cond(_speed == null ? '— km/h' : '${_speed!.toStringAsFixed(0)} km/h', _speed == 0),
              if (_volts != null)
                ListTile(
                  dense: true,
                  leading: Icon(Icons.battery_charging_full, color: _volts! >= 12 ? Colors.green : Colors.orange),
                  title: Text(l.clearBatteryAdvice(_volts!.toStringAsFixed(1))),
                ),
              Align(alignment: AlignmentDirectional.centerEnd, child: TextButton(onPressed: _readConditions, child: Text(l.retry))),
            ]),
          ),
        if (conn.demo != null && _result == null) ...[
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
        if (_result == null)
          Padding(
            padding: const EdgeInsets.all(16),
            child: FilledButton.icon(
              key: const Key('clear-run'),
              style: FilledButton.styleFrom(backgroundColor: Colors.red, minimumSize: const Size.fromHeight(48)),
              icon: const Icon(Icons.delete_sweep),
              label: Text(chosen.isEmpty ? l.clearDtcsConfirm : l.clearSelectedCta(chosen.length)),
              onPressed: chosen.isEmpty || busy ? null : () => _run(chosen),
            ),
          ),
        if (user != null) _Procedures(vehicleId: report?.vehicleId),
      ]),
    );
  }

  Widget _results(BuildContext context, AppLocalizations l, ClearResult r) {
    final entry = r.entry;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SectionCard(
        title: l.clearResultsTitle,
        icon: Icons.fact_check_outlined,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          for (final t in r.results) ...[
            Row(children: [
              Expanded(child: Text(t.key == 'engine' ? 'OBD-II (04)' : '${t.key} (UDS 14)', style: const TextStyle(fontWeight: FontWeight.w700))),
              Text(resultText(l, t.result), style: TextStyle(color: resultColor(t.result), fontWeight: FontWeight.w700)),
            ]),
            if (t.nrc != null) Text('NRC ${t.nrc}', textDirection: TextDirection.ltr, style: Theme.of(context).textTheme.bodySmall),
            for (final c in t.codes.entries)
              Padding(
                padding: const EdgeInsetsDirectional.only(start: 12, top: 2),
                child: Row(children: [
                  Text(c.key, textDirection: TextDirection.ltr),
                  const Spacer(),
                  Text(resultText(l, c.value), key: Key('code-result-${c.key}'), style: TextStyle(color: resultColor(c.value))),
                ]),
              ),
            const Divider(),
          ],
          Text(l.clearCodeVsLamp, style: Theme.of(context).textTheme.bodySmall),
          Text(l.clearSnapshotKept, style: Theme.of(context).textTheme.bodySmall),
        ]),
      ),
      if (entry != null) _lamp(context, l, entry),
      if (entry != null)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: OutlinedButton.icon(
            icon: const Icon(Icons.timeline),
            label: Text(l.clearOpenVerification),
            onPressed: () => context.pushReplacement('/verify/${entry.id}'),
          ),
        ),
    ]);
  }

  Widget _lamp(BuildContext context, AppLocalizations l, ClearEntry e) {
    final (icon, color, text) = switch (e.lampOffBy) {
      'module_status' => (Icons.lightbulb_outline, Colors.green.shade700, l.clearLampByCar),
      'user' => (Icons.visibility_outlined, Colors.green.shade700, l.clearLampConfirmed),
      _ => (Icons.help_outline, Colors.blueGrey, l.clearLampUnknown),
    };
    return Card(
      key: const Key('lamp-state'),
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: ListTile(
        leading: Icon(icon, color: color),
        title: Text(text),
        trailing: e.lampOffBy == null
            ? TextButton(
                key: const Key('lamp-confirm'),
                onPressed: () async {
                  await ref.read(clearProvider.notifier).confirmLampOff(e);
                  if (mounted) setState(() => e.lampOffBy = 'user');
                },
                child: Text(l.clearLampConfirmCta),
              )
            : null,
      ),
    );
  }

  Widget _cond(String label, bool ok) => ListTile(
        dense: true,
        leading: Icon(ok ? Icons.check_circle : Icons.cancel, color: ok ? Colors.green : Colors.red),
        title: Text(label, textAlign: TextAlign.start),
      );
}

/// Control procedures as the server reports them. Unavailable ones (e.g.
/// `clear_srs_dtcs`, safety category airbag) show the server's reason.
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
