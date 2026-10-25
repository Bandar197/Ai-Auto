import 'dart:io';
import 'dart:typed_data';

import 'package:automind_app/core/recording/report_pdf.dart';
import 'package:automind_app/core/storage/clear_entry.dart';
import 'package:automind_app/core/storage/scan_report.dart';
import 'package:automind_app/obd/obd.dart';
import 'package:flutter_test/flutter_test.dart';

ByteData font(String n) => ByteData.sublistView(File('assets/fonts/IBMPlexSansArabic-$n.ttf').readAsBytesSync());

void main() {
  final rec = Recording(
    recordingId: 'r', createdAt: DateTime.utc(2026, 10, 25), dataMode: 'demo', source: const {'kind': 'simulator', 'protocol_name': 'ISO 15765-4'},
    durationMs: 0, signals: const [], samples: const [],
    vehicle: const {'make': 'Hyundai', 'model': 'Sonata', 'model_year': 2012, 'vin': 'KMHEC41CBCA123456'},
    ecus: const ['7E8'],
    dtcs: const [Dtc('P0106', DtcStatus.stored, ecu: '7E8'), Dtc('P0420', DtcStatus.stored, ecu: '7E8')],
    moduleScans: [
      RecordingModuleScan(key: 'srs', nameEn: 'Airbag', nameAr: 'الوسائد الهوائية', outcome: 'no_response', category: 'airbag'),
      RecordingModuleScan(key: 'abs', nameEn: 'ABS', nameAr: 'الفرامل', outcome: 'refused', nrc: 0x33, category: 'abs'),
    ],
  );
  final report = ScanReport(id: 'rep', createdAt: DateTime.utc(2026, 10, 25), dataMode: 'demo', recordingId: 'r');
  final clear = ClearEntry(
    id: 'c', vehicleKey: 'demo:x',
    record: ClearRecord(clearedAt: DateTime.utc(2026, 10, 25, 1), before: ScanSnapshot(takenAt: DateTime.utc(2026)), dataMode: 'demo'),
    targetResults: [
      {'key': 'engine', 'service': '04', 'result': 'still_active', 'codes': {'P0106': 'cleared', 'P0420': 'still_active'}},
    ],
  );

  for (final lang in ['ar', 'en']) {
    test('builds a valid PDF in $lang', () async {
      final bytes = await buildReportPdf(
        report: report, recording: rec, lang: lang, fontRegular: font('Regular'), fontBold: font('Bold'),
        describe: (c) => c == 'P0106' ? (lang == 'ar' ? 'حساس الضغط' : 'MAP sensor') : null, clear: clear,
      );
      expect(String.fromCharCodes(bytes.sublist(0, 5)), '%PDF-');
      expect(bytes.length, greaterThan(2000));
      final out = Platform.environment['PDF_OUT'];
      if (out != null) File('$out.$lang.pdf').writeAsBytesSync(bytes);
    });
  }
}
