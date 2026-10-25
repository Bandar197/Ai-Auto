/// What the developer console may send: read-only adapter queries and the read-only
/// OBD services. Everything else (clears 04/14, writes, protocol/echo/header changes,
/// EEPROM parameters ATPP/ATSD, resets, monitor-all) is refused before reaching the link.
const Set<String> kConsoleAtAllowlist = {'ATI', 'AT@1', 'AT@2', 'ATRV', 'ATDP', 'ATDPN', 'ATCS', 'ATKW', 'ATIGN', 'ATPPS'};
const Set<String> kConsoleObdServices = {'01', '02', '03', '06', '07', '09', '0A'};

/// Normalised command if allowed, else null.
String? consoleAllowed(String input) {
  final c = input.replaceAll(' ', '').toUpperCase();
  if (c.isEmpty) return null;
  if (c.startsWith('AT')) return kConsoleAtAllowlist.contains(c) ? c : null;
  if (!RegExp(r'^[0-9A-F]+$').hasMatch(c) || c.length.isOdd || c.length > 8) return null;
  return kConsoleObdServices.contains(c.substring(0, 2)) ? c : null;
}
