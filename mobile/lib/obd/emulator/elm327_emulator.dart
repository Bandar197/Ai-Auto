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
  Elm327Emulator(
    this.scenario,
    this.table, {
    Duration Function()? clock,
    int seed = 42,
    String? protocol,
    this.ignitionOn = true,
    bool engineRunning = true,
    this.startEngineAfterClearS,
    this.clearTimeScale = 1,
  })  : model = SignalModel(scenario, seed: seed),
        carProtocol = protocol ?? scenario.protocol,
        _clock = clock ?? _defaultClock() {
    model.engineRunning = engineRunning;
    _resetDtcs();
    reset();
  }

  static Duration Function() _defaultClock() {
    final sw = Stopwatch()..start();
    return () => sw.elapsed;
  }

  static const String description = 'AUTOMIND SIMULATOR';
  static const String engineEcu = '7E8';
  static const String tcmEcu = '7E9';
  static const Map<String, String> _can29Ids = {'7E8': '18DAF110', '7E9': '18DAF118'};
  static const Map<String, int> _legacySrc = {'7E8': 0x10, '7E9': 0x18};
  static const Map<String, String> _protoNames = {
    '1': 'SAE J1850 PWM',
    '2': 'SAE J1850 VPW',
    '3': 'ISO 9141-2',
    '4': 'ISO 14230-4 (KWP 5BAUD)',
    '5': 'ISO 14230-4 (KWP FAST)',
    '6': 'ISO 15765-4 (CAN 11/500)',
    '7': 'ISO 15765-4 (CAN 29/500)',
    '8': 'ISO 15765-4 (CAN 11/250)',
    '9': 'ISO 15765-4 (CAN 29/250)',
  };

  final Scenario scenario;
  final PidTable table;
  final SignalModel model;

  /// Protocol the simulated car speaks (scenario `protocol`, default 6).
  final String carProtocol;
  final Duration Function() _clock;

  /// Ignition OFF → the car does not answer at all.
  bool ignitionOn;

  bool echo = true;
  bool headers = false;
  bool spaces = true;
  bool linefeeds = false;
  String selectedProtocol = '0';
  String? activeProtocol;

  late List<String> stored;
  late List<String> pending;
  late List<String> permanent;
  Map<String, dynamic>? freezeFrame;
  bool monitorsComplete = true;

  // ---- post-clear behaviour (mirrors backend/automind/simulator) ----
  /// Codes that come back after a clear while the fault is still present.
  late final List<String> _faultCodes;

  /// Simulated time (s) of the last service 04, or null.
  double? clearedAt;

  /// Demo: the driver starts the engine this many (scaled) seconds after a clear.
  double? startEngineAfterClearS;

  /// Speeds up only the time since the clear (demo completes in seconds).
  double clearTimeScale;

  bool get engineRunning => model.engineRunning;
  set engineRunning(bool v) => model.engineRunning = v;

  String get _nl => linefeeds ? '\r\n' : '\r';

  void reset() {
    echo = true;
    linefeeds = false;
    spaces = true;
    headers = false;
    selectedProtocol = '0';
    activeProtocol = null;
  }

  void _resetDtcs() {
    final d = scenario.dtcs;
    stored = [for (final x in d) if (x.status == DtcStatus.stored) x.code];
    pending = [for (final x in d) if (x.status == DtcStatus.pending) x.code];
    // Same rule as the Python simulator: without explicit permanent codes,
    // the stored (emission) codes are also permanent. Mode 04 keeps them.
    final perm = [for (final x in d) if (x.status == DtcStatus.permanent) x.code];
    permanent = perm.isEmpty ? [...stored] : perm;
    freezeFrame = scenario.freezeFrame;
    _faultCodes = [for (final x in d) if (x.status == DtcStatus.stored || x.status == DtcStatus.pending) x.code];
  }

  /// Engine-running seconds since the clear (scaled), or null.
  double? _sinceClear(double t) {
    final c = clearedAt;
    if (c == null) return null;
    final dt = (t - c) * clearTimeScale;
    if (!model.engineRunning && startEngineAfterClearS != null && dt >= startEngineAfterClearS!) {
      model.engineRunning = true; // the driver starts the engine after clearing
    }
    if (!model.engineRunning) return null;
    return dt < 0 ? 0 : dt;
  }

  /// A fault that is still present is detected again (pending, then stored);
  /// monitors complete after a while; a repaired fault's permanent code erases itself.
  void _advanceAfterClear(double t) {
    final dt = _sinceClear(t);
    if (dt == null) return;
    if (scenario.faultActive) {
      for (final code in _faultCodes) {
        if (dt >= scenario.redetectStoredS && !stored.contains(code)) {
          stored.add(code);
          pending.remove(code);
        } else if (dt >= scenario.redetectPendingS && dt < scenario.redetectStoredS && !pending.contains(code)) {
          pending.add(code);
        }
      }
      if (dt >= scenario.redetectStoredS && stored.isNotEmpty) {
        permanent = ({...permanent, ...stored}.toList()..sort());
      }
    }
    if (dt >= scenario.monitorCompleteS) {
      monitorsComplete = true;
      if (!scenario.faultActive) permanent = [];
    }
  }

  double get _t => _clock().inMicroseconds / 1e6;

  Map<String, double> currentValues() => model.sample(_t);

  /// Processes one command line (without `\r`) and returns the full adapter
  /// output including echo and the final `>` prompt.
  String handle(String input) {
    final line = input.trim();
    final cmd = line.replaceAll(' ', '').toUpperCase();
    var out = echo ? '$line$_nl' : '';
    String body;
    if (cmd.isEmpty) {
      body = '';
    } else if (cmd.startsWith('AT')) {
      body = _at(cmd.substring(2));
    } else if (isHexString(cmd) && (cmd.length.isEven || cmd.length >= 3)) {
      body = _obd(cmd);
    } else {
      body = '?';
    }
    if (body.isNotEmpty) out += body.replaceAll('\r', _nl) + _nl;
    return '$out$_nl>';
  }

  // ---------------------------------------------------------------- AT

  String _at(String a) {
    switch (a) {
      case 'Z':
        reset();
        return '\r${scenario.firmware}';
      case 'WS':
        reset();
        return scenario.firmware;
      case 'I':
        return scenario.firmware;
      case '@1':
        return description;
      case 'RV':
        final v = ignitionOn ? (currentValues()['module_voltage'] ?? 12.6) : 12.6;
        return '${v.toStringAsFixed(1)}V';
      case 'E0':
      case 'E1':
        echo = a == 'E1';
        return 'OK';
      case 'L0':
      case 'L1':
        linefeeds = a == 'L1';
        return 'OK';
      case 'S0':
      case 'S1':
        spaces = a == 'S1';
        return 'OK';
      case 'H0':
      case 'H1':
        headers = a == 'H1';
        return 'OK';
      case 'DPN':
        if (activeProtocol == null) return selectedProtocol;
        return '${selectedProtocol == '0' ? 'A' : ''}$activeProtocol';
      case 'DP':
        if (activeProtocol == null) return 'AUTO';
        return '${selectedProtocol == '0' ? 'AUTO, ' : ''}${_protoNames[activeProtocol] ?? '?'}';
      case 'D':
      case 'PC':
      case 'CAF0':
      case 'CAF1':
      case 'M0':
        return 'OK';
    }
    if (RegExp(r'^[ST]P[0-9A-C]$').hasMatch(a)) {
      selectedProtocol = a[2];
      activeProtocol = a[2] == '0' ? null : a[2];
      return 'OK';
    }
    if (RegExp(r'^AT[0-2]$').hasMatch(a) || RegExp(r'^ST[0-9A-F]{2}$').hasMatch(a)) return 'OK';
    return '?';
  }

  // ---------------------------------------------------------------- OBD

  bool get _isCan => const ['6', '7', '8', '9'].contains(activeProtocol ?? carProtocol);
  bool get _is29 => const ['7', '9'].contains(activeProtocol);

  String _obd(String cmd) {
    var prefix = '';
    if (activeProtocol == null) {
      if ((selectedProtocol != '0' && selectedProtocol != carProtocol) || !ignitionOn) {
        return selectedProtocol == '0' ? 'SEARCHING...\rUNABLE TO CONNECT' : 'NO DATA';
      }
      activeProtocol = carProtocol;
      prefix = selectedProtocol == '0' ? 'SEARCHING...\r' : '';
    }
    if (!ignitionOn) return 'NO DATA';
    var c = cmd;
    if (c.length.isOdd) c = c.substring(0, c.length - 1); // response-count hint
    final req = parseHexBytes(c);
    if (req == null || req.isEmpty) return '?';
    final replies = _respond(req);
    if (replies.isEmpty) return '${prefix}NO DATA';
    return prefix + [for (final (ecu, payload) in replies) _format(ecu, payload)].join('\r');
  }

  List<(String, List<int>)> _respond(List<int> req) {
    final service = req[0];
    final rest = req.sublist(1);
    final out = <(String, List<int>)>[];
    switch (service) {
      case 0x01:
        if (rest.isEmpty) return out;
        for (final ecu in scenario.ecus) {
          final data = _mode01(ecu, rest[0]);
          if (data != null) out.add((ecu, [0x41, rest[0], ...data]));
        }
      case 0x02:
        if (rest.isEmpty) return out;
        final data = _mode02(rest[0]);
        if (data != null) out.add((engineEcu, [0x42, rest[0], 0x00, ...data]));
      case 0x03:
      case 0x07:
      case 0x0A:
        _advanceAfterClear(_t);
        final codes = service == 0x03 ? stored : (service == 0x07 ? pending : permanent);
        final body = [for (final c in codes) ...encodeDtc(c)];
        out.add((engineEcu, _isCan ? [service + 0x40, codes.length, ...body] : [service + 0x40, ...body]));
      case 0x04:
        stored = [];
        pending = [];
        freezeFrame = null;
        monitorsComplete = false;
        clearedAt = _t;
        out.add((engineEcu, [0x44]));
      case 0x09:
        if (rest.isEmpty) return out;
        final d = _mode09(rest[0]);
        if (d != null) out.add((engineEcu, [0x49, rest[0], ...d]));
    }
    return out;
  }

  Set<int> get _engineSupported => scenario.supportedPids('01').toSet();

  List<int> _mask(int base, Set<int> pids) {
    final m = encodeSupportedBitmask(base, pids);
    if (pids.any((p) => p > base + 0x20)) m[3] |= 0x01; // next range available
    return m;
  }

  List<int>? _mode01(String ecu, int pid) {
    if (ecu != engineEcu) {
      // Transmission ECU: answers only the supported-PID request.
      return pid == 0x00 ? [0x80, 0x00, 0x00, 0x00] : null;
    }
    final sup = _engineSupported;
    if (pid % 0x20 == 0) {
      if (pid == 0 || sup.any((p) => p > pid)) return _mask(pid, sup);
      return null;
    }
    if (!sup.contains(pid)) return null;
    _advanceAfterClear(_t);
    if (clearedAt != null && (pid == 0x30 || pid == 0x31 || pid == 0x4E)) {
      // Counters restart at the clear. (Python keeps the pre-clear value while
      // the engine is still off after a clear; here they read 0 until it runs.)
      final dt = _sinceClear(_t) ?? 0;
      if (pid == 0x30) return [dt >= scenario.monitorCompleteS ? 1 : 0];
      final x = pid == 0x31 ? (dt * 0.012).floor() : dt ~/ 60;
      return [(x >> 8) & 0xFF, x & 0xFF];
    }
    return _encodeValue(pid, currentValues());
  }

  List<int>? _encodeValue(int pid, Map<String, double> v) {
    switch (pid) {
      case 0x01:
        final a = (stored.isNotEmpty ? 0x80 : 0) | (stored.length > 0x7F ? 0x7F : stored.length);
        const c = 0x65;
        return [a, 0x07, c, monitorsComplete ? 0x00 : c];
      case 0x03:
        return [(v['fuel_system_1_status'] ?? 2).round(), (v['fuel_system_2_status'] ?? 0).round()];
      case 0x13:
        return [0x33];
      case 0x1C:
        return [0x01];
      case 0x21:
        return table.encode(pid, {'distance_mil_on': stored.isNotEmpty ? 42 : 0});
    }
    final def = table[pid];
    if (def == null || def.outputs.isEmpty) return null;
    final vals = <String, double>{};
    for (final o in def.outputs) {
      final x = v[o.key];
      if (x == null) {
        // O2 trim not applicable → 0xFF (like the Python simulator).
        if (o.key.startsWith('o2_') && o.key.endsWith('_stft')) continue;
        return null;
      }
      vals[o.key] = x;
    }
    final data = table.encode(pid, vals);
    for (final o in def.outputs) {
      if (!vals.containsKey(o.key)) data[o.start] = 0xFF;
    }
    return data;
  }

  List<int>? _mode02(int pid) {
    final ff = freezeFrame;
    if (ff == null) {
      if (pid == 0x00) return [0x40, 0x00, 0x00, 0x00]; // only PID 02 (= 0000)
      if (pid == 0x02) return [0x00, 0x00];
      return null;
    }
    final values = <String, double>{
      for (final e in (ff['values'] as Map<String, dynamic>? ?? const {}).entries) e.key: (e.value as num).toDouble(),
    };
    final pids = <int>{0x02};
    for (final k in values.keys) {
      final d = table.pidForKey(k);
      if (d != null) pids.add(d.pidByte);
    }
    if (pid == 0x00) return _mask(0, pids);
    if (pid == 0x02) return encodeDtc(ff['dtc'] as String);
    if (!pids.contains(pid)) return null;
    final def = table[pid];
    if (def == null) return null;
    final vals = <String, double>{};
    for (final o in def.outputs) {
      if (!values.containsKey(o.key)) return null;
      vals[o.key] = values[o.key]!;
    }
    return table.encode(pid, vals);
  }

  List<int>? _mode09(int pid) {
    final sup = scenario.supportedPids('09');
    switch (pid) {
      case 0x00:
        return encodeSupportedBitmask(0, sup);
      case 0x02:
        if (!sup.contains(0x02)) return null;
        return [0x01, ...scenario.vin.codeUnits];
      case 0x04:
        if (!sup.contains(0x04)) return null;
        return [0x01, ...'AMSIM-CAL-0001\x00\x00'.codeUnits];
    }
    return null;
  }

  // ---------------------------------------------------------------- framing

  String _hex(List<int> b) => toHex(b, spaces: spaces);

  String _format(String ecu, List<int> p) => _isCan ? _formatCan(ecu, p) : _formatLegacy(ecu, p);

  String _formatCan(String ecu, List<int> p) {
    final sep = spaces ? ' ' : '';
    var hid = ecu;
    if (_is29) {
      final id = _can29Ids[ecu] ?? ecu;
      hid = [for (var i = 0; i < 8; i += 2) id.substring(i, i + 2)].join(sep);
    }
    final frames = <List<int>>[];
    if (p.length <= 7) {
      frames.add([p.length, ...p]);
    } else {
      frames.add([0x10 | (p.length >> 8), p.length & 0xFF, ...p.sublist(0, 6)]);
      var rest = p.sublist(6);
      var seq = 1;
      while (rest.isNotEmpty) {
        final n = rest.length > 7 ? 7 : rest.length;
        frames.add([0x20 | (seq & 0x0F), ...rest.sublist(0, n)]);
        rest = rest.sublist(n);
        seq++;
      }
    }
    if (headers) {
      return [for (final f in frames) '$hid$sep${_hex([...f, ...List<int>.filled(8 - f.length, 0)])}'].join('\r');
    }
    // Headers off: ELM strips the PCI; multi-frame shows length + "n:" lines.
    if (frames.length == 1) return _hex(p);
    final lines = <String>[p.length.toRadixString(16).toUpperCase().padLeft(3, '0'), '0:$sep${_hex(p.sublist(0, 6))}'];
    var rest = p.sublist(6);
    var n = 1;
    while (rest.isNotEmpty) {
      final k = rest.length > 7 ? 7 : rest.length;
      lines.add('${(n & 0xF).toRadixString(16).toUpperCase()}:$sep${_hex(rest.sublist(0, k))}');
      rest = rest.sublist(k);
      n++;
    }
    return lines.join('\r');
  }

  String _formatLegacy(String ecu, List<int> p) {
    final header = [0x48, 0x6B, _legacySrc[ecu] ?? 0x10];
    final sid = p[0];
    final msgs = <List<int>>[];
    if (sid == 0x43 || sid == 0x47 || sid == 0x4A) {
      final body = p.sublist(1);
      for (var i = 0; i < (body.isEmpty ? 1 : body.length); i += 6) {
        final chunk = body.sublist(i, i + 6 > body.length ? body.length : i + 6);
        msgs.add([sid, ...chunk, ...List<int>.filled(6 - chunk.length, 0)]);
      }
    } else if (sid == 0x49 && p.length > 3) {
      var data = p.sublist(3); // legacy uses a message counter instead of a count byte
      data = [...List<int>.filled((4 - data.length % 4) % 4, 0), ...data];
      for (var i = 0; i < data.length ~/ 4; i++) {
        msgs.add([0x49, p[1], i + 1, ...data.sublist(i * 4, i * 4 + 4)]);
      }
    } else {
      msgs.add(p);
    }
    return [
      for (final m in msgs)
        headers ? _hex([...header, ...m, ([...header, ...m].fold<int>(0, (a, b) => a + b)) & 0xFF]) : _hex(m),
    ].join('\r');
  }
}
