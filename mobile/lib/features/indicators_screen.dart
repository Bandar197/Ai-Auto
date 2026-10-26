import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/indicators.dart';
import '../core/storage/scan_report.dart';
import '../l10n/app_localizations.dart';
import '../obd/obd.dart';
import '../state/connection_controller.dart';
import '../state/providers.dart';
import '../ui/l10n_helpers.dart';
import '../ui/widgets.dart';

/// Warning indicators: for each dashboard lamp, what the car's computers report
/// ("read state") — kept apart from the lamp the driver sees. Airbag/ABS are only
/// inferred from module codes; a module that was not read is "unknown", never OK.
/// The app never switches real dashboard lamps on or off.
class IndicatorsScreen extends ConsumerStatefulWidget {
  const IndicatorsScreen({super.key});
  @override
  ConsumerState<IndicatorsScreen> createState() => _IndicatorsScreenState();
}

class _IndicatorsScreenState extends ConsumerState<IndicatorsScreen> with SingleTickerProviderStateMixin {
  ScanReport? _report;
  Recording? _recording;
  LiveReadings _live = const LiveReadings();
  bool _checking = false;
  late final AnimationController _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))
    ..repeat(reverse: true);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _loadLatest();
      if (ref.read(connectionProvider).ecuReady) await _checkNow();
    });
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  Future<void> _loadLatest() async {
    final store = ref.read(localStoreProvider);
    final mode = ref.read(connectionProvider).mode?.apiValue;
    ScanReport? pick;
    for (final r in await store.listReports()) {
      if (r.recordingId == null) continue;
      if (mode == null || r.dataMode == mode) {
        pick = r;
        break;
      }
    }
    final rec = pick == null ? null : await store.loadRecording(pick.recordingId!);
    if (mounted) {
      setState(() {
        _report = pick;
        _recording = rec;
      });
    }
  }

  /// Read-only: 01 01 (MIL), 01 0C (rpm), 01 05 (coolant), ATRV (voltage).
  Future<void> _checkNow() async {
    final c = ref.read(connectionProvider).client;
    if (c == null || !c.isReady || _checking) return;
    setState(() => _checking = true);
    try {
      if (c.supported == null) await c.readSupportedPids();
      Future<double?> read(int pid, String key) async {
        if (!c.supported!.supports(pid)) return null;
        final r = await c.readPid(pid);
        return r.isEmpty ? null : r.first.values[key];
      }

      final readiness = await c.readReadiness();
      final rpm = await read(0x0C, 'engine_rpm');
      final coolant = await read(0x05, 'coolant_temp');
      double? volts;
      final rv = await c.elm.send('ATRV');
      final m = RegExp(r'(\d+(?:\.\d+)?)').firstMatch(rv.ok ? rv.text : '');
      volts = m == null ? null : double.tryParse(m.group(1)!);
      if (mounted) {
        setState(() => _live = LiveReadings(
              milOn: readiness?['mil_on'] as bool?,
              dtcCount: (readiness?['dtc_count'] as num?)?.toInt(),
              rpm: rpm,
              coolantC: coolant,
              volts: volts,
            ));
      }
    } on Object catch (_) {
      // Keep whatever was read; unknown stays unknown.
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  static String title(AppLocalizations l, String key) => switch (key) {
        'engine' => l.ind_engine,
        'airbag' => l.ind_airbag,
        'abs' => l.ind_abs,
        'battery' => l.ind_battery,
        'coolant' => l.ind_coolant,
        'oil' => l.ind_oil,
        'tpms' => l.ind_tpms,
        'esc' => l.ind_esc,
        'eps' => l.ind_eps,
        _ => l.ind_seatbelt,
      };

  static IconData icon(String key) => switch (key) {
        'engine' => Icons.engineering,
        'airbag' => Icons.airline_seat_recline_extra,
        'abs' => Icons.disc_full_outlined,
        'battery' => Icons.battery_alert_outlined,
        'coolant' => Icons.thermostat,
        'oil' => Icons.oil_barrel_outlined,
        'tpms' => Icons.tire_repair,
        'esc' => Icons.swap_calls,
        'eps' => Icons.settings_input_component_outlined,
        _ => Icons.event_seat_outlined,
      };

  static String detailText(AppLocalizations l, String? d) => switch (d) {
        'mil_on' => l.indDetail_mil_on,
        'mil_off' => l.indDetail_mil_off,
        'codes_stored' => l.indDetail_codes_stored,
        'module_no_codes' => l.indDetail_module_no_codes,
        'module_not_read' => l.indDetail_module_not_read,
        'module_refused' => l.indDetail_module_refused,
        'charging_low' => l.indDetail_charging_low,
        'charging_ok' => l.indDetail_charging_ok,
        'battery_low' => l.indDetail_battery_low,
        'battery_ok_engine_off' => l.indDetail_battery_ok_engine_off,
        'coolant_high' => l.indDetail_coolant_high,
        'coolant_ok' => l.indDetail_coolant_ok,
        'not_readable' => l.indDetail_not_readable,
        _ => l.indDetail_no_data,
      };

  static (Color, String) stateLook(AppLocalizations l, IndicatorState s) => switch (s) {
        IndicatorState.ok => (Colors.green.shade700, l.indState_ok),
        IndicatorState.fault => (Colors.red.shade700, l.indState_fault),
        IndicatorState.warning => (Colors.orange.shade800, l.indState_warning),
        IndicatorState.unknown => (Colors.blueGrey, l.indState_unknown),
        IndicatorState.unsupported => (Colors.grey, l.indState_unsupported),
      };

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final conn = ref.watch(connectionProvider);
    final items = buildIndicators(recording: _recording, live: _live);
    final liveKeys = {'engine', 'battery', 'coolant'};
    return Scaffold(
      appBar: AppBar(title: Text(l.indicatorsTitle)),
      body: ListView(padding: const EdgeInsets.only(bottom: 24), children: [
        if (conn.mode != null) ModeBanner(mode: conn.mode!.apiValue, simulator: conn.isSimulator),
        if (conn.mode == null && _report != null && _report!.dataMode != 'live') ModeBanner(mode: _report!.dataMode),
        Container(
          margin: const EdgeInsets.all(12),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: Colors.blue.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(10)),
          child: Text(l.indicatorsIntro),
        ),
        if (_recording == null || _recording!.moduleScans.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Text(l.indicatorsNoScan, style: Theme.of(context).textTheme.bodySmall),
          ),
        for (final it in items) _card(context, l, it, checking: _checking && liveKeys.contains(it.key)),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: FilledButton.icon(
            key: const Key('indicators-check'),
            icon: const Icon(Icons.refresh),
            label: Text(l.indicatorsCheckNow),
            onPressed: conn.ecuReady && !_checking ? _checkNow : null,
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: OutlinedButton.icon(
            icon: const Icon(Icons.radar),
            label: Text(l.fullScanTitle),
            onPressed: () => context.push(conn.ecuReady ? '/full-scan' : '/connect?next=full-scan'),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: OutlinedButton.icon(
            key: const Key('open-ecu-map'),
            icon: const Icon(Icons.account_tree_outlined),
            label: Text(l.ecuMapTitle),
            onPressed: () => context.push('/ecu-map'),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: OutlinedButton.icon(
            key: const Key('open-monitor-tests'),
            icon: const Icon(Icons.fact_check_outlined),
            label: Text(l.monitorTestsTitle),
            onPressed: () => context.push('/monitor-tests'),
          ),
        ),
      ]),
    );
  }

  Widget _card(BuildContext context, AppLocalizations l, IndicatorStatus it, {required bool checking}) {
    final (color, label) = stateLook(l, it.state);
    final lit = it.state == IndicatorState.fault || it.state == IndicatorState.warning;
    return Card(
      key: Key('indicator-${it.key}'),
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // In-app animation only: it shows the check, not the real lamp.
          AnimatedBuilder(
            animation: _pulse,
            builder: (_, child) => Opacity(opacity: checking ? 0.35 + 0.65 * _pulse.value : 1, child: child),
            child: Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: (checking ? Colors.blue : color).withValues(alpha: lit ? 0.22 : 0.1),
                boxShadow: lit && !checking ? [BoxShadow(color: color.withValues(alpha: 0.35), blurRadius: 10)] : null,
              ),
              child: Icon(icon(it.key), color: checking ? Colors.blue : color),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(child: Text(title(l, it.key), style: const TextStyle(fontWeight: FontWeight.w700))),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(color: (checking ? Colors.blue : color).withValues(alpha: 0.15), borderRadius: BorderRadius.circular(8)),
                  child: Text(checking ? l.indState_checking : label,
                      key: Key('indicator-state-${it.key}'),
                      style: TextStyle(color: checking ? Colors.blue : color, fontWeight: FontWeight.w700, fontSize: 12)),
                ),
              ]),
              const SizedBox(height: 4),
              Text(detailText(l, it.detail), style: Theme.of(context).textTheme.bodySmall),
              if (it.source != IndicatorSource.none)
                Text(it.source == IndicatorSource.read ? l.indSource_read : l.indSource_inferred,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(fontStyle: FontStyle.italic)),
              if (it.key == 'battery' && _live.volts != null)
                Text('${_live.volts!.toStringAsFixed(1)} V', textDirection: TextDirection.ltr),
              if (it.key == 'coolant' && _live.coolantC != null)
                Text('${_live.coolantC!.toStringAsFixed(0)} °C', textDirection: TextDirection.ltr),
              if (it.codes.isNotEmpty) Text(it.codes.join(' · '), textDirection: TextDirection.ltr),
              if (it.state == IndicatorState.fault && it.codes.isNotEmpty && _report != null)
                Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: TextButton(
                    onPressed: () => context.push('/clear-dtcs?report=${_report!.id}'),
                    child: Text(l.indicatorsClearCta),
                  ),
                ),
            ]),
          ),
        ]),
      ),
    );
  }
}
