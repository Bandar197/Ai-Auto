import '../hex.dart';
import 'protocol.dart';

/// One reassembled OBD message from one ECU. [data] starts at the service
/// byte (e.g. `41 0C 1A F8`); headers, PCI bytes and checksums are removed.
class ObdMessage {
  ObdMessage({required this.ecu, required this.data, required this.rawLines, this.checksumOk});

  /// ECU address: `7E8` (CAN 11), `18DAF110` (CAN 29), `10` (legacy source
  /// address) or `?` when headers were off.
  final String ecu;
  final List<int> data;
  final List<String> rawLines;

  /// Legacy protocols only: whether the trailing checksum byte matched.
  final bool? checksumOk;

  String get hex => toHex(data);

  @override
  String toString() => 'ObdMessage($ecu: $hex)';
}

/// Parses cleaned ELM327 response lines into messages, grouping frames by
/// ECU and reassembling ISO-TP (ISO 15765-2) multi-frame payloads.
///
/// Handles: CAN 11-bit and 29-bit with headers, legacy J1850/ISO 9141/KWP
/// with 3 header bytes + checksum, headers-off single lines and the
/// headers-off CAN multi-frame format (`014` / `0: ...` / `1: ...`), with
/// spaces on or off.
class FrameParser {
  const FrameParser({this.family = ProtocolFamily.unknown, this.headersOn = true});

  final ProtocolFamily family;
  final bool headersOn;

  static const String unknownEcu = '?';

  List<ObdMessage> parse(List<String> lines) {
    final cleaned = [
      for (final l in lines)
        if (l.trim().isNotEmpty) l.trim().toUpperCase(),
    ];
    if (cleaned.isEmpty) return const [];

    // Headers-off CAN multi-frame: a 3-hex-digit length line followed by
    // "N:" indexed lines (or indexed lines alone).
    final indexed = RegExp(r'^([0-9A-F]{1,2}):\s*(.*)$');
    if (cleaned.any(indexed.hasMatch)) {
      return _parseHeadersOffMulti(cleaned, indexed);
    }

    final frames = <_Frame>[];
    for (final line in cleaned) {
      final f = _parseLine(line);
      if (f != null) frames.add(f);
    }
    return _assemble(frames);
  }

  /// Convenience: messages grouped by ECU address, in first-seen order.
  Map<String, List<ObdMessage>> parseByEcu(List<String> lines) {
    final out = <String, List<ObdMessage>>{};
    for (final m in parse(lines)) {
      out.putIfAbsent(m.ecu, () => []).add(m);
    }
    return out;
  }

  // -------------------------------------------------------------- internals

  List<ObdMessage> _parseHeadersOffMulti(List<String> lines, RegExp indexed) {
    int? total;
    final parts = <int, List<int>>{};
    final raw = <String>[];
    final singles = <ObdMessage>[];
    var wrap = 0;
    var last = -1;
    for (final line in lines) {
      final m = indexed.firstMatch(line);
      if (m != null) {
        var idx = int.parse(m.group(1)!, radix: 16);
        if (idx < last) wrap += 16; // index wraps 0..F
        last = idx;
        idx += wrap;
        final bytes = parseHexBytes(m.group(2)!);
        if (bytes != null) parts[idx] = bytes;
        raw.add(line);
        continue;
      }
      final compact = line.replaceAll(' ', '');
      if (compact.length == 3 && isHexString(compact)) {
        total = int.parse(compact, radix: 16);
        raw.add(line);
        continue;
      }
      final bytes = parseHexBytes(line);
      if (bytes != null) singles.add(ObdMessage(ecu: unknownEcu, data: bytes, rawLines: [line]));
    }
    final keys = parts.keys.toList()..sort();
    final data = <int>[for (final k in keys) ...parts[k]!];
    final payload = total != null && data.length >= total ? data.sublist(0, total) : data;
    return [ObdMessage(ecu: unknownEcu, data: payload, rawLines: raw), ...singles];
  }

  _Frame? _parseLine(String line) {
    final hasSpaces = line.contains(' ');
    final compact = line.replaceAll(' ', '');
    if (!isHexString(compact)) return null;

    final fam = family;
    final headers = headersOn;

    // CAN 11-bit with headers: 3-hex-digit id.
    final firstToken = hasSpaces ? line.split(' ').first : null;
    final looksCan11 = hasSpaces ? firstToken!.length == 3 : compact.length.isOdd;
    if (headers && looksCan11 && (fam == ProtocolFamily.can11 || fam == ProtocolFamily.unknown || !hasSpaces)) {
      final id = compact.substring(0, 3);
      final bytes = parseHexBytes(compact.substring(3));
      if (bytes == null || bytes.isEmpty) return null;
      return _Frame.can(id, bytes, line);
    }

    final bytes = parseHexBytes(compact);
    if (bytes == null || bytes.isEmpty) return null;

    if (headers && (fam == ProtocolFamily.can29 || (fam == ProtocolFamily.unknown && _looksCan29(bytes)))) {
      if (bytes.length < 5) return null;
      final id = toHex(bytes.sublist(0, 4), spaces: false);
      return _Frame.can(id, bytes.sublist(4), line);
    }

    final legacy = fam == ProtocolFamily.j1850 || fam == ProtocolFamily.iso9141 || fam == ProtocolFamily.kwp;
    if (headers && (legacy || (fam == ProtocolFamily.unknown && _looksLegacy(bytes)))) {
      if (bytes.length < 5) return null;
      final body = bytes.sublist(3, bytes.length - 1);
      final sum = bytes.sublist(0, bytes.length - 1).fold<int>(0, (a, b) => a + b) & 0xFF;
      // ISO 9141 / KWP use a sum checksum; J1850 uses a CRC (not verified here).
      final bool? ok = fam == ProtocolFamily.j1850 ? null : sum == bytes.last;
      return _Frame.legacy(hex2(bytes[2]), body, line, ok);
    }

    // Headers off: payload only, ECU unknown.
    return _Frame.plain(bytes, line);
  }

  static bool _looksCan29(List<int> b) => b.length >= 5 && b[0] == 0x18 && (b[1] == 0xDA || b[1] == 0xDB);

  static bool _looksLegacy(List<int> b) =>
      b.length >= 5 && (b[1] == 0x6B || ((b[0] & 0xC0) == 0x80 && b[1] == 0xF1));

  List<ObdMessage> _assemble(List<_Frame> frames) {
    final out = <ObdMessage>[];
    // Per ECU ISO-TP state (CAN only).
    final pending = <String, _IsoTp>{};
    final order = <String>[];

    for (final f in frames) {
      switch (f.kind) {
        case _FrameKind.plain:
          out.add(ObdMessage(ecu: unknownEcu, data: f.bytes, rawLines: [f.line]));
        case _FrameKind.legacy:
          out.add(ObdMessage(ecu: f.ecu, data: f.bytes, rawLines: [f.line], checksumOk: f.checksumOk));
        case _FrameKind.can:
          if (f.bytes.isEmpty) continue;
          final pci = f.bytes[0];
          final type = pci >> 4;
          if (type == 0x0) {
            final n = pci & 0x0F;
            final end = 1 + n > f.bytes.length ? f.bytes.length : 1 + n;
            out.add(ObdMessage(ecu: f.ecu, data: f.bytes.sublist(1, end), rawLines: [f.line]));
          } else if (type == 0x1 && f.bytes.length >= 2) {
            final len = ((pci & 0x0F) << 8) | f.bytes[1];
            final tp = _IsoTp(len)..first = f.bytes.sublist(2);
            tp.lines.add(f.line);
            if (!pending.containsKey(f.ecu)) order.add(f.ecu);
            pending[f.ecu] = tp;
          } else if (type == 0x2) {
            final tp = pending[f.ecu];
            if (tp == null) continue; // stray consecutive frame
            tp.add(pci & 0x0F, f.bytes.sublist(1));
            tp.lines.add(f.line);
          }
          // 0x3 flow control frames are ignored.
      }
    }
    for (final ecu in order) {
      final tp = pending[ecu];
      if (tp != null) out.add(ObdMessage(ecu: ecu, data: tp.assemble(), rawLines: tp.lines));
    }
    return out;
  }
}

enum _FrameKind { can, legacy, plain }

class _Frame {
  _Frame.can(this.ecu, this.bytes, this.line)
      : kind = _FrameKind.can,
        checksumOk = null;
  _Frame.legacy(this.ecu, this.bytes, this.line, this.checksumOk) : kind = _FrameKind.legacy;
  _Frame.plain(this.bytes, this.line)
      : kind = _FrameKind.plain,
        ecu = FrameParser.unknownEcu,
        checksumOk = null;

  final _FrameKind kind;
  final String ecu;
  final List<int> bytes;
  final String line;
  final bool? checksumOk;
}

class _IsoTp {
  _IsoTp(this.length);
  final int length;
  List<int> first = const [];
  final List<String> lines = [];
  final List<(int, List<int>)> _cf = [];

  void add(int seq, List<int> data) => _cf.add((seq, data));

  /// Orders consecutive frames by sequence number (1..F, 0, 1.. wrap).
  List<int> assemble() {
    // Unwrap: sequence numbers restart after 0xF; the expected index of the
    // k-th frame is k (1-based). Sort by the unwrapped index nearest to arrival.
    final indexed = <(int, List<int>)>[];
    var base = 0;
    var prev = 0;
    for (final (seq, data) in _cf) {
      var s = seq == 0 ? 16 : seq;
      if (s + base < prev - 8) base += 16;
      s += base;
      prev = s;
      indexed.add((s, data));
    }
    indexed.sort((a, b) => a.$1.compareTo(b.$1));
    final all = <int>[...first, for (final (_, d) in indexed) ...d];
    return all.length > length ? all.sublist(0, length) : all;
  }
}
