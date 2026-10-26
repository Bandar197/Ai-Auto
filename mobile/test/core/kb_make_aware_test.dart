import 'dart:io';

import 'package:automind_app/core/kb/local_kb.dart';
import 'package:automind_app/core/vehicle_make.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final wmi = WmiTable.fromJsonString(File('assets/shared/obd/wmi.json').readAsStringSync());

  test('VIN → make (longest WMI prefix), unknown/invalid → null', () {
    expect(wmi.makeFromVin('KMHEC41CBCA123456'), 'hyundai');
    expect(wmi.makeFromVin('KNAGM4A73B5123456'), 'kia');
    expect(wmi.makeFromVin('JTHBK1GG2E2123456'), 'lexus');
    expect(wmi.makeFromVin('JTDBR32E720123456'), 'toyota');
    expect(wmi.makeFromVin('ZZZ00000000000000'), isNull);
    expect(wmi.makeFromVin('KMH'), isNull);
    expect(wmi.makeFromVin(null), isNull);
  });

  test('manufacturer-specific ranges (SAE J2012)', () {
    for (final c in ['P1326', 'P3001', 'B1620', 'B2000', 'C1201', 'U1000']) {
      expect(isManufacturerSpecific(c), isTrue, reason: c);
    }
    for (final c in ['P0106', 'P2101', 'P3400', 'B0001', 'C0035', 'U0100', 'U3000']) {
      expect(isManufacturerSpecific(c), isFalse, reason: c);
    }
  });

  test('an OEM description is used only for its own make (or alias)', () {
    final kb = LocalKb.fromJsonString('{"codes": {"P0106": {"en": "MAP", "ar": "حساس"}}}').withOem(
        '{"profiles": [{"make": "hyundai", "aliases": ["kia"], "source": "licensed", "codes": {"P1326": {"en": "KSDS", "ar": ""}}}]}');
    expect(kb.lookupFor('P1326', make: 'hyundai')?.oemMake, 'hyundai');
    expect(kb.lookupFor('P1326', make: 'Kia')?.descriptionEn, 'KSDS');
    expect(kb.lookupFor('P1326', make: 'kia')?.descriptionAr, isNull); // empty Arabic → English shown, never guessed
    expect(kb.lookupFor('P1326', make: 'toyota'), isNull);
    expect(kb.lookupFor('P1326'), isNull);
    expect(kb.lookupFor('P0106', make: 'toyota')?.descriptionAr, 'حساس');
  });

  test('shipped KB: generic part has no manufacturer codes; community overlay is marked unverified', () {
    final kb = LocalKb.fromJsonString(File('assets/shared/kb/dtc_definitions.json').readAsStringSync())
        .withOem(File('assets/shared/kb/dtc_oem.json').readAsStringSync());
    expect(kb.entries.keys.where(isManufacturerSpecific), isEmpty);
    expect(kb.lookupFor('B1620', make: 'hyundai'), isNull); // no Hyundai data → honest "not in database"
    final t = kb.lookupFor('P1100', make: 'toyota')!;
    expect(t.descriptionEn, 'BARO Sensor Circuit');
    expect(t.oemVerified, isFalse);
    expect(kb.lookupFor('P1100', make: 'infiniti'), isNull); // bad source file excluded
  });
}
