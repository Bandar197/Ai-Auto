/// UDS (ISO 14229) extended diagnostics over an ELM327, for non-powertrain modules.
///
/// Generic OBD-II only reaches the powertrain ECU. Airbag (SRS), ABS and body
/// modules answer on manufacturer-specific CAN addresses using UDS service
/// 0x19 0x02 (ReadDTCByStatusMask). The ELM327 is just a CAN gateway: we point it
/// at a module with ATSH/ATCRA, turn headers off for a clean payload, then send
/// the UDS request. This file holds the pure codecs plus a read driver.
///
/// Reading is informational and safe. Clearing (service 0x14) is NOT done here;
/// it stays behind the server-approved, policy-gated path.
library;

import '../elm327/elm327.dart';
import '../hex.dart';
import 'dtc.dart';

const int kUdsReadDtc = 0x19;
const int kUdsClearDtc = 0x14;
const int kSubfnByStatusMask = 0x02;
const int kPositiveOffset = 0x40;
const int kNegativeResponse = 0x7F;

/// status-of-DTC bit meanings (ISO 14229-1 Annex D).
const Map<int, String> kStatusBits = {
  0: 'test_failed',
  1: 'test_failed_this_cycle',
  2: 'pending',
  3: 'confirmed',
  4: 'test_not_completed_since_clear',
  5: 'test_failed_since_clear',
  6: 'test_not_completed_this_cycle',
  7: 'warning_indicator',
};

/// ISO 14229-1 negative response codes surfaced by name.
const Map<int, String> kNrc = {
  0x10: 'general_reject',
  0x11: 'service_not_supported',
  0x12: 'subfunction_not_supported',
  0x13: 'incorrect_length_or_format',
  0x22: 'conditions_not_correct',
  0x31: 'request_out_of_range',
  0x33: 'security_access_denied',
  0x7F: 'service_not_supported_in_active_session',
};

enum ModuleCategory {
  airbag('airbag'),
  abs('abs'),
  other('other');

  const ModuleCategory(this.value);
  final String value;
}

/// A diagnostic module addressed over UDS. Addresses are per-vehicle data.
class UdsModule {
  const UdsModule({
    required this.key,
    required this.nameEn,
    required this.nameAr,
    required this.requestId,
    required this.responseId,
    this.idBits = 11,
    this.category = ModuleCategory.other,
  });

  final String key;
  final String nameEn;
  final String nameAr;
  final int requestId;
  final int responseId;
  final int idBits; // 11 or 29
  final ModuleCategory category;

  String name(String lang) => lang == 'ar' ? nameAr : nameEn;
}

class UdsDtc {
  const UdsDtc({required this.code, required this.ftb, required this.status, required this.flags});

  final String code; // standard 5-char code, e.g. "B0051"
  final int ftb; // failure type byte (3rd DTC byte); 0 for 2-byte codes
  final int status; // raw status-of-DTC byte
  final List<String> flags; // decoded status bit names

  String get display => ftb != 0 ? '$code-${hex2(ftb)}' : code;
  bool get confirmed => flags.contains('confirmed');

  /// The module reports the fault as failing now — the SRS active-fault signal.
  bool get active => flags.contains('test_failed');

  Dtc toDtc(String? ecu) =>
      Dtc(code, confirmed ? DtcStatus.stored : DtcStatus.pending, ecu: ecu);
}

class UdsException implements Exception {
  UdsException(this.code, {this.detail = '', this.nrc});
  final String code;
  final String detail;
  final int? nrc;
  @override
  String toString() => detail.isEmpty ? code : detail;
}

class UdsResult {
  UdsResult({required this.module, required this.request, required this.responseRaw, this.dtcs = const [], this.ok = true});
  final String module;
  final String request;
  final String responseRaw;
  final List<UdsDtc> dtcs;
  final bool ok;
}

// --------------------------------------------------------------------------- pure codecs
String buildReadDtcRequest([int statusMask = 0xFF]) {
  if (statusMask < 0 || statusMask > 0xFF) throw ArgumentError('status_mask must be a byte');
  return '${hex2(kUdsReadDtc)}${hex2(kSubfnByStatusMask)}${hex2(statusMask)}';
}

String buildClearRequest([int group = 0xFFFFFF]) {
  if (group < 0 || group > 0xFFFFFF) throw ArgumentError('group must be a 3-byte value');
  return '${hex2(kUdsClearDtc)}${group.toRadixString(16).toUpperCase().padLeft(6, '0')}';
}

List<String> decodeStatusFlags(int b) =>
    [for (final e in kStatusBits.entries) if ((b & (1 << e.key)) != 0) e.value];

void _checkNegative(List<int> data, int expectedSid) {
  if (data.isNotEmpty && data[0] == kNegativeResponse) {
    final nrc = data.length > 2 ? data[2] : null;
    throw UdsException(
      kNrc[nrc ?? -1] ?? 'negative_response',
      detail: nrc != null
          ? 'negative response to service 0x${hex2(expectedSid)}: NRC 0x${hex2(nrc)}'
          : 'negative response',
      nrc: nrc,
    );
  }
}

/// Parse a 0x59 0x02 response into DTCs. Each record is 4 bytes: 3 DTC + 1 status.
List<UdsDtc> parseReadDtcResponse(List<int> data) {
  _checkNegative(data, kUdsReadDtc);
  if (data.length < 2 || data[0] != kUdsReadDtc + kPositiveOffset || data[1] != kSubfnByStatusMask) {
    throw UdsException('unexpected_response', detail: 'not a 0x59 0x02 response');
  }
  final body = data.sublist(3 > data.length ? data.length : 3); // skip SID, subfn, availability mask
  final out = <UdsDtc>[];
  for (var i = 0; i + 3 < body.length; i += 4) {
    final hi = body[i], mid = body[i + 1], ftb = body[i + 2], status = body[i + 3];
    if (hi == 0 && mid == 0 && ftb == 0) continue;
    final code = decodeDtc(hi, mid);
    if (code == null) continue;
    out.add(UdsDtc(code: code, ftb: ftb, status: status, flags: decodeStatusFlags(status)));
  }
  return out;
}

bool parseClearResponse(List<int> data) {
  _checkNegative(data, kUdsClearDtc);
  return data.isNotEmpty && data[0] == kUdsClearDtc + kPositiveOffset;
}

/// Lenient hex extraction: keep only hex tokens, join, drop a trailing nibble.
List<int> udsHexToBytes(String raw) {
  final toks = raw.replaceAll('\r', ' ').replaceAll('\n', ' ').split(' ');
  final joined = toks.where((t) => t.isNotEmpty && isHexString(t)).join();
  final even = joined.length.isOdd ? joined.substring(0, joined.length - 1) : joined;
  return parseHexBytes(even) ?? const [];
}

/// Curated, UNVERIFIED discovery candidates for the in-app module scan. These are
/// starting points (addresses differ per make/model year); the scan reports which
/// answer, and the real addresses are confirmed per vehicle. Kept short so the scan
/// is quick on a phone. 29-bit FCA entries only answer when the adapter is in 29-bit
/// mode; 11-bit entries cover most other makes via the request+8 convention.
const List<UdsModule> kDiscoveryCandidates = [
  UdsModule(key: 'srs_11', nameEn: 'Airbag (SRS)', nameAr: 'الوسائد الهوائية (SRS)',
      requestId: 0x7D0, responseId: 0x7D8, category: ModuleCategory.airbag),
  UdsModule(key: 'abs_11', nameEn: 'ABS / Stability', nameAr: 'نظام ABS / الثبات',
      requestId: 0x7B0, responseId: 0x7B8, category: ModuleCategory.abs),
  UdsModule(key: 'bcm_11', nameEn: 'Body Control (BCM)', nameAr: 'وحدة الهيكل (BCM)',
      requestId: 0x7A0, responseId: 0x7A8),
  UdsModule(key: 'srs_fca', nameEn: 'Airbag (SRS, FCA)', nameAr: 'الوسائد الهوائية (كرايسلر)',
      requestId: 0x18DA58F1, responseId: 0x18DAF158, idBits: 29, category: ModuleCategory.airbag),
  UdsModule(key: 'abs_fca', nameEn: 'ABS (FCA)', nameAr: 'نظام ABS (كرايسلر)',
      requestId: 0x18DA28F1, responseId: 0x18DAF128, idBits: 29, category: ModuleCategory.abs),
  UdsModule(key: 'bcm_fca', nameEn: 'Body Control (FCA)', nameAr: 'وحدة الهيكل (كرايسلر)',
      requestId: 0x18DA40F1, responseId: 0x18DAF140, idBits: 29),
];

/// One module's result from a scan, carrying its definition for display.
class ModuleScan {
  const ModuleScan({required this.module, this.dtcs = const [], this.refused = false});
  final UdsModule module;
  final List<UdsDtc> dtcs;

  /// Present but it refused the request (e.g. a security gateway); codes unknown.
  final bool refused;
}

/// Probes [candidates] (read-only) and returns the modules that answered, each with its DTCs.
/// A module that refuses (negative response) still counts as present, with an empty DTC list.
Future<List<ModuleScan>> scanModules(
  Elm327 elm, {
  List<UdsModule> candidates = kDiscoveryCandidates,
  Duration perModuleTimeout = const Duration(milliseconds: 700),
}) async {
  final present = <ModuleScan>[];
  for (final m in candidates) {
    try {
      final res = await readModuleDtcs(elm, m, timeout: perModuleTimeout);
      final data = udsHexToBytes(res.responseRaw);
      if (data.isNotEmpty && data[0] == kUdsReadDtc + kPositiveOffset) {
        present.add(ModuleScan(module: m, dtcs: res.dtcs));
      }
    } on UdsException {
      present.add(ModuleScan(module: m, refused: true)); // present but refused (e.g. gateway)
    } catch (_) {
      // No answer / link error → treat as absent.
    }
  }
  return present;
}

String _atHeader(String at, int id, int bits) => bits == 11
    ? '$at${id.toRadixString(16).toUpperCase().padLeft(3, '0')}'
    : '$at${id.toRadixString(16).toUpperCase().padLeft(8, '0')}';

/// Reads one module's fault codes over UDS. Read-only. Restores OBD addressing after.
Future<UdsResult> readModuleDtcs(Elm327 elm, UdsModule module, {int statusMask = 0xFF, Duration? timeout}) async {
  final req = buildReadDtcRequest(statusMask);
  try {
    await elm.send(_atHeader('ATSH', module.requestId, module.idBits));
    await elm.send(_atHeader('ATCRA', module.responseId, module.idBits));
    await elm.send('ATH0'); // headers off → clean ISO-TP payload
    final resp = await elm.sendExtendedRead(req, timeout: timeout);
    final data = udsHexToBytes(resp.raw);
    final dtcs = data.isEmpty ? <UdsDtc>[] : parseReadDtcResponse(data);
    return UdsResult(module: module.key, request: req, responseRaw: resp.raw, dtcs: dtcs);
  } finally {
    // Best-effort restore to normal OBD broadcast addressing.
    try {
      await elm.send('ATH1');
      await elm.send('ATCRA');
      await elm.send(module.idBits == 11 ? 'ATSH7DF' : 'ATSH18DB33F1');
    } catch (_) {}
  }
}
