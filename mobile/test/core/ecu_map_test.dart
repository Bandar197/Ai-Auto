import 'dart:io';

import 'package:automind_app/core/ecu_states.dart';
import 'package:automind_app/core/vehicle_profiles.dart';
import 'package:automind_app/obd/obd.dart';
import 'package:flutter_test/flutter_test.dart';

RecordingModuleScan mod(String key, String outcome, {int? nrc, List<String> codes = const [], String address = '7D4'}) =>
    RecordingModuleScan(
      key: key, nameEn: key, nameAr: key, outcome: outcome, address: address, nrc: nrc,
      codes: [for (final c in codes) Dtc(c, DtcStatus.stored)],
    );

void main() {
  final rec = Recording(
    recordingId: 'r', createdAt: DateTime.utc(2026), dataMode: 'live', source: const {'kind': 'elm327_ble'},
    durationMs: 0, signals: const [], samples: const [],
    ecus: const ['7E8'],
    dtcs: const [Dtc('P0106', DtcStatus.stored, ecu: '7E8')],
    moduleScans: [
      mod('a', 'read_codes', codes: ['B1620']),
      mod('b', 'read_no_codes'),
      mod('c', 'no_response'),
      mod('d', 'refused', nrc: 0x33),
      mod('e', 'refused', nrc: 0x11),
      mod('f', 'refused', nrc: 0x22),
      mod('srs', 'read_codes', codes: ['B0051'], address: '7A0'),
    ],
  );
  EcuEntry of(List<EcuEntry> l, String k) => l.singleWhere((e) => e.key == k);

  test('each module gets one of the ten states — "passed" only after a clean read', () {
    final m = buildEcuMap(rec, registry: const [
      UdsModule(key: 'srs', nameEn: 's', nameAr: 's', requestId: 0x7A0, responseId: 0x7A8, verified: true, clearService: 'uds14'),
    ]);
    expect(of(m, 'obd_7E8').state, EcuState10.faultsPresent);
    expect(of(m, 'obd_7E8').requestId, '7E0');
    expect(of(m, 'a').state, EcuState10.faultsPresent);
    expect(of(m, 'b').state, EcuState10.passed);
    expect(of(m, 'c').state, EcuState10.timedOut);
    expect(of(m, 'd').state, EcuState10.gatewayBlocked);
    expect(of(m, 'e').state, EcuState10.notSupported);
    expect(of(m, 'f').state, EcuState10.refused);
    expect(of(m, 'f').nrc, 0x22);
    expect(of(m, 'srs').flags, contains(EcuState10.clearSupported));
    expect(of(m, 'a').flags, isNot(contains(EcuState10.clearSupported))); // unverified address
    expect(of(m, 'a').verified, isFalse);
    expect(of(m, 'c').toCoverageJson()['state'], 'timed_out');
  });

  test('Sonata YF 2012 profile matches make+model+year only and stays unverified', () {
    final p = VehicleProfiles.fromJsonString(File('assets/shared/obd/vehicle_profiles.json').readAsStringSync());
    final s = p.match(make: 'Hyundai', model: 'Sonata', year: 2012)!;
    expect(s.verified, isFalse);
    expect(s.srsUnreachable('ar'), contains('Hyundai GDS'));
    expect(s.notes('ar').join(), contains('6 ثوانٍ'));
    expect(p.match(make: 'hyundai', model: 'sonata', year: 2019), isNull);
    expect(p.match(make: 'hyundai'), isNull); // make alone is not enough
    expect(p.match(make: 'kia', model: 'sonata', year: 2012), isNull);
  });
}
