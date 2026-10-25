import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:automind_app/core/recording/export_service.dart';
import 'package:automind_app/obd/obd.dart';
import 'package:flutter_test/flutter_test.dart';

Recording _rec({String mode = 'live', String? vin = '1HGCM82633A004352'}) => Recording(
      recordingId: 'rec-1',
      createdAt: DateTime.utc(2026, 10, 25, 10),
      dataMode: mode,
      source: const {'kind': 'elm327_ble', 'protocol_name': 'ISO 15765-4 (CAN 11/500)'},
      vehicle: {'make': 'Hyundai', 'model': 'Sonata', 'model_year': 2012, 'vin': vin},
      durationMs: 1000,
      signals: [RecordingSignal(key: 'engine_rpm', pid: '010C', unit: 'rpm')],
      samples: [RecordingSample(tMs: 0, pid: '010C', ecu: '7E8', raw: '41 0C 0C 30', values: {'engine_rpm': 780})],
      dtcs: const [Dtc('P0106', DtcStatus.stored, ecu: '7E8')],
      moduleScans: [
        RecordingModuleScan(key: 'srs', nameEn: 'Airbag', nameAr: 'الإيرباق', outcome: 'read_codes', address: '7D4',
            category: 'airbag', codes: const [Dtc('B1346', DtcStatus.stored)]),
      ],
    );

Map<String, List<int>> _unzip(List<int> bytes) =>
    {for (final f in ZipDecoder().decodeBytes(bytes).files) f.name: f.content};

void main() {
  test('CSV is UTF-8 with BOM, CRLF, RFC4180 quoting, and keeps Arabic', () {
    final out = ExportService.csv([
      ['a', 'b'],
      ['قيمة, مع فاصلة', 'he said "hi"'],
    ]);
    expect(out.startsWith('﻿'), isTrue);
    expect(out, contains('\r\n'));
    expect(out, contains('"قيمة, مع فاصلة"'));
    expect(out, contains('"he said ""hi"""'));
  });

  test('dtcs.csv lists OBD and module codes with their source; unknown descriptions stay blank', () {
    final out = ExportService.dtcsCsv(_rec(), describe: (c) => c == 'P0106' ? 'MAP sensor range' : null);
    expect(out, contains('P0106,stored,7E8,obd,MAP sensor range'));
    expect(out, contains('B1346,stored,7D4,module:srs,')); // no invented description
  });

  test('live_data.csv carries value, unit and raw bytes', () {
    expect(ExportService.liveDataCsv(_rec()), contains('0,010C,7E8,engine_rpm,780.0,rpm,41 0C 0C 30'));
  });

  test('evidence ZIP has all files and every SHA-256 matches the manifest', () {
    final zip = ExportService.evidenceZip(_rec(), reportHtml: '<html>ok</html>');
    final files = _unzip(zip);
    expect(files.keys, containsAll(['manifest.json', 'session.json', 'dtcs.csv', 'live_data.csv', 'raw.log', 'before_after.json', 'report.html']));
    expect(ExportService.verifyEvidenceZip(zip), isEmpty);

    final session = jsonDecode(utf8.decode(files['session.json']!)) as Map<String, dynamic>;
    expect(session['format'], recordingV2Format);
    expect((session['file_hashes'] as Map)['dtcs.csv'], sha256Hex(files['dtcs.csv']!));
    expect(session['module_scans'], isNotEmpty);
  });

  test('a tampered file is detected by verifyEvidenceZip', () {
    final files = _unzip(ExportService.evidenceZip(_rec()));
    final archive = Archive();
    for (final e in files.entries) {
      archive.addFile(ArchiveFile.bytes(e.key, e.key == 'dtcs.csv' ? utf8.encode('tampered') : e.value));
    }
    expect(ExportService.verifyEvidenceZip(ZipEncoder().encodeBytes(archive)), ['dtcs.csv']);
  });

  test('demo sessions are always labelled DEMO and keep data_mode=demo', () {
    final r = _rec(mode: 'demo');
    expect(ExportService.bundleFileName(r), endsWith('_DEMO.zip'));
    final manifest = jsonDecode(utf8.decode(_unzip(ExportService.evidenceZip(r))['manifest.json']!)) as Map;
    expect(manifest['label'], 'DEMO / SIMULATED');
    expect(manifest['data_mode'], 'demo');
  });

  test('VIN is masked only in the shared export, never in the local recording', () {
    final r = _rec();
    final masked = ExportService.sessionV2(r, maskVin: true);
    expect((masked['vehicle'] as Map)['vin'], '1HGCM8*******4352');
    expect(r.vehicle['vin'], '1HGCM82633A004352'); // original untouched
    expect((ExportService.sessionV2(r)['vehicle'] as Map)['vin'], '1HGCM82633A004352');
  });

  test('raw.log prefers recorded TX/RX frames when available', () {
    final log = ExportService.rawLog(_rec(), txRxFrames: const [
      {'t_ms': 5, 'dir': 'tx', 'can_id': '7D4', 'data': '19 02 FF'},
      {'t_ms': 40, 'dir': 'rx', 'can_id': '7DC', 'data': '7F 19 11'},
    ]);
    expect(log, contains('5\tTX\t7D4\t19 02 FF'));
    expect(log, contains('40\tRX\t7DC\t7F 19 11'));
  });
}
