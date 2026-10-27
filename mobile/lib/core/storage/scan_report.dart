/// A scan as kept on the phone (history + offline upload queue).
class ScanReport {
  ScanReport({
    required this.id,
    required this.createdAt,
    required this.dataMode,
    this.originalMode,
    this.simulator = false,
    this.scenarioKey,
    this.recordingId,
    this.serverRecordingId,
    this.vin,
    this.protocolName,
    this.dtcs = const [],
    this.freezeFrames = const [],
    this.diagnosis,
    this.serverSessionId,
    this.uploadState = 'pending',
    this.lastError,
    this.vehicleId,
    this.connectionLog,
    this.milOn,
    this.sessionState,
    this.origin,
    this.measured = const [],
  });

  factory ScanReport.fromJson(Map<String, dynamic> j) => ScanReport(
        id: j['id'] as String,
        createdAt: DateTime.parse(j['created_at'] as String),
        dataMode: j['data_mode'] as String,
        originalMode: j['original_mode'] as String?,
        simulator: j['simulator'] as bool? ?? false,
        scenarioKey: j['scenario_key'] as String?,
        recordingId: j['recording_id'] as String?,
        serverRecordingId: j['server_recording_id'] as String?,
        vin: j['vin'] as String?,
        protocolName: j['protocol_name'] as String?,
        dtcs: [for (final d in (j['dtcs'] as List? ?? const [])) Map<String, dynamic>.from(d as Map)],
        freezeFrames: [for (final d in (j['freeze_frames'] as List? ?? const [])) Map<String, dynamic>.from(d as Map)],
        diagnosis: (j['diagnosis'] as Map?)?.cast<String, dynamic>(),
        serverSessionId: j['server_session_id'] as String?,
        uploadState: j['upload_state'] as String? ?? 'pending',
        lastError: j['last_error'] as String?,
        vehicleId: j['vehicle_id'] as String?,
        connectionLog: (j['connection_log'] as Map?)?.cast<String, dynamic>(),
        milOn: j['mil_on'] as bool?,
        sessionState: j['session_state'] as String?,
        origin: j['origin'] as String?,
        measured: [for (final m in (j['measured'] as List? ?? const [])) Map<String, dynamic>.from(m as Map)],
      );

  final String id;
  final DateTime createdAt;

  /// live | demo | replay
  final String dataMode;

  /// For replays: the data_mode of the original recording (live/demo).
  final String? originalMode;
  final bool simulator;
  final String? scenarioKey;
  final String? recordingId;
  String? serverRecordingId;
  final String? vin;
  final String? protocolName;
  final List<Map<String, dynamic>> dtcs;
  final List<Map<String, dynamic>> freezeFrames;
  Map<String, dynamic>? diagnosis;
  String? serverSessionId;

  /// pending | uploaded | failed | local_only
  String uploadState;
  String? lastError;
  final String? vehicleId;
  final Map<String, dynamic>? connectionLog;
  final bool? milOn;

  /// null/'completed' = normal; 'interrupted' = recovered from a journal after the
  /// session was cut short (data up to the interruption only).
  final String? sessionState;
  bool get interrupted => sessionState == 'interrupted';

  /// null = captured on this device; 'imported' = read from a file.
  final String? origin;
  bool get imported => origin == 'imported';

  /// Problems seen in measured live values (see `measured_findings.dart`) — e.g. an
  /// overheating engine that stored no fault code.
  final List<Map<String, dynamic>> measured;

  bool get isDemo => dataMode == 'demo' || (dataMode == 'replay' && originalMode == 'demo');
  bool get isReplay => dataMode == 'replay';
  int? get healthScore => (diagnosis?['health_score'] as num?)?.toInt();
  String? get healthBand => diagnosis?['health_band'] as String?;

  Map<String, dynamic> toJson() => {
        'id': id,
        'created_at': createdAt.toUtc().toIso8601String(),
        'data_mode': dataMode,
        'original_mode': originalMode,
        'simulator': simulator,
        'scenario_key': scenarioKey,
        'recording_id': recordingId,
        'server_recording_id': serverRecordingId,
        'vin': vin,
        'protocol_name': protocolName,
        'dtcs': dtcs,
        'freeze_frames': freezeFrames,
        'diagnosis': diagnosis,
        'server_session_id': serverSessionId,
        'upload_state': uploadState,
        'last_error': lastError,
        'vehicle_id': vehicleId,
        'connection_log': connectionLog,
        'mil_on': milOn,
        if (sessionState != null) 'session_state': sessionState,
        if (origin != null) 'origin': origin,
        if (measured.isNotEmpty) 'measured': measured,
      };
}
