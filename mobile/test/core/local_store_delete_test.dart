import 'dart:io';

import 'package:automind_app/core/storage/local_store.dart';
import 'package:automind_app/core/storage/scan_report.dart';
import 'package:automind_app/obd/obd.dart';
import 'package:flutter_test/flutter_test.dart';

/// Deleting a saved scan removes its report, its recording file, and any queue
/// entry — so a scan the user discarded leaves nothing behind on the phone.
void main() {
  late Directory dir;
  late LocalStore store;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('automind_del');
    store = LocalStore(dir);
  });
  tearDown(() => dir.deleteSync(recursive: true));

  test('deleteReport removes report, recording, and queue entry', () async {
    final rec = Recording(
      recordingId: 'rec-1', createdAt: DateTime.utc(2026), dataMode: 'live',
      source: const {'kind': 'elm327_wifi'}, durationMs: 0, signals: const [], samples: const [],
    );
    await store.saveRecording(rec);
    final report = ScanReport(
      id: 'rep-1', createdAt: DateTime.utc(2026), dataMode: 'live', recordingId: 'rec-1',
    );
    await store.saveReport(report);
    await store.writeQueue(['rep-1']);

    expect(await store.loadReport('rep-1'), isNotNull);
    expect(await store.loadRecording('rec-1'), isNotNull);

    await store.deleteReport('rep-1');

    expect(await store.loadReport('rep-1'), isNull);
    expect(await store.loadRecording('rec-1'), isNull);
    expect(await store.readQueue(), isEmpty);
  });

  test('deleteReport is safe when the report is already gone', () async {
    await store.deleteReport('nope'); // must not throw
    expect(await store.loadReport('nope'), isNull);
  });
}
