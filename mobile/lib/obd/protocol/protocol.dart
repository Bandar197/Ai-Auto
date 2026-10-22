/// ELM327 protocol numbers (ATSPn / ATDPN), mirrored from shared/obd/protocols.json.
library;

enum ProtocolFamily { unknown, can11, can29, j1850, iso9141, kwp }

class ObdProtocol {
  const ObdProtocol(this.code, this.name, this.family);
  final String code;
  final String name;
  final ProtocolFamily family;

  bool get isCan => family == ProtocolFamily.can11 || family == ProtocolFamily.can29;
  bool get isLegacy => family == ProtocolFamily.j1850 || family == ProtocolFamily.iso9141 || family == ProtocolFamily.kwp;

  static const List<ObdProtocol> all = [
    ObdProtocol('1', 'SAE J1850 PWM (41.6 kbaud)', ProtocolFamily.j1850),
    ObdProtocol('2', 'SAE J1850 VPW (10.4 kbaud)', ProtocolFamily.j1850),
    ObdProtocol('3', 'ISO 9141-2 (5 baud init, 10.4 kbaud)', ProtocolFamily.iso9141),
    ObdProtocol('4', 'ISO 14230-4 KWP (5 baud init, 10.4 kbaud)', ProtocolFamily.kwp),
    ObdProtocol('5', 'ISO 14230-4 KWP (fast init, 10.4 kbaud)', ProtocolFamily.kwp),
    ObdProtocol('6', 'ISO 15765-4 CAN (11 bit ID, 500 kbaud)', ProtocolFamily.can11),
    ObdProtocol('7', 'ISO 15765-4 CAN (29 bit ID, 500 kbaud)', ProtocolFamily.can29),
    ObdProtocol('8', 'ISO 15765-4 CAN (11 bit ID, 250 kbaud)', ProtocolFamily.can11),
    ObdProtocol('9', 'ISO 15765-4 CAN (29 bit ID, 250 kbaud)', ProtocolFamily.can29),
  ];

  /// Parses ATDPN output such as `A6`, `6`, `A7`.
  static ObdProtocol? fromDpn(String dpn) {
    var s = dpn.trim().toUpperCase();
    if (s.startsWith('A')) s = s.substring(1);
    if (s.isEmpty) return null;
    for (final p in all) {
      if (p.code == s) return p;
    }
    return null;
  }

  static bool isAutoDpn(String dpn) => dpn.trim().toUpperCase().startsWith('A');
}
