import 'package:automind_app/core/storage/clear_entry.dart';
import 'package:automind_app/features/verify_screen.dart';
import 'package:automind_app/l10n/app_localizations.dart';
import 'package:automind_app/obd/obd.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _wrap(Widget child, {String locale = 'ar'}) => MaterialApp(
      locale: Locale(locale),
      supportedLocales: const [Locale('ar'), Locale('en')],
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: Scaffold(body: child),
    );

ClearEntry _entry(String code, List<ScanSnapshot> checks, {String mode = 'demo'}) {
  final t0 = DateTime.utc(2026, 10, 22, 8);
  final rec = ClearRecord(clearedAt: t0, dataMode: mode, before: ScanSnapshot(takenAt: t0, dtcs: [SnapshotDtc(code, ecu: '7E8')]));
  return ClearEntry(
    id: 'e-$code',
    vehicleKey: 'demo:x',
    record: rec,
    checks: checks,
    verification: assessAfterClear(rec, checks),
    verificationSource: 'local',
  );
}

void main() {
  final t0 = DateTime.utc(2026, 10, 22, 8);

  testWidgets('problem_confirmed: red banner, Arabic RTL, DEMO label', (tester) async {
    final e = _entry('P0106', [
      ScanSnapshot(takenAt: t0.add(const Duration(minutes: 1))),
      ScanSnapshot(takenAt: t0.add(const Duration(hours: 1)), dtcs: const [SnapshotDtc('P0106')], warmupsSinceClear: 1),
    ]);
    await tester.pumpWidget(_wrap(VerificationView(entry: e, onCheckNow: () {})));
    await tester.pump();
    expect(find.byKey(const Key('verify-overall-problem_confirmed')), findsOneWidget);
    expect(find.text('يوجد عطل حقيقي'), findsOneWidget);
    expect(find.textContaining('P0106 رجع — يوجد عطل حقيقي'), findsOneWidget);
    expect(find.text('الخطوة التالية'), findsWidgets);
    expect(find.byKey(const Key('demo-banner')), findsOneWidget);
    final ctx = tester.element(find.byType(VerificationView));
    expect(Directionality.of(ctx), TextDirection.rtl);
    final banner = tester.widget<Container>(find.byKey(const Key('verify-overall-problem_confirmed')));
    expect((banner.decoration! as BoxDecoration).color, overallColor('problem_confirmed'));
    expect(find.byKey(const Key('verify-check-now')), findsOneWidget);
  });

  testWidgets('likely_resolved: green banner "غالبا عطل قديم"', (tester) async {
    final e = _entry('P0102', [
      ScanSnapshot(takenAt: t0.add(const Duration(minutes: 1))),
      ScanSnapshot(takenAt: t0.add(const Duration(hours: 2)), warmupsSinceClear: 1, engineRunning: true),
    ]);
    await tester.pumpWidget(_wrap(VerificationView(entry: e)));
    await tester.pump();
    expect(find.byKey(const Key('verify-overall-likely_resolved')), findsOneWidget);
    expect(find.text('غالبا عطل قديم'), findsOneWidget);
    expect(find.textContaining('P0102 لم يرجع'), findsOneWidget);
  });

  testWidgets('verifying: amber banner "التحقق مستمر", live data has no DEMO banner', (tester) async {
    final e = _entry('P0420', [ScanSnapshot(takenAt: t0.add(const Duration(minutes: 1)))], mode: 'live');
    await tester.pumpWidget(_wrap(VerificationView(entry: e)));
    await tester.pump();
    expect(find.byKey(const Key('verify-overall-verifying')), findsOneWidget);
    expect(find.text('التحقق مستمر'), findsOneWidget);
    expect(find.byKey(const Key('demo-banner')), findsNothing);
    expect(find.textContaining('قُد السيارة'), findsOneWidget); // catalyst drive hint
  });

  testWidgets('English rendering', (tester) async {
    final e = _entry('P0106', [ScanSnapshot(takenAt: t0.add(const Duration(minutes: 1)), dtcs: const [SnapshotDtc('P0106')])]);
    await tester.pumpWidget(_wrap(VerificationView(entry: e), locale: 'en'));
    await tester.pump();
    expect(find.text('Real problem'), findsOneWidget);
    expect(find.textContaining('came back immediately'), findsOneWidget);
  });
}
