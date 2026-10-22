/// AutoMind OBD-II engine — pure Dart, no Flutter imports.
library;

export 'client/obd_client.dart';
export 'decode/dtc.dart';
export 'decode/pid_table.dart';
export 'decode/readiness.dart';
export 'elm327/elm327.dart';
export 'emulator/elm327_emulator.dart';
export 'emulator/scenario.dart';
export 'errors.dart';
export 'hex.dart';
export 'live/live_poller.dart';
export 'protocol/frame_parser.dart';
export 'protocol/protocol.dart';
export 'recording/recorder.dart';
export 'recording/recording.dart';
export 'recording/replay_source.dart';
export 'services/obd_services.dart';
export 'transport/ble_profiles.dart';
export 'transport/byte_channel_transport.dart';
export 'transport/gatt_uart_transport.dart';
export 'transport/demo_transport.dart';
export 'transport/obd_transport.dart';
export 'transport/tcp_transport.dart';
export 'verify/recurrence.dart';
