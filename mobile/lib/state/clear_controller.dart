import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../core/api/api_client.dart';
import '../core/api/automind_api.dart';
import '../core/storage/clear_entry.dart';
import '../core/storage/scan_report.dart';
import '../obd/obd.dart';
import 'connection_controller.dart';
import 'providers.dart';
import 'verification_controller.dart';

/// Wait before the immediate re-check in the same key cycle (tests: zero).
final postClearRecheckDelayProvider = Provider<Duration>((ref) => const Duration(seconds: 5));

enum ClearPhase { idle, checking, uploading, requesting, clearing, waiting, rechecking, done }

enum ClearFailure {
  notConnected,
  replay,
  conditionsUnreadable,
  engineRunning,
  moving,
  needsServer,
  uploadFailed,
  rejected,
  policy,
  carDidNotConfirm,
}

class ClearResult {
  ClearResult.ok(this.entry)
      : failure = null,
        detail = null;
  ClearResult.fail(this.failure, [this.detail]) : entry = null;

  final ClearEntry? entry;
  final ClearFailure? failure;
  final String? detail;
  bool get ok => entry != null;
}

/// Clear DTCs and verify. Order matters:
/// 1. the scan to be cleared must already be stored as a server session
///    (codes + freeze frame are kept; the server rejects a live clear without it);
/// 2. server approval, then engine-off / speed-0 from live data, then service 04;
/// 3. a local ClearRecord (before snapshot) is saved;
/// 4. an immediate re-check in the same key cycle gives the first verdict.
class ClearController extends Notifier<ClearPhase> {
  @override
  ClearPhase build() => ClearPhase.idle;

  Future<ClearResult> clearAndVerify(ScanReport report, {required String consentText}) async {
    try {
      return await _run(report, consentText);
    } finally {
      if (state != ClearPhase.done) state = ClearPhase.idle;
    }
  }

  Future<ClearResult> _run(ScanReport report, String consentText) async {
    final conn = ref.read(connectionProvider);
    final client = conn.client;
    if (conn.mode == DataMode.replay) return ClearResult.fail(ClearFailure.replay);
    if (client == null || !conn.ecuReady) return ClearResult.fail(ClearFailure.notConnected);

    state = ClearPhase.checking;
    if (client.supported == null) await client.readSupportedPids();
    Future<double?> read(int pid, String key) async {
      if (!client.supported!.supports(pid)) return null;
      final r = await client.readPid(pid);
      return r.isEmpty ? null : r.first.values[key];
    }

    final rpm = await read(0x0C, 'engine_rpm');
    final speed = await read(0x0D, 'vehicle_speed');
    if (rpm == null || speed == null) return ClearResult.fail(ClearFailure.conditionsUnreadable);
    if (rpm > 0) return ClearResult.fail(ClearFailure.engineRunning, rpm.toStringAsFixed(0));
    if (speed > 0) return ClearResult.fail(ClearFailure.moving, speed.toStringAsFixed(0));

    final api = ref.read(apiProvider);
    final user = ref.read(authProvider).value;
    if (user == null || !await api.isReachable()) return ClearResult.fail(ClearFailure.needsServer);

    // 1. The scan must be saved as a session before anything is erased.
    if (report.serverSessionId == null) {
      state = ClearPhase.uploading;
      try {
        await ref.read(uploadQueueProvider).uploadOne(report);
        final store = ref.read(localStoreProvider);
        await store.writeQueue((await store.readQueue()).where((x) => x != report.id).toList());
      } on ApiException catch (e) {
        return ClearResult.fail(e.isOffline ? ClearFailure.needsServer : ClearFailure.uploadFailed, e.message);
      }
      if (report.serverSessionId == null) return ClearResult.fail(ClearFailure.uploadFailed);
    }

    // 2. Server approval.
    state = ClearPhase.requesting;
    final vehicleId = report.vehicleId ?? ref.read(settingsProvider).selectedVehicleId;
    final serverVehicle = vehicleId != null && !vehicleId.startsWith('local-') ? vehicleId : null;
    Map<String, dynamic> op;
    try {
      op = await api.requestOperation({
        'procedure_key': 'clear_dtcs',
        'vehicle_id': ?serverVehicle,
        'session_id': report.serverSessionId,
        'data_mode': client.dataMode.apiValue,
        'consent_text': consentText,
        'confirmed': true,
        'conditions': {'engine_running': false, 'vehicle_speed_kmh': speed},
      });
    } on ApiException catch (e) {
      return ClearResult.fail(e.isOffline ? ClearFailure.needsServer : ClearFailure.rejected, e.message);
    }
    final approval = ClearDtcApproval(
      operationId: op['id'] as String,
      status: op['status'] as String,
      commands: [for (final c in (op['commands'] as List? ?? const [])) '$c'],
    );
    if (!approval.approvesClear) return ClearResult.fail(ClearFailure.rejected, '${op['reason'] ?? op['status']}');

    // 3. Service 04 (the client re-checks rpm/speed itself).
    state = ClearPhase.clearing;
    ClearDtcOutcome outcome;
    try {
      outcome = await client.clearDtcs(approval);
    } on PolicyViolationException catch (e) {
      await _report(api, approval.operationId, 'failed', const [], const [], {'error': e.message});
      return ClearResult.fail(ClearFailure.policy, e.message);
    }
    final clearedAt = DateTime.now().toUtc();
    await _report(api, approval.operationId, outcome.success ? 'succeeded' : 'failed', outcome.requestFrames, outcome.responseFrames,
        {'error': outcome.error});
    if (!outcome.success) return ClearResult.fail(ClearFailure.carDidNotConfirm, outcome.responseFrames.join(' '));

    // 4. Save the before snapshot locally.
    final recording = report.recordingId == null ? null : await ref.read(localStoreProvider).loadRecording(report.recordingId!);
    final before = recording != null
        ? ScanSnapshot.fromRecording(recording, takenAt: report.createdAt, sessionId: report.serverSessionId)
        : ScanSnapshot(
            takenAt: report.createdAt,
            sessionId: report.serverSessionId,
            dtcs: [for (final d in report.dtcs) SnapshotDtc(d['code'] as String, status: d['status'] as String? ?? 'stored', ecu: d['ecu'] as String?)],
          );
    final dataMode = client.dataMode.apiValue;
    final verify = ref.read(verificationProvider.notifier);
    final entry = await verify.add(ClearEntry(
      id: const Uuid().v4(),
      vehicleKey: vehicleKeyFor(dataMode: dataMode, vehicleId: vehicleId, scenarioKey: conn.scenarioKey, vin: report.vin),
      vehicleId: serverVehicle,
      scenarioKey: conn.scenarioKey,
      sessionId: report.serverSessionId,
      reportId: report.id,
      freezeFrame: report.freezeFrames.isEmpty ? null : report.freezeFrames.first,
      record: ClearRecord(clearedAt: clearedAt, before: before, operationId: approval.operationId, dataMode: dataMode),
    ));

    // 5. Immediate re-check in the same key cycle.
    state = ClearPhase.waiting;
    await Future<void>.delayed(ref.read(postClearRecheckDelayProvider));
    state = ClearPhase.rechecking;
    ClearEntry result = entry;
    try {
      result = await verify.addCheck(entry.id, await client.snapshot());
    } on Object catch (_) {
      result = await verify.evaluate(entry.id);
    }
    state = ClearPhase.done;
    return ClearResult.ok(result);
  }

  Future<void> _report(AutomindApi api, String id, String status, List<String> req, List<String> resp, Map<String, dynamic> result) async {
    try {
      await api.reportOperation(id, {'status': status, 'request_frames': req, 'response_frames': resp, 'result': result});
    } on Object catch (_) {}
  }
}

final clearProvider = NotifierProvider<ClearController, ClearPhase>(ClearController.new);
