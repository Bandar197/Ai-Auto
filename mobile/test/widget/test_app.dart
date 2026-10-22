import 'dart:io';

import 'package:automind_app/core/api/token_store.dart';
import 'package:automind_app/core/kb/local_kb.dart';
import 'package:automind_app/core/storage/local_store.dart';
import 'package:automind_app/obd/obd.dart';
import 'package:automind_app/state/app_assets.dart';
import 'package:automind_app/state/providers.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:shared_preferences/shared_preferences.dart';

AppAssets testAssets() {
  final table = PidTable.fromJsonString(File('assets/shared/obd/pids.json').readAsStringSync());
  final scenarios = [
    for (final k in ['healthy', 'p0106_map_sensor'])
      Scenario.fromJsonString(File('assets/shared/scenarios/$k.json').readAsStringSync()),
  ];
  final kbFile = File('assets/shared/kb/dtc_definitions.json');
  return AppAssets(
    table: table,
    scenarios: scenarios,
    kb: kbFile.existsSync() ? LocalKb.fromJsonString(kbFile.readAsStringSync()) : LocalKb.empty(),
  );
}

Future<List<Override>> testOverrides({String locale = 'ar'}) async {
  SharedPreferences.setMockInitialValues({'onboardingDone': true, 'locale': locale});
  final prefs = await SharedPreferences.getInstance();
  final dir = Directory.systemTemp.createTempSync('automind_test');
  return [
    sharedPrefsProvider.overrideWithValue(prefs),
    localStoreProvider.overrideWithValue(LocalStore(dir)),
    appAssetsProvider.overrideWithValue(testAssets()),
    tokenStoreProvider.overrideWithValue(MemoryTokenStore()),
  ];
}
