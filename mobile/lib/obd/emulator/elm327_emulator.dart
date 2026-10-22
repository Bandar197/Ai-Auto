import '../decode/dtc.dart';
import '../decode/pid_table.dart';
import '../hex.dart';
import 'scenario.dart';
import 'signal_model.dart';

/// In-process ELM327 v1.5 emulator speaking ISO 15765-4 CAN 11/500, driven
/// by a demo scenario. Mirrors the team's Python simulator
/// (`automind simulate`) so the same tests pass on both:
/// * case-insensitive, spaces ignored, `\r` terminated, replies end `\r\r>`;
/// * echo on until ATE0; ATZ/ATI → `ELM327 v1.5`; AT@1 → `AUTOMIND SIMULATOR`;
/// * first OBD request after ATSP0 is prefixed with `SEARCHING...`;
/// * engine ECU 7E8 supports the scenario PIDs; TCM 7E9 only answers 0100.
class Elm327Emulator {
  Elm327Emulator(this.scenario, this.table, {Duration Function()? clock, int seed = 42})
      : model = SignalModel(scenario, seed: seed),
        _clock = clock ?? _defaultClock() {
    _resetDtcs();
  }

  static Duration Function() _defaultClock() {
    final sw = Stopwatch()..start();
    return () => sw.elapsed;
  }

  static const String description = 'AUTOMIND SIMULATOR';
  static const String engineEcu = '7E8';
  static const String tcmEcu = '7E9';

  final Scenario scenario;
  final PidTable table;
  final SignalModel model;
  final Duration Function() _clock;

  bool echo = true;
  bool headers = false;
  bool spaces = true;
  String protocol = '0';
  bool _searchPending = true;

  late List<String> stored;
  late List<String> pending;
  late List<String> permanent;
  Map<String, dynamic>? freezeFrame;
  bool _cleared = false;

  bool get engineRunning => model.engineRunning;
  set engineRunning(bool v) => model.engineRunning = v;

  void _resetDtcs() {
    final d = scenario.dtcs;
    stored = [for (final x in d) if (x.status == DtcStatus.stored) x.code];
    pending = [for (final x in d) if (x.status == DtcStatus.pending) x.code];
    permanent = [for (final x in d) if (x.status == DtcStatus.permanent) x.code];
    freezeFrame = scenario.freezeFrame;
  }

  double get _t => _clock().inMicroseconds / 1e6;

  Map<String, double> currentValues() => model.sample(_t);

  /// Processes one command (without the trailing `\r`) and returns the full
  /// adapter output including echo and the final `>` prompt.
  String handle(String input) {
    final echoed = echo ? '$input\r' : '';
    final cmd = input.replaceAll(' ', '').replaceAll('\n', '').toUpperCase();
    if (cmd.isEmpty) return '$echoed>';
    final body = cmd.startsWith('AT') ? _at(cmd.substring(2)) : _obd(cmd);
    return '$echoed$body\r\r>';
  }

  // ---------------------------------------------------------------- AT

  static const List<String> _okPrefixes = [
    'L', 'M', 'AT', 'ST', 'SH', 'CAF', 'CFC', 'CRA', 'CF', 'CM', 'AL', 'NL', 'PC', 'BI', 'FE', 'IB', 'KW', 'D0', 'D1',
    'R0', 'R1', 'RA', 'SR', 'SW', 'WM', 'IIA', 'V0', 'V1', 'FC', 'TA', 'AMC', 'CSM', 'CEA', 'JE', 'JS', 'MT0', 'SS',
  ];

  String _at(String a) {
    switch (a) {
      case 'Z':
      case 'WS':
        echo = true;
        headers = false;
        spaces = true;
        protocol = '0';
        _searchPending = true;
        return scenario.firmware;
      case 'I':
        return scenario.firmware;
      case '@1':
        return description;
      case 'RV':
        return '${(currentValues()['module_voltage'] ?? 12.6).toStringAsFixed(1)}V';
      case 'DP':
        return protocol == '0' ? 'AUTO, ISO 15765-4 (CAN 11/500)' : 'ISO 15765-4 (CAN 11/500)';
      case 'DPN':
        return protocol == '0' ? 'A${scenario.protocol}' : protocol;
      case 'E0':
        echo = false;
        return 'OK';
      case 'E1':
        echo = true;
        return 'OK';
      case 'H0':
        headers = false;
        return 'OK';
      case 'H1':
        headers = true;
        return 'OK';
      case 'S0':
        spaces = false;
        return 'OK';
      case 'S1':
        spaces = true;
        return 'OK';
      case 'D':
        headers = false;
        spaces = true;
        return 'OK';
      case 'PC':
        return 'OK';
      case 'MA':
        return '?';
    }
    if (a.startsWith('SPA') || a.startsWith('TPA')) {
      protocol = '0';
      _searchPending = true;
      return 'OK';
    }
    if (a.startsWith('SP') || a.startsWith('TP')) {
      final p = a.substring(2);
      if (p.length != 1 || !isHexString(p)) return '?';
      protocol = p;
      _searchPending = p == '0';
      return 'OK';
    }
    for (final p in _okPrefixes) {
      if (a.startsWith(p)) return 'OK';
    }
    return '?';
  }

  // ---------------------------------------------------------------- OBD

  String _obd(String cmd) {
    var c = cmd;
    if (!isHexString(c)) return '?';
    if (c.length.isOdd) c = c.substring(0, c.length - 1); // response-count hint
    final req = parseHexBytes(c);
    if (req == null || req.isEmpty) return '?';
    final prefix = _searchPending ? 'SEARCHING...\r' : '';
    _searchPending = false;
    final replies = _respond(req);
    if (replies.isEmpty) return '${prefix}NO DATA';
    final lines = <String>[];
    for (final (ecu, payload) in replies) {
      lines.addAll(_format(ecu, payload));
    }
    return prefix + lines.join('\r');
  }

  List<(String, List<int>)> _respond(List<int> req) {
    final service = req[0];
    final out = <(String, List<int>)>[];
    switch (service) {
      case 0x01:
        final pids = req.sublist(1);
        if (pids.isEmpty) return out;
        final engine = <int>[0x41];
        final values = currentValues();
        for (final pid in pids) {
          final data = _mode01(pid, values);
          if (data != null) engine.addAll([pid, ...data]);
        }
        if (engine.length > 1) out.add((engineEcu, engine));
        if (pids.length == 1 && pids[0] == 0x00 && scenario.ecus.contains(tcmEcu)) {
          out.add((tcmEcu, [0x41, 0x00, 0x80, 0x00, 0x00, 0x00]));
        }
      case 0x02:
        if (req.length < 2) return out;
        final data = _mode02(req[1]);
        if (data != null) out.add((engineEcu, [0x42, req[1], req.length > 2 ? req[2] : 0, ...data]));
      case 0x03:
        out.add((engineEcu, _dtcList(0x43, stored)));
      case 0x07:
        out.add((engineEcu, _dtcList(0x47, pending)));
      case 0x0A:
        out.add((engineEcu, _dtcList(0x4A, permanent)));
      case 0x04:
        stored = [];
        pending = [];
        freezeFrame = null;
        _cleared = true;
        out.add((engineEcu, [0x44]));
      case 0x09:
        if (req.length < 2) return out;
        final d = _mode09(req[1]);
        if (d != null) out.add((engineEcu, [0x49, req[1], ...d]));
    }
    return out;
  }

  Set<int> get _engineSupported {
    final s = scenario.supportedPids('01').toSet();
    // Advertise the next bitmask PID when a higher PID exists.
    for (var base = 0x20; base <= 0xE0; base += 0x20) {
      if (s.any((p) => p > base)) s.add(base);
    }
    return s;
  }

  List<int>? _mode01(int pid, Map<String, double> v) {
    final sup = _engineSupported;
    if (pid % 0x20 == 0) {
      if (pid != 0 && !sup.contains(pid)) return null;
      return encodeSupportedBitmask(pid, sup);
    }
    if (!sup.contains(pid)) return null;
    return _encodeValue(pid, v);
  }

  List<int>? _encodeValue(int pid, Map<String, double> v) {
    switch (pid) {
      case 0x01:
        final mil = stored.isNotEmpty ? 0x80 : 0;
        return [mil | (stored.length & 0x7F), 0x07, 0xE5, 0x00];
      case 0x03:
        return [(v['fuel_system_1_status'] ?? 2).round(), (v['fuel_system_2_status'] ?? 0).round()];
      case 0x12:
        return [0x01];
      case 0x13:
        return [0x03];
      case 0x15:
        final d = table.encode(pid, {'o2_b1s2_voltage': v['o2_b1s2_voltage'] ?? 0.68});
        return [d[0], 0xFF];
      case 0x1C:
        return [0x01];
      case 0x21:
        return table.encode(pid, {'distance_mil_on': stored.isNotEmpty ? 37 : 0});
      case 0x30:
        return table.encode(pid, {'warmups_since_clear': _cleared ? 0 : (v['warmups_since_clear'] ?? 0)});
      case 0x31:
        return table.encode(pid, {'distance_since_clear': _cleared ? 0 : (v['distance_since_clear'] ?? 0)});
      case 0x41:
        return [0x00, 0x07, 0xE5, 0x00];
      case 0x51:
        return [0x01];
    }
    final def = table[pid];
    if (def == null || def.outputs.isEmpty) return null;
    final vals = <String, double>{};
    for (final o in def.outputs) {
      vals[o.key] = v[o.key] ?? (o.min != null && o.min! > 0 ? o.min! : 0);
    }
    return table.encode(pid, vals);
  }

  List<int>? _mode02(int pid) {
    final ff = freezeFrame;
    if (ff == null) return null;
    final values = <String, double>{
      for (final e in (ff['values'] as Map<String, dynamic>? ?? const {}).entries) e.key: (e.value as num).toDouble(),
    };
    final pids = <int>{0x02};
    for (final k in values.keys) {
      final d = table.pidForKey(k);
      if (d != null) pids.add(d.pidByte);
    }
    if (pid % 0x20 == 0) {
      final withNext = {...pids};
      for (var base = 0x20; base <= 0xE0; base += 0x20) {
        if (pids.any((p) => p > base)) withNext.add(base);
      }
      if (pid != 0 && !withNext.contains(pid)) return null;
      return encodeSupportedBitmask(pid, withNext);
    }
    if (pid == 0x02) {
      final dtc = ff['dtc'] as String?;
      return dtc == null ? [0, 0] : encodeDtc(dtc);
    }
    if (!pids.contains(pid)) return null;
    final def = table[pid];
    if (def == null) return null;
    final vals = <String, double>{for (final o in def.outputs) o.key: values[o.key] ?? 0};
    return table.encode(pid, vals);
  }

  List<int>? _mode09(int pid) {
    final sup = scenario.supportedPids('09');
    switch (pid) {
      case 0x00:
        return encodeSupportedBitmask(0, sup);
      case 0x02:
        if (!sup.contains(0x02)) return null;
        return [0x01, ...scenario.vin.padRight(17, '0').substring(0, 17).codeUnits];
      case 0x04:
        if (!sup.contains(0x04)) return null;
        final cal = 'AMSIM-CAL-0001'.padRight(16, '\x00');
        return [0x01, ...cal.codeUnits];
    }
    return null;
  }

  List<int> _dtcList(int sid, List<String> codes) => [sid, codes.length, for (final c in codes) ...encodeDtc(c)];

  // ---------------------------------------------------------------- framing

  List<String> _format(String ecu, List<int> payload) {
    String bytes(List<int> b) => toHex(b, spaces: spaces);
    String join(String a, String b) => spaces ? '$a $b' : '$a$b';
    List<int> pad(List<int> b) => [...b, ...List<int>.filled(8 - b.length, 0)];

    if (payload.length <= 7) {
      if (!headers) return [bytes(payload)];
      return [join(ecu, bytes(pad([payload.length, ...payload])))];
    }
    // ISO-TP multi-frame.
    final len = payload.length;
    final lines = <String>[];
    final first = payload.sublist(0, 6);
    final rest = payload.sublist(6);
    final cfs = <List<int>>[];
    for (var i = 0; i < rest.length; i += 7) {
      cfs.add(rest.sublist(i, i + 7 > rest.length ? rest.length : i + 7));
    }
    if (headers) {
      lines.add(join(ecu, bytes([0x10 | ((len >> 8) & 0x0F), len & 0xFF, ...first])));
      for (var i = 0; i < cfs.length; i++) {
        lines.add(join(ecu, bytes(pad([0x20 | ((i + 1) & 0x0F), ...cfs[i]]))));
      }
    } else {
      lines.add(len.toRadixString(16).toUpperCase().padLeft(3, '0'));
      lines.add('0:${spaces ? ' ' : ''}${bytes(first)}');
      for (var i = 0; i < cfs.length; i++) {
        final chunk = [...cfs[i], ...List<int>.filled(7 - cfs[i].length, 0)];
        lines.add('${((i + 1) & 0x0F).toRadixString(16).toUpperCase()}:${spaces ? ' ' : ''}${bytes(chunk)}');
      }
    }
    return lines;
  }
}
