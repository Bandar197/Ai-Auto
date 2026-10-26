import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../obd/obd.dart';
import '../storage/scan_report.dart';

/// Append-only audit of every clear attempt on this device (one JSON object per
/// line, flushed on each write): who asked, when, which modules, the exact command,
/// the ECU's reply, NRCs, the result — and every refusal with its reason. Lines are
/// never edited or removed; exports read from it.
///
/// Event types: clear_requested, clear_blocked, snapshot_saved, consent_given,
/// approval, clear_sent, clear_response, clear_failed, verification, lamp_confirmed.
class ClearAuditLog {
  ClearAuditLog(this.root);
  final Directory root;

  File get file => File('${root.path}/audit/clear_audit.jsonl');
  Future<void> _chain = Future.value();

  Future<void> append(Map<String, dynamic> event) {
    final e = {'t': DateTime.now().toUtc().toIso8601String(), 'actor': 'user', ...event};
    return _chain = _chain.then((_) async {
      await file.parent.create(recursive: true);
      final raf = await file.open(mode: FileMode.append);
      try {
        await raf.writeString('${jsonEncode(e)}\n');
        await raf.flush();
      } finally {
        await raf.close();
      }
    });
  }

  /// All events, oldest first; [reportId] narrows to one scan's clears.
  Future<List<Map<String, dynamic>>> read({String? reportId}) async {
    await _chain;
    if (!await file.exists()) return const [];
    final out = <Map<String, dynamic>>[];
    for (final line in const LineSplitter().convert(await file.readAsString())) {
      if (line.trim().isEmpty) continue;
      try {
        final e = (jsonDecode(line) as Map).cast<String, dynamic>();
        if (reportId == null || e['report_id'] == reportId) out.add(e);
      } on Object catch (_) {}
    }
    return out;
  }

  /// recording.v2 `clear_operations` rebuilt from the audit events (one per operation).
  static List<Map<String, dynamic>> operations(List<Map<String, dynamic>> events) {
    final ops = <String, Map<String, dynamic>>{};
    for (final e in events) {
      final id = e['operation_id'] as String?;
      if (id == null) continue;
      final op = ops.putIfAbsent(id, () => {
            'id': id,
            'requested_at': e['t'],
            'operator': e['actor'],
            'target_modules': <String>[],
            'service': e['service'] ?? '04',
            'request_frames': <String>[],
            'response_frames': <String>[],
            'nrc': null,
            'result': 'verification_pending',
            'context': null,
            'before_snapshot_id': null,
            'after_snapshot_id': null,
          });
      switch (e['type']) {
        case 'clear_requested':
          (op['target_modules'] as List<String>).addAll(<String>[for (final t in (e['targets'] as List? ?? const [])) '$t']);
        case 'snapshot_saved':
          op['before_snapshot_id'] = e['snapshot_id'];
        case 'clear_sent':
          op['service'] = e['service'] ?? op['service'];
          (op['request_frames'] as List<String>).addAll(<String>[for (final f in (e['request_frames'] as List? ?? const [])) '$f']);
        case 'clear_response':
          (op['response_frames'] as List<String>).addAll(<String>[for (final f in (e['response_frames'] as List? ?? const [])) '$f']);
          op['nrc'] = e['nrc'] ?? op['nrc'];
          if (e['result'] != null) op['result'] = e['result'];
          if (e['context'] != null) op['context'] = e['context'];
        case 'clear_blocked':
          op['result'] = 'blocked';
          op['context'] = e['context'];
        case 'clear_failed':
          op['result'] = e['result'] ?? 'comm_failed';
          op['context'] = e['context'] ?? 'comm_failed';
        case 'verification':
          if (e['result'] != null) op['result'] = e['result'];
          if (e['result'] == 'cleared') op['context'] = 'cleared_and_verified';
          op['after_snapshot_id'] = e['after_snapshot_id'] ?? op['after_snapshot_id'];
      }
    }
    return ops.values.toList();
  }
}

/// Saves the permanent pre-clear snapshot (atomic write) and returns its id. It holds
/// everything the clear will erase — codes with status, freeze frame, readiness,
/// vehicle data, module results and the raw ECU replies — and is never deleted, even
/// when the scan itself is later removed from History.
Future<String> savePreClearSnapshot(
  Directory root, {
  required String operationId,
  required ScanReport report,
  Recording? recording,
  required List<String> targets,
}) async {
  final id = 'preclear_$operationId';
  final dir = Directory('${root.path}/snapshots');
  await dir.create(recursive: true);
  bool rawFor(String cmd) {
    final c = cmd.replaceAll(' ', '').toUpperCase();
    return c.startsWith('03') || c.startsWith('07') || c.startsWith('0A') || c.startsWith('02') || c.startsWith('19') ||
        c.startsWith('0101');
  }

  final frames = recording?.txRxFrames ?? const <TxRxFrame>[];
  final raw = <Map<String, dynamic>>[];
  for (var i = 0; i < frames.length; i++) {
    if (frames[i].dir == 'tx' && rawFor(frames[i].data)) {
      raw.add(frames[i].toJson());
      if (i + 1 < frames.length && frames[i + 1].dir == 'rx') raw.add(frames[i + 1].toJson());
    }
  }
  final snap = {
    'format': 'automind.preclear_snapshot.v1',
    'id': id,
    'operation_id': operationId,
    'taken_at': DateTime.now().toUtc().toIso8601String(),
    'scan_taken_at': report.createdAt.toUtc().toIso8601String(),
    'report_id': report.id,
    'recording_id': report.recordingId,
    'data_mode': report.dataMode,
    'targets': targets,
    'vehicle': recording?.vehicle ?? {'vin': report.vin},
    'dtcs': recording != null ? [for (final d in recording.dtcs) d.toJson()] : report.dtcs,
    'freeze_frames': recording != null ? [for (final f in recording.freezeFrames) f.toJson()] : report.freezeFrames,
    'readiness': recording?.readiness,
    'module_scans': [for (final m in recording?.moduleScans ?? const <RecordingModuleScan>[]) m.toJson()],
    'raw_responses': raw,
  };
  final f = File('${dir.path}/$id.json');
  final tmp = File('${f.path}.tmp');
  await tmp.writeAsString(const JsonEncoder.withIndent(' ').convert(snap), flush: true);
  await tmp.rename(f.path);
  return id;
}
