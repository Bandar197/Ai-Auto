import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'core/settings.dart';
import 'core/storage/local_store.dart';
import 'state/app_assets.dart';
import 'state/providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  final dir = await getApplicationDocumentsDirectory();
  final assets = await AppAssets.load(rootBundle);
  runApp(
    ProviderScope(
      // Network failures are handled explicitly (offline queue); no auto-retry.
      retry: (_, _) => null,
      overrides: [
        sharedPrefsProvider.overrideWithValue(prefs),
        localStoreProvider.overrideWithValue(LocalStore(dir)..exportDir = AppSettings.load(prefs).exportDir),
        appAssetsProvider.overrideWithValue(assets),
      ],
      child: const AutoMindApp(),
    ),
  );
}
