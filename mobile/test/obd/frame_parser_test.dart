import 'package:automind_app/obd/obd.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CAN 11-bit', () {
    const p = FrameParser(family: ProtocolFamily.can11);

    test('single frames from two ECUs, spaces on', () {
      final msgs = p.parse(['7E8 06 41 00 BE 3F A8 13 00', '7E9 06 41 00 80 00 00 00 00']);
      expect(msgs, hasLength(2));
      expect(msgs[0].ecu, '7E8');
      expect(msgs[0].hex, '41 00 BE 3F A8 13');
      expect(msgs[1].ecu, '7E9');
      expect(msgs[1].hex, '41 00 80 00 00 00');
    });

    test('single frame, spaces off', () {
      final msgs = p.parse(['7E804410C1AF8AAAAAA']);
      expect(msgs.single.ecu, '7E8');
      expect(msgs.single.hex, '41 0C 1A F8');
    });

    test('multi-frame VIN with ISO-TP reassembly (out of order CF)', () {
      final msgs = p.parse([
        '7E8 10 14 49 02 01 31 47 31',
        '7E8 22 32 33 34 35 36 37 38',
        '7E8 21 4A 43 35 34 34 34 52',
      ]);
      expect(msgs.single.ecu, '7E8');
      expect(String.fromCharCodes(msgs.single.data.sublist(3)), '1G1JC5444R2345678');
      expect(msgs.single.data, hasLength(0x14));
    });

    test('multi-frame interleaved with another ECU single frame, spaces off', () {
      final msgs = p.parse([
        '7E81014490201314731',
        '7E9064900AABBCCDD00',
        '7E8214A433534343452',
        '7E8223233343536373800'.substring(0, 19),
      ]);
      final byEcu = {for (final m in msgs) m.ecu: m};
      expect(byEcu['7E9']!.hex, '49 00 AA BB CC DD');
      expect(String.fromCharCodes(byEcu['7E8']!.data.sublist(3)), '1G1JC5444R2345678');
    });
  });

  group('CAN 29-bit', () {
    test('single frame', () {
      const p = FrameParser(family: ProtocolFamily.can29);
      final msgs = p.parse(['18 DA F1 10 03 41 0D 32 00 00 00 00']);
      expect(msgs.single.ecu, '18DAF110');
      expect(msgs.single.hex, '41 0D 32');
    });

    test('auto-detected without protocol hint, multi-frame', () {
      const p = FrameParser();
      final msgs = p.parse([
        '18DAF1101014490201314731',
        '18DAF110214A433534343452',
        '18DAF1102232333435363738',
      ]);
      expect(msgs.single.ecu, '18DAF110');
      expect(String.fromCharCodes(msgs.single.data.sublist(3)), '1G1JC5444R2345678');
    });
  });

  group('legacy (J1850 / ISO 9141 / KWP)', () {
    test('ISO 9141 with valid checksum; source address is 3rd header byte', () {
      const p = FrameParser(family: ProtocolFamily.iso9141);
      // 48 6B 10 41 0C 1A F8 + checksum
      final bytes = [0x48, 0x6B, 0x10, 0x41, 0x0C, 0x1A, 0xF8];
      final sum = bytes.fold<int>(0, (a, b) => a + b) & 0xFF;
      final msgs = p.parse(['${toHex(bytes)} ${hex2(sum)}']);
      expect(msgs.single.ecu, '10');
      expect(msgs.single.hex, '41 0C 1A F8');
      expect(msgs.single.checksumOk, isTrue);
    });

    test('bad checksum is flagged', () {
      const p = FrameParser(family: ProtocolFamily.kwp);
      final msgs = p.parse(['48 6B 10 41 00 BE 3F A8 13 00']);
      expect(msgs.single.hex, '41 00 BE 3F A8 13');
      expect(msgs.single.checksumOk, isFalse);
    });

    test('auto-detected legacy, spaces off, multiple frames kept separate', () {
      const p = FrameParser();
      final msgs = p.parse(['486B104301060171000016', '486B1043030000000000F7']);
      expect(msgs, hasLength(2));
      expect(msgs[0].hex, '43 01 06 01 71 00 00');
      expect(msgs[0].ecu, '10');
    });
  });

  group('headers off', () {
    const p = FrameParser(family: ProtocolFamily.can11, headersOn: false);

    test('single line payload', () {
      final msgs = p.parse(['41 0C 1A F8']);
      expect(msgs.single.ecu, FrameParser.unknownEcu);
      expect(msgs.single.hex, '41 0C 1A F8');
    });

    test('CAN multi-frame 014 / 0: / 1: / 2:', () {
      final msgs = p.parse(['014', '0: 49 02 01 31 47 31', '1: 4A 43 35 34 34 34 52', '2: 32 33 34 35 36 37 38']);
      expect(msgs.single.data, hasLength(20));
      expect(String.fromCharCodes(msgs.single.data.sublist(3)), '1G1JC5444R2345678');
    });

    test('CAN multi-frame, spaces off', () {
      final msgs = p.parse(['014', '0:490201314731', '1:4A433534343452', '2:32333435363738']);
      expect(String.fromCharCodes(msgs.single.data.sublist(3)), '1G1JC5444R2345678');
    });
  });
}
