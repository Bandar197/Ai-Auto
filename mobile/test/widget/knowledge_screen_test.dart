import 'package:automind_app/core/knowledge.dart';
import 'package:automind_app/features/knowledge_screen.dart';
import 'package:automind_app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> pump(WidgetTester tester, String locale) async {
  await tester.pumpWidget(MaterialApp(
    locale: Locale(locale),
    supportedLocales: const [Locale('ar'), Locale('en')],
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    home: const KnowledgeScreen(),
  ));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('renders every section title (English), scrolling the list', (tester) async {
    await pump(tester, 'en');
    final list = find.byType(Scrollable).first;
    for (final section in kKnowledge) {
      await tester.scrollUntilVisible(find.text(section.title('en')), 200, scrollable: list);
      expect(find.text(section.title('en')), findsOneWidget);
    }
    // The airbag guidance steers to a specialist and never to disabling the system.
    final airbag = kKnowledge.first.items.firstWhere((i) => i.icon == 'airbag');
    expect(airbag.body('en').toLowerCase(), contains('specialist'));
  });

  testWidgets('expanding an item reveals its body (Arabic)', (tester) async {
    await pump(tester, 'ar');
    final first = kKnowledge.first.items.first;
    expect(find.text(first.body('ar')), findsNothing); // collapsed
    await tester.tap(find.text(first.title('ar')));
    await tester.pumpAndSettle();
    expect(find.text(first.body('ar')), findsOneWidget);
  });
}
