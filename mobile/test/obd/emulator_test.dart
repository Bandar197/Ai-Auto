import 'package:automind_app/obd/obd.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

void main() {
  final table = loadTable();
  Elm327Emulator emu() => Elm327Emulator(loadScenario('p0171_vacuum_leak'), table, clock: () => const Duration(seconds: 10));

  test('echo on until ATE0, prompt format', () {
    final e = emu();
    expect(e.handle('ATZ'), 'ATZ\rELM327 v1.5\r\r>');
    expect(e.handle('ate0'), 'ate0\rOK\r\r>');
    expect(e.handle('ATI'), 'ELM327 v1.5\r\r>');
    expect(e.handle('AT@1'), 'AUTOMIND SIMULATOR\r\r>');
    expect(e.handle('ATDPN'), 'A6\r\r>');
    expect(e.handle('ATDP'), 'AUTO, ISO 15765-4 (CAN 11/500)\r\r>');
    expect(e.handle('ATXYZ'), '?\r\r>');
    expect(e.handle('ATRV'), matches(RegExp(r'^1[34]\.\dV\r\r>$')));
  });

  test('SEARCHING... only on the first OBD request after ATSP0', () {
    final e = emu()
      ..handle('ATE0')
      ..handle('ATSP0');
    expect(e.handle('0100'), startsWith('SEARCHING...\r41 00 '));
    expect(e.handle('0100'), startsWith('41 00 '));
  });

  test('headers on: 7E8 + 8 bytes padded, TCM answers 0100 only', () {
    final e = emu()
      ..handle('ATE0')
      ..handle('ATH1')
      ..handle('0100');
    final r = e.handle('0100').split('\r');
    expect(r[0], startsWith('7E8 06 41 00 '));
    expect(r[1], '7E9 06 41 00 80 00 00 00 00');
    expect(e.handle('0 1 0 c'), matches(RegExp(r'^7E8 04 41 0C [0-9A-F]{2} [0-9A-F]{2} 00 00 00\r\r>$')));
    expect(e.handle('010A'), 'NO DATA\r\r>');
  });

  test('spaces off and multi-frame VIN in both header modes', () {
    final e = emu()
      ..handle('ATE0')
      ..handle('ATS0')
      ..handle('ATH1')
      ..handle('0100');
    final v = e.scenario.vin.codeUnits;
    String h(List<int> b, {bool sp = false}) => toHex(b, spaces: sp);
    expect(e.handle('0902'),
        '7E81014490201${h(v.sublist(0, 3))}\r7E821${h(v.sublist(3, 10))}\r7E822${h(v.sublist(10, 17))}\r\r>');
    e
      ..handle('ATH0')
      ..handle('ATS1');
    expect(e.handle('0902'),
        '014\r0: 49 02 01 ${h(v.sublist(0, 3), sp: true)}\r1: ${h(v.sublist(3, 10), sp: true)}\r2: ${h(v.sublist(10, 17), sp: true)}\r\r>');
  });

  test('modes 03/07/0A and 04', () {
    final e = emu()
      ..handle('ATE0')
      ..handle('0100');
    expect(e.handle('03'), '43 01 01 71\r\r>');
    expect(e.handle('07'), '47 01 01 74\r\r>');
    expect(e.handle('0A'), '4A 00\r\r>');
    expect(e.handle('04'), '44\r\r>');
    expect(e.handle('03'), '43 00\r\r>');
    expect(e.handle('020000'), 'NO DATA\r\r>');
  });

  test('freeze frame values from the scenario', () {
    final e = emu()
      ..handle('ATE0')
      ..handle('0100');
    expect(e.handle('020200'), '42 02 00 01 71\r\r>');
    expect(table.decodeHex(e.handle('020700').split('\r').first)['ltft_b1'], closeTo(19.5, 0.8));
  });
}
