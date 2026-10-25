import 'package:automind_app/obd/obd.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('request builders', () {
    expect(buildReadDtcRequest(), '1902FF');
    expect(buildReadDtcRequest(0x08), '190208');
    expect(buildClearRequest(), '14FFFFFF');
    expect(buildClearRequest(0xFFFF33), '14FFFF33');
    expect(() => buildReadDtcRequest(0x100), throwsArgumentError);
    expect(() => buildClearRequest(0x1000000), throwsArgumentError);
  });

  test('parse airbag DTCs with status flags', () {
    // 59 02 FF, then B0051 (80 51) ftb 00 status 09 (confirmed+testFailed),
    // B1013 (90 13) ftb 11 status 08 (confirmed only).
    final data = udsHexToBytes('59 02 FF 80 51 00 09 90 13 11 08');
    final dtcs = parseReadDtcResponse(data);
    expect(dtcs.map((d) => d.code).toList(), ['B0051', 'B1013']);
    expect(dtcs[0].display, 'B0051');
    expect(dtcs[0].active, isTrue);
    expect(dtcs[0].confirmed, isTrue);
    expect(dtcs[1].display, 'B1013-11');
    expect(dtcs[1].active, isFalse);
    expect(dtcs[1].confirmed, isTrue);
  });

  test('empty and filler', () {
    expect(parseReadDtcResponse(udsHexToBytes('59 02 FF')), isEmpty);
    expect(parseReadDtcResponse(udsHexToBytes('59 02 FF 00 00 00 00')), isEmpty);
  });

  test('negative response surfaces NRC', () {
    try {
      parseReadDtcResponse(udsHexToBytes('7F 19 22'));
      fail('expected UdsException');
    } on UdsException catch (e) {
      expect(e.code, 'conditions_not_correct');
      expect(e.nrc, 0x22);
    }
  });

  test('wrong service rejected', () {
    expect(() => parseReadDtcResponse(udsHexToBytes('62 02 FF')), throwsA(isA<UdsException>()));
  });

  test('clear response', () {
    expect(parseClearResponse(udsHexToBytes('54')), isTrue);
    expect(parseClearResponse(const []), isFalse);
    expect(() => parseClearResponse(udsHexToBytes('7F 14 31')), throwsA(isA<UdsException>()));
  });
}
