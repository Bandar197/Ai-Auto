import '../obd/obd.dart';

/// A problem seen in MEASURED live values (service 01), not in stored fault codes.
/// Many real faults set no code at all — a dead radiator fan, low coolant, a stuck
/// thermostat, a weak alternator — so a scan must never call the car healthy just
/// because the code list is empty.
class MeasuredFinding {
  const MeasuredFinding({required this.key, required this.severity, required this.signal, this.value, this.unit});

  factory MeasuredFinding.fromJson(Map<String, dynamic> j) => MeasuredFinding(
        key: j['key'] as String,
        severity: j['severity'] as String? ?? 'info',
        signal: j['signal'] as String? ?? '',
        value: (j['value'] as num?)?.toDouble(),
        unit: j['unit'] as String?,
      );

  /// overheat | coolant_hot | coolant_sensor_suspect | coolant_ok | coolant_not_read |
  /// charging_low | overcharging | battery_low | fuel_trim_lean | fuel_trim_rich
  final String key;

  /// critical | warning | info
  final String severity;
  final String signal;

  /// The worst value seen (max for heat, min/max for voltage, extreme for trims).
  final double? value;
  final String? unit;

  bool get needsAttention => severity == 'critical' || severity == 'warning';

  Map<String, dynamic> toJson() => {'key': key, 'severity': severity, 'signal': signal, 'value': value, 'unit': unit};
}

/// Thresholds (°C / V / %). Coolant on a warm petrol engine normally sits 85–105 °C;
/// the radiator fan should start around 100–105 °C.
const double kCoolantHotC = 105;
const double kCoolantOverheatC = 110;
const double kChargingLowV = 13.0;
const double kOverchargeV = 15.0;
const double kBatteryLowV = 12.0;
const double kFuelTrimPct = 15;

/// Signal key → every value read for it (from recording samples or a live snapshot).
Map<String, List<double>> valuesBySignal(Iterable<RecordingSample> samples) {
  final out = <String, List<double>>{};
  for (final s in samples) {
    for (final e in s.values.entries) {
      final v = e.value;
      if (v != null && v.isFinite) (out[e.key] ??= []).add(v);
    }
  }
  return out;
}

/// Honest findings from measured values. Only what was actually read is judged;
/// [coolantAttempted] marks that a coolant read was tried, so its absence is reported
/// ("not read") instead of silently implying "normal".
List<MeasuredFinding> measuredFindings(Map<String, List<double>> values, {bool coolantAttempted = false}) {
  final out = <MeasuredFinding>[];
  double? maxOf(String k) => values[k]?.isNotEmpty == true ? values[k]!.reduce((a, b) => a > b ? a : b) : null;
  double? minOf(String k) => values[k]?.isNotEmpty == true ? values[k]!.reduce((a, b) => a < b ? a : b) : null;

  final rpmMax = maxOf('engine_rpm');
  final running = rpmMax != null && rpmMax > 400;

  // --- Coolant temperature (01 05) ---
  final ctMax = maxOf('coolant_temp');
  final ctMin = minOf('coolant_temp');
  if (ctMax == null) {
    if (coolantAttempted) out.add(const MeasuredFinding(key: 'coolant_not_read', severity: 'info', signal: 'coolant_temp'));
  } else if (ctMin != null && ctMin <= -39) {
    // −40 °C is the floor of the PID: typical of an open sensor circuit.
    out.add(MeasuredFinding(key: 'coolant_sensor_suspect', severity: 'warning', signal: 'coolant_temp', value: ctMin, unit: '°C'));
  } else if (ctMax >= kCoolantOverheatC) {
    out.add(MeasuredFinding(key: 'overheat', severity: 'critical', signal: 'coolant_temp', value: ctMax, unit: '°C'));
  } else if (ctMax >= kCoolantHotC) {
    out.add(MeasuredFinding(key: 'coolant_hot', severity: 'warning', signal: 'coolant_temp', value: ctMax, unit: '°C'));
  } else {
    // Normal per the sensor — shown with the value so the user can compare it with the
    // dashboard gauge (a sensor reading low hides overheating AND keeps the fan off).
    out.add(MeasuredFinding(key: 'coolant_ok', severity: 'info', signal: 'coolant_temp', value: ctMax, unit: '°C'));
  }

  // --- Control-module voltage (01 42) ---
  final vMin = minOf('module_voltage');
  final vMax = maxOf('module_voltage');
  if (vMin != null && vMax != null && rpmMax != null) {
    if (running && vMax > kOverchargeV) {
      out.add(MeasuredFinding(key: 'overcharging', severity: 'warning', signal: 'module_voltage', value: vMax, unit: 'V'));
    } else if (running && vMin < kChargingLowV) {
      out.add(MeasuredFinding(key: 'charging_low', severity: 'warning', signal: 'module_voltage', value: vMin, unit: 'V'));
    } else if (!running && vMin < kBatteryLowV) {
      out.add(MeasuredFinding(key: 'battery_low', severity: 'warning', signal: 'module_voltage', value: vMin, unit: 'V'));
    }
  }

  // --- Long-term fuel trims (01 07 / 01 09), meaningful only with the engine running ---
  if (running) {
    for (final k in const ['ltft_b1', 'ltft_b2']) {
      final hi = maxOf(k);
      final lo = minOf(k);
      if (hi != null && hi >= kFuelTrimPct) {
        out.add(MeasuredFinding(key: 'fuel_trim_lean', severity: 'warning', signal: k, value: hi, unit: '%'));
      } else if (lo != null && lo <= -kFuelTrimPct) {
        out.add(MeasuredFinding(key: 'fuel_trim_rich', severity: 'warning', signal: k, value: lo, unit: '%'));
      }
    }
  }

  const rank = {'critical': 0, 'warning': 1, 'info': 2};
  out.sort((a, b) => rank[a.severity]!.compareTo(rank[b.severity]!));
  return out;
}

/// PIDs read for the measured check during a full scan (read-only service 01).
const List<int> kMeasuredPids = [0x0C, 0x05, 0x42, 0x07, 0x09];
