import 'package:automind_app/obd/obd.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

void main() {
  test('pending line is skipped in favour of the final answer', () {
    expect(udsPayload('7F 19 78\r59 02 FF 90 01 00 09', 0x19), [0x59, 0x02, 0xFF, 0x90, 0x01, 0x00, 0x09]);
    expect(udsPayload('7F 19 78', 0x19), isEmpty);
    expect(udsPending('7F 19 78', 0x19), isTrue);
    expect(udsPayload('7F 19 33', 0x19), [0x7F, 0x19, 0x33]);
  });

  test('ISO-TP multi-frame is reassembled and cut to its length', () {
    const raw = '00B\r0: 59 02 FF 90 01 00\r1: 09 41 23 00 08 AA AA';
    expect(udsPayload(raw, 0x19), [0x59, 0x02, 0xFF, 0x90, 0x01, 0x00, 0x09, 0x41, 0x23, 0x00, 0x08]);
    final dtcs = parseReadDtcResponse(udsPayload(raw, 0x19));
    expect(dtcs.map((d) => d.code), ['B1001', 'C0123']);
  });

  const m = UdsModule(key: 'srs', nameEn: 'SRS', nameAr: 'x', requestId: 0x7D0, responseId: 0x7D8, category: ModuleCategory.airbag);
  Map<String, String> addr(Map<String, String> extra) => {
        'ATSH7D0': 'OK', 'ATCRA7D8': 'OK', 'ATH0': 'OK', 'ATH1': 'OK', 'ATCRA': 'OK', 'ATSH7DF': 'OK', ...extra,
      };

  test('a refusal keeps its NRC; no answer is never "no faults"', () async {
    final t = ScriptedTransport(addr({'1902FF': '7F 19 33'}));
    await t.connect();
    final elm = Elm327(t)..attach();
    final r = (await scanModules(elm, candidates: const [m], includeNoResponse: true)).single;
    expect(r.outcome, ModuleOutcome.refused);
    expect(r.nrc, 0x33);
    expect(RecordingModuleScan.fromScan(r).nrc, 0x33);
  });

  test('only "pending" every time → re-asked twice, then no response (not "no faults")', () async {
    final t = ScriptedTransport(addr({'1902FF': '7F 19 78'}));
    await t.connect();
    final elm = Elm327(t)..attach();
    final r = (await scanModules(elm, candidates: const [m], includeNoResponse: true)).single;
    expect(r.outcome, ModuleOutcome.noResponse);
    expect(t.sent.where((s) => s == '1902FF').length, 3);
  });
}
