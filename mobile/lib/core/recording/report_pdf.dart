import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../obd/obd.dart';
import '../storage/clear_entry.dart';
import '../storage/scan_report.dart';

const Map<String, Map<String, String>> _t = {
  'title': {'ar': 'تقرير فحص السيارة', 'en': 'Vehicle scan report'},
  'demo': {'ar': 'تجريبي — بيانات محاكاة وليست من سيارة حقيقية', 'en': 'DEMO — simulated data, not from a real car'},
  'replay': {'ar': 'إعادة تشغيل تسجيل', 'en': 'Replay of a recording'},
  'interrupted': {'ar': 'جلسة منقطعة — البيانات حتى لحظة الانقطاع فقط', 'en': 'Interrupted session — data up to the interruption only'},
  'vehicle': {'ar': 'السيارة', 'en': 'Vehicle'},
  'date': {'ar': 'التاريخ', 'en': 'Date'},
  'adapter': {'ar': 'الجهاز / البروتوكول', 'en': 'Adapter / protocol'},
  'checked': {'ar': 'ما تم فحصه', 'en': 'What was checked'},
  'notChecked': {'ar': 'ما لم يتم فحصه ولماذا', 'en': 'What was NOT checked, and why'},
  'codes': {'ar': 'أكواد الأعطال', 'en': 'Fault codes'},
  'noCodes': {'ar': 'لم تبلغ الأنظمة المقروءة عن أكواد.', 'en': 'The systems that were read reported no codes.'},
  'beforeAfter': {'ar': 'قبل المسح وبعده', 'en': 'Before and after clearing'},
  'stillNeeds': {'ar': 'ما زال يحتاج إصلاحا أو تحققا', 'en': 'Still needs repair or verification'},
  'nothingPending': {'ar': 'لا شيء مسجل في الأنظمة المقروءة.', 'en': 'Nothing recorded in the systems that were read.'},
  'obd': {'ar': 'المحرك والانبعاثات (OBD-II): قراءة الأكواد المخزنة والمعلقة والدائمة', 'en': 'Engine & emissions (OBD-II): stored, pending and permanent codes read'},
  'moduleOk': {'ar': 'قرئت بنجاح', 'en': 'read successfully'},
  'noResponse': {'ar': 'لم تستجب (لا يعني سليمة)', 'en': 'did not answer (does not mean OK)'},
  'refused': {'ar': 'رفضت الوصول', 'en': 'refused access'},
  'gateway': {'ar': 'محجوبة بالبوابة الأمنية', 'en': 'blocked by the security gateway'},
  'notSupported': {'ar': 'لا تدعم الخدمة', 'en': 'service not supported'},
  'noModules': {
    'ar': 'وحدات الإيرباق والفرامل والهيكل لم تفحص في هذه الجلسة (فحص سريع). استخدم الفحص الكامل.',
    'en': 'Airbag, ABS and body modules were not scanned in this session (quick scan). Use the full scan.'
  },
  'lampsNote': {
    'ar': 'لمبات ضغط الزيت والإطارات والثبات والدركسون والحزام لا تقرأ عبر OBD العام في هذه السيارة.',
    'en': 'Oil-pressure, TPMS, ESC, EPS and seatbelt lamps are not readable through generic OBD on this car.'
  },
  'code': {'ar': 'الكود', 'en': 'Code'},
  'status': {'ar': 'الحالة', 'en': 'Status'},
  'source': {'ar': 'المصدر', 'en': 'Source'},
  'desc': {'ar': 'الوصف', 'en': 'Description'},
  'result': {'ar': 'النتيجة', 'en': 'Result'},
  'unknownDesc': {'ar': 'غير موجود في القاعدة المحلية', 'en': 'not in the local database'},
  'lampModule': {'ar': 'لمبة المحرك: أبلغ الكمبيوتر أنها مطفأة', 'en': 'Engine lamp: the computer reported it OFF'},
  'lampUser': {'ar': 'اللمبة: أكد المستخدم أنها انطفأت', 'en': 'Lamp: the user confirmed it went off'},
  'lampUnknown': {'ar': 'اللمبة: لم تؤكد بعد («تم مسح الكود» لا يعني انطفاء اللمبة)', 'en': 'Lamp: not confirmed ("code cleared" does not mean the lamp is off)'},
  'disclaimer': {
    'ar': 'هذا التقرير يشمل الأنظمة المذكورة أعلاه فقط ولا يصف السيارة بأنها سليمة بالكامل. المسح لا يصلح سبب العطل.',
    'en': 'This report covers only the systems listed above and does not describe the car as fully healthy. Clearing does not fix the cause.'
  },
};

const Map<String, Map<String, String>> _res = {
  'cleared': {'ar': 'تم المسح', 'en': 'Cleared'},
  'still_active': {'ar': 'ما زال موجودا', 'en': 'Still present'},
  'read_failed': {'ar': 'فشلت إعادة القراءة', 'en': 'Re-read failed'},
  'verification_pending': {'ar': 'التحقق معلق', 'en': 'Verification pending'},
  'refused': {'ar': 'رفضته الوحدة', 'en': 'Refused'},
  'comm_failed': {'ar': 'لا استجابة', 'en': 'No answer'},
  'blocked': {'ar': 'لم يرسل', 'en': 'Not sent'},
};

/// The PDF engine swallows one space after a final «ر» (e.g. «تقرير الفحص» renders
/// glued — checked visually); doubling that space renders as a normal gap.
String _fixAr(String s) => s.replaceAll(RegExp('ر (?=\\S)'), 'ر  ');

/// Builds the bilingual (Arabic RTL / English) PDF report on the device — no server.
/// Fonts are passed in (the bundled IBM Plex Sans Arabic) so this stays pure/testable.
Future<Uint8List> buildReportPdf({
  required ScanReport report,
  Recording? recording,
  required String lang,
  required ByteData fontRegular,
  required ByteData fontBold,
  String? Function(String code)? describe,
  ClearEntry? clear,
  bool maskVin = true,
}) async {
  final ar = lang == 'ar';
  String tr(String k) => _fixAr(_t[k]![ar ? 'ar' : 'en']!);
  final dir = ar ? pw.TextDirection.rtl : pw.TextDirection.ltr;
  final base = pw.Font.ttf(fontRegular);
  final bold = pw.Font.ttf(fontBold);
  final theme = pw.ThemeData.withFont(base: base, bold: bold);
  final rec = recording;

  final vin = rec?.vehicle['vin'] as String? ?? report.vin;
  final shownVin = maskVin && vin != null && vin.length >= 10 ? '${vin.substring(0, 6)}${'*' * (vin.length - 10)}${vin.substring(vin.length - 4)}' : vin;
  final vehicle = [
    '${rec?.vehicle['make'] ?? ''}',
    '${rec?.vehicle['model'] ?? ''}',
    '${rec?.vehicle['model_year'] ?? ''}',
    if (shownVin != null) 'VIN $shownVin',
  ].where((x) => x.isNotEmpty).join(' · ');

  // What was / was not checked.
  final checked = <String>[if (rec == null || rec.dtcs.isNotEmpty || rec.ecus.isNotEmpty || report.dtcs.isNotEmpty || rec.moduleScans.isEmpty) tr('obd')];
  final notChecked = <String>[];
  for (final m in rec?.moduleScans ?? const <RecordingModuleScan>[]) {
    final name = ar ? m.nameAr : m.nameEn;
    switch (m.outcome) {
      case 'read_codes' || 'read_no_codes':
        checked.add('$name — ${tr('moduleOk')}');
      case 'refused':
        final why = m.nrc == 0x33 ? tr('gateway') : ({0x11, 0x12, 0x7F}.contains(m.nrc) ? tr('notSupported') : tr('refused'));
        notChecked.add('$name — $why${m.nrc != null ? ' (NRC 0x${m.nrc!.toRadixString(16).padLeft(2, '0').toUpperCase()})' : ''}');
      default:
        notChecked.add('$name — ${tr('noResponse')}');
    }
  }
  if ((rec?.moduleScans ?? const []).isEmpty) notChecked.add(tr('noModules'));
  notChecked.add(tr('lampsNote'));

  // Codes.
  final codeRows = <List<String>>[
    if (rec != null) ...[
      for (final d in rec.dtcs) [d.code, d.status.apiValue, 'OBD ${d.ecu ?? ''}'.trim(), describe?.call(d.code) ?? tr('unknownDesc')],
      for (final m in rec.moduleScans)
        for (final c in m.codes) [c.code, c.status.apiValue, ar ? m.nameAr : m.nameEn, describe?.call(c.code) ?? tr('unknownDesc')],
    ] else
      for (final d in report.dtcs) ['${d['code']}', '${d['status'] ?? ''}', 'OBD', describe?.call('${d['code']}') ?? tr('unknownDesc')],
  ];

  // Still needs work: codes not proven cleared.
  final cleared = <String>{
    for (final t in clear?.targetResults ?? const <Map<String, dynamic>>[])
      for (final e in ((t['codes'] as Map?) ?? const {}).entries)
        if (e.value == 'cleared') '${e.key}',
  };
  final still = <String>{for (final r in codeRows) if (!cleared.contains(r[0])) r[0]}.toList();

  pw.Widget h(String s) => pw.Padding(
        padding: const pw.EdgeInsets.only(top: 12, bottom: 4),
        child: pw.Text(s, textDirection: dir, style: pw.TextStyle(font: bold, fontSize: 13, color: PdfColor.fromInt(0xFF1565C0))),
      );
  pw.Widget p(String s, {PdfColor? color}) => pw.Padding(
        padding: const pw.EdgeInsets.only(bottom: 2),
        child: pw.Text(_fixAr(s), textDirection: dir, style: pw.TextStyle(fontSize: 10, color: color)),
      );
  pw.Widget bullets(List<String> xs) => pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [for (final x in xs) p('• $x')]);
  pw.Widget table(List<String> head, List<List<String>> rows) => pw.TableHelper.fromTextArray(
        headers: ar ? head.reversed.toList() : head,
        data: [for (final r in rows) [for (final c in (ar ? r.reversed.toList() : r)) _fixAr(c)]],
        headerStyle: pw.TextStyle(font: bold, fontSize: 9),
        cellStyle: const pw.TextStyle(fontSize: 9),
        headerDirection: dir,
        tableDirection: dir,
        cellAlignment: ar ? pw.Alignment.centerRight : pw.Alignment.centerLeft,
      );

  final doc = pw.Document(title: tr('title'), creator: 'AutoMind');
  final isDemo = report.isDemo;
  doc.addPage(pw.MultiPage(
    theme: theme,
    textDirection: dir,
    pageFormat: PdfPageFormat.a4,
    margin: const pw.EdgeInsets.all(32),
    header: (ctx) => isDemo
        ? pw.Container(
            width: double.infinity,
            padding: const pw.EdgeInsets.all(4),
            color: PdfColor.fromInt(0xFFFFE0B2),
            child: pw.Text(tr('demo'), textDirection: dir, textAlign: pw.TextAlign.center, style: pw.TextStyle(font: bold, fontSize: 10)),
          )
        : pw.SizedBox(),
    footer: (ctx) => pw.Text('${ctx.pageNumber}/${ctx.pagesCount}', style: const pw.TextStyle(fontSize: 8)),
    build: (ctx) => [
      pw.Text(tr('title'), textDirection: dir, style: pw.TextStyle(font: bold, fontSize: 18)),
      if (report.isReplay) p(tr('replay'), color: PdfColors.blue800),
      if (report.interrupted) p(tr('interrupted'), color: PdfColors.orange800),
      p('${tr('date')}: ${report.createdAt.toLocal().toString().substring(0, 16)}'),
      if (vehicle.isNotEmpty) p('${tr('vehicle')}: $vehicle'),
      if (rec != null)
        p('${tr('adapter')}: ${[rec.source['adapter_firmware'] ?? rec.adapterCapabilities?.firmware, rec.source['protocol_name'] ?? report.protocolName].whereType<Object>().join(' · ')}'),
      h(tr('checked')),
      bullets(checked),
      h(tr('notChecked')),
      bullets(notChecked),
      h(tr('codes')),
      if (codeRows.isEmpty) p(tr('noCodes')) else table([tr('code'), tr('status'), tr('source'), tr('desc')], codeRows),
      if (clear != null) ...[
        h(tr('beforeAfter')),
        table([tr('code'), tr('result')], [
          for (final t in clear.targetResults)
            for (final e in ((t['codes'] as Map?) ?? const {}).entries) ['${e.key}', _res['${e.value}']?[ar ? 'ar' : 'en'] ?? '${e.value}'],
        ]),
        p(switch (clear.lampOffBy) {
          'module_status' => tr('lampModule'),
          'user' => tr('lampUser'),
          _ => tr('lampUnknown'),
        }),
      ],
      h(tr('stillNeeds')),
      if (still.isEmpty) p(tr('nothingPending')) else bullets(still),
      pw.SizedBox(height: 12),
      p(tr('disclaimer'), color: PdfColors.grey700),
    ],
  ));
  return doc.save();
}
