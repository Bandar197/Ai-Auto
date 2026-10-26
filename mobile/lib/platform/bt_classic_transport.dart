import 'dart:async';

import 'package:flutter/services.dart';

import '../obd/errors.dart';
import '../obd/transport/byte_channel_transport.dart';
import '../obd/transport/obd_transport.dart';
import 'host_platform.dart';

/// A Bluetooth Classic device already paired (bonded) in Android settings.
class BondedDevice {
  const BondedDevice(this.name, this.address);
  final String name;
  final String address;
}

/// ELM327 over Bluetooth Classic SPP (RFCOMM) on Android, through the app's
/// own platform channel (android/app/src/main/kotlin/.../BtClassicPlugin.kt).
/// v1 lists bonded devices only: pair the adapter in Android Bluetooth
/// settings first (PIN usually 1234 or 0000).
class BtClassicTransport extends ByteChannelTransport {
  BtClassicTransport(String address, {String name = ''})
      : super(AndroidBtClassicChannel(address, name: name), kind: TransportKind.usbSerial);

  static const MethodChannel methods = MethodChannel('automind/bt_classic');
  static const EventChannel events = EventChannel('automind/bt_classic/rx');

  static bool get isAvailable => detectHostPlatform() == HostPlatform.android;

  static Future<bool> isSupported() async => await methods.invokeMethod<bool>('isSupported') ?? false;
  static Future<bool> isEnabled() async => await methods.invokeMethod<bool>('isEnabled') ?? false;

  /// Requests BLUETOOTH_CONNECT (Android 12+); true when granted.
  static Future<bool> requestPermission() async => await methods.invokeMethod<bool>('requestPermission') ?? false;

  static Future<List<BondedDevice>> bondedDevices() async {
    final list = await methods.invokeListMethod<Map<Object?, Object?>>('bondedDevices') ?? const [];
    return [for (final m in list) BondedDevice('${m['name'] ?? ''}', '${m['address']}')];
  }
}

class AndroidBtClassicChannel implements ByteChannel {
  AndroidBtClassicChannel(this.address, {this.name = ''});

  final String address;
  final String name;
  StreamController<List<int>>? _input;
  StreamSubscription<dynamic>? _sub;

  @override
  String get description => name.isEmpty ? address : '$name ($address)';

  @override
  Stream<List<int>> get input => _input!.stream;

  @override
  Future<void> open() async {
    await close();
    final input = StreamController<List<int>>();
    _input = input;
    // Subscribe to the RX stream before connecting so no byte is lost.
    _sub = BtClassicTransport.events.receiveBroadcastStream().listen((dynamic e) {
      if (e is Uint8List) {
        input.add(e);
      } else if (e is List<int>) {
        input.add(e);
      } else if (e is Map && e['event'] == 'disconnected') {
        _closeInput();
      }
    }, onError: (Object _) => _closeInput(), onDone: _closeInput);
    try {
      await BtClassicTransport.methods.invokeMethod<bool>('connect', {'address': address});
    } on PlatformException catch (e) {
      await close();
      throw TransportException('Bluetooth Classic connect failed: ${e.message ?? e.code}',
          code: e.code == 'permission' ? 'rejected' : 'unreachable');
    }
  }

  void _closeInput() {
    final i = _input;
    if (i != null && !i.isClosed) i.close();
  }

  @override
  Future<void> write(List<int> bytes) async {
    try {
      await BtClassicTransport.methods.invokeMethod<void>('write', {'data': Uint8List.fromList(bytes)});
    } on PlatformException catch (e) {
      throw TransportException('Bluetooth Classic write failed: ${e.message ?? e.code}', code: 'socket_closed');
    }
  }

  @override
  Future<void> close() async {
    await _sub?.cancel();
    _sub = null;
    _closeInput();
    _input = null;
    try {
      await BtClassicTransport.methods.invokeMethod<void>('disconnect');
    } on Object catch (_) {}
  }
}
