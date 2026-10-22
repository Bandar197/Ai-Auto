import 'dart:io' show Platform;

import 'api/api_client.dart';
import 'api/automind_api.dart';
import 'storage/local_store.dart';
import 'storage/scan_report.dart';

/// Persistent offline queue: scans recorded while the phone was on the
/// adapter's Wi-Fi (no internet) are uploaded when the backend is reachable.
/// Each step stores its server id so retries never duplicate sessions.
class UploadQueue {
  UploadQueue(this.store, this.api, {this.appVersion = '1.0.0', this.language = 'ar', this.includeVin = false});

  final LocalStore store;
  final AutomindApi api;
  final String appVersion;
  String language;
  bool includeVin;
  bool _busy = false;

  bool get busy => _busy;

  Future<List<String>> pending() => store.readQueue();

  Future<void> enqueue(String reportId) async {
    final q = await store.readQueue();
    if (!q.contains(reportId)) await store.writeQueue([...q, reportId]);
  }

  /// Uploads everything it can. Returns the number of reports processed.
  Future<int> process() async {
    if (_busy) return 0;
    _busy = true;
    var done = 0;
    try {
      final queue = await store.readQueue();
      if (queue.isEmpty) return 0;
      if (await api.tokens.read() == null) return 0; // needs an account
      if (!await api.isReachable()) return 0;
      final remaining = [...queue];
      for (final id in queue) {
        final report = await store.loadReport(id);
        if (report == null) {
          remaining.remove(id);
          continue;
        }
        try {
          await uploadOne(report);
          remaining.remove(id);
          done++;
        } on ApiException catch (e) {
          report
            ..uploadState = e.isOffline ? 'pending' : 'failed'
            ..lastError = '${e.code}: ${e.message}';
          await store.saveReport(report);
          if (e.isOffline) break;
          // Validation/policy errors will not fix themselves: drop from queue.
          if (e.status != null && e.status! >= 400 && e.status! < 500 && e.status != 401 && e.status != 429) {
            remaining.remove(id);
          }
        }
      }
      await store.writeQueue(remaining);
    } finally {
      _busy = false;
    }
    return done;
  }

  Future<void> uploadOne(ScanReport report) async {
    final recording = report.recordingId == null ? null : await store.loadRecording(report.recordingId!);
    final recJson = recording == null ? null : (includeVin ? recording : recording.redactVin()).toJson();

    if (report.isReplay) {
      // Replays go through the server's replay endpoint so the session is
      // linked to the original recording and keeps data_mode = replay.
      if (report.serverRecordingId == null && recJson != null) {
        final meta = await api.uploadRecording(recJson);
        report.serverRecordingId = meta['id'] as String;
        await store.saveReport(report);
      }
      if (report.serverRecordingId == null) throw ApiException('validation_error', 'no recording to replay');
      final r = await api.replayRecording(report.serverRecordingId!, language: language);
      report
        ..serverSessionId = (r['session'] as Map?)?['id'] as String?
        ..diagnosis = (r['diagnosis'] as Map?)?.cast<String, dynamic>()
        ..uploadState = 'uploaded'
        ..lastError = null;
      await store.saveReport(report);
      return;
    }

    String? connectionId;
    if (report.serverSessionId == null) {
      final log = report.connectionLog;
      if (log != null && log['transport'] != 'demo') {
        try {
          connectionId = await api.postConnection(log);
        } on ApiException catch (e) {
          if (e.isOffline) rethrow; // connection logs are best effort otherwise
        }
      }
      final s = await api.createSession({
        'data_mode': report.dataMode,
        'vehicle_id': ?report.vehicleId,
        'connection_id': ?connectionId,
        'demo_scenario_key': ?report.scenarioKey,
        'protocol_name': ?report.protocolName,
        'app_platform': Platform.isIOS ? 'ios' : 'android',
        'app_version': appVersion,
      });
      report.serverSessionId = s['id'] as String;
      await store.saveReport(report);
    }
    final sid = report.serverSessionId!;
    if (report.dtcs.isNotEmpty) {
      await api.postDtcs(sid, [
        for (final d in report.dtcs)
          {
            'code': d['code'],
            'status': d['status'],
            'source_service': switch (d['status']) { 'pending' => '07', 'permanent' => '0A', _ => '03' },
            'ecu_address': ?d['ecu'],
            if (report.freezeFrames.isNotEmpty && report.freezeFrames.first['dtc'] == d['code'])
              'freeze_frame': report.freezeFrames.first['values'],
          },
      ]);
    }
    if (recJson != null) await api.uploadSessionRecording(sid, recJson);
    final diagnosis = await api.completeSession(sid, milOn: report.milOn, language: language);
    report
      ..diagnosis = diagnosis
      ..uploadState = 'uploaded'
      ..lastError = null;
    await store.saveReport(report);
  }
}
