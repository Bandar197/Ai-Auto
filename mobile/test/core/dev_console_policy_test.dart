import 'package:automind_app/core/dev_console_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('read-only commands pass, normalised', () {
    expect(consoleAllowed('01 00'), '0100');
    expect(consoleAllowed('atrv'), 'ATRV');
    expect(consoleAllowed('0902'), '0902');
    expect(consoleAllowed('0600'), '0600');
  });

  test('clears, writes, resets, protocol/header changes and EEPROM params are refused', () {
    for (final c in ['04', '14FFFFFF', '2E F1 90 00', '3101', '10 03', 'ATZ', 'ATWS', 'ATSP6', 'ATH0', 'ATE1', 'ATMA',
      'ATPP 2C SV 81', 'ATSD 12', 'ATSH7DF', 'ATCRA7E8', 'AT BRD 23', '', 'hello', '010']) {
      expect(consoleAllowed(c), isNull, reason: c);
    }
  });
}
