import 'dart:convert';

import 'package:flutter/services.dart';

import '../core/kb/local_kb.dart';
import '../obd/obd.dart';

/// Bundled shared contracts (copied by tools/sync_shared.sh).
class AppAssets {
  AppAssets({required this.table, required this.scenarios, required this.kb});

  final PidTable table;
  final List<Scenario> scenarios;
  final LocalKb kb;

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
    return AppAssets(table: table, scenarios: scenarios, kb: kb);
  }
}
