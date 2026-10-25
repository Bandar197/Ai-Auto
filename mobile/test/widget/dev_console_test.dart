import 'package:automind_app/features/dev_console_screen.dart';
import 'package:automind_app/l10n/app_localizations.dart';
import 'package:automind_app/state/connection_controller.dart';
import 'package:automind_app/state/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_app.dart';

void main() {
  testWidgets('live traffic appears; a clear command is refused before reaching the link (English)', (tester) async {
    final c = ProviderContainer(overrides: [...await testOverrides(locale: 'en'), demoLatencyProvider.overrideWithValue(Duration.zero)]);
    addTearDown(c.dispose);
    await tester.runAsync(() => c.read(connectionProvider.notifier).connectDemo(c.read(appAssetsProvider).scenario('p0106_map_sensor')!));
    await tester.pumpWidget(UncontrolledProviderScope(
      container: c,
      child: const MaterialApp(
        locale: Locale('en'),
        supportedLocales: [Locale('ar'), Locale('en')],
        localizationsDelegates: [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: DevConsoleScreen(),
      ),
    ));
    await tester.pump();

    await tester.enterText(find.byKey(const Key('console-input')), '04');
    await tester.tap(find.byKey(const Key('console-send')));
    await tester.pump();
    expect(find.text('Refused: only read-only commands are allowed here.'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('console-input')), 'ATRV');
    await tester.tap(find.byKey(const Key('console-send')));
    for (var i = 0; i < 10; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump();
    }
    expect(find.textContaining('> ATRV'), findsOneWidget);
    expect(find.textContaining('V'), findsWidgets);
    await tester.runAsync(() => c.read(connectionProvider.notifier).disconnect());
  });
}
