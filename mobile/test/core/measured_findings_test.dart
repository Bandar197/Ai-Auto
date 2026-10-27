import 'package:automind_app/core/measured_findings.dart';
import 'package:automind_app/core/storage/scan_report.dart';
import 'package:automind_app/obd/obd.dart';
import 'package:automind_app/state/connection_controller.dart';
import 'package:automind_app/state/full_scan_controller.dart';
import 'package:automind_app/state/providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../widget/test_app.dart';

/// A scan must not call the car healthy because no code is stored: overheating, a weak
/// alternator or a lean mixture are judged from measured values.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  List<String> keys(Map<String, List<double>> v, {bool attempted = true}) =>
      [for (final f in measuredFindings(v, coolantAttempted: attempted)) f.key];

  test('coolant: overheat / hot / sensor open / normal / not read', () {
    expect(measuredFindings({'coolant_temp': [104, 112], 'engine_rpm': [800]}).first
        .toJson(), containsPair('severity', 'critical'));
    expect(keys({'coolant_temp': [112]}), ['overheat']);
    expect(keys({'coolant_temp': [106]}), ['coolant_hot']);
    expect(keys({'coolant_temp': [-40]}), ['coolant_sensor_suspect']);
    expect(keys({'coolant_temp': [91]}), ['coolant_ok']);
    expect(keys({}), ['coolant_not_read']); // tried and missing → said, never "normal"
    expect(keys({}, attempted: false), isEmpty);
  });

  test('voltage depends on engine running; fuel trims only when running', () {
    expect(keys({'module_voltage': [12.4], 'engine_rpm': [780]}, attempted: false), ['charging_low']);
    expect(keys({'module_voltage': [15.6], 'engine_rpm': [780]}, attempted: false), ['overcharging']);
    expect(keys({'module_voltage': [11.6], 'engine_rpm': [0]}, attempted: false), ['battery_low']);
    expect(keys({'module_voltage': [12.5], 'engine_rpm': [0]}, attempted: false), isEmpty);
    expect(keys({'ltft_b1': [18], 'engine_rpm': [800]}, attempted: false), ['fuel_trim_lean']);
    expect(keys({'ltft_b1': [-19], 'engine_rpm': [800]}, attempted: false), ['fuel_trim_rich']);
    expect(keys({'ltft_b1': [18], 'engine_rpm': [0]}, attempted: false), isEmpty);
  });

  test('critical first; report json round trip keeps findings', () {
    final f = measuredFindings({'coolant_temp': [113], 'module_voltage': [12.3], 'engine_rpm': [800]});
    expect(f.map((x) => x.key), ['overheat', 'charging_low']);
    final r = ScanReport(id: 'r', createdAt: DateTime.utc(2026), dataMode: 'live', measured: [for (final x in f) x.toJson()]);
    final back = ScanReport.fromJson(r.toJson());
    expect(MeasuredFinding.fromJson(back.measured.first).value, 113);
    expect(ScanReport.fromJson(ScanReport(id: 'x', createdAt: DateTime.utc(2026), dataMode: 'live').toJson()).measured, isEmpty);
  });

  test('full scan (demo): overheating with no fault code is flagged, not "all clear"', () async {
    final container = ProviderContainer(retry: (_, _) => null, overrides: [...await testOverrides()]);
    addTearDown(container.dispose);
    final hot = Scenario({
      ...container.read(appAssetsProvider).scenario('healthy')!.json,
      'key': 'overheat_no_code',
      'faults': [
        {'signal': 'coolant_temp', 'type': 'override', 'value': 116, 'noise': 0.2},
      ],
    });
    final r = await container.read(connectionProvider.notifier).connectDemo(hot);
    expect(r.ecuOk, isTrue);

    await container.read(fullScanProvider.notifier).run();
    final s = container.read(fullScanProvider);
    expect(s.obdDtcs, isEmpty); // the car stored nothing…
    expect(s.measured.first.key, 'overheat'); // …but the engine is hot
    expect(s.measuredAlerts, 1);
    expect(s.samples.where((x) => x.pid == '0105'), isNotEmpty);

    await container.read(fullScanProvider.notifier).finalizeToReport();
    final store = container.read(localStoreProvider);
    final report = await store.loadReport(container.read(fullScanProvider).reportId!);
    expect(report!.measured.first['key'], 'overheat');
    final rec = await store.loadRecording(report.recordingId!);
    expect(rec!.samples, isNotEmpty);
    expect(rec.signals.map((x) => x.key), contains('coolant_temp'));
  });
}
