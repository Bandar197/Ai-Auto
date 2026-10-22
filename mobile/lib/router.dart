import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'features/auth_screens.dart';
import 'features/clear_dtcs_screen.dart';
import 'features/connect_screen.dart';
import 'features/history_screen.dart';
import 'features/home_screen.dart';
import 'features/live_screen.dart';
import 'features/maintenance_screen.dart';
import 'features/onboarding_screen.dart';
import 'features/report_screen.dart';
import 'features/scan_screen.dart';
import 'features/settings_screen.dart';
import 'features/shell.dart';
import 'features/vehicles_screen.dart';
import 'features/verify_screen.dart';
import 'state/providers.dart';

final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/',
    redirect: (context, state) {
      final done = ref.read(settingsProvider).onboardingDone;
      const open = ['/onboarding', '/login', '/register'];
      if (!done && !open.contains(state.matchedLocation)) return '/onboarding';
      return null;
    },
    routes: [
      GoRoute(path: '/onboarding', builder: (_, _) => const OnboardingScreen()),
      GoRoute(path: '/login', builder: (_, _) => const LoginScreen()),
      GoRoute(path: '/register', builder: (_, _) => const LoginScreen(register: true)),
      StatefulShellRoute.indexedStack(
        builder: (_, _, shell) => AppShell(shell: shell),
        branches: [
          StatefulShellBranch(routes: [GoRoute(path: '/', builder: (_, _) => const HomeScreen())]),
          StatefulShellBranch(routes: [GoRoute(path: '/live', builder: (_, _) => const LiveScreen())]),
          StatefulShellBranch(routes: [GoRoute(path: '/history', builder: (_, _) => const HistoryScreen())]),
          StatefulShellBranch(routes: [GoRoute(path: '/settings', builder: (_, _) => const SettingsScreen())]),
        ],
      ),
      GoRoute(path: '/connect', builder: (_, s) => ConnectScreen(next: s.uri.queryParameters['next'])),
      GoRoute(path: '/scan', builder: (_, _) => const ScanScreen()),
      GoRoute(path: '/report/:id', builder: (_, s) => ReportScreen(reportId: s.pathParameters['id']!)),
      GoRoute(path: '/vehicles', builder: (_, _) => const VehiclesScreen()),
      GoRoute(path: '/vehicles/edit', builder: (_, s) => VehicleEditScreen(vehicle: s.extra as Map<String, dynamic>?)),
      GoRoute(path: '/maintenance/:vehicleId', builder: (_, s) => MaintenanceScreen(vehicleId: s.pathParameters['vehicleId']!)),
      GoRoute(path: '/clear-dtcs', builder: (_, s) => ClearDtcsScreen(reportId: s.uri.queryParameters['report'])),
      GoRoute(path: '/verify', builder: (_, _) => const VerifyScreen()),
      GoRoute(path: '/verify/:id', builder: (_, s) => VerifyScreen(entryId: s.pathParameters['id'])),
    ],
  );
});
