import 'package:automind_app/core/indicators.dart';
import 'package:automind_app/obd/obd.dart';
import 'package:flutter_test/flutter_test.dart';

Recording rec({Map<String, dynamic>? readiness, List<RecordingModuleScan> modules = const [], List<Dtc> dtcs = const []}) => Recording(
      recordingId: 'r', createdAt: DateTime.utc(2026), dataMode: 'live', source: const {'kind': 'elm327_ble'},
      durationMs: 0, signals: const [], samples: const [], readiness: readiness, moduleScans: modules, dtcs: dtcs,
    );

IndicatorStatus of(List<IndicatorStatus> l, String k) => l.singleWhere((x) => x.key == k);

void main() {
  test('nothing read → unknown/not readable, never OK', () {
    final l = buildIndicators();
    for (final k in ['engine', 'airbag', 'abs', 'battery', 'coolant']) {
      expect(of(l, k).state, IndicatorState.unknown, reason: k);
    }
    for (final k in ['oil', 'tpms', 'esc', 'eps', 'seatbelt']) {
      expect(of(l, k).state, IndicatorState.unsupported, reason: k);
    }
  });

  test('MIL is read from the engine computer', () {
    expect(of(buildIndicators(recording: rec(readiness: {'mil_on': true})), 'engine').state, IndicatorState.fault);
    final off = of(buildIndicators(live: const LiveReadings(milOn: false)), 'engine');
    expect(off.state, IndicatorState.ok);
    expect(off.source, IndicatorSource.read);
  });

  test('airbag: codes → fault (inferred); clean read → OK (inferred); no answer → unknown', () {
    RecordingModuleScan srs(String o, [List<String> c = const []]) => RecordingModuleScan(
        key: 'srs', nameEn: 'SRS', nameAr: 'x', outcome: o, category: 'airbag', codes: [for (final x in c) Dtc(x, DtcStatus.stored)]);
    final f = of(buildIndicators(recording: rec(modules: [srs('read_codes', ['B1620'])])), 'airbag');
    expect(f.state, IndicatorState.fault);
    expect(f.source, IndicatorSource.inferred);
    expect(f.codes, ['B1620']);
    expect(of(buildIndicators(recording: rec(modules: [srs('read_no_codes')])), 'airbag').state, IndicatorState.ok);
    final u = of(buildIndicators(recording: rec(modules: [srs('no_response')])), 'airbag');
    expect(u.state, IndicatorState.unknown);
    expect(u.detail, 'module_not_read');
  });

  test('battery lamp with engine off is normal; low charging with engine running is flagged', () {
    final off = of(buildIndicators(live: const LiveReadings(volts: 12.4, rpm: 0)), 'battery');
    expect(off.state, IndicatorState.ok);
    expect(off.detail, 'battery_ok_engine_off');
    expect(of(buildIndicators(live: const LiveReadings(volts: 12.5, rpm: 800)), 'battery').detail, 'charging_low');
    expect(of(buildIndicators(live: const LiveReadings(volts: 14.1, rpm: 800)), 'battery').state, IndicatorState.ok);
    expect(of(buildIndicators(live: const LiveReadings(volts: 14.1)), 'battery').state, IndicatorState.unknown); // engine state unknown
  });

  test('coolant over 110 °C is a warning', () {
    expect(of(buildIndicators(live: const LiveReadings(coolantC: 112)), 'coolant').state, IndicatorState.warning);
    expect(of(buildIndicators(live: const LiveReadings(coolantC: 90)), 'coolant').state, IndicatorState.ok);
  });
}
