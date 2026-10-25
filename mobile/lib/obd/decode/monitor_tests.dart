/// SAE J1979 service 06 (on-board monitoring test results), CAN format:
/// `46 MID TID UASID TVhi TVlo MINhi MINlo MAXhi MAXlo` — 9 bytes per test after 0x46.
/// Pass/fail is decided on the raw values (min ≤ value ≤ max), which is valid for any
/// unit; values are shown raw with their Unit-and-Scaling ID (UASID) — no guessed units.
class MonitorTest {
  const MonitorTest({required this.mid, required this.tid, required this.uasid, required this.value, required this.min, required this.max, this.ecu});
  final int mid;
  final int tid;
  final int uasid;
  final int value;
  final int min;
  final int max;
  final String? ecu;

  /// UASIDs 0x80–0xFE carry signed two's-complement values.
  bool get signed => uasid >= 0x80 && uasid <= 0xFE;
  bool get passed => value >= min && value <= max;

  Map<String, dynamic> toJson() => {
        'mid': mid, 'tid': tid, 'uasid': uasid, 'value': value, 'min': min, 'max': max, 'passed': passed, 'ecu': ?ecu,
      };
}

int _s16(int v, bool signed) => signed && v >= 0x8000 ? v - 0x10000 : v;

/// Parses one positive 06 response (`data` starts with 0x46). Incomplete trailing
/// bytes (a cut multi-frame) are ignored, never padded.
List<MonitorTest> parseMonitorResponse(List<int> data, {String? ecu}) {
  if (data.isEmpty || data[0] != 0x46) return const [];
  final out = <MonitorTest>[];
  for (var i = 1; i + 9 <= data.length; i += 9) {
    final uasid = data[i + 2];
    final signed = uasid >= 0x80 && uasid <= 0xFE;
    int w(int o) => _s16((data[i + o] << 8) | data[i + o + 1], signed);
    out.add(MonitorTest(mid: data[i], tid: data[i + 1], uasid: uasid, value: w(3), min: w(5), max: w(7), ecu: ecu));
  }
  return out;
}

/// MIDs that are "supported MIDs" bitmaps (0x00, 0x20, 0x40 …).
bool isAvailabilityMid(int mid) => mid % 0x20 == 0;

/// Names for common OBD monitor IDs (SAE J1979 Appendix D). Unknown MIDs are shown
/// by their hex id only.
const Map<int, (String, String)> kMidNames = {
  0x01: ('O2 sensor monitor — bank 1 sensor 1', 'مراقبة حساس الأكسجين — الجهة 1 الحساس 1'),
  0x02: ('O2 sensor monitor — bank 1 sensor 2', 'مراقبة حساس الأكسجين — الجهة 1 الحساس 2'),
  0x03: ('O2 sensor monitor — bank 1 sensor 3', 'مراقبة حساس الأكسجين — الجهة 1 الحساس 3'),
  0x05: ('O2 sensor monitor — bank 2 sensor 1', 'مراقبة حساس الأكسجين — الجهة 2 الحساس 1'),
  0x06: ('O2 sensor monitor — bank 2 sensor 2', 'مراقبة حساس الأكسجين — الجهة 2 الحساس 2'),
  0x21: ('Catalyst monitor — bank 1', 'مراقبة دبة التلوث — الجهة 1'),
  0x22: ('Catalyst monitor — bank 2', 'مراقبة دبة التلوث — الجهة 2'),
  0x31: ('EGR monitor — bank 1', 'مراقبة صمام EGR — الجهة 1'),
  0x35: ('VVT monitor — bank 1', 'مراقبة التوقيت المتغير VVT — الجهة 1'),
  0x39: ('EVAP monitor (cap off)', 'مراقبة نظام أبخرة الوقود (الغطاء مفتوح)'),
  0x3A: ('EVAP monitor (0.090")', 'مراقبة نظام أبخرة الوقود (تسريب 0.090")'),
  0x3B: ('EVAP monitor (0.040")', 'مراقبة نظام أبخرة الوقود (تسريب 0.040")'),
  0x3C: ('EVAP monitor (0.020")', 'مراقبة نظام أبخرة الوقود (تسريب 0.020")'),
  0x3D: ('Purge flow monitor', 'مراقبة تدفق التنظيف (Purge)'),
  0x41: ('O2 sensor heater — bank 1 sensor 1', 'سخّان حساس الأكسجين — الجهة 1 الحساس 1'),
  0x42: ('O2 sensor heater — bank 1 sensor 2', 'سخّان حساس الأكسجين — الجهة 1 الحساس 2'),
  0x45: ('O2 sensor heater — bank 2 sensor 1', 'سخّان حساس الأكسجين — الجهة 2 الحساس 1'),
  0x46: ('O2 sensor heater — bank 2 sensor 2', 'سخّان حساس الأكسجين — الجهة 2 الحساس 2'),
  0x61: ('Heated catalyst — bank 1', 'دبة التلوث المسخّنة — الجهة 1'),
  0x71: ('Secondary air monitor 1', 'مراقبة الهواء الثانوي 1'),
  0x81: ('Fuel system monitor — bank 1', 'مراقبة نظام الوقود — الجهة 1'),
  0x82: ('Fuel system monitor — bank 2', 'مراقبة نظام الوقود — الجهة 2'),
  0xA1: ('Misfire monitor — general data', 'مراقبة خلل الإشعال — بيانات عامة'),
  0xA2: ('Misfire — cylinder 1', 'خلل الإشعال — السلندر 1'),
  0xA3: ('Misfire — cylinder 2', 'خلل الإشعال — السلندر 2'),
  0xA4: ('Misfire — cylinder 3', 'خلل الإشعال — السلندر 3'),
  0xA5: ('Misfire — cylinder 4', 'خلل الإشعال — السلندر 4'),
  0xA6: ('Misfire — cylinder 5', 'خلل الإشعال — السلندر 5'),
  0xA7: ('Misfire — cylinder 6', 'خلل الإشعال — السلندر 6'),
  0xA8: ('Misfire — cylinder 7', 'خلل الإشعال — السلندر 7'),
  0xA9: ('Misfire — cylinder 8', 'خلل الإشعال — السلندر 8'),
};

String midName(int mid, String lang) {
  final n = kMidNames[mid];
  final hex = 'MID \$${mid.toRadixString(16).padLeft(2, '0').toUpperCase()}';
  return n == null ? hex : (lang == 'ar' ? n.$2 : n.$1);
}

/// Result of a service 06 read.
class MonitorTestReport {
  const MonitorTestReport({this.tests = const [], this.supportedMids = const {}, this.unsupportedReason});
  final List<MonitorTest> tests;
  final Set<int> supportedMids;

  /// 'not_can' (legacy format not decoded) | 'not_supported' (no MIDs) | null.
  final String? unsupportedReason;

  int get failed => tests.where((t) => !t.passed).length;
}
