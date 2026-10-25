import 'package:automind_app/core/storage/scan_report.dart';
import 'package:automind_app/features/clear_dtcs_screen.dart';
import 'package:automind_app/l10n/app_localizations.dart';
import 'package:automind_app/obd/obd.dart';
import 'package:automind_app/state/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_app.dart';

void main() {
  testWidgets('not connected: nothing clearable, every target explains why (English)', (tester) async {
    tester.view.physicalSize = const Size(1200, 6000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final overrides = await testOverrides(locale: 'en');
    final c = ProviderContainer(overrides: overrides);
    addTearDown(c.dispose);
    final store = c.read(localStoreProvider);
    await tester.runAsync(() async {
      await store.saveRecording(Recording(
        recordingId: 'rec-1', createdAt: DateTime.utc(2026, 10, 25), dataMode: 'live', source: const {'kind': 'elm327_ble'},
        durationMs: 0, signals: const [], samples: const [],
        dtcs: const [Dtc('P0106', DtcStatus.stored)],
        moduleScans: [
          RecordingModuleScan(key: 'srs', nameEn: 'Airbag (SRS)', nameAr: 'x', outcome: 'read_codes', category: 'airbag',
              address: '7D4', codes: const [Dtc('B1620', DtcStatus.stored)]),
        ],
      ));
      await store.saveReport(ScanReport(
        id: 'rep-1', createdAt: DateTime.utc(2026, 10, 25), dataMode: 'live', recordingId: 'rec-1',
        dtcs: const [{'code': 'P0106', 'status': 'stored'}],
      ));
    });
    await tester.pumpWidget(UncontrolledProviderScope(
      container: c,
      child: const MaterialApp(
        locale: Locale('en'),
        supportedLocales: [Locale('ar'), Locale('en')],
        localizationsDelegates: [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: ClearDtcsScreen(reportId: 'rep-1'),
      ),
    ));
    for (var i = 0; i < 20; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
      await tester.pump();
    }
    expect(find.text('Nothing on this scan can be cleared right now.'), findsOneWidget);
    expect(find.byKey(const Key('blocked-engine')), findsOneWidget);
    expect(find.descendant(of: find.byKey(const Key('blocked-engine')), matching: find.text('Connect to the car first.')), findsOneWidget);
    expect(find.byKey(const Key('blocked-srs')), findsOneWidget);
    final btn = tester.widget<ButtonStyleButton>(find.byKey(const Key('clear-run')));
    expect(btn.onPressed, isNull);
  });
}
