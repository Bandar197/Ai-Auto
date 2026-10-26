import 'package:automind_app/features/adapter_screen.dart';
import 'package:automind_app/l10n/app_localizations.dart';
import 'package:automind_app/obd/obd.dart';
import 'package:automind_app/state/adapter_caps_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _Fixed extends AdapterCapsController {
  _Fixed(this.value);
  final AdapterCapabilities? value;
  @override
  AsyncValue<AdapterCapabilities?> build() => AsyncData(value);
}

Future<void> pump(WidgetTester tester, String locale, {AdapterCapabilities? caps}) async {
  await tester.pumpWidget(ProviderScope(
    overrides: [adapterCapabilitiesProvider.overrideWith(() => _Fixed(caps))],
    child: MaterialApp(
      locale: Locale(locale),
      supportedLocales: const [Locale('ar'), Locale('en')],
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: const AdapterScreen(),
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('without a connection the test cannot start (Arabic)', (tester) async {
    await pump(tester, 'ar');
    expect(find.text('اتصل بجهاز الفحص أولاً.'), findsOneWidget);
    final btn = tester.widget<ButtonStyleButton>(find.byKey(const Key('adapter-probe')));
    expect(btn.onPressed, isNull);
    expect(find.text('لم يُختبر بعد على هذا الاتصال.'), findsOneWidget);
  });

  testWidgets('shows passed / failed / not tested honestly (English)', (tester) async {
    await pump(
      tester,
      'en',
      caps: AdapterCapabilities(
        connection: 'ble',
        firmware: 'ELM327 v1.5',
        capabilities: {Capability.headers: true, Capability.flowControl: false},
        evidence: {Capability.headers: Evidence.behavioral, Capability.flowControl: Evidence.acceptedOnly},
        probe: const [ProbeStep('ATI', 'ELM327 v1.5', true)],
      ),
    );
    expect(find.descendant(of: find.byKey(const Key('cap-headers')), matching: find.text('Passed · verified by behaviour')), findsOneWidget);
    await tester.scrollUntilVisible(find.byKey(const Key('cap-flow_control')), 200, scrollable: find.byType(Scrollable).first);
    expect(find.descendant(of: find.byKey(const Key('cap-flow_control')), matching: find.text('Failed · command accepted only')), findsOneWidget);
    await tester.scrollUntilVisible(find.byKey(const Key('cap-protocol_switching')), 200, scrollable: find.byType(Scrollable).first);
    expect(find.descendant(of: find.byKey(const Key('cap-protocol_switching')), matching: find.text('Not tested')), findsOneWidget);
  });
}
