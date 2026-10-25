import 'package:automind_app/obd/obd.dart';
import 'package:flutter_test/flutter_test.dart';

/// Module-scan outcomes must survive the trip into a recording honestly: a module
/// that did not answer or refused never carries codes, and outcomes map to the
/// wire strings the backend report expects.
ModuleScan _scan(ModuleOutcome outcome, {List<UdsDtc> dtcs = const [], int reqId = 0x7D0, int idBits = 11}) => ModuleScan(
      module: UdsModule(
        key: 'srs', nameEn: 'Airbag (SRS)', nameAr: 'الإيرباق',
        requestId: reqId, responseId: reqId + 8, idBits: idBits, category: ModuleCategory.airbag,
      ),
      dtcs: dtcs,
      outcome: outcome,
    );

void main() {
  test('outcome enum maps to the backend wire strings', () {
    expect(moduleOutcomeWire(ModuleOutcome.readSuccessCodes), 'read_codes');
    expect(moduleOutcomeWire(ModuleOutcome.readSuccessNoCodes), 'read_no_codes');
    expect(moduleOutcomeWire(ModuleOutcome.refused), 'refused');
    expect(moduleOutcomeWire(ModuleOutcome.noResponse), 'no_response');
  });

  test('a read with codes keeps them; address is hex-formatted', () {
    final r = RecordingModuleScan.fromScan(_scan(
      ModuleOutcome.readSuccessCodes,
      dtcs: const [UdsDtc(code: 'B0051', ftb: 0, status: 0x09, flags: ['confirmed'])],
    ));
    expect(r.outcome, 'read_codes');
    expect(r.address, '7D0');
    expect(r.category, 'airbag');
    expect(r.codes.single.code, 'B0051');
  });

  test('no_response and refused never carry codes', () {
    final noResp = RecordingModuleScan.fromScan(_scan(
      ModuleOutcome.noResponse,
      dtcs: const [UdsDtc(code: 'B0051', ftb: 0, status: 0x09, flags: ['confirmed'])],
    ));
    expect(noResp.outcome, 'no_response');
    expect(noResp.codes, isEmpty);
    final refused = RecordingModuleScan.fromScan(_scan(ModuleOutcome.refused));
    expect(refused.outcome, 'refused');
    expect(refused.codes, isEmpty);
  });

  test('29-bit module address pads to 8 nibbles', () {
    final r = RecordingModuleScan.fromScan(_scan(ModuleOutcome.readSuccessNoCodes, reqId: 0x18DA58F1, idBits: 29));
    expect(r.address, '18DA58F1');
  });

  test('recording round-trips module_scans through JSON', () {
    final rec = Recording(
      recordingId: 'r1', createdAt: DateTime.utc(2026), dataMode: 'live',
      source: const {'kind': 'elm327_wifi'}, durationMs: 0, signals: const [], samples: const [],
      moduleScans: [
        RecordingModuleScan.fromScan(_scan(ModuleOutcome.noResponse)),
        RecordingModuleScan.fromScan(_scan(
          ModuleOutcome.readSuccessCodes,
          dtcs: const [UdsDtc(code: 'B0051', ftb: 0, status: 0x09, flags: ['confirmed'])],
        )),
      ],
    );
    final back = Recording.fromJsonString(rec.toJsonString());
    expect(back.moduleScans.length, 2);
    expect(back.moduleScans[0].outcome, 'no_response');
    expect(back.moduleScans[1].codes.single.code, 'B0051');
    // redactVin() (the default upload path when VIN is excluded) must keep module scans.
    expect(rec.redactVin().moduleScans.length, 2);
    expect(rec.redactVin().toJson().containsKey('module_scans'), isTrue);

    // A recording with no module scans omits the key entirely.
    final bare = Recording(
      recordingId: 'r2', createdAt: DateTime.utc(2026), dataMode: 'live',
      source: const {'kind': 'simulator'}, durationMs: 0, signals: const [], samples: const [],
    );
    expect(bare.toJson().containsKey('module_scans'), isFalse);
  });
}
