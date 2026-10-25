import 'package:flutter/widgets.dart';

import '../core/kb/local_kb.dart';
import '../l10n/app_localizations.dart';
import '../obd/obd.dart';

extension L10nX on BuildContext {
  AppLocalizations get l10n => AppLocalizations.of(this);
  String get lang => Localizations.localeOf(this).languageCode;
}

String adapterStateText(AppLocalizations l, AdapterState s) => switch (s) {
      AdapterState.disconnected => l.adapterDisconnected,
      AdapterState.connecting => l.adapterConnecting,
      AdapterState.connected => l.adapterConnected,
      AdapterState.error => l.adapterError,
    };

String ecuStateText(AppLocalizations l, EcuState s) => switch (s) {
      EcuState.unknown => l.ecuUnknown,
      EcuState.searching => l.ecuSearching,
      EcuState.connected => l.ecuConnected,
      EcuState.noResponse => l.ecuNoResponse,
      EcuState.busError => l.ecuBusError,
    };

String linkMessageText(AppLocalizations l, LinkMessage m) => switch (m) {
      LinkMessage.idle => l.linkIdle,
      LinkMessage.connectingAdapter => l.linkConnectingAdapter,
      LinkMessage.adapterUnreachable => l.linkAdapterUnreachable,
      LinkMessage.adapterTimeout => l.linkAdapterTimeout,
      LinkMessage.adapterNotElm => l.linkAdapterNotElm,
      LinkMessage.initializing => l.linkInitializing,
      LinkMessage.searchingProtocol => l.linkSearchingProtocol,
      LinkMessage.ecuConnected => l.linkEcuConnected,
      LinkMessage.ecuNoResponse => l.linkEcuNoResponse,
      LinkMessage.ecuBusError => l.linkEcuBusError,
      LinkMessage.linkLost => l.linkLost,
      LinkMessage.reconnecting => l.linkReconnecting,
      LinkMessage.reconnected => l.linkReconnected,
      LinkMessage.disconnected => l.linkDisconnected,
    };

String modeText(AppLocalizations l, String mode) => switch (mode) {
      'demo' => l.modeDemo,
      'replay' => l.modeReplay,
      _ => l.modeLive,
    };

String healthBandText(AppLocalizations l, String? band) => switch (band) {
      'good' => l.healthBand_good,
      'fair' => l.healthBand_fair,
      'attention' => l.healthBand_attention,
      'critical' => l.healthBand_critical,
      _ => l.healthUnknown,
    };

String severityText(AppLocalizations l, String? s) => switch (s) {
      'low' => l.severity_low,
      'medium' => l.severity_medium,
      'high' => l.severity_high,
      'critical' => l.severity_critical,
      _ => l.severity_info,
    };

/// Picks `<base>_ar` / `<base>_en` (or nested {ar, en}) from server JSON.
String pickLang(Map<String, dynamic>? m, String base, String lang) {
  if (m == null) return '';
  final v = m['${base}_$lang'] ?? m['${base}_en'] ?? m[base];
  if (v is Map) return '${v[lang] ?? v['en'] ?? ''}';
  return v == null ? '' : '$v';
}

String pickBi(dynamic v, String lang) {
  if (v is Map) return '${v[lang] ?? v['en'] ?? ''}';
  return v == null ? '' : '$v';
}

/// Description of [code] for the vehicle's [make]: the make's own entry, a generic
/// one for generic codes, or an honest "manufacturer-specific / not in the database".
String describeCode(AppLocalizations l, LocalKb kb, String code, String lang, {String? make}) {
  final e = kb.lookupFor(code, make: make);
  if (e != null) {
    final d = e.description(lang) ?? l.kbUnknownCode;
    return e.oemMake != null && !e.oemVerified ? '$d · ${l.kbOemUnverifiedTag}' : d;
  }
  return isManufacturerSpecific(code) ? l.kbOemUnknown(make == null ? '' : ' (${make.toUpperCase()})') : l.kbUnknownCode;
}
