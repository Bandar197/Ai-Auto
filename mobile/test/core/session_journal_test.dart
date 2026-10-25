import 'dart:io';

import 'package:automind_app/core/recording/journal_recovery.dart';
import 'package:automind_app/core/recording/session_journal.dart';
import 'package:automind_app/core/storage/local_store.dart';
import 'package:automind_app/obd/obd.dart';
import 'package:flutter_test/flutter_test.dart';

import '../obd/helpers.dart';

void main() {
  late Directory dir;
  late LocalStore store;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('automind_journal');
    store = LocalStore(dir);
  });
  tearDown(() => dir.deleteSync(recursive: true));

  Map<String, dynamic> header({String id = 'rec-1', String mode = 'demo'}) => {
        'recording_id': id,
        'created_at': '2026-10-25T10:00:00.000Z',
        'data_mode': mode,
        'source': {'kind': 'simulator', 'app': 'test'},
      };

  test('a journal closed without end is offered for recovery; a completed one is removed', () async {
    final a = await SessionJournal.start(dir, header(id: 'a'));
    a.write({'type': 'event', 'e': {'t_ms': 10, 'type': 'note', 'detail': 'x'}});
    await a.close();
    final b = await SessionJournal.start(dir, header(id: 'b'));
    await b.complete();
    expect(await b.file.exists(), isFalse);
    final open = await SessionJournal.start(dir, header(id: 'c')); // still being written
    final found = await SessionJournal.interrupted(dir);
    expect(found.map((f) => f.uri.pathSegments.last), ['a.jsonl']);
    await open.complete();
  });

  test('recovery keeps data_mode, snapshot, samples, frames and marks the interruption', () async {
    final j = await SessionJournal.start(dir, header(mode: 'demo'));
    j
      ..write({
        'type': 'snapshot',
        'r': {
          'vehicle': {'vin': 'KMHEC41CBCA123456'},
          'dtcs': [const Dtc('P0106', DtcStatus.stored, ecu: '7E8').toJson()],
        },
      })
      ..write({'type': 'sample', 's': {'t_ms': 500, 'pid': '010C', 'ecu': '7E8', 'raw': '41 0C 0C 30', 'values': {'engine_rpm': 780.0}}})
      ..write({'type': 'frame', 'f': const TxRxFrame(tMs: 900, dir: 'tx', data: '0105').toJson()});
    await j.close();
    // Simulate a crash mid-write: a torn last line.
    await j.file.writeAsString('{"type":"sample","s":{"t_ms":9', mode: FileMode.append);

    final rec = SessionJournal.recover(await j.file.readAsString())!;
    expect(rec.dataMode, 'demo'); // never relabelled
    expect(rec.recordingId, 'rec-1');
    expect(rec.dtcs.single.code, 'P0106');
    expect(rec.samples.single.values['engine_rpm'], 780);
    expect(rec.signals.single.key, 'engine_rpm');
    expect(rec.txRxFrames.single.data, '0105');
    expect(rec.durationMs, 900);
    expect(rec.events.last.type, 'session_interrupted');
  });

  test('no valid start line → nothing to recover', () {
    expect(SessionJournal.recover('garbage\n{"type":"sample"}'), isNull);
  });

  test('recoverInterruptedSessions saves recording + interrupted local-only report, then removes the journal', () async {
    final j = await SessionJournal.start(dir, header(mode: 'live'));
    j.write({'type': 'snapshot', 'r': {'dtcs': [const Dtc('P0300', DtcStatus.stored).toJson()]}});
    await j.close();
    final reports = await recoverInterruptedSessions(store);
    expect(reports.length, 1);
    final r = reports.single;
    expect(r.interrupted, isTrue);
    expect(r.uploadState, 'local_only'); // never auto-uploaded
    expect(r.dataMode, 'live');
    expect(r.dtcs.single['code'], 'P0300');
    expect((await store.loadReport(r.id))!.interrupted, isTrue);
    expect(await store.loadRecording('rec-1'), isNotNull);
    expect(await j.file.exists(), isFalse);
    expect(await SessionJournal.interrupted(dir), isEmpty);
  });

  test('Recorder feeds the journal: what was captured before a crash comes back', () async {
    final t = ScriptedTransport({'0100': '41 00 BE 3F A8 13'});
    await t.connect();
    final elm = Elm327(t)..attach();
    final rec = Recorder(dataMode: DataMode.live, sourceKind: 'elm327_ble', table: loadTable(), newId: () => 'rec-9');
    final j = await SessionJournal.start(dir, rec.journalHeader());
    rec.onEntry = j.write;
    rec.attachTraffic(elm.log);
    rec.dtcs = [const Dtc('P0420', DtcStatus.stored)];
    rec.checkpoint();
    rec.addEvent('note', 'before crash');
    await elm.send('0100');
    await Future<void>.delayed(Duration.zero);
    await rec.detachTraffic();
    await j.close(); // app dies here — no build(), no save

    final back = SessionJournal.recover(await j.file.readAsString())!;
    expect(back.recordingId, 'rec-9');
    expect(back.dataMode, 'live');
    expect(back.dtcs.single.code, 'P0420');
    expect(back.events.any((e) => e.detail == 'before crash'), isTrue);
    expect(back.txRxFrames.map((f) => f.data), contains('0100'));
  });
}
