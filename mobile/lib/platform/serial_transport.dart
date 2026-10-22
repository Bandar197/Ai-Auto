import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_libserialport/flutter_libserialport.dart';

import '../obd/errors.dart';
import '../obd/transport/byte_channel_transport.dart';
import '../obd/transport/obd_transport.dart';
import 'host_platform.dart';

/// A serial port the user can pick (COM3, /dev/ttyUSB0, /dev/rfcomm0…).
class SerialPortInfo {
  const SerialPortInfo(this.name, this.description);
  final String name;
  final String description;
}

/// ELM327 over a serial port on desktop: USB adapters, or Bluetooth Classic
/// (SPP) adapters after pairing in the OS (Windows creates an outgoing COM
/// port). Uses flutter_libserialport (libserialport, LGPL-3.0, loaded dynamically).
class SerialTransport extends ByteChannelTransport {
  SerialTransport(String portName, {int baudRate = defaultBaud})
      : super(LibSerialPortChannel(portName, baudRate: baudRate), kind: TransportKind.usbSerial);

  static const int defaultBaud = 38400;
  static const List<int> baudRates = [9600, 38400, 115200];

  static bool get isAvailable => detectHostPlatform().isDesktop;

  static List<SerialPortInfo> listPorts() {
    final out = <SerialPortInfo>[];
    for (final name in SerialPort.availablePorts) {
      String desc = '';
      final p = SerialPort(name);
      try {
        desc = p.description ?? '';
      } on Object catch (_) {
      } finally {
        p.dispose();
      }
      out.add(SerialPortInfo(name, desc));
    }
    return out;
  }
}

class LibSerialPortChannel implements ByteChannel {
  LibSerialPortChannel(this.portName, {this.baudRate = SerialTransport.defaultBaud});

  final String portName;
  final int baudRate;
  SerialPort? _port;
  SerialPortReader? _reader;
  StreamController<List<int>>? _input;

  @override
  String get description => '$portName @ $baudRate';

  @override
  Stream<List<int>> get input => _input!.stream;

  @override
  Future<void> open() async {
    await close();
    await Future<void>.delayed(Duration.zero); // let the UI paint "connecting" (open() blocks)
    final port = SerialPort(portName);
    if (!port.openReadWrite()) {
      final err = SerialPort.lastError;
      port.dispose();
      throw TransportException('cannot open $portName: ${err?.message ?? 'unknown error'}', code: 'unreachable');
    }
    final cfg = SerialPortConfig()
      ..baudRate = baudRate
      ..bits = 8
      ..parity = SerialPortParity.none
      ..stopBits = 1
      ..setFlowControl(SerialPortFlowControl.none);
    port.config = cfg;
    cfg.dispose();
    _port = port;
    final input = StreamController<List<int>>();
    _input = input;
    final reader = SerialPortReader(port);
    _reader = reader;
    reader.stream.listen(input.add, onError: (Object e) {
      if (!input.isClosed) input.close();
    }, onDone: () {
      if (!input.isClosed) input.close();
    });
  }

  @override
  Future<void> write(List<int> bytes) async {
    final port = _port;
    if (port == null) throw TransportException('port closed', code: 'socket_closed');
    var data = Uint8List.fromList(bytes);
    while (data.isNotEmpty) {
      final n = port.write(data, timeout: 2000);
      if (n <= 0) throw TransportException('serial write failed', code: 'socket_closed');
      data = data.sublist(n);
    }
  }

  @override
  Future<void> close() async {
    _reader?.close();
    _reader = null;
    final p = _port;
    _port = null;
    if (p != null) {
      try {
        p.close();
      } on Object catch (_) {}
      p.dispose();
    }
    final i = _input;
    _input = null;
    if (i != null && !i.isClosed) await i.close();
  }
}
