import 'dart:io';

import 'package:automind_app/core/vehicle_profiles.dart';
import 'package:automind_app/core/kb/local_kb.dart';
import 'package:automind_app/core/storage/scan_report.dart';
import 'package:automind_app/features/report_screen.dart';
import 'package:automind_app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _wrap(Widget child, {String locale = 'en'}) => MaterialApp(
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

Map<String, dynamic> _diagnosis() => {
      'engine_version': '1.0.0',
      'data_mode': 'demo',
      'health_score': 72,
      'health_band': 'attention',
      'summary': {'en': 'MAP sensor reading is implausible at idle.', 'ar': 'قراءة حساس MAP غير منطقية في الخمول.'},
      'dtcs': [
        {'code': 'P0106', 'status': 'stored', 'description_en': 'MAP sensor range/performance', 'description_ar': 'أداء حساس MAP', 'severity': 'medium', 'known': true},
      ],
      'findings': [
        {
          'id': 'f1',
          'title_en': 'MAP sensor plausibility',
          'title_ar': 'منطقية حساس MAP',
          'severity': 'medium',
          'confidence': 0.74,
          'related_dtcs': ['P0106'],
          'causes': [
            {'key': 'map_sensor_fault', 'title_en': 'MAP sensor fault', 'title_ar': 'عطل حساس MAP', 'likelihood': 0.62, 'rank': 1},
          ],
          'evidence': [
            {'id': 'e1', 'kind': 'pid_statistic', 'is_measured': true, 'signal': 'map_kpa', 'observed_value': 61.2, 'unit': 'kPa', 'expected_min': 25, 'expected_max': 45, 'expected_context': 'warm idle', 'note_en': 'High at idle'},
            {'id': 'e2', 'kind': 'inference', 'is_measured': false, 'note_en': 'Trims normal → not a vacuum leak'},
          ],
          'tests': [
            {'title_en': 'MAP key-on engine-off', 'how_en': 'Compare MAP with BARO', 'expected_en': 'Within 3 kPa'},
          ],
          'parts_candidates': [
            {'name_en': 'MAP sensor', 'requires_confirmation': true, 'condition_en': 'Only if the test fails'},
          ],
          'missing_data': [
            {'signal': 'baro_kpa', 'description_en': 'Barometric pressure not reported'},
          ],
        },
      ],
      'disclaimers': [
        {'en': 'Not a substitute for a professional inspection.', 'ar': 'لا يغني عن الفحص لدى مختص.'},
      ],
    };

void main() {
  testWidgets('demo report shows the DEMO banner, watermark and evidence split', (tester) async {
    final report = ScanReport(
      id: 'r1',
      createdAt: DateTime.utc(2026, 10, 22),
      dataMode: 'demo',
      simulator: true,
      scenarioKey: 'p0106_map_sensor',
      dtcs: const [
        {'code': 'P0106', 'status': 'stored', 'ecu': '7E8'},
      ],
      diagnosis: _diagnosis(),
      uploadState: 'uploaded',
    );
    await tester.pumpWidget(_wrap(ReportView(report: report, kb: LocalKb.empty())));
    await tester.pump();

    expect(find.byKey(const Key('demo-banner')), findsOneWidget);
    expect(find.textContaining('DEMO — simulated data'), findsOneWidget);
    expect(find.textContaining('Simulator'), findsWidgets);
    expect(find.byKey(const Key('watermark')), findsOneWidget);
    expect(find.text('72'), findsOneWidget);
    expect(find.text('MAP sensor plausibility'), findsOneWidget);
    expect(find.byKey(const Key('evidence-table')), findsOneWidget);
    expect(find.text('Measured'), findsWidgets);
    expect(find.text('Inferred'), findsOneWidget);
    expect(find.text('MAP sensor'), findsOneWidget);
    expect(find.textContaining('Requires confirmation'), findsOneWidget);
  });

  testWidgets('replay report shows REPLAY with the original mode; live shows no banner', (tester) async {
    final replay = ScanReport(id: 'r2', createdAt: DateTime.utc(2026), dataMode: 'replay', originalMode: 'live');
    await tester.pumpWidget(_wrap(ReportView(report: replay, kb: LocalKb.empty())));
    await tester.pump();
    expect(find.byKey(const Key('replay-banner')), findsOneWidget);
    expect(find.text('REPLAY of a Live recording'), findsOneWidget);
    expect(find.byKey(const Key('demo-banner')), findsNothing);

    final live = ScanReport(id: 'r3', createdAt: DateTime.utc(2026), dataMode: 'live');
    await tester.pumpWidget(_wrap(ReportView(report: live, kb: LocalKb.empty())));
    await tester.pump();
    expect(find.byKey(const Key('demo-banner')), findsNothing);
    expect(find.byKey(const Key('replay-banner')), findsNothing);
    expect(find.byKey(const Key('watermark')), findsNothing);
  });

  testWidgets('offline report uses the local KB and says full analysis needs the server (Arabic)', (tester) async {
    final kb = LocalKb.fromJsonString('[{"code":"P0106","description_en":"MAP sensor range/performance","description_ar":"أداء حساس ضغط مجمع السحب","severity":"medium"}]');
    final report = ScanReport(
      id: 'r4',
      createdAt: DateTime.utc(2026),
      dataMode: 'live',
      dtcs: const [
        {'code': 'P0106', 'status': 'stored', 'ecu': '7E8'},
        {'code': 'P1234', 'status': 'pending', 'ecu': '7E8'},
      ],
    );
    await tester.pumpWidget(_wrap(ReportView(report: report, kb: kb), locale: 'ar'));
    await tester.pump();
    expect(find.byKey(const Key('offline-note')), findsOneWidget);
    expect(find.text('أداء حساس ضغط مجمع السحب'), findsOneWidget);
    // P1234 is manufacturer-specific and the make is unknown: never borrowed or invented.
    expect(find.textContaining('كود خاص بالشركة المصنعة'), findsOneWidget);
  });

  testWidgets('measured overheating is shown even with no fault codes (Arabic)', (tester) async {
    final r = ScanReport(
      id: 'm',
      createdAt: DateTime.utc(2026, 10, 27),
      dataMode: 'live',
      measured: const [
        {'key': 'overheat', 'severity': 'critical', 'signal': 'coolant_temp', 'value': 114.0, 'unit': '°C'},
      ],
    );
    await tester.pumpWidget(_wrap(ReportView(report: r, kb: LocalKb.empty()), locale: 'ar'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('measured-card')), findsOneWidget);
    expect(find.textContaining('ارتفاع حرارة المحرك (114 °C)'), findsOneWidget);
    expect(find.textContaining('لا تفتح غطاء الرديتر'), findsOneWidget);
    expect(find.byKey(const Key('measured-cooling-note')), findsNothing); // no profile note given
  });

  testWidgets('Sonata profile adds the radiator fan fuse hint to a heat finding', (tester) async {
    final profiles = VehicleProfiles.fromJsonString(File('../shared/obd/vehicle_profiles.json').readAsStringSync());
    final p = profiles.match(make: 'hyundai', model: 'Sonata', year: 2012)!;
    expect(p.cooling('ar'), contains('C/FAN'));
    final r = ScanReport(id: 'c', createdAt: DateTime.utc(2026, 10, 27), dataMode: 'live', measured: const [
      {'key': 'coolant_hot', 'severity': 'warning', 'signal': 'coolant_temp', 'value': 107.0, 'unit': '°C'},
    ]);
    await tester.pumpWidget(_wrap(ReportView(report: r, kb: LocalKb.empty(), coolingNote: p.cooling('ar')), locale: 'ar'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('measured-cooling-note')), findsOneWidget);
  });
}
