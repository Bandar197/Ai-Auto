import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../ui/l10n_helpers.dart';

class AppShell extends StatelessWidget {
  const AppShell({super.key, required this.shell});
  final StatefulNavigationShell shell;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return Scaffold(
      body: shell,
      bottomNavigationBar: NavigationBar(
        selectedIndex: shell.currentIndex,
        onDestinationSelected: (i) => shell.goBranch(i, initialLocation: i == shell.currentIndex),
        destinations: [
          NavigationDestination(icon: const Icon(Icons.home_outlined), selectedIcon: const Icon(Icons.home), label: l.homeTitle),
          NavigationDestination(icon: const Icon(Icons.show_chart), label: l.liveTitle),
          NavigationDestination(icon: const Icon(Icons.history), label: l.historyTitle),
          NavigationDestination(icon: const Icon(Icons.settings_outlined), selectedIcon: const Icon(Icons.settings), label: l.settingsTitle),
        ],
      ),
    );
  }
}
