/// Clear-and-verify: did a cleared trouble code come back?
///
/// Pure-Dart port of backend `automind/diagnosis/recurrence.py` (the source
/// of truth for logic and texts). Used offline and to show an instant verdict;
/// when online the server's verdict (same algorithm) is preferred.
library;

import '../recording/recording.dart';

// --------------------------------------------------------------------------- models

class SnapshotDtc {
  const SnapshotDtc(this.code, {this.status = 'stored', this.ecu});
  final String code;

  /// stored | pending | permanent
  final String status;
  final String? ecu;

  factory SnapshotDtc.fromJson(Map<String, dynamic> j) =>
      SnapshotDtc(j['code'] as String, status: j['status'] as String? ?? 'stored', ecu: j['ecu'] as String?);
  Map<String, dynamic> toJson() => {'code': code, 'status': status, 'ecu': ecu};
}

class ScanSnapshot {
  ScanSnapshot({
    required this.takenAt,
    this.sessionId,
    this.dtcs = const [],
    this.readiness,
    this.warmupsSinceClear,
    this.distanceSinceClearKm,
    this.engineRunning,
    this.readOk,
  });

  factory ScanSnapshot.fromJson(Map<String, dynamic> j) => ScanSnapshot(
        takenAt: DateTime.parse(j['taken_at'] as String),
        sessionId: j['session_id'] as String?,
        dtcs: [for (final d in (j['dtcs'] as List? ?? const [])) SnapshotDtc.fromJson(Map<String, dynamic>.from(d as Map))],
        readiness: (j['readiness'] as Map?)?.cast<String, dynamic>(),
        warmupsSinceClear: (j['warmups_since_clear'] as num?)?.toDouble(),
        distanceSinceClearKm: (j['distance_since_clear_km'] as num?)?.toDouble(),
        engineRunning: j['engine_running'] as bool?,
        readOk: j['read_ok'] as bool?,
      );

  final DateTime takenAt;
  final String? sessionId;
  final List<SnapshotDtc> dtcs;
  final Map<String, dynamic>? readiness;
  final double? warmupsSinceClear;
  final double? distanceSinceClearKm;
  final bool? engineRunning;

  /// The stored-code read (service 03) succeeded. false = an empty code list means
  /// "couldn't read", NOT "cleared". null = unknown (older snapshots).
  final bool? readOk;

  Map<String, dynamic> toJson() => {
        'taken_at': takenAt.toUtc().toIso8601String(),
        'session_id': ?sessionId,
        'dtcs': [for (final d in dtcs) d.toJson()],
        'readiness': readiness,
        'warmups_since_clear': warmupsSinceClear,
        'distance_since_clear_km': distanceSinceClearKm,
        'engine_running': engineRunning,
        'read_ok': ?readOk,
      };

  /// Snapshot of a recording (codes, readiness, counters, engine running).
  static ScanSnapshot fromRecording(Recording rec, {DateTime? takenAt, String? sessionId}) {
    final series = rec.series();
    double? last(String key) {
      final pts = series[key];
      return pts == null || pts.isEmpty ? null : pts.last.$2;
    }

    final rpm = series['engine_rpm'] ?? const [];
    return ScanSnapshot(
      takenAt: takenAt ?? rec.createdAt,
      sessionId: sessionId,
      dtcs: [for (final d in rec.dtcs) SnapshotDtc(d.code, status: d.status.apiValue, ecu: d.ecu)],
      readiness: rec.readiness,
      warmupsSinceClear: last('warmups_since_clear'),
      distanceSinceClearKm: last('distance_since_clear'),
      engineRunning: rpm.isEmpty ? null : rpm.any((p) => p.$2 > 300),
    );
  }
}

class ClearRecord {
  ClearRecord({required this.clearedAt, required this.before, this.operationId, this.dataMode = 'live'});

  factory ClearRecord.fromJson(Map<String, dynamic> j) => ClearRecord(
        clearedAt: DateTime.parse(j['cleared_at'] as String),
        before: ScanSnapshot.fromJson(Map<String, dynamic>.from(j['before'] as Map)),
        operationId: j['operation_id'] as String?,
        dataMode: j['data_mode'] as String? ?? 'live',
      );

  final DateTime clearedAt;
  final ScanSnapshot before;
  final String? operationId;

  /// live | demo | replay
  final String dataMode;

  Map<String, dynamic> toJson() => {
        'cleared_at': clearedAt.toUtc().toIso8601String(),
        'before': before.toJson(),
        'operation_id': operationId,
        'data_mode': dataMode,
      };
}

class CodeVerdict {
  CodeVerdict({
    required this.code,
    this.ecu,
    required this.family,
    required this.verdict,
    required this.isRealProblem,
    this.monitor,
    this.monitorComplete,
    this.returnedInCheck,
    required this.titleEn,
    required this.titleAr,
    required this.explanationEn,
    required this.explanationAr,
    required this.nextStepEn,
    required this.nextStepAr,
  });

  factory CodeVerdict.fromJson(Map<String, dynamic> j) => CodeVerdict(
        code: j['code'] as String,
        ecu: j['ecu'] as String?,
        family: j['family'] as String? ?? 'powertrain',
        verdict: j['verdict'] as String,
        isRealProblem: j['is_real_problem'] as bool?,
        monitor: j['monitor'] as String?,
        monitorComplete: j['monitor_complete'] as bool?,
        returnedInCheck: (j['returned_in_check'] as num?)?.toInt(),
        titleEn: j['title_en'] as String? ?? '',
        titleAr: j['title_ar'] as String? ?? '',
        explanationEn: j['explanation_en'] as String? ?? '',
        explanationAr: j['explanation_ar'] as String? ?? '',
        nextStepEn: j['next_step_en'] as String? ?? '',
        nextStepAr: j['next_step_ar'] as String? ?? '',
      );

  final String code;
  final String? ecu;

  /// powertrain | airbag_body | network | chassis
  final String family;

  /// returned_immediately | returned_confirmed | returned_pending | new_code |
  /// still_permanent | not_returned_verified | not_returned_yet
  final String verdict;

  /// null = not decided yet.
  final bool? isRealProblem;
  final String? monitor;
  final bool? monitorComplete;
  final int? returnedInCheck;
  final String titleEn, titleAr, explanationEn, explanationAr, nextStepEn, nextStepAr;

  String title(String lang) => lang == 'ar' ? titleAr : titleEn;
  String explanation(String lang) => lang == 'ar' ? explanationAr : explanationEn;
  String nextStep(String lang) => lang == 'ar' ? nextStepAr : nextStepEn;

  Map<String, dynamic> toJson() => {
        'code': code,
        'ecu': ecu,
        'family': family,
        'verdict': verdict,
        'is_real_problem': isRealProblem,
        'monitor': monitor,
        'monitor_complete': monitorComplete,
        'returned_in_check': returnedInCheck,
        'title_en': titleEn,
        'title_ar': titleAr,
        'explanation_en': explanationEn,
        'explanation_ar': explanationAr,
        'next_step_en': nextStepEn,
        'next_step_ar': nextStepAr,
      };
}

class ClearVerification {
  ClearVerification({
    required this.overall,
    required this.dataMode,
    required this.clearedAt,
    required this.checksAfterClear,
    required this.summaryEn,
    required this.summaryAr,
    required this.codes,
  });

  factory ClearVerification.fromJson(Map<String, dynamic> j) => ClearVerification(
        overall: j['overall'] as String,
        dataMode: j['data_mode'] as String? ?? 'live',
        clearedAt: DateTime.parse(j['cleared_at'] as String),
        checksAfterClear: (j['checks_after_clear'] as num?)?.toInt() ?? 0,
        summaryEn: j['summary_en'] as String? ?? '',
        summaryAr: j['summary_ar'] as String? ?? '',
        codes: [for (final c in (j['codes'] as List? ?? const [])) CodeVerdict.fromJson(Map<String, dynamic>.from(c as Map))],
      );

  /// problem_confirmed | likely_resolved | verifying | nothing_cleared
  final String overall;
  final String dataMode;
  final DateTime clearedAt;
  final int checksAfterClear;
  final String summaryEn;
  final String summaryAr;
  final List<CodeVerdict> codes;

  String summary(String lang) => lang == 'ar' ? summaryAr : summaryEn;

  Map<String, dynamic> toJson() => {
        'overall': overall,
        'data_mode': dataMode,
        'cleared_at': clearedAt.toUtc().toIso8601String(),
        'checks_after_clear': checksAfterClear,
        'summary_en': summaryEn,
        'summary_ar': summaryAr,
        'codes': [for (final c in codes) c.toJson()],
      };
}

// --------------------------------------------------------------------------- monitors

const List<(String, List<(int, int)>, List<String>)> _monitorRanges = [
  ('misfire', [(300, 316)], []),
  ('fuel_system', [(170, 175), (87, 93)], ['P2187', 'P2188', 'P2189', 'P2190']),
  ('o2_sensor_heater', [(30, 64), (135, 135), (141, 141), (155, 155), (161, 161)], []),
  ('o2_sensor', [(130, 167)], ['P2195', 'P2196', 'P2197', 'P2198', 'P2270', 'P2271', 'P2272', 'P2273']),
  ('catalyst', [(420, 439)], []),
  ('evap_system', [(440, 457), (496, 499)], []),
  ('egr_system', [(400, 409), (486, 489)], []),
  ('secondary_air', [(410, 419)], []),
];

const Map<String, (String, String)> monitorNames = {
  'misfire': ('misfire monitor', 'مراقب الاحتراق غير المكتمل'),
  'fuel_system': ('fuel system monitor', 'مراقب نظام الوقود'),
  'o2_sensor': ('oxygen sensor monitor', 'مراقب حساس الأكسجين'),
  'o2_sensor_heater': ('oxygen sensor heater monitor', 'مراقب سخان حساس الأكسجين'),
  'catalyst': ('catalyst monitor', 'مراقب المحول الحفاز (الدبة)'),
  'evap_system': ('EVAP monitor', 'مراقب نظام EVAP'),
  'egr_system': ('EGR monitor', 'مراقب EGR'),
  'secondary_air': ('secondary air monitor', 'مراقب الهواء الثانوي'),
  'components': ('comprehensive component monitor', 'مراقب المكونات الشامل'),
};

/// Readiness monitor that re-tests this powertrain code (null for non-P codes).
String? monitorFor(String code) {
  if (!code.startsWith('P')) return null;
  final numeric = code.startsWith('P0') && RegExp(r'^\d+$').hasMatch(code.substring(1));
  final n = numeric ? int.parse(code.substring(1)) : -1;
  for (final (name, ranges, exact) in _monitorRanges) {
    if (exact.contains(code)) return name;
    if (numeric && ranges.any((r) => r.$1 <= n && n <= r.$2)) return name;
  }
  return 'components';
}

String _family(String code) => switch (code.isEmpty ? 'P' : code[0]) {
      'B' => 'airbag_body',
      'U' => 'network',
      'C' => 'chassis',
      _ => 'powertrain',
    };

Set<String> _statusIn(ScanSnapshot s, String code) => {for (final d in s.dtcs) if (d.code == code) d.status};

bool _immediate(ScanSnapshot s, DateTime clearedAt) {
  final driven = (s.distanceSinceClearKm ?? 0) > 0 || (s.warmupsSinceClear ?? 0) > 0;
  return !driven && s.takenAt.difference(clearedAt).inMilliseconds < 15 * 60 * 1000;
}

bool? _monitorComplete(ScanSnapshot? s, String? monitor) {
  if (s == null || s.readiness == null || monitor == null) return null;
  final mons = s.readiness!['monitors'];
  if (mons is! Map) return null;
  final m = mons[monitor];
  if (m is! Map) return null;
  return (m['available'] ?? true) == true ? m['complete'] == true : null;
}

// --------------------------------------------------------------------------- texts

(String, String) _driveHint(String? monitor, String family) {
  if (family == 'airbag_body' || family == 'network' || family == 'chassis') {
    return (
      'Switch the ignition off and on at least twice (wait for the warning-lamp self-check each time), then scan again.',
      'أطفئ الإشعال وشغّله مرتين على الأقل (انتظر فحص اللمبات الذاتي في كل مرة) ثم افحص مرة أخرى.',
    );
  }
  if (const ['catalyst', 'evap_system', 'o2_sensor', 'o2_sensor_heater', 'egr_system', 'secondary_air'].contains(monitor)) {
    final (enM, arM) = monitorNames[monitor]!;
    return (
      'Drive normally for 2–3 days, including a cold start and 15+ minutes of steady 60–100 km/h, so the $enM can run; then scan again.',
      'قُد السيارة بشكل طبيعي يومين إلى ثلاثة، مع تشغيل والمحرك بارد و15 دقيقة أو أكثر بسرعة ثابتة 60–100 كم/س حتى يعمل $arM، ثم افحص مرة أخرى.',
    );
  }
  return (
    'Start the engine, let it reach normal temperature and drive 10–20 minutes in mixed conditions, then scan again.',
    'شغّل المحرك حتى يصل للحرارة الطبيعية وقُد 10–20 دقيقة في ظروف متنوعة، ثم افحص مرة أخرى.',
  );
}

typedef _Texts = (String, String, String, String, String, String);

_Texts _texts(String v, String code, String family, String? monitor, int? checkNo) {
  final airbag = family == 'airbag_body';
  final (hintEn, hintAr) = _driveHint(monitor, family);
  switch (v) {
    case 'returned_immediately':
      return (
        '$code came back immediately — real fault present now',
        '$code رجع فورا — العطل موجود الآن',
        'The code returned in the same key cycle, without driving. The module still detects the fault, so clearing cannot fix it.'
            '${airbag ? ' Do not assume the airbags will deploy correctly until it is repaired.' : ''}',
        'رجع الكود في نفس دورة التشغيل ودون قيادة، أي أن الكمبيوتر ما زال يكتشف العطل، والمسح لا يصلحه.'
            '${airbag ? ' لا تعتمد على عمل الوسائد الهوائية حتى يتم الإصلاح.' : ''}',
        'Do not keep clearing it. Follow the tests in the diagnosis report for this code and repair the cause.',
        'لا تكرر المسح. اتبع اختبارات التشخيص لهذا الكود في التقرير وأصلح السبب.',
      );
    case 'returned_confirmed':
      return (
        '$code came back — real fault',
        '$code رجع — يوجد عطل حقيقي',
        'The code was stored again (scan #$checkNo after clearing). The fault is real but appears only under certain conditions (intermittent or load-related).',
        'تم تخزين الكود مرة أخرى (الفحص رقم $checkNo بعد المسح). العطل حقيقي لكنه يظهر في ظروف معينة (متقطع أو مع الحمل).',
        'Have it diagnosed and repaired; the freeze frame saved before clearing shows the conditions when it happened.',
        'افحصه وأصلحه؛ الإطار المجمد المحفوظ قبل المسح يوضح الظروف التي حدث فيها.',
      );
    case 'returned_pending':
      return (
        '$code detected again (pending) — very likely real',
        '$code اكتُشف مرة أخرى (معلق) — غالبا عطل حقيقي',
        'The module detected the fault again once; the light usually turns on if it repeats on the next drive.',
        'اكتشف الكمبيوتر العطل مرة أخرى؛ عادة تضيء اللمبة إذا تكرر في القيادة التالية.',
        'Treat it as a real fault and plan the repair; scan again after the next drive to confirm.',
        'تعامل معه كعطل حقيقي وخطط للإصلاح، وافحص بعد القيادة التالية للتأكيد.',
      );
    case 'new_code':
      return (
        '$code is new since clearing',
        '$code كود جديد بعد المسح',
        'This code was not present before clearing; it is a separate issue that needs its own diagnosis.',
        'هذا الكود لم يكن موجودا قبل المسح، فهو مشكلة مستقلة تحتاج تشخيصا خاصا.',
        'Run a full scan with live data so the diagnosis engine can analyse it.',
        'شغّل فحصا كاملا مع البيانات الحية حتى يحلله محرك التشخيص.',
      );
    case 'still_permanent':
      return (
        '$code still listed as permanent — waiting for the self-test',
        '$code ما زال مسجلا كدائم — بانتظار الاختبار الذاتي',
        'Permanent codes cannot be erased by a scan tool. They disappear by themselves after the vehicle re-runs its self-test and passes. On its own this is not a sign the fault is back.',
        'الأكواد الدائمة لا يمكن مسحها بجهاز الفحص، وتختفي وحدها بعد أن تعيد السيارة اختبارها الذاتي وتنجح. وجوده وحده لا يعني أن العطل رجع.',
        hintEn,
        hintAr,
      );
    case 'not_returned_verified':
      final enM = monitorNames[monitor ?? '']?.$1 ?? 'self-test';
      final arM = monitorNames[monitor ?? '']?.$2 ?? 'الاختبار الذاتي';
      return (
        '$code did not come back — most likely an old fault',
        '$code لم يرجع — غالبا عطل قديم',
        airbag
            ? 'The airbag module self-tests at every ignition-on; the code stayed away over several key cycles. Typical causes of such an old code: a connector unplugged with the ignition on, low battery voltage, or a part (e.g. steering-wheel clock spring, seat connector) replaced.'
            : 'The $enM has run since clearing and the code did not return. Typical causes of such an old code: a part already replaced or repaired, a connector unplugged with the ignition on, or a one-off condition (e.g. low battery, loose fuel cap).',
        airbag
            ? 'كمبيوتر الوسائد يختبر نفسه عند كل تشغيل للإشعال، والكود لم يرجع خلال عدة دورات تشغيل. أسباب الكود القديم عادة: فصل فيش والإشعال يعمل، أو ضعف البطارية، أو تغيير قطعة مثل فحمة الدركسون (الساعة) أو فيش المقعد.'
            : 'تم تشغيل $arM بعد المسح ولم يرجع الكود. أسباب الكود القديم عادة: قطعة تم تغييرها أو إصلاحها، أو فصل فيش والإشعال يعمل، أو حالة عابرة (مثل ضعف البطارية أو غطاء البنزين غير محكم).',
        'No action needed now. If the light returns later, scan again — the history is kept.',
        'لا يلزم إجراء الآن. إذا رجعت اللمبة لاحقا افحص مرة أخرى، فالسجل محفوظ.',
      );
  }
  return (
    '$code not back yet — verification still running',
    '$code لم يرجع حتى الآن — التحقق مستمر',
    'The code has not returned, but the vehicle has not yet completed the self-test that would detect it, so this is not proof that it is fixed.',
    'الكود لم يرجع، لكن السيارة لم تكمل بعد الاختبار الذاتي الذي يكتشفه، لذلك هذا ليس دليلا على أنه انتهى.',
    hintEn,
    hintAr,
  );
}

// --------------------------------------------------------------------------- main

const Map<String, int> _order = {
  'returned_immediately': 0,
  'returned_confirmed': 1,
  'returned_pending': 2,
  'new_code': 3,
  'not_returned_yet': 4,
  'still_permanent': 5,
  'not_returned_verified': 6,
};

CodeVerdict _make(String code, String? ecu, String fam, String verdict, bool? real, String? mon, bool? mc, int? checkNo) {
  final (te, ta, ee, ea, ne, na) = _texts(verdict, code, fam, mon, checkNo);
  return CodeVerdict(
    code: code,
    ecu: ecu,
    family: fam,
    verdict: verdict,
    isRealProblem: real,
    monitor: mon,
    monitorComplete: mc,
    returnedInCheck: checkNo,
    titleEn: te,
    titleAr: ta,
    explanationEn: ee,
    explanationAr: ea,
    nextStepEn: ne,
    nextStepAr: na,
  );
}

ClearVerification assessAfterClear(ClearRecord record, List<ScanSnapshot> checks) {
  final after = [for (final s in checks) if (!s.takenAt.isBefore(record.clearedAt)) s]..sort((a, b) => a.takenAt.compareTo(b.takenAt));
  final beforeCodes = <String, String?>{};
  for (final d in record.before.dtcs) {
    beforeCodes.putIfAbsent(d.code, () => d.ecu);
  }
  final last = after.isEmpty ? null : after.last;
  final verdicts = <CodeVerdict>[];

  for (final code in beforeCodes.keys.toList()..sort()) {
    final ecu = beforeCodes[code];
    final fam = _family(code);
    final mon = fam == 'powertrain' ? monitorFor(code) : null;
    String? verdict;
    int? checkNo;
    for (var i = 0; i < after.length; i++) {
      final st = _statusIn(after[i], code);
      if (st.contains('stored')) {
        verdict = i == 0 && _immediate(after[i], record.clearedAt) ? 'returned_immediately' : 'returned_confirmed';
        checkNo = i + 1;
        break;
      }
      if (st.contains('pending') && verdict == null) {
        verdict = 'returned_pending';
        checkNo = i + 1;
      }
    }
    final mc = _monitorComplete(last, mon);
    if (verdict == null) {
      final lastSt = last == null ? const <String>{} : _statusIn(last, code);
      if (last != null && lastSt.contains('permanent') && lastSt.length == 1) {
        verdict = 'still_permanent';
      } else if (fam != 'powertrain') {
        verdict = after.length >= 2 ? 'not_returned_verified' : 'not_returned_yet';
      } else if (last != null) {
        final driven = (last.warmupsSinceClear ?? 0) >= 1 || (last.distanceSinceClearKm ?? 0) >= 10;
        final ok = mon == 'components' ? (driven || after.where((s) => s.engineRunning == true).length >= 2) : (mc == true && driven);
        verdict = ok ? 'not_returned_verified' : 'not_returned_yet';
      } else {
        verdict = 'not_returned_yet';
      }
    }
    final real = switch (verdict) {
      'returned_immediately' || 'returned_confirmed' || 'returned_pending' => true,
      'not_returned_verified' => false,
      _ => null,
    };
    verdicts.add(_make(code, ecu, fam, verdict, real, mon, mc, checkNo));
  }

  final seenNew = <String>{};
  for (final s in after) {
    for (final d in s.dtcs) {
      if (!beforeCodes.containsKey(d.code) && !seenNew.contains(d.code) && (d.status == 'stored' || d.status == 'pending')) {
        seenNew.add(d.code);
        verdicts.add(_make(d.code, d.ecu, _family(d.code), 'new_code', true, null, null, null));
      }
    }
  }

  String overall;
  if (beforeCodes.isEmpty) {
    overall = 'nothing_cleared';
  } else if (verdicts.any((v) => v.isRealProblem == true)) {
    overall = 'problem_confirmed';
  } else if (verdicts.isNotEmpty && verdicts.every((v) => v.verdict == 'not_returned_verified')) {
    overall = 'likely_resolved';
  } else {
    overall = 'verifying';
  }
  final real = [for (final v in verdicts) if (v.isRealProblem == true) v.code];
  var (sEn, sAr) = switch (overall) {
    'problem_confirmed' => (
        'Real problem: ${real.join(', ')} came back after clearing. Clearing the light does not fix it.',
        'يوجد عطل حقيقي: ${real.join('، ')} رجع بعد المسح. مسح اللمبة لا يصلحه.',
      ),
    'likely_resolved' => (
        'No cleared code came back after the vehicle re-ran its self-tests — most likely old faults (e.g. after replacing a part).',
        'لم يرجع أي كود بعد أن أعادت السيارة اختباراتها الذاتية — غالبا أعطال قديمة (مثلا بعد تغيير قطعة).',
      ),
    'verifying' => (
        'Nothing has come back so far (${after.length} scan(s) since clearing), but the self-tests are not complete yet — keep driving and scan again.',
        'لم يرجع شيء حتى الآن (${after.length} فحص بعد المسح)، لكن الاختبارات الذاتية لم تكتمل بعد — استمر في القيادة وافحص مرة أخرى.',
      ),
    _ => (
        'There were no codes saved before clearing, so there is nothing to verify.',
        'لم تكن هناك أكواد محفوظة قبل المسح، فلا يوجد ما يتم التحقق منه.',
      ),
  };
  if (record.dataMode != 'live') {
    final demo = record.dataMode == 'demo';
    sEn = '${demo ? '[DEMO] ' : '[REPLAY] '}$sEn';
    sAr = '${demo ? '[تجريبي] ' : '[إعادة تشغيل] '}$sAr';
  }
  verdicts.sort((a, b) {
    final c = _order[a.verdict]!.compareTo(_order[b.verdict]!);
    return c != 0 ? c : a.code.compareTo(b.code);
  });
  return ClearVerification(
    overall: overall,
    dataMode: record.dataMode,
    clearedAt: record.clearedAt,
    checksAfterClear: after.length,
    summaryEn: sEn,
    summaryAr: sAr,
    codes: verdicts,
  );
}
