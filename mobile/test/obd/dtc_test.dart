import 'package:automind_app/obd/obd.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('decode DTC bytes', () {
    expect(decodeDtc(0x01, 0x06), 'P0106');
    expect(decodeDtc(0xC1, 0x23), 'U0123');
    expect(decodeDtc(0x41, 0x71), 'C0171');
    expect(decodeDtc(0x81, 0x00), 'B0100');
    expect(decodeDtc(0x03, 0x02), 'P0302');
    expect(decodeDtc(0x11, 0x23), 'P1123');
    expect(decodeDtc(0x2A, 0xBC), 'P2ABC');
    expect(decodeDtc(0x00, 0x00), isNull);
  });

  test('encode round trip', () {
    for (final c in ['P0106', 'U0123', 'C0171', 'B3FFF', 'P0420']) {
      final b = encodeDtc(c);
      expect(decodeDtc(b[0], b[1]), c);
    }
  });

  test('CAN payload uses the count byte', () {
    expect(ObdServices.parseDtcPayload([0x43, 0x02, 0x01, 0x06, 0x01, 0x71], ProtocolFamily.can11), ['P0106', 'P0171']);
    expect(ObdServices.parseDtcPayload([0x43, 0x00], ProtocolFamily.can11), isEmpty);
  });

  test('legacy payload: 3 DTCs per frame, no count, 0000 skipped', () {
    expect(ObdServices.parseDtcPayload([0x43, 0x01, 0x06, 0x01, 0x71, 0x00, 0x00], ProtocolFamily.iso9141),
        ['P0106', 'P0171']);
  });

  test('unknown family uses heuristic', () {
    expect(ObdServices.parseDtcPayload([0x43, 0x01, 0x01, 0x06], ProtocolFamily.unknown), ['P0106']);
  });
}
