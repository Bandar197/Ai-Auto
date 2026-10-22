import '../../obd/verify/recurrence.dart';

/// A clear performed through the app plus every check taken afterwards.
/// Persisted on the phone so verification works offline and across restarts.
class ClearEntry {
  ClearEntry({
    required this.id,
    required this.vehicleKey,
    required this.record,
    this.vehicleId,
    this.scenarioKey,
    this.sessionId,
    this.reportId,
    this.freezeFrame,
    List<ScanSnapshot>? checks,
    this.verification,
    this.verificationSource,
    this.open = true,
  }) : checks = checks ?? [];

  factory ClearEntry.fromJson(Map<String, dynamic> j) => ClearEntry(
        id: j['id'] as String,
        vehicleKey: j['vehicle_key'] as String,
        record: ClearRecord.fromJson(Map<String, dynamic>.from(j['record'] as Map)),
        vehicleId: j['vehicle_id'] as String?,
        scenarioKey: j['scenario_key'] as String?,
        sessionId: j['session_id'] as String?,
        reportId: j['report_id'] as String?,
        freezeFrame: (j['freeze_frame'] as Map?)?.cast<String, dynamic>(),
        checks: [for (final c in (j['checks'] as List? ?? const [])) ScanSnapshot.fromJson(Map<String, dynamic>.from(c as Map))],
        verification: j['verification'] == null ? null : ClearVerification.fromJson(Map<String, dynamic>.from(j['verification'] as Map)),
        verificationSource: j['verification_source'] as String?,
        open: j['open'] as bool? ?? true,
      );

  final String id;

  /// Server vehicle id, `vin:<VIN>`, or `demo:<scenario>`.
  final String vehicleKey;
  final ClearRecord record;
  final String? vehicleId;
  final String? scenarioKey;

  /// Session that holds the codes + freeze frame saved before clearing.
  final String? sessionId;
  final String? reportId;
  final Map<String, dynamic>? freezeFrame;
  final List<ScanSnapshot> checks;
  ClearVerification? verification;

  /// server | local
  String? verificationSource;
  bool open;

  String get dataMode => record.dataMode;
  String get overall => verification?.overall ?? 'verifying';

  Map<String, dynamic> toJson() => {
        'id': id,
        'vehicle_key': vehicleKey,
        'record': record.toJson(),
        'vehicle_id': vehicleId,
        'scenario_key': scenarioKey,
        'session_id': sessionId,
        'report_id': reportId,
        'freeze_frame': freezeFrame,
        'checks': [for (final c in checks) c.toJson()],
        'verification': verification?.toJson(),
        'verification_source': verificationSource,
        'open': open,
      };
}

/// Key that identifies "the same vehicle" for later checks.
String vehicleKeyFor({required String dataMode, String? vehicleId, String? scenarioKey, String? vin}) {
  if (dataMode == 'demo') return 'demo:${scenarioKey ?? vin ?? 'simulator'}';
  if (vehicleId != null && !vehicleId.startsWith('local-')) return vehicleId;
  if (vin != null && vin.isNotEmpty) return 'vin:$vin';
  return vehicleId ?? 'live';
}
