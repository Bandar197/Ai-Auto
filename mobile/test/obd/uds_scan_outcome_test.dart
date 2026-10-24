import 'package:automind_app/obd/obd.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

/// scanModules must classify each module honestly: a no-answer or refusal is never
/// turned into "no faults". One candidate per scan (the scripted transport maps by command).
Future<List<ModuleScan>> scanOne(String readReply, {bool includeNoResponse = true}) async {
  final t = ScriptedTransport({'1902FF': readReply});
  final elm = Elm327(t);
  await t.connect();
  elm.attach();
  const m = UdsModule(
    key: 'srs', nameEn: 'SRS', nameAr: 'SRS',
    requestId: 0x7D0, responseId: 0x7D8, category: ModuleCategory.airbag,
  );
  return scanModules(elm, candidates: const [m], includeNoResponse: includeNoResponse);
}

void main() {
  test('positive response with codes → readSuccessCodes', () async {
    final r = await scanOne('59 02 FF 80 51 00 09');
    expect(r.single.outcome, ModuleOutcome.readSuccessCodes);
    expect(r.single.readOk, isTrue);
    expect(r.single.dtcs.single.code, 'B0051');
  });

  test('positive response, zero codes → readSuccessNoCodes (the only honest "no faults")', () async {
    final r = await scanOne('59 02 FF');
    expect(r.single.outcome, ModuleOutcome.readSuccessNoCodes);
    expect(r.single.readOk, isTrue);
  });

  test('negative response → refused, never readOk', () async {
    final r = await scanOne('7F 19 22');
    expect(r.single.outcome, ModuleOutcome.refused);
    expect(r.single.readOk, isFalse);
  });

  test('no answer → noResponse, never readOk; dropped unless includeNoResponse', () async {
    final shown = await scanOne('NO DATA');
    expect(shown.single.outcome, ModuleOutcome.noResponse);
    expect(shown.single.readOk, isFalse);
    final hidden = await scanOne('NO DATA', includeNoResponse: false);
    expect(hidden, isEmpty);
  });
}
