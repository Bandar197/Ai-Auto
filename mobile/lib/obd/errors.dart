/// Typed errors of the OBD stack. They separate the two physical links:
/// phone ↔ adapter ([TransportException], [AdapterTimeoutException]) and
/// adapter ↔ vehicle ([EcuException]).
library;

class ObdException implements Exception {
  ObdException(this.code, [this.message = '']);
  final String code;
  final String message;
  @override
  String toString() => 'ObdException($code${message.isEmpty ? '' : ': $message'})';
}

/// The phone ↔ adapter link failed (socket refused/closed, BLE dropped).
class TransportException extends ObdException {
  TransportException(String message, {String code = 'transport_error'}) : super(code, message);
}

/// The adapter did not answer with a `>` prompt in time.
class AdapterTimeoutException extends ObdException {
  AdapterTimeoutException(String command) : super('adapter_timeout', 'no prompt after "$command"');
}

/// The adapter ↔ vehicle link failed (NO DATA, UNABLE TO CONNECT, bus errors).
class EcuException extends ObdException {
  EcuException(super.code, [super.message]);
}

/// A request the vehicle did not report as supported.
class NotSupportedException extends ObdException {
  NotSupportedException(String what) : super('not_supported', what);
}

/// An ECU write was attempted without server approval / safe conditions.
class PolicyViolationException extends ObdException {
  PolicyViolationException(String message) : super('policy_violation', message);
}
