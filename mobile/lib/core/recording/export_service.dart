import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';

import '../../obd/obd.dart';

/// recording.v2 — a backward-compatible superset of v1 (shared/schemas/recording.v2.schema.json).
const String recordingV2Format = 'automind.recording.v2';

/// SHA-256 (lower-case hex) of [bytes].
String sha256Hex(List<int> bytes) => sha256.convert(bytes).toString();

/// Optional recorder evidence that goes into a v2 session (all default to empty, so a
/// plain v1 recording still exports cleanly — nothing is invented).
class SessionEvidence {
  const SessionEvidence({
    this.adapterCapabilities,
    this.ecuCoverage = const [],
    this.txRxFrames = const [],
    this.clearOperations = const [],
    this.verification,
    this.warnings = const [],
    this.auditEvents = const [],
    this.sessionState,
    this.beforeAfter,
  });

  final Map<String, dynamic>? adapterCapabilities;
  final List<Map<String, dynamic>> ecuCoverage;
  final List<Map<String, dynamic>> txRxFrames;
  final List<Map<String, dynamic>> clearOperations;
  final Map<String, dynamic>? verification;
  final List<Map<String, dynamic>> warnings;
  final List<Map<String, dynamic>> auditEvents;

  /// 'active' | 'completed' | 'interrupted'.
  final String? sessionState;

  /// Free-form before/after comparison for before_after.json.
  final Map<String, dynamic>? beforeAfter;
}

/// Builds the exports required by the diagnostic recorder: CSV (UTF-8 BOM, opens with
/// Arabic intact in Excel), a v2 session JSON, and an Evidence ZIP with a manifest and a
/// SHA-256 per file. Pure (bytes in, bytes out) so it is fully unit-testable.
class ExportService {
  const ExportService._();

  /// RFC 4180 CSV for Excel: UTF-8 BOM + CRLF, quoting fields with comma/quote/newline.
  static String csv(List<List<Object?>> rows) {
    String cell(Object? v) {
      final s = v?.toString() ?? '';
      return s.contains(RegExp(r'[",\r\n]')) ? '"${s.replaceAll('"', '""')}"' : s;
    }

    return '﻿${rows.map((r) => r.map(cell).join(',')).join('\r\n')}\r\n';
  }

  /// Every code found: standard OBD codes plus module-scan codes, with their source.
  /// [describe] may supply a KB description; unknown codes are left blank, never guessed.
  static String dtcsCsv(Recording r, {String? Function(String code)? describe}) {
    final rows = <List<Object?>>[
      ['code', 'status', 'ecu', 'source', 'description'],
      for (final d in r.dtcs) [d.code, d.status.apiValue, d.ecu ?? '', 'obd', describe?.call(d.code) ?? ''],
      for (final m in r.moduleScans)
        for (final c in m.codes) [c.code, c.status.apiValue, m.address ?? '', 'module:${m.key}', describe?.call(c.code) ?? ''],
    ];
    return csv(rows);
  }

  /// Live data, one row per decoded value, raw bytes kept alongside.
  static String liveDataCsv(Recording r) {
    final units = {for (final s in r.signals) if (s.unit != null) s.key: s.unit!};
    final rows = <List<Object?>>[
      ['t_ms', 'pid', 'ecu', 'signal', 'value', 'unit', 'raw'],
      for (final s in r.samples)
        for (final e in s.values.entries) [s.tMs, s.pid, s.ecu ?? '', e.key, e.value ?? '', units[e.key] ?? '', s.raw ?? ''],
    ];
    return csv(rows);
  }

  /// raw.log — adapter traffic exactly as recorded (TX/RX frames when available, else the
  /// raw bytes kept with each sample).
  static String rawLog(Recording r, {List<Map<String, dynamic>> txRxFrames = const []}) {
    final b = StringBuffer();
    if (txRxFrames.isNotEmpty) {
      for (final f in txRxFrames) {
        b.writeln('${f['t_ms']}\t${(f['dir'] ?? '').toString().toUpperCase()}\t${f['can_id'] ?? ''}\t${f['data'] ?? ''}');
      }
    } else {
      for (final s in r.samples) {
        if (s.raw != null) b.writeln('${s.tMs}\tRX\t${s.ecu ?? ''}\t${s.raw}');
      }
    }
    return b.toString();
  }

  /// The session as recording.v2. VIN is masked only when [maskVin] (for sharing) — the
  /// local original is never altered. data_mode is carried as-is (demo stays demo).
  static Map<String, dynamic> sessionV2(Recording r, {bool maskVin = false, SessionEvidence evidence = const SessionEvidence()}) {
    final j = r.toJson();
    j['format'] = recordingV2Format;
    if (maskVin) {
      final v = Map<String, dynamic>.from(j['vehicle'] as Map? ?? const {});
      final vin = v['vin'] as String?;
      if (vin != null && vin.length >= 10) v['vin'] = '${vin.substring(0, 6)}${'*' * (vin.length - 10)}${vin.substring(vin.length - 4)}';
      j['vehicle'] = v;
    }
    // Explicit evidence wins; otherwise the capabilities probed during capture.
    j['adapter_capabilities'] = evidence.adapterCapabilities ?? r.adapterCapabilities?.toJson();
    j['ecu_coverage'] = evidence.ecuCoverage;
    j['tx_rx_frames'] = evidence.txRxFrames;
    j['clear_operations'] = evidence.clearOperations;
    j['verification'] = evidence.verification;
    j['warnings'] = evidence.warnings;
    j['audit_events'] = evidence.auditEvents;
    j['session_state'] = evidence.sessionState;
    return j;
  }

  /// File name for the bundle; demo bundles are always labelled DEMO.
  static String bundleFileName(Recording r) =>
      'automind_evidence_${r.recordingId}${r.dataMode == 'demo' ? '_DEMO' : ''}.zip';

  /// ZIP Evidence Bundle: manifest.json, session.json (v2), dtcs.csv, live_data.csv,
  /// raw.log, before_after.json and an optional report, each with its SHA-256 in the
  /// manifest (and in session.json's file_hashes for the data files).
  static Uint8List evidenceZip(
    Recording r, {
    bool maskVin = false,
    SessionEvidence evidence = const SessionEvidence(),
    List<int>? reportPdf,
    String? reportHtml,
    String? Function(String code)? describe,
    DateTime? generatedAt,
  }) {
    final files = <String, List<int>>{
      'dtcs.csv': utf8.encode(dtcsCsv(r, describe: describe)),
      'live_data.csv': utf8.encode(liveDataCsv(r)),
      'raw.log': utf8.encode(rawLog(r, txRxFrames: evidence.txRxFrames)),
      'before_after.json': utf8.encode(const JsonEncoder.withIndent(' ').convert(evidence.beforeAfter ?? const {})),
      'report.pdf': ?reportPdf,
      if (reportHtml != null) 'report.html': utf8.encode(reportHtml),
    };
    final dataHashes = {for (final e in files.entries) e.key: sha256Hex(e.value)};
    final session = sessionV2(r, maskVin: maskVin, evidence: evidence)..['file_hashes'] = dataHashes;
    files['session.json'] = utf8.encode(const JsonEncoder.withIndent(' ').convert(session));

    final manifest = {
      'format': 'automind.evidence.v1',
      'recording_format': recordingV2Format,
      'recording_id': r.recordingId,
      'data_mode': r.dataMode,
      'label': r.dataMode == 'demo' ? 'DEMO / SIMULATED' : 'LIVE',
      'created_at': r.createdAt.toUtc().toIso8601String(),
      'generated_at': (generatedAt ?? DateTime.now()).toUtc().toIso8601String(),
      'vin_masked': maskVin,
      'session_state': evidence.sessionState,
      'files': {
        for (final e in files.entries) e.key: {'sha256': sha256Hex(e.value), 'bytes': e.value.length},
      },
    };

    final archive = Archive();
    archive.addFile(ArchiveFile.bytes('manifest.json', utf8.encode(const JsonEncoder.withIndent(' ').convert(manifest))));
    for (final e in files.entries) {
      archive.addFile(ArchiveFile.bytes(e.key, e.value));
    }
    return ZipEncoder().encodeBytes(archive);
  }

  /// Verify an evidence bundle: every file listed in the manifest is present and its
  /// SHA-256 matches. Returns the names of files that fail (empty = intact).
  static List<String> verifyEvidenceZip(List<int> zipBytes) {
    final archive = ZipDecoder().decodeBytes(zipBytes);
    final manifestFile = archive.findFile('manifest.json');
    if (manifestFile == null) return ['manifest.json'];
    final manifest = jsonDecode(utf8.decode(manifestFile.content)) as Map<String, dynamic>;
    final bad = <String>[];
    for (final e in (manifest['files'] as Map<String, dynamic>).entries) {
      final f = archive.findFile(e.key);
      if (f == null || sha256Hex(f.content) != (e.value as Map)['sha256']) bad.add(e.key);
    }
    return bad;
  }
}
