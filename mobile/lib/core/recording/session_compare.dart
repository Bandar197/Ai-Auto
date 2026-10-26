import '../../obd/obd.dart';

/// Change of one fault code between an earlier session [a] and a later one [b].
enum CodeChange { newCode, resolved, persisting }

class CodeDiff {
  const CodeDiff(this.code, this.change, {this.module});
  final String code;
  final CodeChange change;

  /// Module key for non-powertrain codes (SRS/ABS/…); null for standard OBD codes.
  final String? module;
}

/// A module whose read outcome differs (e.g. "no response" before, "read" after).
class ModuleChange {
  const ModuleChange(this.key, this.before, this.after);
  final String key;
  final String? before; // wire outcome, null = not attempted in that session
  final String? after;
}

/// Honest comparison: a code only counts as "resolved" when the later session
/// actually READ that module/OBD successfully. If the later read failed, the code
/// is listed under [unverified] — never as fixed.
class SessionDiff {
  const SessionDiff({
    required this.codes,
    required this.modules,
    required this.unverified,
    required this.mixedModes,
  });

  final List<CodeDiff> codes;
  final List<ModuleChange> modules;

  /// Codes from [a] that could not be checked in [b] (module not read).
  final List<CodeDiff> unverified;

  /// Comparing a live session with a demo one (shown as a warning).
  final bool mixedModes;

  Iterable<CodeDiff> of(CodeChange c) => codes.where((d) => d.change == c);
}

SessionDiff compareSessions(Recording a, Recording b) {
  final codes = <CodeDiff>[];
  final unverified = <CodeDiff>[];

  // Standard OBD codes: the later session read OBD if it has any OBD data at all.
  final aObd = {for (final d in a.dtcs) d.code};
  final bObd = {for (final d in b.dtcs) d.code};
  final bReadObd = b.dtcs.isNotEmpty || b.samples.isNotEmpty || b.supportedPids.isNotEmpty;
  for (final c in {...aObd, ...bObd}) {
    if (aObd.contains(c) && bObd.contains(c)) {
      codes.add(CodeDiff(c, CodeChange.persisting));
    } else if (bObd.contains(c)) {
      codes.add(CodeDiff(c, CodeChange.newCode));
    } else if (bReadObd) {
      codes.add(CodeDiff(c, CodeChange.resolved));
    } else {
      unverified.add(CodeDiff(c, CodeChange.resolved));
    }
  }

  // Modules (SRS/ABS/body): keyed by module key.
  final aMods = {for (final m in a.moduleScans) m.key: m};
  final bMods = {for (final m in b.moduleScans) m.key: m};
  final modules = <ModuleChange>[];
  for (final key in {...aMods.keys, ...bMods.keys}) {
    final ma = aMods[key], mb = bMods[key];
    if (ma?.outcome != mb?.outcome) modules.add(ModuleChange(key, ma?.outcome, mb?.outcome));
    final ca = {for (final d in ma?.codes ?? const <Dtc>[]) d.code};
    final cb = {for (final d in mb?.codes ?? const <Dtc>[]) d.code};
    final bRead = mb != null && (mb.outcome == 'read_codes' || mb.outcome == 'read_no_codes');
    for (final c in {...ca, ...cb}) {
      if (ca.contains(c) && cb.contains(c)) {
        codes.add(CodeDiff(c, CodeChange.persisting, module: key));
      } else if (cb.contains(c)) {
        codes.add(CodeDiff(c, CodeChange.newCode, module: key));
      } else if (bRead) {
        codes.add(CodeDiff(c, CodeChange.resolved, module: key));
      } else {
        unverified.add(CodeDiff(c, CodeChange.resolved, module: key));
      }
    }
  }
  codes.sort((x, y) => x.code.compareTo(y.code));
  return SessionDiff(codes: codes, modules: modules, unverified: unverified, mixedModes: a.dataMode != b.dataMode);
}
