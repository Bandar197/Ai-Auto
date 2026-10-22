import 'dart:async';
import 'dart:convert';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../obd/errors.dart';
import '../obd/transport/ble_profiles.dart';
import '../obd/transport/obd_transport.dart';

/// ELM327 over Bluetooth Low Energy (works on iOS and Android).
/// Classic Bluetooth SPP adapters are not supported (iOS forbids SPP for
/// normal apps; Android SPP is a documented future option).
class BleTransport implements ObdTransport {
  BleTransport(this.device, {this.uuidOverride, this.connectTimeout = const Duration(seconds: 12)});

  final BluetoothDevice device;

  /// Manual UUIDs from settings (service/notify/write).
  final BleUartProfile? uuidOverride;
  final Duration connectTimeout;

  BluetoothCharacteristic? _write;
  BluetoothCharacteristic? _notify;
  StreamSubscription<List<int>>? _notifySub;
  StreamSubscription<BluetoothConnectionState>? _stateSub;
  StreamController<String>? _controller;
  BleUartProfile? profile;
  int _mtu = 23;

  @override
  TransportKind get kind => TransportKind.ble;

  @override
  String get description => device.platformName.isEmpty ? device.remoteId.str : device.platformName;

  @override
  bool get isConnected => _controller != null;

  @override
  Stream<String> get incoming {
    final c = _controller;
    if (c == null) throw TransportException('not connected');
    return c.stream;
  }

  /// Scans for nearby BLE devices (the UI lists them; ELM clones often have
  /// names like "OBDII", "OBDBLE", "IOS-Vlink", "V-LINK", "Android-Vlink").
  static Stream<List<ScanResult>> scan({Duration timeout = const Duration(seconds: 8)}) {
    unawaited(FlutterBluePlus.startScan(timeout: timeout));
    return FlutterBluePlus.scanResults;
  }

  static Future<void> stopScan() => FlutterBluePlus.stopScan();

  @override
  Future<void> connect() async {
    await close();
    try {
      await device.connect(timeout: connectTimeout, mtu: null);
    } on Object catch (e) {
      throw TransportException('BLE connect failed: $e', code: e is TimeoutException ? 'timeout' : 'unreachable');
    }
    try {
      try {
        _mtu = await device.requestMtu(185);
      } on Object catch (_) {
        _mtu = device.mtuNow;
      }
      final services = await device.discoverServices();
      final map = <String, List<String>>{
        for (final s in services) s.uuid.str128: [for (final c in s.characteristics) c.uuid.str128],
      };
      final p = pickBleProfile(map, override: uuidOverride);
      if (p == null) {
        throw TransportException('no known ELM327 GATT layout (FFF0/FFE0/18F0); set UUIDs in settings', code: 'rejected');
      }
      profile = p;
      for (final s in services) {
        if (!BleUartProfile.sameUuid(s.uuid.str128, p.service)) continue;
        for (final c in s.characteristics) {
          if (BleUartProfile.sameUuid(c.uuid.str128, p.notify)) _notify = c;
          if (BleUartProfile.sameUuid(c.uuid.str128, p.write)) _write = c;
        }
      }
      final controller = StreamController<String>.broadcast();
      _controller = controller;
      await _notify!.setNotifyValue(true);
      _notifySub = _notify!.onValueReceived.listen((v) => controller.add(latin1.decode(v, allowInvalid: true)));
      _stateSub = device.connectionState.listen((s) {
        if (s == BluetoothConnectionState.disconnected) _teardown();
      });
    } on TransportException {
      await device.disconnect();
      rethrow;
    } on Object catch (e) {
      await device.disconnect();
      throw TransportException('BLE setup failed: $e', code: 'error');
    }
  }

  void _teardown() {
    _notifySub?.cancel();
    _stateSub?.cancel();
    _notifySub = null;
    _stateSub = null;
    final c = _controller;
    _controller = null;
    if (c != null && !c.isClosed) c.close();
  }

  @override
  Future<void> write(String data) async {
    final w = _write;
    if (w == null || _controller == null) throw TransportException('BLE not connected', code: 'socket_closed');
    final noResp = w.properties.writeWithoutResponse && !w.properties.write;
    try {
      for (final chunk in chunkForMtu(latin1.encode(data), _mtu)) {
        await w.write(chunk, withoutResponse: noResp);
      }
    } on Object catch (e) {
      _teardown();
      throw TransportException('BLE write failed: $e', code: 'socket_closed');
    }
  }

  @override
  Future<void> close() async {
    _teardown();
    try {
      await device.disconnect();
    } on Object catch (_) {}
  }
}
