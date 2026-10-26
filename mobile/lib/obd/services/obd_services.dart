import '../decode/dtc.dart';
import '../decode/monitor_tests.dart';
import '../decode/pid_table.dart';
import '../elm327/elm327.dart';
import '../hex.dart';
import '../protocol/frame_parser.dart';
import '../protocol/protocol.dart';
import 'obd_models.dart';

export 'obd_models.dart';

/// Read-only SAE J1979 services on top of [Elm327]. No write requests
/// are possible from here (service 04 lives in the client, approval-gated).
class ObdServices {
  ObdServices(this.elm, this.table, {this.family = ProtocolFamily.unknown, this.headersOn = true});

  final Elm327 elm;
  final PidTable table;
  ProtocolFamily family;
  bool headersOn;

  FrameParser get parser => FrameParser(family: family, headersOn: headersOn);

  /// Sends [cmd] and returns the parsed messages (empty on NO DATA etc).
  Future<(ElmResponse, List<ObdMessage>)> request(String cmd, {Duration? timeout}) async {
    final r = await elm.send(cmd, timeout: timeout);
    if (!r.ok) return (r, const <ObdMessage>[]);
    return (r, parser.parse(r.lines));
  }

  /// Positive responses for [service] (+0x40) and optional [pid], skipping
  /// negative responses (`7F xx yy`).
  static List<ObdMessage> positive(List<ObdMessage> msgs, int service, [int? pid]) => [
        for (final m in msgs)
          if (m.data.isNotEmpty && m.data[0] == service + 0x40 && (pid == null || (m.data.length > 1 && m.data[1] == pid)))
            m,
      ];

  /// Walks 0100, 0120, 0140… while bit 0x20 of the previous block is set
  /// by any ECU. Never assumes a PID exists.
  Future<SupportedPids> supportedPids() async {
    final byEcu = <String, Set<int>>{};
    var base = 0x00;
    while (base <= 0xC0) {
      final cmd = '01${hex2(base)}';
      final (_, msgs) = await request(cmd, timeout: base == 0 ? elm.searchTimeout : null);
      final pos = positive(msgs, 0x01, base);
      if (pos.isEmpty) break;
      var cont = false;
      for (final m in pos) {
        if (m.data.length < 6) continue;
        final pids = decodeSupportedBitmask(base, m.data.sublist(2, 6));
        byEcu.putIfAbsent(m.ecu, () => <int>{}).addAll(pids);
        if (pids.contains(base + 0x20)) cont = true;
      }
      if (!cont) break;
      base += 0x20;
    }
    // Service 09 support (VIN etc.) from the primary ECU set.
    final s09 = <int>{};
    final (_, m09) = await request('0900');
    for (final m in positive(m09, 0x09, 0x00)) {
      // CAN: 49 00 aa bb cc dd ; legacy may include a count byte → take last 4.
      if (m.data.length >= 6) s09.addAll(decodeSupportedBitmask(0, m.data.sublist(m.data.length - 4)));
    }
    return SupportedPids(byEcu, service09: s09);
  }

  /// Service 06 (CAN only): supported MIDs via 0600/0620/…, then every test result.
  /// Read-only; legacy-protocol 06 replies use another layout and are reported as
  /// unsupported rather than mis-decoded.
  Future<MonitorTestReport> readMonitorTests() async {
    if (family != ProtocolFamily.can11 && family != ProtocolFamily.can29) {
      return const MonitorTestReport(unsupportedReason: 'not_can');
    }
    final mids = <int>{};
    var base = 0x00;
    while (base <= 0xE0) {
      final (_, msgs) = await request('06${hex2(base)}');
      final pos = positive(msgs, 0x06, base);
      if (pos.isEmpty) break;
      var cont = false;
      for (final m in pos) {
        if (m.data.length < 6) continue;
        final s = decodeSupportedBitmask(base, m.data.sublist(2, 6));
        mids.addAll(s.where((x) => !isAvailabilityMid(x)));
        if (s.contains(base + 0x20)) cont = true;
      }
      if (!cont) break;
      base += 0x20;
    }
    if (mids.isEmpty) return const MonitorTestReport(unsupportedReason: 'not_supported');
    final tests = <MonitorTest>[];
    for (final mid in mids.toList()..sort()) {
      final (_, msgs) = await request('06${hex2(mid)}');
      for (final m in positive(msgs, 0x06, mid)) {
        tests.addAll(parseMonitorResponse(m.data, ecu: m.ecu));
      }
    }
    return MonitorTestReport(tests: tests, supportedMids: mids);
  }

  /// Reads one mode 01 PID; returns one reading per answering ECU.
  Future<List<PidReading>> readPid(int pid) async {
    final (r, msgs) = await request('01${hex2(pid)}');
    if (!r.ok) return const [];
    final now = DateTime.now().toUtc();
    return [
      for (final m in positive(msgs, 0x01, pid))
        PidReading(pid: pid, ecu: m.ecu, raw: m.hex, values: table.decode(pid, m.data.sublist(2)), at: now),
    ];
  }

  /// Mode 03 (stored), 07 (pending), 0A (permanent).
  Future<DtcReadResult> readDtcs(DtcStatus status) async {
    final service = int.parse(status.service, radix: 16);
    final (r, msgs) = await request(status.service);
    if (!r.ok) {
      // NO DATA simply means "no codes" on many ECUs.
      if (r.error == ElmErrorKind.noData) return DtcReadResult(const []);
      return DtcReadResult(const [], error: r.error?.code);
    }
    final out = <Dtc>[];
    final seen = <String>{};
    for (final m in positive(msgs, service)) {
      for (final code in parseDtcPayload(m.data, family)) {
        if (seen.add('${m.ecu}/$code')) out.add(Dtc(code, status, ecu: m.ecu == FrameParser.unknownEcu ? null : m.ecu));
      }
    }
    return DtcReadResult(out);
  }

  /// [data] starts at the response service byte (43/47/4A).
  /// CAN: count byte then pairs. Legacy: 3 pairs per frame, no count.
  static List<String> parseDtcPayload(List<int> data, ProtocolFamily family) {
    if (data.length < 2) return const [];
    final body = data.sublist(1);
    bool canStyle;
    switch (family) {
      case ProtocolFamily.can11:
      case ProtocolFamily.can29:
        canStyle = true;
      case ProtocolFamily.j1850:
      case ProtocolFamily.iso9141:
      case ProtocolFamily.kwp:
        canStyle = false;
      case ProtocolFamily.unknown:
        canStyle = body.length.isOdd && body[0] == (body.length - 1) ~/ 2;
    }
    if (canStyle) {
      final count = body[0];
      final pairs = body.sublist(1);
      final codes = decodeDtcPairs(pairs);
      return codes.length > count ? codes.sublist(0, count) : codes;
    }
    return decodeDtcPairs(body);
  }

  /// Freeze frame 0: `02 PID 00`. Reads the PIDs reported as supported in
  /// the freeze frame (02 00 00), limited to [interesting] when given.
  Future<FreezeFrame?> readFreezeFrame({Set<int>? interesting}) async {
    final supported = <int>{};
    var base = 0x00;
    String? ecu;
    while (base <= 0xC0) {
      final (_, msgs) = await request('02${hex2(base)}00');
      final pos = positive(msgs, 0x02, base);
      if (pos.isEmpty) break;
      final m = pos.first;
      ecu ??= m.ecu;
      if (m.data.length < 7) break;
      final pids = decodeSupportedBitmask(base, m.data.sublist(3, 7));
      supported.addAll(pids);
      if (!pids.contains(base + 0x20)) break;
      base += 0x20;
    }
    if (supported.isEmpty) return null;
    String? dtc;
    if (supported.contains(0x02)) {
      final (_, msgs) = await request('020200');
      final pos = positive(msgs, 0x02, 0x02);
      if (pos.isNotEmpty && pos.first.data.length >= 5) {
        dtc = decodeDtc(pos.first.data[3], pos.first.data[4]);
      }
    }
    final values = <String, double?>{};
    for (final pid in supported.toList()..sort()) {
      if (pid % 0x20 == 0 || pid == 0x02) continue;
      final def = table[pid];
      if (def == null || !def.isLiveSignal) continue;
      if (interesting != null && !interesting.contains(pid)) continue;
      final (_, msgs) = await request('02${hex2(pid)}00');
      final pos = positive(msgs, 0x02, pid);
      if (pos.isEmpty) continue;
      values.addAll(table.decode(pid, pos.first.data.sublist(3)));
    }
    if (dtc == null && values.isEmpty) return null;
    return FreezeFrame(dtc: dtc, values: values, ecu: ecu);
  }

  /// Mode 09 PID 02. ISO-TP reassembled on CAN; legacy sends 5 frames
  /// `49 02 NN b1 b2 b3 b4` that are ordered by NN.
  Future<VinResult> readVin() async {
    final (r, msgs) = await request('0902', timeout: const Duration(seconds: 5));
    if (!r.ok) return VinResult(null, valid: false, warning: r.error?.code);
    final pos = positive(msgs, 0x09, 0x02);
    if (pos.isEmpty) return VinResult(null, valid: false, warning: 'no_response');
    final bytes = <int>[];
    final isLegacyFrames = pos.length > 1 && pos.every((m) => m.data.length == 7);
    if (isLegacyFrames) {
      final sorted = [...pos]..sort((a, b) => a.data[2].compareTo(b.data[2]));
      for (final m in sorted) {
        bytes.addAll(m.data.sublist(3));
      }
    } else {
      // Use the longest message (one ECU), strip `49 02` and the count byte.
      final m = pos.reduce((a, b) => a.data.length >= b.data.length ? a : b);
      bytes.addAll(m.data.sublist(m.data.length >= 20 ? 3 : 2));
    }
    return decodeVinBytes(bytes);
  }

  static VinResult decodeVinBytes(List<int> bytes) {
    final chars = String.fromCharCodes(bytes.where((b) => b >= 0x20 && b < 0x7F)).trim();
    final vin = chars.length > 17 ? chars.substring(chars.length - 17) : chars;
    if (vin.length != 17 || !RegExp(r'^[A-Z0-9]{17}$').hasMatch(vin)) {
      return VinResult(vin.isEmpty ? null : vin, valid: false, warning: 'invalid_length_or_charset');
    }
    // ISO 3779 forbids I, O and Q — report but keep (simulators use them).
    final strict = !RegExp('[IOQ]').hasMatch(vin);
    return VinResult(vin, valid: true, warning: strict ? null : 'contains_IOQ');
  }

  /// `ATRV` → adapter-measured voltage at the OBD port.
  Future<double?> readAdapterVoltage() async {
    final r = await elm.send('ATRV');
    if (!r.ok) return null;
    final m = RegExp(r'(\d+(?:\.\d+)?)\s*V?', caseSensitive: false).firstMatch(r.text);
    return m == null ? null : double.tryParse(m.group(1)!);
  }
}
