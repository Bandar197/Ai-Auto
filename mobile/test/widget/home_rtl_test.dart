import 'package:automind_app/app.dart';
import 'package:automind_app/features/home_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_app.dart';

void main() {
  testWidgets('home renders right-to-left in Arabic (default locale)', (tester) async {
    final overrides = await testOverrides(locale: 'ar');
    await tester.pumpWidget(ProviderScope(
      retry: (_, _) => null,
      overrides: overrides,
      child: const AutoMindApp(watchConnectivity: false),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byType(HomeScreen), findsOneWidget);
    final ctx = tester.element(find.byType(HomeScreen));
    expect(Directionality.of(ctx), TextDirection.rtl);
    expect(Localizations.localeOf(ctx).languageCode, 'ar');
    expect(find.text('ابدأ الفحص'), findsOneWidget); // Start scan
    expect(find.text('فاحص خارق'), findsOneWidget); // app title (brand name)
    expect(find.textContaining('القارئ'), findsWidgets); // adapter status chip
    // RTL layout: the start-scan icon sits on the right side of the button.
    final button = tester.getRect(find.byKey(const Key('start-scan')));
    final icon = tester.getRect(find.descendant(of: find.byKey(const Key('start-scan')), matching: find.byIcon(Icons.play_circle_outline)));
    expect(icon.center.dx, greaterThan(button.center.dx));
  });

  testWidgets('home renders left-to-right in English', (tester) async {
    final overrides = await testOverrides(locale: 'en');
    await tester.pumpWidget(ProviderScope(
      retry: (_, _) => null,
      overrides: overrides,
      child: const AutoMindApp(watchConnectivity: false),
    ));
    await tester.pump();
    final ctx = tester.element(find.byType(HomeScreen));
    expect(Directionality.of(ctx), TextDirection.ltr);
    expect(find.text('Start scan'), findsOneWidget);
  });
}
