import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:automind_app/core/recording/export_service.dart';
import 'package:automind_app/core/recording/session_compare.dart';
import 'package:automind_app/core/recording/session_import.dart';
import 'package:automind_app/core/storage/local_store.dart';
import 'package:automind_app/obd/obd.dart';
import 'package:flutter_test/flutter_test.dart';

Recording rec({
  String id = '6f1c2b1e-0000-4000-8000-000000000001',
  String mode = 'live',
  List<Dtc> dtcs = const [],
  List<RecordingModuleScan> modules = const [],
  bool obdRead = true,
}) =>
    Recording(
      recordingId: id,
      createdAt: DateTime.utc(2026, 10, 25),
      dataMode: mode,
      source: const {'kind': 'elm327_ble'},
      durationMs: 0,
      signals: const [],
      samples: const [],
      supportedPids: obdRead ? const {'7E8': ['0100']} : const {},
      dtcs: dtcs,
      moduleScans: modules,
    );

RecordingModuleScan srs(String outcome, [List<String> codes = const []]) => RecordingModuleScan(
      key: 'srs',
      nameEn: 'Airbag',
      nameAr: 'الوسائد',
      outcome: outcome,
      category: 'airbag',
      codes: [for (final c in codes) Dtc(c, DtcStatus.stored)],
    );

void main() {
  group('import', () {
    test('v1 JSON (with UTF-8 BOM) keeps its data_mode', () {
      final s = importSessionBytes(utf8.encode('﻿${rec(mode: 'demo').toJsonString()}'));
      expect(s.recording.dataMode, 'demo');
      expect(s.sessionState, isNull);
      expect(s.fromEvidence, isFalse);
    });

    test('v2 JSON keeps session_state', () {
      final j = ExportService.sessionV2(rec(), evidence: const SessionEvidence(sessionState: 'interrupted'));
      final s = importSessionBytes(utf8.encode(jsonEncode(j)));
      expect(s.sessionState, 'interrupted');
      expect(s.recording.recordingId, '6f1c2b1e-0000-4000-8000-000000000001');
    });

    test('an intact evidence ZIP imports; a modified one is refused as tampered', () {
      final zip = ExportService.evidenceZip(rec(dtcs: const [Dtc('P0106', DtcStatus.stored)]));
      final s = importSessionBytes(zip);
      expect(s.fromEvidence, isTrue);
      expect(s.recording.dtcs.single.code, 'P0106');

      final a = ZipDecoder().decodeBytes(zip);
      final out = Archive();
      for (final f in a.files) {
        final bytes = f.name == 'dtcs.csv' ? utf8.encode('tampered') : f.content;
        out.addFile(ArchiveFile.bytes(f.name, bytes));
      }
      expect(
        () => importSessionBytes(ZipEncoder().encodeBytes(out)),
        throwsA(isA<ImportException>().having((e) => e.error, 'error', ImportError.tampered)),
      );
    });

    test('anything else is refused', () {
      expect(() => importSessionBytes(utf8.encode('{"format":"other"}')),
          throwsA(isA<ImportException>().having((e) => e.error, 'error', ImportError.notARecording)));
      expect(() => importSessionBytes(utf8.encode('not json')),
          throwsA(isA<ImportException>().having((e) => e.error, 'error', ImportError.unreadable)));
    });
  });

  group('compare', () {
    test('new, persisting and resolved OBD codes', () {
      final d = compareSessions(
        rec(dtcs: const [Dtc('P0106', DtcStatus.stored), Dtc('P0300', DtcStatus.stored)]),
        rec(id: 'r2', dtcs: const [Dtc('P0300', DtcStatus.stored), Dtc('P0420', DtcStatus.stored)]),
      );
      expect(d.of(CodeChange.newCode).map((c) => c.code), ['P0420']);
      expect(d.of(CodeChange.persisting).map((c) => c.code), ['P0300']);
      expect(d.of(CodeChange.resolved).map((c) => c.code), ['P0106']);
      expect(d.unverified, isEmpty);
      expect(d.mixedModes, isFalse);
    });

    test('an airbag code is NOT "gone" when the later scan could not read the airbag module', () {
      final d = compareSessions(
        rec(modules: [srs('read_codes', ['B0051'])]),
        rec(id: 'r2', modules: [srs('no_response')]),
      );
      expect(d.of(CodeChange.resolved), isEmpty);
      expect(d.unverified.single.code, 'B0051');
      expect(d.modules.single.before, 'read_codes');
      expect(d.modules.single.after, 'no_response');
    });

    test('the airbag code counts as gone only after a successful read without it', () {
      final d = compareSessions(rec(modules: [srs('read_codes', ['B0051'])]), rec(id: 'r2', modules: [srs('read_no_codes')]));
      expect(d.of(CodeChange.resolved).single.module, 'srs');
    });

    test('later session with no OBD read → old OBD codes unverified; demo vs live flagged', () {
      final d = compareSessions(rec(dtcs: const [Dtc('P0106', DtcStatus.stored)]), rec(id: 'r2', mode: 'demo', obdRead: false));
      expect(d.unverified.single.code, 'P0106');
      expect(d.mixedModes, isTrue);
    });
  });

  group('export folder', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('automind_export'));
    tearDown(() => dir.deleteSync(recursive: true));

    test('writes to the chosen folder', () async {
      final store = LocalStore(dir)..exportDir = '${dir.path}/chosen';
      final f = await store.writeExport('a.json', '{}');
      expect(f.path, '${dir.path}/chosen/a.json');
    });

    test('falls back to the app folder when the chosen one is unusable', () async {
      final blocker = File('${dir.path}/blocker')..writeAsStringSync('x'); // a file, not a folder
      final store = LocalStore(dir)..exportDir = '${blocker.path}/sub';
      final f = await store.writeExportBytes('b.zip', [1, 2, 3]);
      expect(f.parent.path, store.defaultExportDir.path);
      expect(await f.readAsBytes(), [1, 2, 3]);
    });
  });
}
