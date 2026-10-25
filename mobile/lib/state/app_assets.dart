import 'dart:convert';

import 'package:flutter/services.dart';

import '../core/controller_catalog.dart';
import '../core/kb/local_kb.dart';
import '../core/module_registry.dart';
import '../core/vehicle_make.dart';
import '../core/vehicle_profiles.dart';
import '../obd/obd.dart';

/// Bundled shared contracts (copied by tools/sync_shared.sh).
class AppAssets {
  AppAssets({
    required this.table,
    required this.scenarios,
    required this.kb,
    ModuleRegistry? modules,
    ControllerCatalog? controllers,
    WmiTable? wmi,
    VehicleProfiles? profiles,
  })  : modules = modules ?? ModuleRegistry.empty(),
        controllers = controllers ?? ControllerCatalog.empty(),
        wmi = wmi ?? WmiTable.empty(),
        profiles = profiles ?? VehicleProfiles.empty();

  final PidTable table;
  final List<Scenario> scenarios;
  final LocalKb kb;
  final ModuleRegistry modules;
  final ControllerCatalog controllers;

  /// VIN → brand (WMI).
  final WmiTable wmi;

  /// Vehicle compatibility profiles (pending verification until read on a car).
  final VehicleProfiles profiles;

  Scenario? scenario(String key) {
    for (final s in scenarios) {
      if (s.key == key) return s;
    }
    return null;
  }

  static Future<AppAssets> load(AssetBundle bundle) async {
    final table = PidTable.fromJsonString(await bundle.loadString('assets/shared/obd/pids.json'));
    final index = jsonDecode(await bundle.loadString('assets/shared/scenarios/index.json')) as Map<String, dynamic>;
    final scenarios = <Scenario>[];
    for (final key in (index['scenarios'] as List).cast<String>()) {
      try {
        scenarios.add(Scenario.fromJsonString(await bundle.loadString('assets/shared/scenarios/$key.json')));
      } on Object catch (_) {}
    }
    LocalKb kb;
    try {
      kb = LocalKb.fromJsonString(await bundle.loadString('assets/shared/kb/dtc_definitions.json'));
    } on Object catch (_) {
      kb = LocalKb.empty(); // KB not shipped yet: handled gracefully
    }
    try {
      kb = kb.withOem(await bundle.loadString('assets/shared/kb/dtc_oem.json'));
    } on Object catch (_) {}
    WmiTable wmi;
    try {
      wmi = WmiTable.fromJsonString(await bundle.loadString('assets/shared/obd/wmi.json'));
    } on Object catch (_) {
      wmi = WmiTable.empty();
    }
    VehicleProfiles profiles;
    try {
      profiles = VehicleProfiles.fromJsonString(await bundle.loadString('assets/shared/obd/vehicle_profiles.json'));
    } on Object catch (_) {
      profiles = VehicleProfiles.empty();
    }
    ModuleRegistry modules;
    try {
      modules = ModuleRegistry.fromJsonString(await bundle.loadString('assets/shared/obd/modules.json'));
    } on Object catch (_) {
      modules = ModuleRegistry.empty();
    }
    ControllerCatalog controllers;
    try {
      controllers = ControllerCatalog.fromJsonString(await bundle.loadString('assets/shared/diag/controller_identifiers.json'));
    } on Object catch (_) {
      controllers = ControllerCatalog.empty();
    }
    return AppAssets(table: table, scenarios: scenarios, kb: kb, modules: modules, controllers: controllers, wmi: wmi, profiles: profiles);
  }
}
