import 'dart:async';

import 'package:automind_app/obd/obd.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

void main() {
  group('parseResponse', () {
    test('strips echo and SEARCHING...', () {
      final r = Elm327.parseResponse('0100', '0100\rSEARCHING...\r7E8 06 41 00 BE 3F A8 13 00\r');
      expect(r.ok, isTrue);
      expect(r.searched, isTrue);
      expect(r.lines, ['7E8 06 41 00 BE 3F A8 13 00']);
    });

    test('strips BUS INIT: ...OK', () {
      final r = Elm327.parseResponse('0100', 'BUS INIT: ...OK\r48 6B 10 41 00 BE 3F A8 13 C6\r');
      expect(r.lines, ['48 6B 10 41 00 BE 3F A8 13 C6']);
    });

    final errors = {
      'NO DATA': ElmErrorKind.noData,
      'UNABLE TO CONNECT': ElmErrorKind.unableToConnect,
      'BUS INIT: ...ERROR': ElmErrorKind.busInitError,
      'CAN ERROR': ElmErrorKind.canError,
      'BUS ERROR': ElmErrorKind.busError,
      'BUFFER FULL': ElmErrorKind.bufferFull,
      'STOPPED': ElmErrorKind.stopped,
      '?': ElmErrorKind.unknownCommand,
      'LV RESET': ElmErrorKind.lowVoltageReset,
    };
    errors.forEach((text, kind) {
      test('maps "$text"', () {
        final r = Elm327.parseResponse('010C', 'SEARCHING...\r$text\r');
        expect(r.ok, isFalse);
        expect(r.error, kind);
        expect(r.lines, isEmpty);
      });
    });

    test('vehicle-side vs adapter-side classification', () {
      expect(ElmErrorKind.noData.isVehicleSide, isTrue);
      expect(ElmErrorKind.timeout.isVehicleSide, isFalse);
    });
  });

  group('command queue over a transport', () {
    test('one command in flight, replies matched in order', () async {
      final t = ScriptedTransport({'ATI': 'ELM327 v1.5', '010C': '41 0C 1A F8', '010D': '41 0D 00'});
      await t.connect();
      final elm = Elm327(t)..attach();
      final results = await Future.wait([elm.send('ATI'), elm.send('010C'), elm.send('01 0d')]);
      expect(results[0].text, 'ELM327 v1.5');
      expect(results[1].lines, ['41 0C 1A F8']);
      expect(results[2].lines, ['41 0D 00']);
      expect(t.sent, ['ATI', '010C', '010D']);
    });

    test('timeout is reported and the next command still works', () async {
      final t = ScriptedTransport({'ATI': 'ELM327 v1.5'}, silent: {'010C'});
      await t.connect();
      final elm = Elm327(t, defaultTimeout: const Duration(milliseconds: 50))..attach();
      final r = await elm.send('010C');
      expect(r.error, ElmErrorKind.timeout);
      expect(elm.consecutiveTimeouts, 1);
      final ok = await elm.send('ATI');
      expect(ok.text, 'ELM327 v1.5');
      expect(elm.consecutiveTimeouts, 0);
    });

    test('write services other than read-only ones are refused', () async {
      final t = ScriptedTransport({});
      await t.connect();
      final elm = Elm327(t)..attach();
      expect(() => elm.send('04'), throwsA(isA<PolicyViolationException>()));
      expect(() => elm.send('2E F1 90 00'), throwsA(isA<PolicyViolationException>()));
      expect(() => elm.send('3101FF00'), throwsA(isA<PolicyViolationException>()));
      expect(t.sent, isEmpty);
    });

    test('transport closing completes pending command with transportClosed', () async {
      final t = ScriptedTransport({}, silent: {'0100'});
      await t.connect();
      final elm = Elm327(t)..attach();
      final lost = Completer<void>();
      elm.onTransportLost.listen((_) => lost.complete());
      final f = elm.send('0100');
      await Future<void>.delayed(const Duration(milliseconds: 10));
      await t.close();
      final r = await f;
      expect(r.error, ElmErrorKind.transportClosed);
      await lost.future;
    });
  });
}
