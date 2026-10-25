import 'package:automind_app/core/recording/export_service.dart';
import 'package:automind_app/obd/obd.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

void main() {
  test('every command/reply becomes a TX and an RX frame with timing', () async {
    final t = ScriptedTransport({'ATI': 'ELM327 v1.5', '0100': '41 00 BE 3F A8 13'}, silent: {'0105'});
    await t.connect();
    final elm = Elm327(t, defaultTimeout: const Duration(milliseconds: 60))..attach();
    final tap = TrafficTap(startedAt: DateTime.now().toUtc())..attach(elm.log);
    await elm.send('ATI');
    await elm.send('0100');
    await elm.send('0105'); // no answer → timeout
    await Future<void>.delayed(Duration.zero);
    await tap.detach();
    final f = tap.frames;
    expect(f.map((x) => x.dir), ['tx', 'rx', 'tx', 'rx', 'tx', 'rx']);
    expect(f[0].data, 'ATI');
    expect(f[1].data, contains('ELM327 v1.5'));
    expect(f[3].data, contains('41 00 BE 3F A8 13'));
    expect(f[5].timeout, isTrue);
    expect(f[1].durationMs, isNotNull);
    for (var i = 1; i < f.length; i++) {
      expect(f[i].tMs, greaterThanOrEqualTo(f[i - 1].tMs));
    }
  });

  test('cap stops capture and marks truncated', () {
    final tap = TrafficTap(startedAt: DateTime.utc(2026), maxFrames: 3, now: () => DateTime.utc(2026));
    const r = ElmResponse(command: 'ATI', raw: 'X', lines: ['X'], elapsed: Duration.zero);
    tap
      ..add(r)
      ..add(r);
    expect(tap.frames.length, 3);
    expect(tap.truncated, isTrue);
  });

  test('VIN replies are masked for sharing, other frames untouched', () {
    const frames = [
      TxRxFrame(tMs: 0, dir: 'tx', data: '0902'),
      TxRxFrame(tMs: 5, dir: 'rx', data: '49 02 01 4B 4D 48'),
      TxRxFrame(tMs: 6, dir: 'tx', data: '0100'),
      TxRxFrame(tMs: 9, dir: 'rx', data: '41 00 BE 3F A8 13'),
    ];
    final m = maskVinTraffic(frames);
    expect(m[1].data, '[VIN masked]');
    expect(m[0].data, '0902');
    expect(m[3].data, '41 00 BE 3F A8 13');
  });

  Recording rec() => Recording(
        recordingId: 'r',
        createdAt: DateTime.utc(2026),
        dataMode: 'live',
        source: const {'kind': 'elm327_ble'},
        durationMs: 0,
        signals: const [],
        samples: const [],
        vehicle: const {'vin': 'KMHEC41CBCA123456'},
        txRxFrames: const [
          TxRxFrame(tMs: 0, dir: 'tx', data: '0902'),
          TxRxFrame(tMs: 5, dir: 'rx', data: '014\r0: 49 02 01 4B 4D 48', durationMs: 5),
        ],
      );

  test('frames round-trip locally but never go out with an upload', () {
    final back = Recording.fromJsonString(rec().toJsonString());
    expect(back.txRxFrames.length, 2);
    expect(back.txRxFrames[1].data, '014\r0: 49 02 01 4B 4D 48');
    expect(rec().redactVin().txRxFrames, isEmpty);
    expect(rec().redactVin().toJson().containsKey('tx_rx_frames'), isFalse);
  });

  test('raw.log keeps one frame per line and masks VIN when sharing', () {
    final log = ExportService.rawLog(rec());
    expect(log.trim().split('\n').length, 2);
    expect(log, contains(r'014\r0: 49 02'));
    expect(log, contains('5ms'));
    expect(ExportService.rawLog(rec(), maskVin: true), contains('[VIN masked]'));
    final v2 = ExportService.sessionV2(rec(), maskVin: true);
    expect(((v2['tx_rx_frames'] as List)[1] as Map)['data'], '[VIN masked]');
  });
}
