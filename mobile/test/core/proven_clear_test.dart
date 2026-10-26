import 'dart:io';

import 'package:automind_app/core/clear/clear_planner.dart';
import 'package:automind_app/core/clear/proven_modules.dart';
import 'package:automind_app/core/storage/local_store.dart';
import 'package:automind_app/obd/obd.dart';
import 'package:flutter_test/flutter_test.dart';

import '../obd/helpers.dart';

const srs = UdsModule(key: 'srs', nameEn: 'Airbag', nameAr: 'الإيرباق', requestId: 0x7D4, responseId: 0x7DC, category: ModuleCategory.airbag);

ModuleScan scan(ModuleOutcome o, {List<UdsDtc> dtcs = const []}) => ModuleScan(module: srs, outcome: o, dtcs: dtcs);
UdsDtc dtc(String c, {bool active = false}) =>
    UdsDtc(code: c, ftb: 0, status: active ? 0x09 : 0x08, flags: [if (active) 'test_failed', 'confirmed']);

void main() {
  late Directory dir;
  late ProvenModulesStore store;
  setUp(() {
    dir = Directory.systemTemp.createTempSync('automind_proven');
    store = ProvenModulesStore(LocalStore(dir));
  });
  tearDown(() => dir.deleteSync(recursive: true));

  test('only a LIVE positive read on an identified car proves an address', () async {
    const car = 'vin:KMHEC41CBCA123456';
    expect(await store.recordFromScan(car, [scan(ModuleOutcome.readSuccessCodes)], mode: DataMode.demo), 0);
    expect(await store.recordFromScan(null, [scan(ModuleOutcome.readSuccessCodes)], mode: DataMode.live), 0);
    expect(await store.recordFromScan(car, [scan(ModuleOutcome.noResponse)], mode: DataMode.live), 0);
    expect(await store.recordFromScan(car, [scan(ModuleOutcome.refused)], mode: DataMode.live), 0);
    expect(await store.recordFromScan(car, [scan(ModuleOutcome.readSuccessNoCodes)], mode: DataMode.live), 1);
    final mine = await store.forVehicle(car);
    expect(mine.single.toUdsModule().verified, isTrue);
    expect(mine.single.toUdsModule().clearService, 'uds14');
    expect(await store.forVehicle('vin:KMHEC41CBCA999999'), isEmpty); // another car: nothing proven
  });

  test('vehicle key needs a real VIN or a server vehicle id', () {
    expect(provenVehicleKey(vin: 'KMHEC41CBCA123456'), 'vin:KMHEC41CBCA123456');
    expect(provenVehicleKey(vehicleId: 'v-1'), 'vehicle:v-1');
    expect(provenVehicleKey(vehicleId: 'local-1'), isNull);
    expect(provenVehicleKey(vin: 'BAD'), isNull);
  });

  Recording rec(List<RecordingModuleScan> m) => Recording(
        recordingId: 'r', createdAt: DateTime.utc(2026), dataMode: 'live', source: const {'kind': 'elm327_ble'},
        durationMs: 0, signals: const [], samples: const [], moduleScans: m,
      );
  RecordingModuleScan rsrs({List<String> codes = const ['B1620'], List<String> active = const []}) => RecordingModuleScan(
        key: 'srs', nameEn: 'Airbag', nameAr: 'x', outcome: 'read_codes', category: 'airbag', address: '7D4',
        codes: [for (final c in codes) Dtc(c, DtcStatus.stored)], activeCodes: active,
      );

  test('a car-proven airbag module is clearable offline; active / crash codes still are not', () async {
    await store.recordFromScan('vin:KMHEC41CBCA123456', [scan(ModuleOutcome.readSuccessCodes)], mode: DataMode.live);
    final proven = [for (final p in await store.forVehicle('vin:KMHEC41CBCA123456')) p.toUdsModule()];
    final ok = planClear(recording: rec([rsrs()]), connected: true, replay: false, proven: proven);
    final t = ok.targets.single;
    expect(t.clearable, isTrue);
    expect(t.proven, isTrue);
    expect(t.module!.verified, isTrue);

    final active = planClear(recording: rec([rsrs(active: ['B1620'])]), connected: true, replay: false, proven: proven);
    expect(active.targets.single.context, ClearContext.activeFaultNotClearable);
    final crash = planClear(recording: rec([rsrs()]), connected: true, replay: false, proven: proven, describeEn: (_) => 'Crash data stored');
    expect(crash.targets.single.context, ClearContext.crashDataSpecialist);
    final notProven = planClear(recording: rec([rsrs()]), connected: true, replay: false);
    expect(notProven.targets.single.reason, ClearReason.addressUnverified);
  });

  Map<String, String> addr(String reply) =>
      {'ATSH7D4': 'OK', 'ATCRA7DC': 'OK', 'ATH0': 'OK', 'ATH1': 'OK', 'ATCRA': 'OK', 'ATSH7DF': 'OK', '1902FF': reply};
  Future<PreClearCheck> check(String reply) async {
    final t = ScriptedTransport(addr(reply));
    await t.connect();
    return preClearCheck(Elm327(t)..attach(), srs);
  }

  test('pre-clear read: stored-only → ok; active → blocked; refused / silent → no clear', () async {
    expect((await check('59 02 FF 96 20 00 08')).status, PreClearStatus.ok); // B1620 confirmed, not failing now
    final a = await check('59 02 FF 96 20 00 09'); // testFailed bit set
    expect(a.status, PreClearStatus.activeFault);
    expect(a.activeCodes, ['B1620']);
    final r = await check('7F 19 33');
    expect(r.status, PreClearStatus.refused);
    expect(r.nrc, 0x33);
    expect((await check('NO DATA')).status, PreClearStatus.readFailed);
  });
}
