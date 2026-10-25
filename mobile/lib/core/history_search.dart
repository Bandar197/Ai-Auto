import '../obd/obd.dart';
import 'storage/scan_report.dart';

/// History filters.
enum HistoryFilter { all, live, demo, interrupted, imported }

/// Searchable text for one saved scan: codes (OBD + module), module keys/names, VIN,
/// make/model/year and the date (YYYY-MM-DD).
String searchTextFor(ScanReport r, Recording? rec) {
  final d = r.createdAt.toLocal();
  final date = '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  return [
    for (final x in r.dtcs) '${x['code']}',
    r.vin ?? '',
    r.dataMode,
    date,
    if (rec != null) ...[
      for (final m in rec.moduleScans) ...[m.key, m.nameEn, m.nameAr, for (final c in m.codes) c.code],
      '${rec.vehicle['make'] ?? ''}',
      '${rec.vehicle['model'] ?? ''}',
      '${rec.vehicle['model_year'] ?? ''}',
      '${rec.vehicle['vin'] ?? ''}',
    ],
  ].join(' ').toLowerCase();
}

/// True when [r] passes [filter] and every word of [query] appears in [text].
bool matchesHistory(ScanReport r, String text, {String query = '', HistoryFilter filter = HistoryFilter.all}) {
  final okFilter = switch (filter) {
    HistoryFilter.all => true,
    HistoryFilter.live => r.dataMode == 'live',
    HistoryFilter.demo => r.isDemo,
    HistoryFilter.interrupted => r.interrupted,
    HistoryFilter.imported => r.imported,
  };
  if (!okFilter) return false;
  final words = query.toLowerCase().split(RegExp(r'\s+')).where((w) => w.isNotEmpty);
  return words.every(text.contains);
}
