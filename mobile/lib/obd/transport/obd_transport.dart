/// Byte/line transport between the app and an ELM327-compatible adapter.
library;

import 'dart:async';

/// How the adapter is reached. Values match the backend `transport` enum,
/// except [demo], which never leaves the phone.
enum TransportKind {
  wifiTcp('wifi_tcp'),
  ble('ble'),
  usbSerial('usb_serial'),
  demo('demo');

  const TransportKind(this.apiValue);
  final String apiValue;
}

/// A raw text channel to an ELM327. Implementations must:
/// * complete [connect] or throw a `TransportException`;
/// * emit received text chunks (any split) on [incoming];
/// * close [incoming] when the link drops.
abstract class ObdTransport {
  TransportKind get kind;

  /// Human readable endpoint, e.g. `192.168.0.10:35000` or a BLE name.
  String get description;

  bool get isConnected;

  Future<void> connect();

  Future<void> write(String data);

  Stream<String> get incoming;

  Future<void> close();
}
