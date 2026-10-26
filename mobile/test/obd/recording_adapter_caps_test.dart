import 'package:automind_app/core/recording/export_service.dart';
import 'package:automind_app/obd/obd.dart';
import 'package:flutter_test/flutter_test.dart';

AdapterCapabilities _caps() => AdapterCapabilities(
      name: null,
      connection: 'ble',
      firmware: 'ELM327 v1.5',
      voltage: 12.4,
      protocol: 'ISO 15765-4 (CAN 11/500)',
      capabilities: {Capability.headers: true, Capability.flowControl: false, Capability.isoTp: null},
      evidence: {Capability.headers: Evidence.behavioral, Capability.flowControl: Evidence.acceptedOnly},
      notes: {Capability.flowControl: 'ATFCSM not supported (common on clones)'},
      probe: const [ProbeStep('ATI', 'ELM327 v1.5', true), ProbeStep('AT@1', '?', false)],
      probedAt: DateTime.utc(2026, 10, 25, 9),
    );

Recording _rec({AdapterCapabilities? caps}) => Recording(
      recordingId: 'rec-1',
      createdAt: DateTime.utc(2026, 10, 25, 10),
      dataMode: 'live',
      source: const {'kind': 'elm327_ble'},
      vehicle: const {'vin': '1HGCM82633A004352'},
      durationMs: 0,
      signals: const [],
      samples: const [],
      adapterCapabilities: caps,
    );

void main() {
  test('capabilities round-trip through recording JSON', () {
    final back = Recording.fromJsonString(_rec(caps: _caps()).toJsonString());
    final c = back.adapterCapabilities!;
    expect(c.usable(Capability.headers), isTrue);
    expect(c.usable(Capability.flowControl), isFalse);
    expect(c.capabilities[Capability.isoTp], isNull);
    expect(c.evidence[Capability.flowControl], Evidence.acceptedOnly);
    expect(c.probe.last.ok, isFalse);
    expect(c.probedAt, DateTime.utc(2026, 10, 25, 9));
  });

  test('no probe → no adapter_capabilities key (v1 files unchanged)', () {
    expect(_rec().toJson().containsKey('adapter_capabilities'), isFalse);
  });

  test('redactVin keeps the capabilities', () {
    expect(_rec(caps: _caps()).redactVin().adapterCapabilities, isNotNull);
  });

  test('recording.v2 export defaults to the probed capabilities', () {
    final j = ExportService.sessionV2(_rec(caps: _caps()));
    expect((j['adapter_capabilities'] as Map)['firmware'], 'ELM327 v1.5');
    expect(((j['adapter_capabilities'] as Map)['capabilities'] as Map)['flow_control'], isFalse);
    expect(ExportService.sessionV2(_rec())['adapter_capabilities'], isNull);
  });

  test('Recorder attaches capabilities to the built recording', () {
    final r = Recorder(
      dataMode: DataMode.live,
      sourceKind: 'elm327_ble',
      table: PidTable.fromJsonString('{"pids": []}'),
      newId: () => 'id-1',
    )..adapterCapabilities = _caps();
    expect(r.build().adapterCapabilities?.firmware, 'ELM327 v1.5');
  });
}
