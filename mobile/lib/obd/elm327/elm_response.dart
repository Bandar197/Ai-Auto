/// Result types for the ELM327 command layer.
library;

/// Error strings an ELM327 can return, mapped to stable codes
/// (same codes as `shared/obd/protocols.json` → `elm_errors`).
enum ElmErrorKind {
  noData('ecu_no_data', true),
  unableToConnect('ecu_unable_to_connect', true),
  busInitError('bus_init_error', true),
  busError('bus_error', true),
  canError('can_error', true),
  bufferFull('buffer_full', false),
  dataError('data_error', true),
  feedbackError('feedback_error', true),
  lowVoltageReset('low_voltage_reset', false),
  stopped('stopped', false),
  activityAlert('activity_alert', false),
  unknownCommand('unknown_command', false),
  timeout('adapter_timeout', false),
  transportClosed('transport_closed', false);

  const ElmErrorKind(this.code, this.isVehicleSide);

  /// Stable error code reported to the backend.
  final String code;

  /// true → adapter ↔ car link problem; false → phone ↔ adapter / adapter itself.
  final bool isVehicleSide;
}

/// Maps one cleaned response line to an error kind, or null if it is data.
ElmErrorKind? classifyElmLine(String line) {
  final l = line.trim().toUpperCase();
  if (l.isEmpty) return null;
  if (l == '?') return ElmErrorKind.unknownCommand;
  if (l.startsWith('NO DATA')) return ElmErrorKind.noData;
  if (l.startsWith('UNABLE TO CONNECT')) return ElmErrorKind.unableToConnect;
  if (l.startsWith('BUS INIT') && l.contains('ERROR')) return ElmErrorKind.busInitError;
  if (l.startsWith('CAN ERROR')) return ElmErrorKind.canError;
  if (l.startsWith('BUS ERROR') || l.startsWith('BUS BUSY')) return ElmErrorKind.busError;
  if (l.startsWith('BUFFER FULL')) return ElmErrorKind.bufferFull;
  if (l.startsWith('STOPPED')) return ElmErrorKind.stopped;
  if (l.startsWith('LV RESET')) return ElmErrorKind.lowVoltageReset;
  if (l.contains('DATA ERROR')) return ElmErrorKind.dataError;
  if (l.startsWith('FB ERROR')) return ElmErrorKind.feedbackError;
  if (l.startsWith('ACT ALERT')) return ElmErrorKind.activityAlert;
  if (RegExp(r'^ERR\d+').hasMatch(l)) return ElmErrorKind.busError;
  return null;
}

class ElmResponse {
  const ElmResponse({
    required this.command,
    required this.raw,
    required this.lines,
    required this.elapsed,
    this.error,
    this.errorLine,
    this.searched = false,
  });

  final String command;

  /// Everything received before the prompt (unmodified, `>` excluded).
  final String raw;

  /// Cleaned data lines: echo, `SEARCHING...`, `BUS INIT: ...OK` and error
  /// lines removed. Empty when [error] is set.
  final List<String> lines;
  final Duration elapsed;
  final ElmErrorKind? error;
  final String? errorLine;

  /// The adapter performed an automatic protocol search for this command.
  final bool searched;

  bool get ok => error == null;

  /// First cleaned line or empty string (handy for AT commands).
  String get text => lines.isEmpty ? '' : lines.join('\n');

  @override
  String toString() => 'ElmResponse($command → ${ok ? lines : error})';
}
