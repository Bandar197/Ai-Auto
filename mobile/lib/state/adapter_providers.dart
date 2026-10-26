import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../platform/bt_classic_transport.dart';
import '../platform/host_platform.dart';
import '../platform/serial_transport.dart';

/// Host OS (overridden in widget tests).
final hostPlatformProvider = Provider<HostPlatform>((ref) => detectHostPlatform());

/// A Bluetooth Classic target: an Android bonded device or a desktop COM port.
class ClassicTarget {
  const ClassicTarget({required this.id, required this.title, this.subtitle = ''});

  /// MAC address (Android) or port name (desktop).
  final String id;
  final String title;
  final String subtitle;
}

/// Android: devices paired in Android settings. Desktop: serial/COM ports.
final classicTargetsProvider = FutureProvider.autoDispose<List<ClassicTarget>>((ref) async {
  final host = ref.watch(hostPlatformProvider);
  if (host == HostPlatform.android) {
    if (!await BtClassicTransport.isSupported()) return const [];
    await BtClassicTransport.requestPermission();
    if (!await BtClassicTransport.isEnabled()) throw StateError('bluetooth_off');
    return [
      for (final d in await BtClassicTransport.bondedDevices()) ClassicTarget(id: d.address, title: d.name.isEmpty ? d.address : d.name, subtitle: d.address),
    ];
  }
  if (host.isDesktop) {
    return [for (final p in SerialTransport.listPorts()) ClassicTarget(id: p.name, title: p.name, subtitle: p.description)];
  }
  return const [];
});
