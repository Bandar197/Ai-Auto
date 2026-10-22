import 'dart:async';
import 'dart:convert';

import '../errors.dart';
import 'ble_profiles.dart';
import 'obd_transport.dart';

/// One GATT characteristic as discovered on the adapter.
class GattCharacteristicInfo {
  const GattCharacteristicInfo(this.uuid, {this.write = false, this.writeWithoutResponse = false, this.notify = false, this.indicate = false});
  final String uuid;
  final bool write;
  final bool writeWithoutResponse;
  final bool notify;
  final bool indicate;
}

/// Minimal GATT client operations needed for an ELM327 "BLE UART".
/// Implemented with universal_ble in lib/platform/ble_transport.dart and by
/// fakes in tests.
abstract class GattLink {
  String get description;
  Future<void> connect(Duration timeout);

  /// Best-effort MTU request; returns the effective ATT MTU (23 if unknown).
  Future<int> requestMtu(int mtu);
  Future<Map<String, List<GattCharacteristicInfo>>> discover();
  Future<Stream<List<int>>> subscribe(String service, String characteristic, {bool indicate = false});
  Future<void> write(String service, String characteristic, List<int> data, {required bool withResponse});

  /// Emits false when the link drops.
  Stream<bool> get connection;
  Future<void> disconnect();
}

/// [ObdTransport] over a GATT UART: picks the known ELM327 layout (FFF0/FFF1/
/// FFF2, FFE0/FFE1, 18F0/2AF0/2AF1) or the manual override, subscribes to the
/// notify characteristic, chunks writes to the MTU and detects disconnects.
class GattUartTransport implements ObdTransport {
  GattUartTransport(this.link, {this.uuidOverride, this.connectTimeout = const Duration(seconds: 12), this.preferredMtu = 185});

  final GattLink link;
  final BleUartProfile? uuidOverride;
  final Duration connectTimeout;
  final int preferredMtu;

  BleUartProfile? profile;
  int mtu = 23;
  bool _withResponse = true;
  StreamController<String>? _controller;
  StreamSubscription<List<int>>? _rx;
  StreamSubscription<bool>? _state;

  @override
  TransportKind get kind => TransportKind.ble;

  @override
  String get description => link.description;

  @override
  bool get isConnected => _controller != null;

  @override
  Stream<String> get incoming {
    final c = _controller;
    if (c == null) throw TransportException('not connected');
    return c.stream;
  }

  @override
  Future<void> connect() async {
    await close();
    try {
      await link.connect(connectTimeout);
    } on Object catch (e) {
      throw TransportException('BLE connect failed: $e', code: e is TimeoutException ? 'timeout' : 'unreachable');
    }
    try {
      final services = await link.discover();
      final p = pickBleProfile(
        {for (final e in services.entries) e.key: [for (final c in e.value) c.uuid]},
        override: uuidOverride,
      );
      if (p == null) {
        throw TransportException('no known ELM327 GATT layout (FFF0/FFE0/18F0); set UUIDs in settings', code: 'rejected');
      }
      profile = p;
      GattCharacteristicInfo? w, n;
      for (final e in services.entries) {
        if (!BleUartProfile.sameUuid(e.key, p.service)) continue;
        for (final c in e.value) {
          if (BleUartProfile.sameUuid(c.uuid, p.write)) w = c;
          if (BleUartProfile.sameUuid(c.uuid, p.notify)) n = c;
        }
      }
      // Use write-with-response unless the characteristic only allows without.
      _withResponse = !(w!.writeWithoutResponse && !w.write);
      try {
        mtu = await link.requestMtu(preferredMtu);
      } on Object catch (_) {
        mtu = 23;
      }
      final controller = StreamController<String>.broadcast();
      _controller = controller;
      final rx = await link.subscribe(p.service, p.notify, indicate: !n!.notify && n.indicate);
      _rx = rx.listen((v) {
        if (!controller.isClosed) controller.add(latin1.decode(v, allowInvalid: true));
      }, onDone: _teardown, onError: (Object _) => _teardown());
      _state = link.connection.listen((connected) {
        if (!connected) _teardown();
      });
    } on TransportException {
      _teardown();
      await _safeDisconnect();
      rethrow;
    } on Object catch (e) {
      _teardown();
      await _safeDisconnect();
      throw TransportException('BLE setup failed: $e', code: 'error');
    }
  }

  void _teardown() {
    _rx?.cancel();
    _state?.cancel();
    _rx = null;
    _state = null;
    final c = _controller;
    _controller = null;
    if (c != null && !c.isClosed) c.close();
  }

  Future<void> _safeDisconnect() async {
    try {
      await link.disconnect();
    } on Object catch (_) {}
  }

  @override
  Future<void> write(String data) async {
    final p = profile;
    if (p == null || _controller == null) throw TransportException('BLE not connected', code: 'socket_closed');
    try {
      for (final part in chunkForMtu(latin1.encode(data), mtu)) {
        await link.write(p.service, p.write, part, withResponse: _withResponse);
      }
    } on Object catch (e) {
      _teardown();
      throw TransportException('BLE write failed: $e', code: 'socket_closed');
    }
  }

  @override
  Future<void> close() async {
    _teardown();
    await _safeDisconnect();
  }
}
