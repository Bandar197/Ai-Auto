import '../obd/obd.dart';

/// What the app could establish for one dashboard warning indicator.
enum IndicatorState { ok, fault, warning, unknown, unsupported }

/// How it was established: read from the ECU, inferred from module codes, or not at all.
enum IndicatorSource { read, inferred, none }

/// Fresh values read now (all optional — anything not readable stays null).
class LiveReadings {
  const LiveReadings({this.milOn, this.dtcCount, this.rpm, this.coolantC, this.volts});
  final bool? milOn;
  final int? dtcCount;
  final double? rpm;
  final double? coolantC;
  final double? volts;
}

class IndicatorStatus {
  const IndicatorStatus({required this.key, required this.state, required this.source, this.detail, this.codes = const [], this.moduleKey});

  /// engine | airbag | abs | battery | coolant | oil | tpms | esc | eps | seatbelt
  final String key;
  final IndicatorState state;
  final IndicatorSource source;

  /// Machine-readable reason (localised by the screen):
  /// mil_on, mil_off, codes_stored, module_no_codes, module_not_read, module_refused,
  /// charging_low, charging_ok, battery_low, battery_ok_engine_off, coolant_high,
  /// coolant_ok, no_data, not_readable.
  final String? detail;
  final List<String> codes;
  final String? moduleKey;
}

/// Builds the indicator list from the last scan [recording] and optional [live]
/// readings. Honest by construction: a module that was not read is "unknown", never
/// "OK"; airbag/ABS lamp states are only *inferred* from module codes (the cluster
/// lamp itself is not readable over generic OBD); the battery lamp being on with the
/// engine off is normal and is not reported as a fault.
List<IndicatorStatus> buildIndicators({Recording? recording, LiveReadings live = const LiveReadings()}) {
  final out = <IndicatorStatus>[];

  // Engine (MIL): read directly from service 01 PID 01.
  final mil = live.milOn ?? (recording?.readiness?['mil_on'] as bool?);
  final engineCodes = [for (final d in recording?.dtcs ?? const <Dtc>[]) d.code];
  out.add(IndicatorStatus(
    key: 'engine',
    state: mil == null ? IndicatorState.unknown : (mil ? IndicatorState.fault : IndicatorState.ok),
    source: mil == null ? IndicatorSource.none : IndicatorSource.read,
    detail: mil == null ? 'no_data' : (mil ? 'mil_on' : 'mil_off'),
    codes: engineCodes,
  ));

  // Airbag / ABS: inferred from the module read.
  for (final (key, category) in const [('airbag', 'airbag'), ('abs', 'abs')]) {
    final mods = [for (final m in recording?.moduleScans ?? const <RecordingModuleScan>[]) if (m.category == category) m];
    final withCodes = mods.where((m) => m.outcome == 'read_codes' && m.codes.isNotEmpty).toList();
    final readClean = mods.where((m) => m.outcome == 'read_no_codes').toList();
    final refused = mods.where((m) => m.outcome == 'refused').toList();
    if (withCodes.isNotEmpty) {
      out.add(IndicatorStatus(
        key: key,
        state: IndicatorState.fault,
        source: IndicatorSource.inferred,
        detail: 'codes_stored',
        codes: [for (final m in withCodes) ...m.codes.map((d) => d.code)],
        moduleKey: withCodes.first.key,
      ));
    } else if (readClean.isNotEmpty) {
      out.add(IndicatorStatus(key: key, state: IndicatorState.ok, source: IndicatorSource.inferred, detail: 'module_no_codes', moduleKey: readClean.first.key));
    } else {
      out.add(IndicatorStatus(
        key: key,
        state: IndicatorState.unknown,
        source: IndicatorSource.none,
        detail: refused.isNotEmpty ? 'module_refused' : 'module_not_read',
        moduleKey: mods.firstOrNull?.key,
      ));
    }
  }

  // Battery / charging: judged only with the engine state known.
  final v = live.volts;
  final rpm = live.rpm;
  if (v == null || rpm == null) {
    out.add(const IndicatorStatus(key: 'battery', state: IndicatorState.unknown, source: IndicatorSource.none, detail: 'no_data'));
  } else if (rpm > 400) {
    out.add(IndicatorStatus(
      key: 'battery',
      state: v < 13.0 ? IndicatorState.warning : IndicatorState.ok,
      source: IndicatorSource.read,
      detail: v < 13.0 ? 'charging_low' : 'charging_ok',
    ));
  } else {
    out.add(IndicatorStatus(
      key: 'battery',
      state: v < 12.0 ? IndicatorState.warning : IndicatorState.ok,
      source: IndicatorSource.read,
      detail: v < 12.0 ? 'battery_low' : 'battery_ok_engine_off',
    ));
  }

  // Coolant temperature (service 01 PID 05).
  final t = live.coolantC;
  out.add(IndicatorStatus(
    key: 'coolant',
    state: t == null ? IndicatorState.unknown : (t >= 110 ? IndicatorState.warning : IndicatorState.ok),
    source: t == null ? IndicatorSource.none : IndicatorSource.read,
    detail: t == null ? 'no_data' : (t >= 110 ? 'coolant_high' : 'coolant_ok'),
  ));

  // Not readable over generic OBD without a verified module for this car.
  for (final k in const ['oil', 'tpms', 'esc', 'eps', 'seatbelt']) {
    out.add(IndicatorStatus(key: k, state: IndicatorState.unsupported, source: IndicatorSource.none, detail: 'not_readable'));
  }
  return out;
}
