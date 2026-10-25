import 'dart:io';

import 'package:automind_app/core/storage/local_store.dart';
import 'package:automind_app/core/storage/scan_report.dart';
import 'package:automind_app/features/compare_screen.dart';
import 'package:automind_app/l10n/app_localizations.dart';
import 'package:automind_app/obd/obd.dart';
import 'package:automind_app/state/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('shows gone / unverified honestly (English)', (tester) async {
    final dir = Directory.systemTemp.createTempSync('automind_cmp');
    addTearDown(() => dir.deleteSync(recursive: true));
    final store = LocalStore(dir);
    await tester.runAsync(() async {
      Future<void> add(String id, DateTime at, List<Dtc> dtcs, List<RecordingModuleScan> mods) async {
        await store.saveRecording(Recording(
          recordingId: id, createdAt: at, dataMode: 'live', source: const {'kind': 'elm327_ble'},
          durationMs: 0, signals: const [], samples: const [], supportedPids: const {'7E8': ['0100']},
          dtcs: dtcs, moduleScans: mods,
        ));
        await store.saveReport(ScanReport(id: 'rep-$id', createdAt: at, dataMode: 'live', recordingId: id));
      }

      await add('a', DateTime.utc(2026, 10, 1), const [Dtc('P0106', DtcStatus.stored)], [
        RecordingModuleScan(key: 'srs', nameEn: 'Airbag', nameAr: 'x', outcome: 'read_codes', codes: const [Dtc('B0051', DtcStatus.stored)]),
      ]);
      await add('b', DateTime.utc(2026, 10, 2), const [], [
        RecordingModuleScan(key: 'srs', nameEn: 'Airbag', nameAr: 'x', outcome: 'no_response'),
      ]);
    });

    final container = ProviderContainer(overrides: [localStoreProvider.overrideWithValue(store)]);
    addTearDown(container.dispose);
    await tester.runAsync(() => container.read(reportsProvider.future)); // load History outside fake time
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(
        locale: Locale('en'),
        supportedLocales: [Locale('ar'), Locale('en')],
        localizationsDelegates: [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: CompareScreen(),
      ),
    ));
    for (var i = 0; i < 20; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump();
    }
    // P0106 gone after a successful OBD read; B0051 not counted as fixed (airbag not read).
    expect(find.descendant(of: find.byKey(const Key('diff-resolved')), matching: find.text('P0106')), findsOneWidget);
    expect(find.descendant(of: find.byKey(const Key('diff-unverified')), matching: find.text('B0051 · srs')), findsOneWidget);
    expect(find.byKey(const Key('diff-new')), findsNothing);
  });
}
