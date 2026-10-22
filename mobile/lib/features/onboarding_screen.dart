import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../state/providers.dart';
import '../ui/l10n_helpers.dart';

class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});
  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final _page = PageController();
  int _index = 0;

  Future<void> _finish(String next) async {
    await ref.read(settingsProvider.notifier).change((s) => s.copyWith(onboardingDone: true));
    if (mounted) context.go(next);
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final pages = [
      (Icons.directions_car_filled, l.onboardingTitle1, l.onboardingBody1),
      (Icons.fact_check_outlined, l.onboardingTitle2, l.onboardingBody2),
      (Icons.cloud_off_outlined, l.onboardingTitle3, l.onboardingBody3),
    ];
    return Scaffold(
      body: SafeArea(
        child: Column(children: [
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: TextButton(
              onPressed: () {
                final cur = ref.read(settingsProvider).locale;
                ref.read(settingsProvider.notifier).change((s) => s.copyWith(locale: cur == 'ar' ? 'en' : 'ar'));
              },
              child: Text(context.lang == 'ar' ? l.english : l.arabic),
            ),
          ),
          Expanded(
            child: PageView(
              controller: _page,
              onPageChanged: (i) => setState(() => _index = i),
              children: [
                for (final (icon, title, body) in pages)
                  Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                      Icon(icon, size: 96, color: Theme.of(context).colorScheme.primary),
                      const SizedBox(height: 24),
                      Text(title, style: Theme.of(context).textTheme.headlineSmall, textAlign: TextAlign.center),
                      const SizedBox(height: 12),
                      Text(body, textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodyLarge),
                    ]),
                  ),
              ],
            ),
          ),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            for (var i = 0; i < pages.length; i++)
              Container(
                margin: const EdgeInsets.all(4),
                width: i == _index ? 20 : 8,
                height: 8,
                decoration: BoxDecoration(
                  color: i == _index ? Theme.of(context).colorScheme.primary : Colors.grey,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
          ]),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(children: [
              FilledButton(
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                onPressed: () => _index < pages.length - 1
                    ? _page.nextPage(duration: const Duration(milliseconds: 250), curve: Curves.easeOut)
                    : _finish('/login'),
                child: Text(_index < pages.length - 1 ? l.next : l.getStarted),
              ),
              TextButton(onPressed: () => _finish('/'), child: Text(l.continueOffline)),
            ]),
          ),
        ]),
      ),
    );
  }
}
