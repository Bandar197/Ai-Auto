import 'dart:convert';

import '../decode/dtc.dart';

class DrivePhase {
  DrivePhase({required this.phase, required this.durationS, required this.rpm, required this.speed, required this.throttle});

  factory DrivePhase.fromJson(Map<String, dynamic> j) => DrivePhase(
        phase: j['phase'] as String? ?? 'phase',
        durationS: (j['duration_s'] as num?)?.toDouble() ?? 10,
        rpm: (j['rpm'] as num?)?.toDouble() ?? 750,
        speed: (j['speed'] as num?)?.toDouble() ?? 0,
        throttle: (j['throttle'] as num?)?.toDouble() ?? 0,
      );

  final String phase;
  final double durationS;
  final double rpm;
  final double speed;
  final double throttle;
}

class ScenarioFault {
  ScenarioFault(this.json);
  final Map<String, dynamic> json;

  String get signal => json['signal'] as String;
  String get type => json['type'] as String;
  double num_(String k, [double d = 0]) => (json[k] as num?)?.toDouble() ?? d;
}

/// A demo scenario (`shared/scenarios/*.json`, format automind.scenario.v1).
class Scenario {
  Scenario(this.json);

  factory Scenario.fromJsonString(String s) => Scenario(jsonDecode(s) as Map<String, dynamic>);

  final Map<String, dynamic> json;

  String get key => json['key'] as String? ?? 'scenario';
  String name(String lang) => (json[lang == 'ar' ? 'name_ar' : 'name_en'] ?? json['name_en'] ?? key) as String;
  String description(String lang) => (json[lang == 'ar' ? 'description_ar' : 'description_en'] ?? '') as String;
  String get protocol => json['protocol'] as String? ?? '6';
  List<String> get ecus => [for (final e in (json['ecus'] as List? ?? const ['7E8'])) e as String];
  Map<String, dynamic> get vehicle => (json['vehicle'] as Map<String, dynamic>?) ?? const {};
  String get vin => vehicle['vin'] as String? ?? 'AMDEMO1234567890X';
  String get firmware => json['adapter_firmware'] as String? ?? 'ELM327 v1.5';
  double get batteryOff => (json['battery_voltage_off'] as num?)?.toDouble() ?? 12.6;
  double get chargingVoltage => (json['charging_voltage'] as num?)?.toDouble() ?? 14.2;
  double get initialCoolant => (json['initial_coolant_c'] as num?)?.toDouble() ?? 88;
  double get ambient => (json['ambient_c'] as num?)?.toDouble() ?? 35;
  double get baro => (json['baro_kpa'] as num?)?.toDouble() ?? 100;

  List<int> supportedPids(String service) {
    final sp = json['supported_pids'] as Map<String, dynamic>? ?? const {};
    return [for (final p in (sp[service] as List? ?? const [])) int.parse(p as String, radix: 16)];
  }

  List<DrivePhase> get driveCycle => [
        for (final p in (json['drive_cycle'] as List? ?? const [])) DrivePhase.fromJson(p as Map<String, dynamic>),
      ];

  List<ScenarioFault> get faults => [for (final f in (json['faults'] as List? ?? const [])) ScenarioFault(f as Map<String, dynamic>)];

  List<Dtc> get dtcs => [for (final d in (json['dtcs'] as List? ?? const [])) Dtc.fromJson(d as Map<String, dynamic>)];

  Map<String, dynamic>? get freezeFrame => json['freeze_frame'] as Map<String, dynamic>?;

  /// Whether the fault is still physically present (re-detected after a clear).
  bool get faultActive => json['fault_active'] as bool? ?? (json['faults'] as List? ?? const []).isNotEmpty;
  double get redetectPendingS => (json['redetect_pending_s'] as num?)?.toDouble() ?? 20;
  double get redetectStoredS => (json['redetect_stored_s'] as num?)?.toDouble() ?? 45;
  double get monitorCompleteS => (json['monitor_complete_s'] as num?)?.toDouble() ?? 90;
}
