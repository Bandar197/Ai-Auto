import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/api/api_client.dart';
import '../core/storage/clear_entry.dart';
import '../obd/verify/recurrence.dart';
import 'providers.dart';

/// Clear-and-verify records (newest first). Each later scan of the same
/// vehicle adds a check; the verdict comes from the server when reachable
/// (same algorithm) and from the Dart port of recurrence.py otherwise.
class VerificationController extends AsyncNotifier<List<ClearEntry>> {
  static const String _file = 'clear_records';

  @override
  Future<List<ClearEntry>> build() async {
    final raw = await ref.read(localStoreProvider).readJson(_file);
    final list = <ClearEntry>[];
    for (final x in (raw as List? ?? const [])) {
      try {
        list.add(ClearEntry.fromJson(Map<String, dynamic>.from(x as Map)));
      } on Object catch (_) {}
    }
    list.sort((a, b) => b.record.clearedAt.compareTo(a.record.clearedAt));
    return list;
  }

  Future<List<ClearEntry>> _all() async => state.value ?? await future;

  Future<void> _save(List<ClearEntry> list) async {
    await ref.read(localStoreProvider).writeJson(_file, [for (final e in list) e.toJson()]);
    state = AsyncData([...list]);
  }

  Future<ClearEntry?> byId(String id) async {
    for (final e in await _all()) {
      if (e.id == id) return e;
    }
    return null;
  }

  /// Open verification for this vehicle (and data mode), if any.
  Future<ClearEntry?> openFor(String vehicleKey, String dataMode) async {
    for (final e in await _all()) {
      if (e.open && e.vehicleKey == vehicleKey && e.dataMode == dataMode) return e;
    }
    return null;
  }

  Future<ClearEntry> add(ClearEntry entry) async {
    final list = await _all();
    // A new clear of the same vehicle supersedes the previous verification.
    for (final e in list) {
      if (e.vehicleKey == entry.vehicleKey && e.dataMode == entry.dataMode) e.open = false;
    }
    await _save([entry, ...list]);
    return entry;
  }

  Future<ClearEntry> addCheck(String id, ScanSnapshot snap) async {
    final list = await _all();
    final e = list.firstWhere((x) => x.id == id);
    e.checks.add(snap);
    await _save(list);
    return evaluate(id);
  }

  Future<ClearEntry?> setTargetResults(String id, List<Map<String, dynamic>> results, {String? lampOffBy, DateTime? lampOffAt}) async {
    final list = await _all();
    final e = list.where((x) => x.id == id).firstOrNull;
    if (e == null) return null;
    e
      ..targetResults = results
      ..lampOffBy = lampOffBy ?? e.lampOffBy
      ..lampOffAt = lampOffAt ?? e.lampOffAt;
    await _save(list);
    return e;
  }

  /// Record who confirmed the warning lamp is off ('module_status' or 'user').
  Future<void> setLampOff(String id, {required String by}) async {
    final list = await _all();
    final e = list.where((x) => x.id == id).firstOrNull;
    if (e == null) return;
    e
      ..lampOffBy = by
      ..lampOffAt = DateTime.now().toUtc();
    await _save(list);
  }

  Future<void> close(String id) async {
    final list = await _all();
    for (final e in list) {
      if (e.id == id) e.open = false;
    }
    await _save(list);
  }

  /// Local verdict first (instant, offline), then the server's when reachable.
  Future<ClearEntry> evaluate(String id) async {
    final list = await _all();
    final e = list.firstWhere((x) => x.id == id);
    e
      ..verification = assessAfterClear(e.record, e.checks)
      ..verificationSource = 'local';
    await _save(list);
    final user = ref.read(authProvider).value;
    if (user == null) return e;
    final api = ref.read(apiProvider);
    try {
      Map<String, dynamic>? server;
      if (e.dataMode == 'live' && e.vehicleId != null && !e.vehicleId!.startsWith('local-')) {
        try {
          server = await api.vehicleClearVerification(e.vehicleId!);
        } on ApiException catch (x) {
          if (x.isOffline) rethrow;
          server = null; // 404: the server has no record of this clear yet
        }
        // The server only sees uploaded sessions; quick re-checks stay local.
        if (server != null && ((server['checks_after_clear'] as num?) ?? 0) < e.checks.length) server = null;
      }
      server ??= await api.clearVerification(e.record.toJson(), [for (final c in e.checks) c.toJson()]);
      e
        ..verification = ClearVerification.fromJson(server)
        ..verificationSource = 'server';
      await _save(list);
    } on ApiException catch (_) {
      // offline / server error → keep the local verdict
    } on Object catch (_) {}
    return e;
  }
}

final verificationProvider = AsyncNotifierProvider<VerificationController, List<ClearEntry>>(VerificationController.new);

/// The most recent open verification (Home card).
final openVerificationProvider = Provider<ClearEntry?>((ref) {
  final list = ref.watch(verificationProvider).value ?? const <ClearEntry>[];
  for (final e in list) {
    if (e.open) return e;
  }
  return null;
});
