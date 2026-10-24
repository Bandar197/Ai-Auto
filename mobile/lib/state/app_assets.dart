import 'dart:convert';

import 'package:flutter/services.dart';

import '../core/controller_catalog.dart';
import '../core/kb/local_kb.dart';
import '../core/module_registry.dart';
import '../obd/obd.dart';

/// Bundled shared contracts (copied by tools/sync_shared.sh).
class AppAssets {
  AppAssets({
    required this.table,
    required this.scenarios,
    required this.kb,
    ModuleRegistry? modules,
    ControllerCatalog? controllers,
  })  : modules = modules ?? ModuleRegistry.empty(),
        controllers = controllers ?? ControllerCatalog.empty();

  final PidTable table;
  final List<Scenario> scenarios;
  final LocalKb kb;
  final ModuleRegistry modules;
  final ControllerCatalog controllers;

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
    return AppAssets(table: table, scenarios: scenarios, kb: kb, modules: modules, controllers: controllers);
  }
}
