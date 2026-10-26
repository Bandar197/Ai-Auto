import 'package:automind_app/core/clear/clear_planner.dart';
import 'package:automind_app/obd/obd.dart';
import 'package:flutter_test/flutter_test.dart';

RecordingModuleScan mod(String key, String outcome,
        {String category = 'other', String address = '7D4', List<String> codes = const [], List<String> active = const []}) =>
    RecordingModuleScan(
      key: key, nameEn: key, nameAr: key, outcome: outcome, category: category, address: address,
      codes: [for (final c in codes) Dtc(c, DtcStatus.stored)], activeCodes: active,
    );

Recording rec({List<Dtc> dtcs = const [], List<RecordingModuleScan> modules = const []}) => Recording(
      recordingId: 'r', createdAt: DateTime.utc(2026), dataMode: 'live', source: const {'kind': 'elm327_ble'},
      durationMs: 0, signals: const [], samples: const [], dtcs: dtcs, moduleScans: modules,
    );

const verifiedSrs = UdsModule(
  key: 'srs', nameEn: 'Airbag', nameAr: 'x', requestId: 0x7D4, responseId: 0x7DC,
  category: ModuleCategory.airbag, verified: true, clearService: 'uds14',
);

ClearTarget only(ClearPlan p, String key) => p.targets.singleWhere((t) => t.key == key);

void main() {
  test('engine codes are clearable with 04 when connected; permanent codes flagged', () {
    final p = planClear(
      recording: rec(dtcs: const [Dtc('P0106', DtcStatus.stored), Dtc('P0420', DtcStatus.permanent)]),
      connected: true, replay: false,
    );
    final e = only(p, 'engine');
    expect(e.clearable, isTrue);
    expect(e.service, '04');
    expect(e.permanentCodes, ['P0420']);
  });

  test('not connected / replay → comm_failed, nothing clearable', () {
    final r = rec(dtcs: const [Dtc('P0106', DtcStatus.stored)], modules: [mod('srs', 'read_codes', codes: ['B0051'])]);
    for (final (connected, replay, reason) in [(false, false, ClearReason.notConnected), (true, true, ClearReason.replay)]) {
      final p = planClear(recording: r, connected: connected, replay: replay);
      expect(p.clearable, isEmpty);
      expect(p.targets.every((t) => t.context == ClearContext.commFailed && t.reason == reason), isTrue);
    }
  });

  test('Hyundai SRS 7D4 as shipped (unverified) is never clearable', () {
    final p = planClear(
      recording: rec(modules: [mod('srs', 'read_codes', category: 'airbag', codes: ['B1620'])]),
      connected: true, replay: false,
      registry: const [UdsModule(key: 'srs', nameEn: 'a', nameAr: 'a', requestId: 0x7D4, responseId: 0x7DC)],
      serverProcedures: const {'clear_srs_dtcs'},
    );
    expect(only(p, 'srs').context, ClearContext.unsupportedByVehicle);
    expect(only(p, 'srs').reason, ClearReason.addressUnverified);
  });

  test('each blocking context with its reason', () {
    final r = rec(modules: [
      mod('a', 'no_response'),
      mod('b', 'refused'),
      mod('c', 'read_codes', codes: ['B0001'], active: ['B0001']),
      mod('d', 'read_codes', codes: ['B0002']),
      mod('srs', 'read_codes', category: 'airbag', codes: ['B0051']),
      mod('e', 'read_no_codes'),
    ]);
    final p = planClear(
      recording: r, connected: true, replay: false, registry: const [verifiedSrs],
      describeEn: (c) => c == 'B0002' ? 'Crash data stored' : null,
    );
    expect(only(p, 'a').context, ClearContext.commFailed);
    expect(only(p, 'b').context, ClearContext.requiresOemAuthorization);
    expect(only(p, 'c').context, ClearContext.activeFaultNotClearable);
    expect(only(p, 'c').flaggedCodes, ['B0001']);
    expect(only(p, 'd').context, ClearContext.crashDataSpecialist);
    // Verified + documented, but airbag needs the server allowlist → blocked offline.
    expect(only(p, 'srs').context, ClearContext.requiresOemAuthorization);
    expect(only(p, 'srs').reason, ClearReason.safetyPolicy);
    expect(p.targets.any((t) => t.key == 'e'), isFalse); // nothing to clear
  });

  test('verified + documented + allowlisted airbag is clearable; adapter without headers is not', () {
    final r = rec(modules: [mod('srs', 'read_codes', category: 'airbag', codes: ['B0051'])]);
    final ok = planClear(recording: r, connected: true, replay: false, registry: const [verifiedSrs], serverProcedures: const {'clear_srs_dtcs'});
    expect(only(ok, 'srs').clearable, isTrue);
    expect(only(ok, 'srs').service, '14');

    final noHeaders = AdapterCapabilities(
      connection: 'ble', capabilities: {Capability.headers: false}, evidence: const {}, probe: const [],
    );
    final hw = planClear(
      recording: r, connected: true, replay: false, registry: const [verifiedSrs],
      serverProcedures: const {'clear_srs_dtcs'}, adapter: noHeaders,
    );
    expect(only(hw, 'srs').context, ClearContext.unsupportedByHardware);
  });

  test('verified address without a documented 0x14 clear is not offered', () {
    const noClear = UdsModule(key: 'bcm', nameEn: 'b', nameAr: 'b', requestId: 0x7A0, responseId: 0x7A8, verified: true);
    final p = planClear(
      recording: rec(modules: [mod('bcm', 'read_codes', address: '7A0', codes: ['B1000'])]),
      connected: true, replay: false, registry: const [noClear],
    );
    expect(only(p, 'bcm').reason, ClearReason.clearNotDocumented);
  });

  test('active-code flags survive the recording round-trip', () {
    final r = rec(modules: [mod('srs', 'read_codes', codes: ['B0051'], active: ['B0051'])]);
    expect(Recording.fromJsonString(r.toJsonString()).moduleScans.single.activeCodes, ['B0051']);
  });
}
