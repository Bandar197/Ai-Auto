import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:uuid/uuid.dart';

import '../../obd/obd.dart';
import '../measured_findings.dart';
import '../storage/scan_report.dart';
import 'export_service.dart';

/// Why an import was refused.
enum ImportError { unreadable, notARecording, tampered }

class ImportException implements Exception {
  const ImportException(this.error, [this.detail]);
  final ImportError error;
  final String? detail;
  @override
  String toString() => 'ImportException($error${detail == null ? '' : ': $detail'})';
}

/// A session read from a file, with its recorded state.
class ImportedSession {
  const ImportedSession(this.recording, {this.sessionState, this.fromEvidence = false});
  final Recording recording;

  /// From a v2 file: 'completed' | 'interrupted' | 'active' (null for v1).
  final String? sessionState;

  /// Came from an evidence ZIP whose SHA-256 manifest checked out.
  final bool fromEvidence;
}

/// Reads a recording.v1 / recording.v2 JSON file or an evidence ZIP. data_mode is
/// kept exactly as recorded (a demo file stays demo). A ZIP whose files don't match
/// their SHA-256 in the manifest is refused as tampered.
ImportedSession importSessionBytes(List<int> bytes, {String? fileName}) {
  final isZip = bytes.length > 4 && bytes[0] == 0x50 && bytes[1] == 0x4B; // "PK"
  if (isZip) {
    final List<String> bad;
    final Archive archive;
    try {
      bad = ExportService.verifyEvidenceZip(bytes);
      archive = ZipDecoder().decodeBytes(bytes);
    } on Object catch (e) {
      throw ImportException(ImportError.unreadable, '$e');
    }
    if (bad.isNotEmpty) throw ImportException(ImportError.tampered, bad.join(', '));
    final session = archive.findFile('session.json');
    if (session == null) throw const ImportException(ImportError.notARecording, 'session.json missing');
    final s = _parse(utf8.decode(session.content));
    return ImportedSession(s.recording, sessionState: s.sessionState, fromEvidence: true);
  }
  final String text;
  try {
    text = utf8.decode(bytes);
  } on Object catch (e) {
    throw ImportException(ImportError.unreadable, '$e');
  }
  return _parse(text);
}

ImportedSession _parse(String text) {
  final Object? data;
  try {
    data = jsonDecode(text.startsWith('﻿') ? text.substring(1) : text);
  } on Object catch (e) {
    throw ImportException(ImportError.unreadable, '$e');
  }
  if (data is! Map) throw const ImportException(ImportError.notARecording);
  final j = data.cast<String, dynamic>();
  final format = j['format'];
  if (format != recordingFormat && format != recordingV2Format) {
    throw ImportException(ImportError.notARecording, '$format');
  }
  final problems = Recording.validateJson({...j, 'format': recordingFormat});
  if (problems.isNotEmpty) throw ImportException(ImportError.notARecording, problems.join(', '));
  try {
    // v2 is a superset of v1: parse the shared part, keep session_state.
    final rec = Recording.fromJson({...j, 'format': recordingFormat});
    return ImportedSession(rec, sessionState: format == recordingV2Format ? j['session_state'] as String? : null);
  } on Object catch (e) {
    throw ImportException(ImportError.notARecording, '$e');
  }
}

/// A local-only History entry for a recording that did not come from a fresh scan
/// on this device (recovered journal or imported file). Never queued for upload.
ScanReport localReportFor(Recording rec, {String? sessionState, String? origin}) => ScanReport(
      id: const Uuid().v4(),
      createdAt: rec.createdAt,
      dataMode: rec.dataMode,
      simulator: rec.source['kind'] == 'simulator',
      scenarioKey: rec.demoScenario,
      recordingId: rec.recordingId,
      vin: rec.vehicle['vin'] as String?,
      protocolName: rec.source['protocol_name'] as String?,
      dtcs: [for (final d in rec.dtcs) d.toJson()],
      freezeFrames: [for (final x in rec.freezeFrames) x.toJson()],
      uploadState: 'local_only',
      sessionState: sessionState,
      origin: origin,
      measured: [
        for (final f in measuredFindings(valuesBySignal(rec.samples), coolantAttempted: rec.samples.isNotEmpty)) f.toJson(),
      ],
    );
