import 'package:automind_app/features/indicators_screen.dart';
import 'package:automind_app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_app.dart';

void main() {
  testWidgets('without a connection or scan nothing claims "OK" (Arabic)', (tester) async {
    tester.view.physicalSize = const Size(1200, 5000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final c = ProviderContainer(overrides: await testOverrides());
    addTearDown(c.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: c,
      child: const MaterialApp(
        locale: Locale('ar'),
        supportedLocales: [Locale('ar'), Locale('en')],
        localizationsDelegates: [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: IndicatorsScreen(),
      ),
    ));
    for (var i = 0; i < 10; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump();
    }
    expect(find.text('سليم'), findsNothing);
    expect(find.descendant(of: find.byKey(const Key('indicator-airbag')), matching: find.text('غير معروف')), findsOneWidget);
    expect(find.descendant(of: find.byKey(const Key('indicator-oil')), matching: find.text('غير مقروء')), findsOneWidget);
    final btn = tester.widget<ButtonStyleButton>(find.byKey(const Key('indicators-check')));
    expect(btn.onPressed, isNull);
  });
}
