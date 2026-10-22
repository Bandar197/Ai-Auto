/// GATT layouts used by common ELM327 BLE clones (pure Dart so it is
/// unit-testable; the Flutter BLE transport lives in lib/platform/).
library;

class BleUartProfile {
  const BleUartProfile({
    required this.name,
    required this.service,
    required this.notify,
    required this.write,
  });

  final String name;
  final String service;
  final String notify;
  final String write;

  static String expand(String uuid) {
    final u = uuid.trim().toLowerCase();
    if (u.length == 4) return '0000$u-0000-1000-8000-00805f9b34fb';
    if (u.length == 8) return '$u-0000-1000-8000-00805f9b34fb';
    return u;
  }

  static bool sameUuid(String a, String b) => expand(a) == expand(b);
}

/// Known layouts in probing order.
const List<BleUartProfile> knownBleProfiles = [
  BleUartProfile(name: 'FFF0', service: 'fff0', notify: 'fff1', write: 'fff2'),
  BleUartProfile(name: 'FFE0', service: 'ffe0', notify: 'ffe1', write: 'ffe1'),
  BleUartProfile(name: '18F0', service: '18f0', notify: '2af0', write: '2af1'),
];

/// Picks a profile given the discovered service → characteristic UUIDs.
/// [override] (manual UUIDs from settings) wins when its service exists.
BleUartProfile? pickBleProfile(
  Map<String, List<String>> services, {
  BleUartProfile? override,
}) {
  bool has(BleUartProfile p) {
    for (final entry in services.entries) {
      if (!BleUartProfile.sameUuid(entry.key, p.service)) continue;
      final chars = entry.value;
      final n = chars.any((c) => BleUartProfile.sameUuid(c, p.notify));
      final w = chars.any((c) => BleUartProfile.sameUuid(c, p.write));
      if (n && w) return true;
    }
    return false;
  }

  if (override != null && has(override)) return override;
  for (final p in knownBleProfiles) {
    if (has(p)) return p;
  }
  return null;
}

/// Splits [data] into chunks that fit the negotiated ATT MTU (payload = mtu-3).
List<List<int>> chunkForMtu(List<int> data, int mtu) {
  final size = (mtu - 3).clamp(20, 512);
  final out = <List<int>>[];
  for (var i = 0; i < data.length; i += size) {
    out.add(data.sublist(i, i + size > data.length ? data.length : i + size));
  }
  return out;
}
