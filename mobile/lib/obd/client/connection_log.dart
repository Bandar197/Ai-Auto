/// Body of `POST /connections` (docs/API.md).
library;

class ConnectionLog {
  ConnectionLog({
    required this.dataMode,
    required this.transport,
    required this.startedAt,
    this.adapterStatus = 'error',
    this.ecuStatus = 'not_attempted',
    this.protocolCode,
    this.protocolName,
    this.adapterFirmware,
    this.attempts = 0,
    this.latencyMs,
    this.errorCode,
    this.errorMessage,
    this.appPlatform,
    this.appVersion,
    this.endedAt,
    this.deviceId,
    this.vehicleId,
  });

  String dataMode;
  String transport;

  /// connected | unreachable | timeout | rejected | error
  String adapterStatus;

  /// connected | no_response | bus_error | not_attempted | error
  String ecuStatus;
  String? protocolCode;
  String? protocolName;
  String? adapterFirmware;
  int attempts;
  int? latencyMs;
  String? errorCode;
  String? errorMessage;
  String? appPlatform;
  String? appVersion;
  DateTime startedAt;
  DateTime? endedAt;
  String? deviceId;
  String? vehicleId;

  Map<String, dynamic> toJson() => {
        if (deviceId != null) 'device_id': deviceId,
        if (vehicleId != null) 'vehicle_id': vehicleId,
        'data_mode': dataMode,
        'transport': transport,
        'adapter_status': adapterStatus,
        'ecu_status': ecuStatus,
        'protocol_code': protocolCode,
        'protocol_name': protocolName,
        'adapter_firmware': adapterFirmware,
        'attempts': attempts,
        'latency_ms': latencyMs,
        'error_code': errorCode,
        'error_message': errorMessage,
        'app_platform': appPlatform,
        'app_version': appVersion,
        'started_at': startedAt.toUtc().toIso8601String(),
        'ended_at': endedAt?.toUtc().toIso8601String(),
      };
}
