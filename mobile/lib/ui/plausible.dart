/// Per-signal plausible ranges for a running, warm engine. Used only to
/// highlight values in Live Data — the diagnosis itself is server-side.
const Map<String, (double, double)> plausibleRanges = {
  'engine_rpm': (500, 6500),
  'coolant_temp': (-30, 110),
  'map_kpa': (15, 105),
  'maf_gs': (1.5, 250),
  'stft_b1': (-15, 15),
  'ltft_b1': (-15, 15),
  'stft_b2': (-15, 15),
  'ltft_b2': (-15, 15),
  'module_voltage': (12.2, 14.8),
  'intake_air_temp': (-30, 75),
  'engine_load': (0, 100),
  'throttle_pos': (0, 100),
  'vehicle_speed': (0, 200),
  'timing_advance': (-15, 50),
  'o2_b1s1_voltage': (0, 1.1),
  'o2_b1s2_voltage': (0, 1.1),
  'oil_temp': (-30, 130),
  'fuel_level': (5, 100),
};

/// True when [v] is outside the PID's own min/max or the plausible range.
bool isAnomalous(String key, double v, {double? min, double? max}) {
  if (min != null && v < min) return true;
  if (max != null && v > max) return true;
  final r = plausibleRanges[key];
  if (r == null) return false;
  return v < r.$1 || v > r.$2;
}
