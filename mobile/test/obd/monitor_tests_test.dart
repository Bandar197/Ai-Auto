import 'package:automind_app/obd/obd.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

void main() {
  test('parses 9-byte records, decides pass/fail on raw values', () {
    final t = parseMonitorResponse([0x46, 0x21, 0x80, 0x0A, 0x01, 0x2C, 0x00, 0xC8, 0x01, 0xF4, 0x21, 0x81, 0x0A, 0x02, 0x58, 0x00, 0xC8, 0x01, 0xF4]);
    expect(t.length, 2);
    expect(t[0].value, 300);
    expect(t[0].passed, isTrue);
    expect(t[1].value, 600);
    expect(t[1].passed, isFalse);
  });

  test('signed UASIDs use two\'s complement; a cut record is ignored', () {
    final t = parseMonitorResponse([0x46, 0xA2, 0x0B, 0x8A, 0xFF, 0xF6, 0xFF, 0xEC, 0x00, 0x14, 0xA2, 0x0C]);
    expect(t.single.value, -10);
    expect(t.single.min, -20);
    expect(t.single.passed, isTrue);
    expect(midName(0xA2, 'en'), 'Misfire — cylinder 1');
    expect(midName(0xEE, 'en'), r'MID $EE');
  });

  test('client reads supported MIDs then each test (CAN)', () async {
    final t = ScriptedTransport({
      'ATZ': 'ELM327 v1.5', 'ATE0': 'OK', 'ATL0': 'OK', 'ATS1': 'OK', 'ATH1': 'OK', 'ATAT1': 'OK', 'ATSP0': 'OK',
      'AT@1': '?', 'ATRV': '12.5V', 'ATDPN': 'A6', 'ATDP': 'ISO 15765-4 (CAN 11/500)',
      '0100': '7E8 06 41 00 98 18 80 13',
      '0600': '7E8 06 46 00 00 00 40 00', // 3rd bitmap byte (MIDs 0x11–0x18), 0x40 → MID 0x12
      '0612': '7E8 10 0A 46 12 01 0A 01 2C\r7E8 21 00 C8 01 F4 00 00 00',
    });
    final c = ObdClient(transport: t, table: loadTable());
    await c.connect();
    final r = await c.readMonitorTests();
    expect(r.unsupportedReason, isNull);
    expect(r.supportedMids, {0x12});
    expect(r.tests.single.value, 300);
    expect(r.tests.single.passed, isTrue);
    expect(t.sent.where((s) => s.startsWith('04') || s.startsWith('14')), isEmpty);
  });

  test('legacy protocol → reported unsupported, nothing mis-decoded', () async {
    final t = ScriptedTransport({
      'ATZ': 'ELM327 v1.5', 'ATE0': 'OK', 'ATL0': 'OK', 'ATS1': 'OK', 'ATH1': 'OK', 'ATAT1': 'OK', 'ATSP0': 'OK',
      'AT@1': '?', 'ATRV': '12.5V', 'ATDPN': 'A3', 'ATDP': 'ISO 9141-2',
      '0100': '48 6B 10 41 00 98 18 80 13 BC',
    });
    final c = ObdClient(transport: t, table: loadTable());
    await c.connect();
    expect((await c.readMonitorTests()).unsupportedReason, 'not_can');
    expect(t.sent.where((s) => s.startsWith('06')), isEmpty);
  });
}
