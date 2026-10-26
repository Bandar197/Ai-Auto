import 'package:automind_app/features/connect_screen.dart';
import 'package:automind_app/l10n/app_localizations.dart';
import 'package:automind_app/platform/host_platform.dart';
import 'package:automind_app/state/adapter_providers.dart';
import 'package:automind_app/state/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'test_app.dart';

Future<void> pumpConnect(WidgetTester tester, HostPlatform host,
    {String locale = 'en', List<ClassicTarget> targets = const [], String? lastLink}) async {
  final overrides = await testOverrides(locale: locale);
  if (lastLink != null) await (await SharedPreferences.getInstance()).setString('lastLink', lastLink);
  await tester.pumpWidget(ProviderScope(
    retry: (_, _) => null,
    overrides: [
      ...overrides,
      hostPlatformProvider.overrideWithValue(host),
      classicTargetsProvider.overrideWith((ref) async => targets),
    ],
    child: Consumer(
      builder: (context, ref, _) => MaterialApp(
        locale: Locale(ref.watch(settingsProvider).locale),
        supportedLocales: const [Locale('ar'), Locale('en')],
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: const ConnectScreen(),
      ),
    ),
  ));
  await tester.pump();
}

Map<AdapterLink, bool> segmentsEnabled(WidgetTester tester) {
  final w = tester.widget<SegmentedButton<AdapterLink>>(find.byKey(const Key('link-selector')));
  return {for (final s in w.segments) s.value: s.enabled};
}

Future<void> selectClassic(WidgetTester tester) async {
  await tester.tap(find.text('Bluetooth Classic').first);
  await tester.pump();
  await tester.pump();
}

void main() {
  testWidgets('Android: Wi-Fi, BLE and Classic (paired devices) all available', (tester) async {
    await pumpConnect(tester, HostPlatform.android, targets: const [ClassicTarget(id: '00:1D:A5:68:98:8B', title: 'OBDII', subtitle: '00:1D:A5:68:98:8B')]);
    expect(segmentsEnabled(tester), {AdapterLink.wifi: true, AdapterLink.ble: true, AdapterLink.classic: true});
    expect(find.byKey(const Key('wifi-connect')), findsOneWidget); // default = Wi-Fi
    await selectClassic(tester);
    expect(find.textContaining('Pair the adapter first in Android Settings'), findsOneWidget);
    expect(find.byKey(const Key('classic-00:1D:A5:68:98:8B')), findsOneWidget);
    expect(find.byKey(const Key('baud-rate')), findsNothing); // no COM settings on Android
    await tester.tap(find.text('Bluetooth LE'));
    await tester.pump();
    expect(find.byKey(const Key('ble-scan')), findsOneWidget);
  });

  testWidgets('iOS: Classic shown but disabled with a bilingual reason (Arabic)', (tester) async {
    await pumpConnect(tester, HostPlatform.ios, locale: 'ar');
    expect(segmentsEnabled(tester), {AdapterLink.wifi: true, AdapterLink.ble: true, AdapterLink.classic: false});
    expect(find.text('بلوتوث كلاسيكي'), findsOneWidget);
    expect(find.byKey(const Key('classic-ios-note')), findsOneWidget);
    expect(find.textContaining('لا يسمح الآيفون'), findsOneWidget);
    expect(Directionality.of(tester.element(find.byType(ConnectScreen))), TextDirection.rtl);
  });

  testWidgets('iOS English reason', (tester) async {
    await pumpConnect(tester, HostPlatform.ios);
    expect(find.textContaining('iPhone does not allow Bluetooth Classic'), findsOneWidget);
  });

  testWidgets('Windows: BLE enabled; Classic = COM ports with baud rate and pairing note', (tester) async {
    await pumpConnect(tester, HostPlatform.windows,
        targets: const [ClassicTarget(id: 'COM5', title: 'COM5', subtitle: 'Standard Serial over Bluetooth link (COM5)')]);
    expect(segmentsEnabled(tester), {AdapterLink.wifi: true, AdapterLink.ble: true, AdapterLink.classic: true});
    expect(find.byIcon(Icons.usb), findsOneWidget);
    await selectClassic(tester);
    expect(find.textContaining('Serial / COM (Bluetooth Classic or USB)'), findsOneWidget);
    expect(find.textContaining('Windows then creates an outgoing COM port'), findsOneWidget);
    expect(find.byKey(const Key('classic-COM5')), findsOneWidget);
    expect(find.byKey(const Key('baud-rate')), findsOneWidget);
    expect(find.text('38400'), findsOneWidget);
    expect(find.byKey(const Key('classic-ios-note')), findsNothing);
  });

  testWidgets('remembers the last transport; falls back to Wi-Fi where unsupported', (tester) async {
    await pumpConnect(tester, HostPlatform.linux, lastLink: 'classic');
    expect(tester.widget<SegmentedButton<AdapterLink>>(find.byKey(const Key('link-selector'))).selected, {AdapterLink.classic});
    expect(find.text('No paired adapters / COM ports found.'), findsOneWidget);
  });

  testWidgets('last transport Classic on iOS → Wi-Fi', (tester) async {
    await pumpConnect(tester, HostPlatform.ios, lastLink: 'classic');
    expect(tester.widget<SegmentedButton<AdapterLink>>(find.byKey(const Key('link-selector'))).selected, {AdapterLink.wifi});
  });
}
