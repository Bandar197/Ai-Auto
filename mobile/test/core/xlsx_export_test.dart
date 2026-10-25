import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:automind_app/core/recording/export_service.dart';
import 'package:automind_app/core/recording/xlsx_writer.dart';
import 'package:automind_app/obd/obd.dart';
import 'package:flutter_test/flutter_test.dart';

Recording rec() => Recording(
      recordingId: 'rec-x',
      createdAt: DateTime.utc(2026, 10, 25),
      dataMode: 'demo',
      source: const {'kind': 'simulator', 'protocol_name': 'ISO 15765-4'},
      vehicle: const {'vin': 'KMHEC41CBCA123456', 'make': 'Hyundai'},
      durationMs: 1000,
      signals: [RecordingSignal(key: 'engine_rpm', pid: '010C', unit: 'rpm')],
      samples: [RecordingSample(tMs: 0, pid: '010C', ecu: '7E8', raw: '41 0C 0C 30', values: {'engine_rpm': 780})],
      dtcs: const [Dtc('P0106', DtcStatus.stored, ecu: '7E8')],
      moduleScans: [
        RecordingModuleScan(key: 'srs', nameEn: 'Airbag', nameAr: 'الوسائد الهوائية', outcome: 'refused', address: '7D4', nrc: 0x33),
      ],
      txRxFrames: const [TxRxFrame(tMs: 0, dir: 'tx', data: '0902'), TxRxFrame(tMs: 9, dir: 'rx', data: '49 02 01 4B')],
    );

String sheet(Archive a, int i) => utf8.decode(a.findFile('xl/worksheets/sheet$i.xml')!.content);

void main() {
  test('workbook has the five sheets with Arabic intact, DEMO label and masked VIN', () {
    final bytes = ExportService.sessionXlsx(rec(), maskVin: true, describe: (c) => c == 'P0106' ? 'حساس الضغط' : null);
    final a = ZipDecoder().decodeBytes(bytes);
    expect(utf8.decode(a.findFile('xl/workbook.xml')!.content), allOf(contains('Summary'), contains('TX-RX')));
    final summary = sheet(a, 1);
    expect(summary, contains('DEMO / SIMULATED'));
    expect(summary, contains('KMHEC4*******3456'));
    expect(summary, isNot(contains('KMHEC41CBCA123456')));
    expect(sheet(a, 2), contains('حساس الضغط'));
    expect(sheet(a, 3), contains('الوسائد الهوائية'));
    expect(sheet(a, 3), contains('<v>51</v>')); // NRC 0x33 as a number
    expect(sheet(a, 5), contains('[VIN masked]'));
    // Keep a copy for an external reader check (openpyxl) in CI-less local runs.
    final out = Platform.environment['XLSX_OUT'];
    if (out != null) File(out).writeAsBytesSync(bytes);
  });

  test('special characters are escaped; many columns get AA-style refs', () {
    final bytes = buildXlsx([
      XlsxSheet('A<b>&"c"/d', [
        [for (var i = 0; i < 28; i++) 'h$i'],
        ['<tag> & "q"', 1.5, true, null],
      ], rightToLeft: true),
    ]);
    final a = ZipDecoder().decodeBytes(bytes);
    final s = sheet(a, 1);
    expect(s, contains('&lt;tag&gt; &amp; &quot;q&quot;'));
    expect(s, contains('r="AB1"'));
    expect(s, contains('rightToLeft="1"'));
    expect(utf8.decode(a.findFile('xl/workbook.xml')!.content), contains('name="A&lt;b&gt;&amp;&quot;c&quot; d"'));
  });

  test('evidence ZIP now includes session.xlsx with its SHA-256', () {
    final zip = ExportService.evidenceZip(rec());
    final a = ZipDecoder().decodeBytes(zip);
    expect(a.findFile('session.xlsx'), isNotNull);
    expect(ExportService.verifyEvidenceZip(zip), isEmpty);
  });
}
