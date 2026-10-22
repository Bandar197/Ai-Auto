import 'package:automind_app/obd/obd.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

void main() {
  final t = loadTable();

  test('table loaded with all PIDs', () {
    expect(t.byPid.length, greaterThan(80));
    expect(t[0x0C]!.outputs.single.key, 'engine_rpm');
  });

  final cases = <String, Map<String, double>>{
    '41 0C 1A F8': {'engine_rpm': 1726},
    '41 05 7B': {'coolant_temp': 83},
    '41 06 80': {'stft_b1': 0},
    '41 10 01 F4': {'maf_gs': 5.0},
    '41 42 37 0E': {'module_voltage': 14.094},
    '41 0D 50': {'vehicle_speed': 80},
    '41 0B 1F': {'map_kpa': 31},
    '41 04 FF': {'engine_load': 100},
    '41 11 33': {'throttle_pos': 20},
    '41 0E 98': {'timing_advance': 12},
    '41 0F 54': {'intake_air_temp': 44},
    '41 2F 80': {'fuel_level': 50.196078},
    '41 32 FF 38': {'evap_vapor_pressure': -50},
    '41 3C 0F A0': {'cat_temp_b1s1': 360},
    '41 A6 00 00 30 39': {'odometer_km': 1234.5},
  };
  cases.forEach((hex, expected) {
    test('decode $hex', () {
      final v = t.decodeHex(hex);
      expected.forEach((k, e) => expect(v[k], closeTo(e, 1e-4), reason: k));
    });
  });

  test('O2 sensor trim is null when byte B = 0xFF', () {
    final v = t.decodeHex('41 15 8C FF');
    expect(v['o2_b1s2_voltage'], closeTo(0.7, 1e-9));
    expect(v.containsKey('o2_b1s2_stft'), isTrue);
    expect(v['o2_b1s2_stft'], isNull);
    final w = t.decodeHex('41 14 8C 80');
    expect(w['o2_b1s1_stft'], closeTo(0, 1e-9));
  });

  test('monitor status: MIL bit and DTC count', () {
    final v = t.decodeHex('41 01 83 07 E5 00');
    expect(v['mil_on'], 1);
    expect(v['dtc_count'], 3);
  });

  test('enums: fuel system status, OBD standard, fuel type', () {
    final v = t.decodeHex('41 03 02 00');
    expect(v['fuel_system_1_status'], 2);
    expect(t.enumLabel('fuel_system_1_status', 2), startsWith('Closed loop'));
    expect(t.enumLabel('fuel_system_1_status', 1, lang: 'ar'), contains('حلقة مفتوحة'));
    expect(t.enumLabel('obd_standard', t.decodeHex('41 1C 01')['obd_standard']), 'OBD-II (CARB)');
    expect(t.enumLabel('fuel_type', t.decodeHex('41 51 04')['fuel_type']), 'Diesel');
  });

  test('freeze frame (mode 02) response decodes with frame byte skipped', () {
    expect(t.decodeHex('42 0C 00 0B B0')['engine_rpm'], 748);
  });

  test('supported bitmask decode/encode round trip', () {
    final pids = decodeSupportedBitmask(0, [0xBE, 0x3F, 0xA8, 0x13]);
    expect(pids, containsAll([0x01, 0x03, 0x04, 0x05, 0x06, 0x07, 0x0C, 0x0D, 0x20]));
    expect(pids, isNot(contains(0x02)));
    expect(encodeSupportedBitmask(0, pids), [0xBE, 0x3F, 0xA8, 0x13]);
  });

  test('encode is the inverse of decode for linear PIDs', () {
    final data = t.encode(0x0C, {'engine_rpm': 1726});
    expect(toHex(data), '1A F8');
    expect(t.decode(0x42, t.encode(0x42, {'module_voltage': 14.094}))['module_voltage'], closeTo(14.094, 1e-9));
  });
}
