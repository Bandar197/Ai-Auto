import 'package:flutter/material.dart';

import '../core/measured_findings.dart';
import '../l10n/app_localizations.dart';
import 'l10n_helpers.dart';
import 'widgets.dart';

/// "Live engine readings" — problems seen in measured values even when no fault code
/// was stored (e.g. an overheating engine with a dead radiator fan).
class MeasuredFindingsCard extends StatelessWidget {
  const MeasuredFindingsCard({super.key, required this.findings});
  final List<MeasuredFinding> findings;

  @override
  Widget build(BuildContext context) {
    if (findings.isEmpty) return const SizedBox.shrink();
    final l = context.l10n;
    return SectionCard(
      key: const Key('measured-card'),
      title: l.measuredTitle,
      icon: Icons.thermostat,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(l.measuredIntro, style: Theme.of(context).textTheme.bodySmall),
        for (final f in findings) _row(context, l, f),
      ]),
    );
  }

  Widget _row(BuildContext context, AppLocalizations l, MeasuredFinding f) {
    final (IconData icon, Color color) = switch (f.severity) {
      'critical' => (Icons.dangerous_outlined, Colors.red),
      'warning' => (Icons.warning_amber_rounded, Colors.orange),
      _ => (Icons.info_outline, Colors.blueGrey),
    };
    final (title, advice) = measuredTexts(l, f);
    return ListTile(
      key: Key('measured-${f.key}'),
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon, color: color),
      title: Text(title, style: TextStyle(fontWeight: FontWeight.w600, color: f.needsAttention ? color : null)),
      subtitle: Text(advice),
    );
  }
}

String measuredValueText(MeasuredFinding f) {
  final v = f.value;
  if (v == null) return '';
  return switch (f.unit) {
    'V' => '${v.toStringAsFixed(1)} V',
    '%' => '${v > 0 ? '+' : ''}${v.toStringAsFixed(0)}%',
    '°C' => '${v.toStringAsFixed(0)} °C',
    _ => v.toStringAsFixed(1),
  };
}

/// (title, advice) for one finding in the current language.
(String, String) measuredTexts(AppLocalizations l, MeasuredFinding f) {
  final v = measuredValueText(f);
  return switch (f.key) {
    'overheat' => (l.measured_overheat(v), l.measured_overheat_advice),
    'coolant_hot' => (l.measured_coolant_hot(v), l.measured_coolant_hot_advice),
    'coolant_sensor_suspect' => (l.measured_coolant_sensor_suspect(v), l.measured_coolant_sensor_suspect_advice),
    'coolant_ok' => (l.measured_coolant_ok(v), l.measured_coolant_ok_advice),
    'coolant_not_read' => (l.measured_coolant_not_read, l.measured_coolant_not_read_advice),
    'charging_low' => (l.measured_charging_low(v), l.measured_charging_low_advice),
    'overcharging' => (l.measured_overcharging(v), l.measured_overcharging_advice),
    'battery_low' => (l.measured_battery_low(v), l.measured_battery_low_advice),
    'fuel_trim_lean' => (l.measured_fuel_trim_lean(v), l.measured_fuel_trim_lean_advice),
    'fuel_trim_rich' => (l.measured_fuel_trim_rich(v), l.measured_fuel_trim_rich_advice),
    _ => (f.key, ''),
  };
}
