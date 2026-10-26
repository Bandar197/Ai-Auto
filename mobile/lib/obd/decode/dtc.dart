/// SAE J2012 diagnostic trouble codes.
library;

import '../hex.dart';

enum DtcStatus {
  stored('stored', '03'),
  pending('pending', '07'),
  permanent('permanent', '0A');

  const DtcStatus(this.apiValue, this.service);
  final String apiValue;
  final String service;

  static DtcStatus parse(String s) => DtcStatus.values.firstWhere((e) => e.apiValue == s, orElse: () => DtcStatus.stored);
}

class Dtc {
  const Dtc(this.code, this.status, {this.ecu});
  final String code;
  final DtcStatus status;
  final String? ecu;

  Map<String, dynamic> toJson() => {'code': code, 'status': status.apiValue, 'ecu': ecu};

  factory Dtc.fromJson(Map<String, dynamic> j) =>
      Dtc(j['code'] as String, DtcStatus.parse(j['status'] as String? ?? 'stored'), ecu: j['ecu'] as String?);

  /// P/C/B/U system name.
  String get system => switch (code[0]) {
        'P' => 'powertrain',
        'C' => 'chassis',
        'B' => 'body',
        _ => 'network',
      };

  @override
  bool operator ==(Object other) => other is Dtc && other.code == code && other.status == status && other.ecu == ecu;

  @override
  int get hashCode => Object.hash(code, status, ecu);

  @override
  String toString() => '$code(${status.apiValue}${ecu == null ? '' : '@$ecu'})';
}

const String _systems = 'PCBU';

/// Decodes two DTC bytes; null for the 0x0000 filler.
String? decodeDtc(int b1, int b2) {
  if (b1 == 0 && b2 == 0) return null;
  final letter = _systems[(b1 >> 6) & 0x03];
  final d1 = (b1 >> 4) & 0x03;
  return '$letter$d1${(b1 & 0x0F).toRadixString(16).toUpperCase()}${hex2(b2)}';
}

List<int> encodeDtc(String code) {
  final c = code.trim().toUpperCase();
  final sys = _systems.indexOf(c[0]);
  if (c.length != 5 || sys < 0) throw ArgumentError('invalid DTC $code');
  final d1 = int.parse(c[1], radix: 16);
  if (d1 > 3) throw ArgumentError('invalid DTC $code');
  return [(sys << 6) | (d1 << 4) | int.parse(c[2], radix: 16), int.parse(c.substring(3), radix: 16)];
}

/// Decodes a DTC list from pairs of bytes, skipping `00 00` fillers.
List<String> decodeDtcPairs(List<int> bytes) {
  final out = <String>[];
  for (var i = 0; i + 1 < bytes.length; i += 2) {
    final c = decodeDtc(bytes[i], bytes[i + 1]);
    if (c != null) out.add(c);
  }
  return out;
}
