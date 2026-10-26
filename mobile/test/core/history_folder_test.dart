import 'dart:io';

import 'package:automind_app/core/history_search.dart';
import 'package:automind_app/core/storage/local_store.dart';
import 'package:automind_app/core/storage/scan_report.dart';
import 'package:automind_app/obd/obd.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final rec = Recording(
    recordingId: 'r1', createdAt: DateTime.utc(2026, 10, 25), dataMode: 'live', source: const {'kind': 'elm327_ble'},
    durationMs: 0, signals: const [], samples: const [],
    vehicle: const {'make': 'Hyundai', 'model': 'Sonata', 'model_year': 2012, 'vin': 'KMHEC41CBCA123456'},
    moduleScans: [RecordingModuleScan(key: 'srs', nameEn: 'Airbag', nameAr: 'الإيرباق', outcome: 'read_codes', codes: const [Dtc('B1620', DtcStatus.stored)])],
  );
  final live = ScanReport(id: 'a', createdAt: DateTime.utc(2026, 10, 25, 12), dataMode: 'live', dtcs: const [{'code': 'P0106'}]);
  final demo = ScanReport(id: 'b', createdAt: DateTime.utc(2026, 10, 20, 12), dataMode: 'demo', sessionState: 'interrupted');

  test('search covers OBD + module codes, module names (Arabic too), make/model, VIN and date', () {
    final t = searchTextFor(live, rec);
    for (final q in ['p0106', 'B1620', 'srs', 'الإيرباق', 'sonata 2012', 'KMHEC4', '2026-10-25']) {
      expect(matchesHistory(live, t, query: q), isTrue, reason: q);
    }
    expect(matchesHistory(live, t, query: 'toyota'), isFalse);
  });

  test('filters', () {
    final t = searchTextFor(demo, null);
    expect(matchesHistory(demo, t, filter: HistoryFilter.demo), isTrue);
    expect(matchesHistory(demo, t, filter: HistoryFilter.interrupted), isTrue);
    expect(matchesHistory(demo, t, filter: HistoryFilter.live), isFalse);
    expect(matchesHistory(live, searchTextFor(live, null), filter: HistoryFilter.imported), isFalse);
  });

  group('session folder', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('automind_sessions'));
    tearDown(() => dir.deleteSync(recursive: true));

    test('Windows default is %LOCALAPPDATA%\\AutoMind\\Sessions; a chosen folder wins', () {
      final store = LocalStore(dir);
      expect(store.sessionsRoot(env: {'LOCALAPPDATA': r'C:\Users\x\AppData\Local'}, windows: true).path,
          r'C:\Users\x\AppData\Local\AutoMind\Sessions');
      expect(store.sessionsRoot(env: const {}, windows: false).path, '${dir.path}/Sessions');
      store.exportDir = '${dir.path}/D_AutoMindLogs';
      expect(store.sessionsRoot().path, endsWith('D_AutoMindLogs${Platform.pathSeparator}Sessions'));
    });

    test('writes YYYY/MM/<id>/ with every file (Arabic path ok)', () async {
      final store = LocalStore(dir)..exportDir = '${dir.path}/سجلات';
      final out = await store.saveSessionFolder('rec-1', DateTime.utc(2026, 10, 25), {
        'manifest.json': [123, 125],
        'dtcs.csv': [0xEF, 0xBB, 0xBF, 0x41],
      });
      final sep = Platform.pathSeparator;
      expect(out.path, endsWith('Sessions${sep}2026${sep}10${sep}rec-1'));
      expect(File('${out.path}${sep}dtcs.csv').readAsBytesSync(), [0xEF, 0xBB, 0xBF, 0x41]);
      expect(out.listSync().where((f) => f.path.endsWith('.tmp')), isEmpty);
    });
  });
}
