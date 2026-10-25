import '../obd/obd.dart';

/// The ten ECU states of the developer prompt (recording.v2 `ecu_coverage.state`).
enum EcuState10 {
  discovered('discovered'),
  reachable('reachable'),
  dtcReadSupported('dtc_read_supported'),
  clearSupported('clear_supported'),
  notSupported('not_supported'),
  timedOut('timed_out'),
  gatewayBlocked('gateway_blocked'),
  refused('refused'),
  passed('passed'),
  faultsPresent('faults_present');

  const EcuState10(this.wire);
  final String wire;
}

/// One row of the ECU map.
class EcuEntry {
  const EcuEntry({
    required this.key,
    required this.nameEn,
    required this.nameAr,
    required this.state,
    this.flags = const {},
    this.requestId,
    this.responseId,
    this.idBits,
    this.verified,
    this.source,
    this.nrc,
    this.codes = const [],
  });

  final String key;
  final String nameEn;
  final String nameAr;

  /// The headline state (never "passed" without a successful read).
  final EcuState10 state;

  /// Capabilities shown next to it (reachable, dtc_read_supported, clear_supported).
  final Set<EcuState10> flags;
  final String? requestId;
  final String? responseId;
  final int? idBits;

  /// Address verified on a real car (registry `verified`), null for OBD ECUs.
  final bool? verified;

  /// Where the address came from (e.g. "OBD-II standard", "modules.json").
  final String? source;
  final int? nrc;
  final List<String> codes;

  String name(String lang) => lang == 'ar' ? nameAr : nameEn;

  Map<String, dynamic> toCoverageJson() => {
        'key': key,
        'name_en': nameEn,
        'name_ar': nameAr,
        'state': state.wire,
        'request_id': ?requestId,
        'response_id': ?responseId,
        'id_bits': ?idBits,
        if (codes.isNotEmpty) 'dtc_count': codes.length,
        if (nrc != null) 'reason': 'NRC 0x${nrc!.toRadixString(16).padLeft(2, '0').toUpperCase()}',
        if (source != null) 'source': '$source${verified == false ? ' verified=false' : ''}',
      };
}

/// NRCs meaning "this service is not supported here".
const Set<int> kNotSupportedNrcs = {0x11, 0x12, 0x7F};

/// NRC 0x33 (security access denied) — typical of a security gateway.
const int kGatewayNrc = 0x33;

/// Builds the ECU map from a recording. A module that did not answer is "timed out",
/// one that refused keeps its NRC; "passed" only after a successful read with no codes.
/// OBD ECUs (from the 01 00 responders) are "reachable" — and "faults present" with codes;
/// they are not called "passed" because a failed 03 read is not recorded as such.
List<EcuEntry> buildEcuMap(Recording rec, {List<UdsModule> registry = const []}) {
  final out = <EcuEntry>[];
  for (final ecu in rec.ecus) {
    final codes = [for (final d in rec.dtcs) if (d.ecu == null || d.ecu == ecu) d.code];
    final resp = int.tryParse(ecu, radix: 16);
    out.add(EcuEntry(
      key: 'obd_$ecu',
      nameEn: 'OBD-II ECU $ecu',
      nameAr: 'كمبيوتر OBD-II ‏$ecu',
      state: codes.isEmpty ? EcuState10.reachable : EcuState10.faultsPresent,
      flags: {EcuState10.discovered, EcuState10.reachable, EcuState10.dtcReadSupported},
      requestId: resp != null && resp >= 0x7E8 && resp <= 0x7EF ? (resp - 8).toRadixString(16).toUpperCase() : null,
      responseId: ecu,
      idBits: ecu.length > 3 ? 29 : 11,
      source: 'OBD-II standard',
      codes: codes.toSet().toList(),
    ));
  }
  for (final m in rec.moduleScans) {
    final reg = registry.where((r) => r.key == m.key && _hex(r.requestId, r.idBits) == (m.address ?? '')).firstOrNull ??
        registry.where((r) => _hex(r.requestId, r.idBits) == (m.address ?? '')).firstOrNull;
    final flags = <EcuState10>{};
    EcuState10 state;
    switch (m.outcome) {
      case 'read_codes':
        state = EcuState10.faultsPresent;
        flags.addAll({EcuState10.discovered, EcuState10.reachable, EcuState10.dtcReadSupported});
      case 'read_no_codes':
        state = EcuState10.passed;
        flags.addAll({EcuState10.discovered, EcuState10.reachable, EcuState10.dtcReadSupported});
      case 'refused':
        flags.addAll({EcuState10.discovered, EcuState10.reachable});
        state = m.nrc == kGatewayNrc
            ? EcuState10.gatewayBlocked
            : (kNotSupportedNrcs.contains(m.nrc) ? EcuState10.notSupported : EcuState10.refused);
      default:
        state = EcuState10.timedOut;
    }
    if (reg != null && reg.verified && reg.clearService == 'uds14' && flags.contains(EcuState10.reachable)) {
      flags.add(EcuState10.clearSupported);
    }
    out.add(EcuEntry(
      key: m.key,
      nameEn: m.nameEn,
      nameAr: m.nameAr,
      state: state,
      flags: flags,
      requestId: m.address,
      responseId: reg == null ? null : _hex(reg.responseId, reg.idBits),
      idBits: reg?.idBits ?? ((m.address ?? '').length > 3 ? 29 : 11),
      verified: reg?.verified ?? false,
      source: 'modules.json',
      nrc: m.nrc,
      codes: [for (final d in m.codes) d.code],
    ));
  }
  return out;
}

String _hex(int id, int bits) => id.toRadixString(16).toUpperCase().padLeft(bits == 29 ? 8 : 3, '0');
