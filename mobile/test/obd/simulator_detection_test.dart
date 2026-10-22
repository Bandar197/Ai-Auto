import 'package:automind_app/obd/obd.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

Map<String, String> _adapter(String description) => {
      'ATZ': 'ELM327 v1.5',
      'ATE0': 'ATE0\rOK',
      'ATL0': 'OK',
      'ATS1': 'OK',
      'ATH1': 'OK',
      'ATAT1': '?', // clone without adaptive timing: must continue
      'ATSP0': 'OK',
      'AT@1': description,
      'ATRV': '12.4V',
      '0100': 'SEARCHING...\r7E8 06 41 00 BE 3F A8 13 00',
      'ATDPN': 'A6',
      'ATDP': 'AUTO, ISO 15765-4 (CAN 11/500)',
    };

void main() {
  final table = loadTable();

  test('AT@1 = AUTOMIND SIMULATOR over TCP forces demo mode', () async {
    final client = ObdClient(transport: ScriptedTransport(_adapter('AUTOMIND SIMULATOR')), table: table);
    final r = await client.connect();
    expect(r.adapterOk && r.ecuOk, isTrue);
    expect(client.info.isSimulator, isTrue);
    expect(r.dataMode, DataMode.demo);
    expect(r.log.toJson()['data_mode'], 'demo');
    expect(r.log.toJson()['transport'], 'wifi_tcp');
  });

  test('a real adapter stays live and tolerates "?" to ATAT1', () async {
    final client = ObdClient(transport: ScriptedTransport(_adapter('OBDII to RS232 Interpreter')), table: table);
    final r = await client.connect();
    expect(r.dataMode, DataMode.live);
    expect(client.info.isSimulator, isFalse);
    expect(client.info.unsupportedAtCommands, ['ATAT1']);
    expect(client.info.voltage, 12.4);
    expect(client.info.protocolCode, '6');
  });

  test('UNABLE TO CONNECT → adapter connected, ECU no response', () async {
    final replies = _adapter('x')..['0100'] = 'SEARCHING...\rUNABLE TO CONNECT';
    final client = ObdClient(transport: ScriptedTransport(replies), table: table);
    final r = await client.connect();
    expect(r.adapterOk, isTrue);
    expect(r.ecuOk, isFalse);
    expect(client.currentStatus.adapter, AdapterState.connected);
    expect(client.currentStatus.ecu, EcuState.noResponse);
    expect(client.currentStatus.message, LinkMessage.ecuNoResponse);
    expect(r.log.ecuStatus, 'no_response');
    expect(r.log.errorCode, 'ecu_unable_to_connect');
  });

  test('CAN ERROR → bus error state', () async {
    final replies = _adapter('x')..['0100'] = 'CAN ERROR';
    final client = ObdClient(transport: ScriptedTransport(replies), table: table);
    final r = await client.connect();
    expect(r.log.ecuStatus, 'bus_error');
    expect(client.currentStatus.ecu, EcuState.busError);
  });

  test('silent adapter → 3 attempts then timeout', () async {
    final t = ScriptedTransport({}, silent: {'ATZ'});
    final client = ObdClient(
      transport: t,
      table: table,
      config: const ObdClientConfig(resetTimeout: Duration(milliseconds: 20), backoff: Duration.zero),
    );
    final r = await client.connect();
    expect(r.adapterOk, isFalse);
    expect(r.log.attempts, 3);
    expect(r.log.adapterStatus, 'timeout');
    expect(client.currentStatus.adapter, AdapterState.error);
  });
}
