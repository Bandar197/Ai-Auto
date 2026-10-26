import 'dart:math' as math;

import 'scenario.dart';

/// Generates physically plausible engine signals following a scenario's
/// drive cycle, then applies its faults. Deterministic for a given seed and
/// time, so tests are reproducible.
class SignalModel {
  SignalModel(this.scenario, {int seed = 42}) : _rng = math.Random(seed);

  final Scenario scenario;
  final math.Random _rng;

  /// When false the engine is off (ignition on): 0 rpm, 0 km/h.
  bool engineRunning = true;

  static const double rampS = 3.0;

  double _noise(double amp) => (_rng.nextDouble() * 2 - 1) * amp;

  /// Target (rpm, speed, throttle, phase) at time [t] seconds, smoothly
  /// ramped from the previous phase over [rampS] seconds. The cycle loops.
  (double, double, double, String) targets(double t) {
    final phases = scenario.driveCycle;
    if (phases.isEmpty) return (750, 0, 0, 'idle');
    final total = phases.fold<double>(0, (a, p) => a + p.durationS);
    var tt = total <= 0 ? 0.0 : t % total;
    var idx = 0;
    while (idx < phases.length - 1 && tt >= phases[idx].durationS) {
      tt -= phases[idx].durationS;
      idx++;
    }
    final cur = phases[idx];
    final prev = phases[(idx - 1 + phases.length) % phases.length];
    final k = t < rampS && idx == 0 ? 1.0 : (tt / rampS).clamp(0.0, 1.0);
    // smoothstep
    final s = k * k * (3 - 2 * k);
    double lerp(double a, double b) => a + (b - a) * s;
    return (lerp(prev.rpm, cur.rpm), lerp(prev.speed, cur.speed), lerp(prev.throttle, cur.throttle), cur.phase);
  }

  /// All signal values (pids.json output keys) at [t] seconds.
  Map<String, double> sample(double t) {
    final v = <String, double>{};
    final baro = scenario.baro;
    final ambient = scenario.ambient;
    final coolant0 = scenario.initialCoolant;
    final coolant = (coolant0 + (90 - coolant0) * (1 - math.exp(-t / 120)) + 0.6 * math.sin(t / 40) + _noise(0.3));

    if (!engineRunning) {
      v.addAll({
        'engine_rpm': 0,
        'vehicle_speed': 0,
        'throttle_pos': 14.5,
        'map_kpa': baro,
        'maf_gs': 0,
        'engine_load': 0,
        'timing_advance': 0,
        'stft_b1': 0,
        'ltft_b1': 1.6,
        'o2_b1s1_voltage': 0.45,
        'o2_b1s1_stft': 0,
        'o2_b1s2_voltage': 0.45,
        'module_voltage': scenario.batteryOff + _noise(0.02),
        'accel_pedal_d': 15.3,
        'commanded_throttle': 0,
      });
    } else {
      final (tRpm, tSpeed, tThr, _) = targets(t);
      final rpm = math.max(0.0, tRpm + _noise(tRpm < 1000 ? 12 : 25));
      final speed = math.max(0.0, tSpeed + (tSpeed > 1 ? _noise(0.8) : 0));
      final thr = math.max(0.0, tThr + (tThr > 0.5 ? _noise(0.6) : 0));
      final loaded = speed > 5;
      // Intake manifold pressure: ~31 kPa warm idle, lower on a free rev,
      // higher under road load. Never above barometric.
      final map = (31 - (rpm - 750) / 1750 * 5 + thr * (loaded ? 1.0 : 0.15) + _noise(0.7)).clamp(18.0, baro);
      final maf = math.max(0.5, 3.0 * (rpm / 750) * (map / 31) + _noise(0.12));
      final load = (map / baro * 75).clamp(0.0, 100.0);
      final o2 = 0.5 + 0.4 * _tanhSin(2 * math.pi * 1.0 * t);
      v.addAll({
        'engine_rpm': rpm,
        'vehicle_speed': speed,
        'throttle_pos': 14.5 + thr * 0.85,
        'map_kpa': map,
        'maf_gs': maf,
        'engine_load': load,
        'timing_advance': (12 + (rpm - 750) / 1750 * 18 - (map - 30) * 0.15 + _noise(0.5)).clamp(-10.0, 45.0),
        'stft_b1': 2.5 * math.sin(2 * math.pi * t / 7) + _noise(1.0),
        'ltft_b1': 1.6 + _noise(0.2),
        'o2_b1s1_voltage': (o2 + _noise(0.02)).clamp(0.05, 0.95),
        'o2_b1s1_stft': 2.5 * math.sin(2 * math.pi * t / 7),
        'o2_b1s2_voltage': 0.68 + _noise(0.02),
        'module_voltage': scenario.chargingVoltage + _noise(0.08),
        'accel_pedal_d': 15.3 + thr * 0.8,
        'commanded_throttle': (thr * 0.9 + 3).clamp(0.0, 100.0),
      });
    }
    v.addAll({
      'coolant_temp': coolant,
      'intake_air_temp': ambient + 6 - (v['vehicle_speed']! / 40) + _noise(0.4),
      'ambient_temp': ambient,
      'baro_kpa': baro,
      'fuel_level': 62 - t / 600,
      'run_time': engineRunning ? 120 + t : 0,
      'warmups_since_clear': 12,
      'distance_since_clear': 1450,
      'distance_mil_on': 0,
    });

    _applyFaults(v);

    // Derived after faults (closed loop needs a warm engine).
    final cool = v['coolant_temp']!;
    final decel = v['throttle_pos']! < 15 && v['vehicle_speed']! > 5 && v['engine_rpm']! > 1200;
    v['fuel_system_1_status'] = !engineRunning ? 0 : (cool < 50 ? 1 : (decel ? 4 : 2));
    v['fuel_system_2_status'] = 0;
    return v;
  }

  static double _tanhSin(double x) {
    final y = 3 * math.sin(x);
    final e = math.exp(2 * y);
    return (e - 1) / (e + 1);
  }

  void _applyFaults(Map<String, double> v) {
    for (final f in scenario.faults) {
      final key = f.signal;
      if (!v.containsKey(key)) continue;
      final when = f.json['when'] as String?;
      if (when == 'rpm_below' && !(v['engine_rpm']! < f.num_('threshold', 1200))) continue;
      if (when == 'rpm_above' && !(v['engine_rpm']! > f.num_('threshold', 1200))) continue;
      final x = v[key]!;
      switch (f.type) {
        case 'offset':
          v[key] = x + f.num_('value');
        case 'noise':
          v[key] = x + _noise(f.num_('amplitude'));
        case 'rpm_dependent':
          final rpm = v['engine_rpm']!;
          final k = ((rpm - 800) / (2500 - 800)).clamp(0.0, 1.0);
          final idle = f.num_('idle_value');
          final high = f.num_('high_rpm_value');
          v[key] = idle + (high - idle) * k + _noise(0.6);
        case 'cap':
          v[key] = math.min(x, f.num_('value'));
        case 'override':
          v[key] = f.num_('value') + _noise(f.num_('noise'));
      }
    }
  }
}
