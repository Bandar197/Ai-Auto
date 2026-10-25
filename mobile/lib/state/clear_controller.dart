import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../core/api/api_client.dart';
import '../core/api/automind_api.dart';
import '../core/clear/clear_audit.dart';
import '../core/clear/clear_planner.dart';
import '../core/storage/clear_entry.dart';
import '../core/storage/scan_report.dart';
import '../obd/obd.dart';
import 'connection_controller.dart';
import 'providers.dart';
import 'verification_controller.dart';

/// Wait before the immediate re-check in the same key cycle (tests: zero).
final postClearRecheckDelayProvider = Provider<Duration>((ref) => const Duration(seconds: 5));

/// Append-only clear audit log on this device.
final clearAuditProvider = Provider<ClearAuditLog>((ref) => ClearAuditLog(ref.watch(localStoreProvider).root));

enum ClearPhase { idle, checking, snapshot, uploading, requesting, clearing, waiting, rechecking, done }

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
  snapshotFailed,
  nothingClearable,
}

/// Outcome per target: result is one of cleared | still_active | read_failed |
/// verification_pending | refused | comm_failed | blocked (recording.v2 wire values).
class TargetResult {
  const TargetResult({required this.key, required this.service, required this.result, this.nrc, this.codes = const {}, this.responseFrames = const []});
  final String key;
  final String service;
  final String result;
  final String? nrc;

  /// code → cleared | still_active | read_failed | verification_pending
  final Map<String, String> codes;
  final List<String> responseFrames;

  Map<String, dynamic> toJson() => {
        'key': key,
        'service': service,
        'result': result,
        'nrc': ?nrc,
        'codes': codes,
        if (responseFrames.isNotEmpty) 'response_frames': responseFrames,
      };
}

class ClearResult {
  ClearResult.ok(this.entry, {this.results = const [], this.operationId})
      : failure = null,
        detail = null;
  ClearResult.fail(this.failure, [this.detail, this.results = const []])
      : entry = null,
        operationId = null;

  /// Verification entry for the engine clear (null when only modules were cleared).
  final ClearEntry? entry;
  final ClearFailure? failure;
  final String? detail;
  final List<TargetResult> results;
  final String? operationId;
  bool get ok => failure == null;
}

/// Clear DTCs and verify — honestly and with a full trail:
/// 1. link + engine-off / speed-0 checks (refusals are audited too);
/// 2. a permanent pre-clear snapshot is written BEFORE anything is sent;
/// 3. approval: the server's when signed in and reachable (the scan is uploaded
///    first); otherwise, for the engine (service 04) only, a local approval recorded
///    in the on-device audit log — offline-first. Module clears (UDS 0x14) always
///    need the server allowlist;
/// 4. the command, the ECU's reply and any NRC are logged; a positive reply alone is
///    never "cleared" — the codes are re-read in the same session;
/// 5. per code: cleared / still active / read failed / verification pending.
class ClearController extends Notifier<ClearPhase> {
  @override
  ClearPhase build() => ClearPhase.idle;

  /// Engine-only clear (service 04) of [report] — kept for existing callers.
  Future<ClearResult> clearAndVerify(ScanReport report, {required String consentText}) {
    final conn = ref.read(connectionProvider);
    final plan = planClear(
      recording: null,
      reportDtcs: report.dtcs,
      connected: conn.client != null && conn.ecuReady,
      replay: conn.mode == DataMode.replay,
    );
    return clearTargets(report, plan.targets.where((t) => t.key == 'engine').toList(), consentText: consentText);
  }

  Future<ClearResult> clearTargets(ScanReport report, List<ClearTarget> targets, {required String consentText}) async {
    try {
      return await _run(report, targets, consentText);
    } finally {
      if (state != ClearPhase.done) state = ClearPhase.idle;
    }
  }

  Future<ClearResult> _run(ScanReport report, List<ClearTarget> targets, String consentText) async {
    final audit = ref.read(clearAuditProvider);
    final opId = const Uuid().v4();
    Future<void> log(String type, [Map<String, dynamic> extra = const {}]) =>
        audit.append({'type': type, 'operation_id': opId, 'report_id': report.id, 'data_mode': report.dataMode, ...extra});
    Future<ClearResult> refuse(ClearFailure f, String context, [String? detail]) async {
      await log('clear_blocked', {'context': context, 'reason': f.name, 'detail': ?detail, 'targets': [for (final t in targets) t.key]});
      return ClearResult.fail(f, detail);
    }

    final conn = ref.read(connectionProvider);
    final client = conn.client;
    if (conn.mode == DataMode.replay) return refuse(ClearFailure.replay, 'comm_failed');
    if (client == null || !conn.ecuReady) return refuse(ClearFailure.notConnected, 'comm_failed');

    final chosen = targets.where((t) => t.clearable).toList();
    for (final t in targets.where((t) => !t.clearable)) {
      await log('clear_blocked', {'targets': [t.key], 'context': t.context.wire, 'reason': t.reason?.wire});
    }
    if (chosen.isEmpty) return ClearResult.fail(ClearFailure.nothingClearable);
    final engine = chosen.where((t) => t.service == '04').firstOrNull;
    final modules = chosen.where((t) => t.service == '14' && t.module != null).toList();

    state = ClearPhase.checking;
    if (client.supported == null) await client.readSupportedPids();
    Future<double?> read(int pid, String key) async {
      if (!client.supported!.supports(pid)) return null;
      final r = await client.readPid(pid);
      return r.isEmpty ? null : r.first.values[key];
    }

    final rpm = await read(0x0C, 'engine_rpm');
    final speed = await read(0x0D, 'vehicle_speed');
    if (rpm == null || speed == null) return refuse(ClearFailure.conditionsUnreadable, 'comm_failed');
    if (rpm > 0) return refuse(ClearFailure.engineRunning, 'allowed', rpm.toStringAsFixed(0));
    if (speed > 0) return refuse(ClearFailure.moving, 'allowed', speed.toStringAsFixed(0));

    await log('clear_requested', {
      'targets': [for (final t in chosen) t.key],
      'services': [for (final t in chosen) t.service],
      'codes': {for (final t in chosen) t.key: t.codes},
    });
    await log('consent_given', {'consent_text': consentText});

    // Permanent pre-clear snapshot — nothing is sent unless it is safely on disk.
    state = ClearPhase.snapshot;
    final store = ref.read(localStoreProvider);
    final recording = report.recordingId == null ? null : await store.loadRecording(report.recordingId!);
    String snapshotId;
    try {
      snapshotId = await savePreClearSnapshot(store.root,
          operationId: opId, report: report, recording: recording, targets: [for (final t in chosen) t.key]);
    } on Object catch (e) {
      await log('clear_failed', {'result': 'blocked', 'context': 'comm_failed', 'detail': 'snapshot: $e'});
      return ClearResult.fail(ClearFailure.snapshotFailed, '$e');
    }
    await log('snapshot_saved', {'snapshot_id': snapshotId});

    final api = ref.read(apiProvider);
    final user = ref.read(authProvider).value;
    final online = user != null && await api.isReachable();

    // Server path: the scan must be stored as a session before anything is erased.
    if (online && report.serverSessionId == null) {
      state = ClearPhase.uploading;
      try {
        await ref.read(uploadQueueProvider).uploadOne(report);
        await store.writeQueue((await store.readQueue()).where((x) => x != report.id).toList());
      } on ApiException catch (e) {
        await log('clear_failed', {'result': 'blocked', 'context': 'comm_failed', 'detail': 'upload: ${e.message}'});
        return ClearResult.fail(e.isOffline ? ClearFailure.needsServer : ClearFailure.uploadFailed, e.message);
      }
      if (report.serverSessionId == null) return ClearResult.fail(ClearFailure.uploadFailed);
    }

    final vehicleId = report.vehicleId ?? ref.read(settingsProvider).selectedVehicleId;
    final serverVehicle = vehicleId != null && !vehicleId.startsWith('local-') ? vehicleId : null;
    final results = <TargetResult>[];
    ClearEntry? entry;

    // ---------------- Engine: OBD-II service 04 ----------------
    if (engine != null) {
      state = ClearPhase.requesting;
      ClearDtcApproval approval;
      if (online) {
        try {
          final op = await api.requestOperation({
            'procedure_key': 'clear_dtcs',
            'vehicle_id': ?serverVehicle,
            'session_id': report.serverSessionId,
            'data_mode': client.dataMode.apiValue,
            'consent_text': consentText,
            'confirmed': true,
            'conditions': {'engine_running': false, 'vehicle_speed_kmh': speed},
          });
          approval = ClearDtcApproval(
            operationId: op['id'] as String,
            status: op['status'] as String,
            commands: [for (final c in (op['commands'] as List? ?? const [])) '$c'],
          );
          if (!approval.approvesClear) {
            await log('approval', {'source': 'server', 'approved': false, 'server_operation_id': op['id'], 'detail': '${op['reason'] ?? op['status']}'});
            return ClearResult.fail(ClearFailure.rejected, '${op['reason'] ?? op['status']}');
          }
        } on ApiException catch (e) {
          await log('approval', {'source': 'server', 'approved': false, 'detail': e.message});
          return ClearResult.fail(e.isOffline ? ClearFailure.needsServer : ClearFailure.rejected, e.message);
        }
        await log('approval', {'source': 'server', 'approved': true, 'server_operation_id': approval.operationId});
      } else {
        // Offline-first: the user's explicit consent + this audit log are the record.
        approval = ClearDtcApproval(operationId: 'local-$opId', status: 'approved', commands: const ['04']);
        await log('approval', {'source': 'local', 'approved': true});
      }

      state = ClearPhase.clearing;
      await log('clear_sent', {'targets': ['engine'], 'service': '04', 'request_frames': ['04']});
      ClearDtcOutcome outcome;
      try {
        outcome = await client.clearDtcs(approval);
      } on PolicyViolationException catch (e) {
        await log('clear_failed', {'result': 'blocked', 'context': 'allowed', 'detail': e.message});
        if (online) await _report(api, approval.operationId, 'failed', const [], const [], {'error': e.message});
        return ClearResult.fail(ClearFailure.policy, e.message);
      }
      final clearedAt = DateTime.now().toUtc();
      await log('clear_response', {
        'targets': ['engine'],
        'service': '04',
        'response_frames': outcome.responseFrames,
        'positive': outcome.success,
        if (!outcome.success) 'result': 'comm_failed',
      });
      if (online) {
        await _report(api, approval.operationId, outcome.success ? 'succeeded' : 'failed', outcome.requestFrames, outcome.responseFrames,
            {'error': outcome.error});
      }
      if (!outcome.success) {
        results.add(TargetResult(key: 'engine', service: '04', result: 'comm_failed', responseFrames: outcome.responseFrames));
        return ClearResult.fail(ClearFailure.carDidNotConfirm, outcome.responseFrames.join(' '), results);
      }

      final before = recording != null
          ? ScanSnapshot.fromRecording(recording, takenAt: report.createdAt, sessionId: report.serverSessionId)
          : ScanSnapshot(
              takenAt: report.createdAt,
              sessionId: report.serverSessionId,
              dtcs: [
                for (final d in report.dtcs) SnapshotDtc(d['code'] as String, status: d['status'] as String? ?? 'stored', ecu: d['ecu'] as String?),
              ],
            );
      final dataMode = client.dataMode.apiValue;
      final verify = ref.read(verificationProvider.notifier);
      entry = await verify.add(ClearEntry(
        id: const Uuid().v4(),
        vehicleKey: vehicleKeyFor(dataMode: dataMode, vehicleId: vehicleId, scenarioKey: conn.scenarioKey, vin: report.vin),
        vehicleId: serverVehicle,
        scenarioKey: conn.scenarioKey,
        sessionId: report.serverSessionId,
        reportId: report.id,
        freezeFrame: report.freezeFrames.isEmpty ? null : report.freezeFrames.first,
        record: ClearRecord(clearedAt: clearedAt, before: before, operationId: approval.operationId, dataMode: dataMode),
        snapshotId: snapshotId,
      ));

      // Immediate re-check in the same key cycle.
      state = ClearPhase.waiting;
      await Future<void>.delayed(ref.read(postClearRecheckDelayProvider));
      state = ClearPhase.rechecking;
      ScanSnapshot? after;
      final entryId = entry.id;
      try {
        after = await client.snapshot();
        entry = await verify.addCheck(entryId, after);
      } on Object catch (_) {
        entry = await verify.evaluate(entryId);
      }
      final codes = <String, String>{};
      for (final c in engine.codes) {
        final statuses = {for (final d in after?.dtcs ?? const <SnapshotDtc>[]) if (d.code == c) d.status};
        if (after == null || after.readOk == false) {
          codes[c] = 'read_failed';
        } else if (statuses.contains('stored') || statuses.contains('pending')) {
          codes[c] = 'still_active';
        } else if (statuses.contains('permanent')) {
          // Service 04 never erases permanent codes; they go once the monitor passes.
          codes[c] = 'verification_pending';
        } else {
          codes[c] = 'cleared';
        }
      }
      final engineResult = ['read_failed', 'still_active', 'verification_pending'].firstWhere(
        codes.values.contains,
        orElse: () => 'cleared',
      );
      results.add(TargetResult(key: 'engine', service: '04', result: engineResult, codes: codes, responseFrames: outcome.responseFrames));
      // The engine lamp counts as OFF only when the car itself reports MIL off.
      if (after?.readOk == true && after?.readiness?['mil_on'] == false) {
        entry
          ..lampOffBy = 'module_status'
          ..lampOffAt = DateTime.now().toUtc();
        await log('lamp_confirmed', {'targets': ['engine'], 'by': 'module_status'});
      }
      await log('verification', {'targets': ['engine'], 'result': engineResult, 'per_code': codes});
    }

    // ---------------- Modules: UDS 0x14 (server allowlist only) ----------------
    for (final t in modules) {
      if (!online) {
        await log('clear_blocked', {'targets': [t.key], 'context': 'requires_oem_authorization', 'reason': 'needs_server_allowlist'});
        results.add(TargetResult(key: t.key, service: '14', result: 'blocked'));
        continue;
      }
      state = ClearPhase.requesting;
      ModuleClearApproval approval;
      try {
        final op = await api.requestOperation({
          'procedure_key': kSafetyClearProcedure[t.category] ?? kModuleClearProcedure,
          'vehicle_id': ?serverVehicle,
          'session_id': report.serverSessionId,
          'data_mode': client.dataMode.apiValue,
          'consent_text': consentText,
          'confirmed': true,
          'modules': [t.key],
          'conditions': {'engine_running': false, 'vehicle_speed_kmh': speed},
        });
        approval = ModuleClearApproval(
          operationId: op['id'] as String,
          status: op['status'] as String,
          commands: [for (final c in (op['commands'] as List? ?? const [])) '$c'],
        );
      } on ApiException catch (e) {
        await log('approval', {'targets': [t.key], 'source': 'server', 'approved': false, 'detail': e.message});
        results.add(TargetResult(key: t.key, service: '14', result: 'blocked'));
        continue;
      }
      if (!approval.approves(t.key)) {
        await log('approval', {'targets': [t.key], 'source': 'server', 'approved': false, 'server_operation_id': approval.operationId});
        results.add(TargetResult(key: t.key, service: '14', result: 'blocked'));
        continue;
      }
      await log('approval', {'targets': [t.key], 'source': 'server', 'approved': true, 'server_operation_id': approval.operationId});
      state = ClearPhase.clearing;
      await log('clear_sent', {'targets': [t.key], 'service': '14', 'request_frames': [buildClearRequest()]});
      ModuleClearOutcome out;
      try {
        out = await client.clearModuleDtcs(t.module!, approval);
      } on PolicyViolationException catch (e) {
        await log('clear_failed', {'targets': [t.key], 'result': 'blocked', 'detail': e.message});
        results.add(TargetResult(key: t.key, service: '14', result: 'blocked'));
        continue;
      }
      final nrc = out.reply.nrc == null ? null : '0x${hex2(out.reply.nrc!)} ${out.reply.nrcName}';
      final codes = <String, String>{};
      String result;
      if (!out.reply.positive) {
        result = out.reply.nrc != null ? 'refused' : 'comm_failed';
      } else if (out.after == null) {
        result = 'verification_pending';
        for (final c in t.codes) {
          codes[c] = 'verification_pending';
        }
      } else {
        for (final c in t.codes) {
          codes[c] = out.after!.dtcs.any((d) => d.code == c) ? 'still_active' : 'cleared';
        }
        result = codes.values.contains('still_active') ? 'still_active' : 'cleared';
      }
      await log('clear_response', {
        'targets': [t.key],
        'service': '14',
        'response_frames': [out.reply.responseRaw],
        'nrc': ?nrc,
        'positive': out.reply.positive,
        'result': result,
      });
      await _report(api, approval.operationId, out.reply.positive ? 'succeeded' : 'failed', [out.reply.request], [out.reply.responseRaw], {'nrc': nrc});
      await log('verification', {'targets': [t.key], 'result': result, 'per_code': codes});
      results.add(TargetResult(key: t.key, service: '14', result: result, nrc: nrc, codes: codes, responseFrames: [out.reply.responseRaw]));
    }

    if (entry != null) {
      final saved = await ref.read(verificationProvider.notifier).setTargetResults(entry.id, [for (final r in results) r.toJson()],
          lampOffBy: entry.lampOffBy, lampOffAt: entry.lampOffAt);
      entry = saved ?? entry;
    }
    state = ClearPhase.done;
    return ClearResult.ok(entry, results: results, operationId: opId);
  }

  /// The user looked at the dashboard and confirms the lamp is OFF (audited).
  Future<void> confirmLampOff(ClearEntry entry) async {
    await ref.read(verificationProvider.notifier).setLampOff(entry.id, by: 'user');
    await ref.read(clearAuditProvider).append({
      'type': 'lamp_confirmed',
      'operation_id': entry.auditOperationId,
      'report_id': entry.reportId,
      'by': 'user',
    });
  }

  Future<void> _report(AutomindApi api, String id, String status, List<String> req, List<String> resp, Map<String, dynamic> result) async {
    try {
      await api.reportOperation(id, {'status': status, 'request_frames': req, 'response_frames': resp, 'result': result});
    } on Object catch (_) {}
  }
}

final clearProvider = NotifierProvider<ClearController, ClearPhase>(ClearController.new);
