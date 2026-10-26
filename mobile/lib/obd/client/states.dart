/// Connection state model. The two links are reported separately so the
/// user can tell "phone cannot reach the adapter" from "adapter cannot reach
/// the car".
library;

enum DataMode {
  live('live'),
  demo('demo'),
  replay('replay');

  const DataMode(this.apiValue);
  final String apiValue;

  static DataMode parse(String? s) => DataMode.values.firstWhere((e) => e.apiValue == s, orElse: () => DataMode.live);
}

/// Phone ↔ adapter link.
enum AdapterState { disconnected, connecting, connected, error }

/// Adapter ↔ vehicle ECU link.
enum EcuState { unknown, searching, connected, noResponse, busError }

/// Machine-readable reason codes; the UI maps them to localized text.
enum LinkMessage {
  idle,
  connectingAdapter,
  adapterUnreachable,
  adapterTimeout,
  adapterNotElm,
  initializing,
  searchingProtocol,
  ecuConnected,
  ecuNoResponse,
  ecuBusError,
  linkLost,
  reconnecting,
  reconnected,
  disconnected,
}

class LinkStatus {
  const LinkStatus({
    this.adapter = AdapterState.disconnected,
    this.ecu = EcuState.unknown,
    this.message = LinkMessage.idle,
    this.detail = '',
  });

  final AdapterState adapter;
  final EcuState ecu;
  final LinkMessage message;

  /// Technical English detail (error string from the adapter etc).
  final String detail;

  LinkStatus copyWith({AdapterState? adapter, EcuState? ecu, LinkMessage? message, String? detail}) => LinkStatus(
        adapter: adapter ?? this.adapter,
        ecu: ecu ?? this.ecu,
        message: message ?? this.message,
        detail: detail ?? this.detail,
      );

  @override
  String toString() => 'LinkStatus($adapter, $ecu, $message, $detail)';
}

/// What we learnt about the adapter during init.
class AdapterInfo {
  AdapterInfo({
    this.firmware,
    this.description,
    this.isSimulator = false,
    this.voltage,
    this.protocolCode,
    this.protocolName,
    this.protocolAuto = false,
    this.headersOn = true,
    this.unsupportedAtCommands = const [],
  });

  String? firmware;
  String? description;
  bool isSimulator;
  double? voltage;
  String? protocolCode;
  String? protocolName;
  bool protocolAuto;
  bool headersOn;
  List<String> unsupportedAtCommands;
}
