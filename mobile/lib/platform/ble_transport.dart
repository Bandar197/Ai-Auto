import 'dart:async';

import 'package:universal_ble/universal_ble.dart';

import '../obd/errors.dart';
import '../obd/transport/ble_profiles.dart';
import '../obd/transport/gatt_uart_transport.dart';
import 'host_platform.dart';

/// ELM327 over Bluetooth Low Energy using universal_ble (BSD-3) — one BLE
/// stack for Android, iOS, macOS, Windows and Linux.
class BleTransport extends GattUartTransport {
  BleTransport(BleDevice device, {super.uuidOverride, super.connectTimeout}) : super(UniversalBleLink(device));

  static bool get isAvailable => detectHostPlatform().supportsBle;

  /// Scans for nearby BLE devices; emits the accumulated list (ELM clones are
  /// often named "OBDII", "OBDBLE", "IOS-Vlink", "V-LINK", "Android-Vlink").
  static Stream<List<BleDevice>> scan({Duration timeout = const Duration(seconds: 8)}) async* {
    final state = await UniversalBle.getBluetoothAvailabilityState();
    if (state == AvailabilityState.unsupported) throw TransportException('Bluetooth LE is not supported on this device', code: 'rejected');
    if (state == AvailabilityState.poweredOff) throw TransportException('Bluetooth is off', code: 'unreachable');
    if (state == AvailabilityState.unauthorized) {
      try {
        await UniversalBle.requestPermissions();
      } on Object catch (_) {}
    }
    final found = <String, BleDevice>{};
    final out = StreamController<List<BleDevice>>();
    final sub = UniversalBle.scanStream.listen((d) {
      found[d.deviceId] = d;
      out.add(found.values.toList()..sort((a, b) => (b.rssi ?? -999).compareTo(a.rssi ?? -999)));
    });
    final timer = Timer(timeout, () async {
      await stopScan();
      await out.close();
    });
    try {
      await UniversalBle.startScan();
      yield* out.stream;
    } finally {
      timer.cancel();
      await sub.cancel();
      await stopScan();
    }
  }

  static Future<void> stopScan() async {
    try {
      await UniversalBle.stopScan();
    } on Object catch (_) {}
  }

  static String displayName(BleDevice d) => (d.name ?? '').isNotEmpty ? d.name! : d.deviceId;
}

/// [GattLink] implemented with universal_ble.
class UniversalBleLink implements GattLink {
  UniversalBleLink(this.device);
  final BleDevice device;

  @override
  String get description => BleTransport.displayName(device);

  @override
  Stream<bool> get connection => device.connectionStream;

  @override
  Future<void> connect(Duration timeout) => device.connect(timeout: timeout);

  @override
  Future<int> requestMtu(int mtu) async {
    try {
      return await device.requestMtu(mtu); // Windows/Apple: OS-managed, returns the effective value
    } on Object catch (_) {
      return 23;
    }
  }

  @override
  Future<Map<String, List<GattCharacteristicInfo>>> discover() async {
    final services = await device.discoverServices();
    return {
      for (final s in services)
        s.uuid: [
          for (final c in s.characteristics)
            GattCharacteristicInfo(
              c.uuid,
              write: c.properties.contains(CharacteristicProperty.write),
              writeWithoutResponse: c.properties.contains(CharacteristicProperty.writeWithoutResponse),
              notify: c.properties.contains(CharacteristicProperty.notify),
              indicate: c.properties.contains(CharacteristicProperty.indicate),
            ),
        ],
    };
  }

  @override
  Future<Stream<List<int>>> subscribe(String service, String characteristic, {bool indicate = false}) async {
    final c = await device.getCharacteristic(BleUartProfile.expand(characteristic), service: BleUartProfile.expand(service));
    final stream = c.onValueReceived; // listen before subscribing so no reply is lost
    if (indicate) {
      await c.indications.subscribe();
    } else {
      await c.notifications.subscribe();
    }
    return stream;
  }

  @override
  Future<void> write(String service, String characteristic, List<int> data, {required bool withResponse}) async {
    final c = await device.getCharacteristic(BleUartProfile.expand(characteristic), service: BleUartProfile.expand(service));
    await c.write(data, withResponse: withResponse);
  }

  @override
  Future<void> disconnect() => device.disconnect();
}
