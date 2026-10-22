import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/api/api_client.dart';
import '../core/api/automind_api.dart';
import '../core/api/token_store.dart';
import '../core/settings.dart';
import '../core/storage/local_store.dart';
import '../core/storage/scan_report.dart';
import '../core/upload_queue.dart';
import 'app_assets.dart';

const String appVersion = '1.0.0';

/// Overridden in main() / tests.
final sharedPrefsProvider = Provider<SharedPreferences>((ref) => throw UnimplementedError('override in main'));
final localStoreProvider = Provider<LocalStore>((ref) => throw UnimplementedError('override in main'));
final appAssetsProvider = Provider<AppAssets>((ref) => throw UnimplementedError('override in main'));
final tokenStoreProvider = Provider<TokenStore>((ref) => SecureTokenStore());

class SettingsNotifier extends Notifier<AppSettings> {
  @override
  AppSettings build() => AppSettings.load(ref.watch(sharedPrefsProvider));

  Future<void> change(AppSettings Function(AppSettings s) f) async {
    state = f(state);
    await state.save(ref.read(sharedPrefsProvider));
  }
}

final settingsProvider = NotifierProvider<SettingsNotifier, AppSettings>(SettingsNotifier.new);

final apiProvider = Provider<AutomindApi>((ref) {
  final url = ref.watch(settingsProvider.select((s) => s.backendUrl));
  final tokens = ref.watch(tokenStoreProvider);
  return AutomindApi(buildDio(url, tokens), tokens);
});

/// Logged-in user (null = anonymous/offline use). Cached for offline starts.
class AuthNotifier extends AsyncNotifier<Map<String, dynamic>?> {
  @override
  Future<Map<String, dynamic>?> build() async {
    final store = ref.read(localStoreProvider);
    final tokens = await ref.read(tokenStoreProvider).read();
    if (tokens == null) return null;
    try {
      final me = await ref.read(apiProvider).me();
      await store.writeJson('user', me);
      return me;
    } on ApiException catch (e) {
      if (e.status == 401) return null;
      final cached = await store.readJson('user');
      return cached is Map<String, dynamic> ? cached : {'email': ''};
    }
  }

  Future<void> login(String email, String password, {String? totp}) async {
    final user = await ref.read(apiProvider).login(email: email, password: password, totp: totp);
    await ref.read(localStoreProvider).writeJson('user', user);
    state = AsyncData(user);
  }

  Future<void> register(String email, String password, String? name) async {
    final locale = ref.read(settingsProvider).locale;
    final user = await ref.read(apiProvider).register(email: email, password: password, fullName: name, locale: locale);
    await ref.read(localStoreProvider).writeJson('user', user);
    state = AsyncData(user);
  }

  Future<void> logout() async {
    await ref.read(apiProvider).logout();
    await ref.read(localStoreProvider).writeJson('user', null);
    state = const AsyncData(null);
  }
}

final authProvider = AsyncNotifierProvider<AuthNotifier, Map<String, dynamic>?>(AuthNotifier.new);

final uploadQueueProvider = Provider<UploadQueue>((ref) {
  final s = ref.watch(settingsProvider);
  return UploadQueue(ref.watch(localStoreProvider), ref.watch(apiProvider),
      appVersion: appVersion, language: s.locale, includeVin: s.includeVin);
});

/// Local scan history (newest first).
class ReportsNotifier extends AsyncNotifier<List<ScanReport>> {
  @override
  Future<List<ScanReport>> build() => ref.read(localStoreProvider).listReports();

  Future<void> refresh() async => state = AsyncData(await ref.read(localStoreProvider).listReports());
}

final reportsProvider = AsyncNotifierProvider<ReportsNotifier, List<ScanReport>>(ReportsNotifier.new);

final reportProvider = FutureProvider.family<ScanReport?, String>((ref, id) => ref.watch(localStoreProvider).loadReport(id));

/// Number of scans waiting for upload; [sync] processes the queue.
class PendingUploadsNotifier extends AsyncNotifier<int> {
  @override
  Future<int> build() async => (await ref.read(localStoreProvider).readQueue()).length;

  Future<int> sync() async {
    final n = await ref.read(uploadQueueProvider).process();
    state = AsyncData((await ref.read(localStoreProvider).readQueue()).length);
    if (n > 0) await ref.read(reportsProvider.notifier).refresh();
    return n;
  }

  Future<void> refresh() async => state = AsyncData((await ref.read(localStoreProvider).readQueue()).length);
}

final pendingUploadsProvider = AsyncNotifierProvider<PendingUploadsNotifier, int>(PendingUploadsNotifier.new);

/// Vehicles: server list when logged in, otherwise local-only entries.
class VehiclesNotifier extends AsyncNotifier<List<Map<String, dynamic>>> {
  @override
  Future<List<Map<String, dynamic>>> build() async {
    final user = await ref.watch(authProvider.future);
    final store = ref.read(localStoreProvider);
    final local = ((await store.readJson('vehicles')) as List? ?? const []).cast<Map<String, dynamic>>();
    if (user == null) return local;
    try {
      final remote = await ref.read(apiProvider).vehicles();
      await store.writeJson('vehicles', remote);
      return remote;
    } on ApiException catch (_) {
      return local;
    }
  }

  Future<void> save(Map<String, dynamic> body, {String? id}) async {
    final store = ref.read(localStoreProvider);
    final user = ref.read(authProvider).value;
    final list = [...(state.value ?? const <Map<String, dynamic>>[])];
    if (user != null) {
      final api = ref.read(apiProvider);
      final v = id == null || id.startsWith('local-') ? await api.createVehicle(body) : await api.updateVehicle(id, body);
      list.removeWhere((x) => x['id'] == id || x['id'] == v['id']);
      list.insert(0, v);
    } else {
      final v = {...body, 'id': id ?? 'local-${DateTime.now().microsecondsSinceEpoch}', 'created_at': DateTime.now().toUtc().toIso8601String()};
      list.removeWhere((x) => x['id'] == v['id']);
      list.insert(0, v);
    }
    await store.writeJson('vehicles', list);
    state = AsyncData(list);
  }

  Future<void> remove(String id) async {
    final user = ref.read(authProvider).value;
    if (user != null && !id.startsWith('local-')) await ref.read(apiProvider).deleteVehicle(id);
    final list = [...(state.value ?? const <Map<String, dynamic>>[])]..removeWhere((x) => x['id'] == id);
    await ref.read(localStoreProvider).writeJson('vehicles', list);
    state = AsyncData(list);
  }
}

final vehiclesProvider = AsyncNotifierProvider<VehiclesNotifier, List<Map<String, dynamic>>>(VehiclesNotifier.new);

final selectedVehicleProvider = Provider<Map<String, dynamic>?>((ref) {
  final id = ref.watch(settingsProvider.select((s) => s.selectedVehicleId));
  final list = ref.watch(vehiclesProvider).value ?? const [];
  if (list.isEmpty) return null;
  for (final v in list) {
    if (v['id'] == id) return v;
  }
  return list.first;
});

/// Maintenance records per vehicle (server when possible, local cache).
final maintenanceProvider = FutureProvider.family<List<Map<String, dynamic>>, String>((ref, vehicleId) async {
  final store = ref.read(localStoreProvider);
  final key = 'maintenance_$vehicleId';
  final local = ((await store.readJson(key)) as List? ?? const []).cast<Map<String, dynamic>>();
  final user = await ref.watch(authProvider.future);
  if (user == null || vehicleId.startsWith('local-')) return local;
  try {
    final remote = await ref.read(apiProvider).maintenance(vehicleId);
    await store.writeJson(key, remote);
    return remote;
  } on ApiException catch (_) {
    return local;
  }
});

Future<void> addMaintenanceRecord(WidgetRef ref, String vehicleId, Map<String, dynamic> body) async {
  final store = ref.read(localStoreProvider);
  final key = 'maintenance_$vehicleId';
  final local = ((await store.readJson(key)) as List? ?? const []).cast<Map<String, dynamic>>();
  Map<String, dynamic> rec = {...body, 'id': 'local-${DateTime.now().microsecondsSinceEpoch}'};
  final user = ref.read(authProvider).value;
  if (user != null && !vehicleId.startsWith('local-')) {
    rec = await ref.read(apiProvider).addMaintenance(vehicleId, body);
  }
  await store.writeJson(key, [rec, ...local]);
  ref.invalidate(maintenanceProvider(vehicleId));
}
