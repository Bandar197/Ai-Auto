import '../storage/local_store.dart';
import '../storage/scan_report.dart';
import 'session_import.dart';
import 'session_journal.dart';

/// Turns every interrupted journal into a saved recording + a report marked
/// `interrupted` (local only — never auto-uploaded), then removes the journal. A
/// journal is removed only after both files are safely written; one that cannot be
/// read is left in place untouched.
Future<List<ScanReport>> recoverInterruptedSessions(LocalStore store) async {
  final out = <ScanReport>[];
  for (final f in await SessionJournal.interrupted(store.root)) {
    final rec = SessionJournal.recover(await f.readAsString());
    if (rec == null) continue;
    await store.saveRecording(rec);
    final report = localReportFor(rec, sessionState: 'interrupted');
    await store.saveReport(report);
    await f.delete();
    out.add(report);
  }
  return out;
}
