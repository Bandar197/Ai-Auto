import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'l10n/app_localizations.dart';
import 'router.dart';
import 'state/providers.dart';

const String appFont = 'IBMPlexSansArabic';

/// AutoMind brand seed (teal). The whole palette derives from it per brightness.
const Color brandSeed = Color(0xFF00A88F);

ThemeData buildTheme(Brightness b) {
  final dark = b == Brightness.dark;
  final scheme = ColorScheme.fromSeed(seedColor: brandSeed, brightness: b);
  final buttonShape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(12));
  return ThemeData(
    colorScheme: scheme,
    useMaterial3: true,
    fontFamily: appFont,
    scaffoldBackgroundColor: dark ? scheme.surface : const Color(0xFFF5F7F8),
    appBarTheme: AppBarTheme(
      centerTitle: false,
      scrolledUnderElevation: 2,
      backgroundColor: dark ? scheme.surface : scheme.surface,
      foregroundColor: scheme.onSurface,
      titleTextStyle: TextStyle(
        fontFamily: appFont, fontSize: 20, fontWeight: FontWeight.w700, color: scheme.onSurface),
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      clipBehavior: Clip.antiAlias,
      color: scheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48), shape: buttonShape),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48), shape: buttonShape),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
    ),
    chipTheme: ChipThemeData(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
    dividerTheme: DividerThemeData(color: scheme.outlineVariant, space: 1, thickness: 1),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
  );
}

class AutoMindApp extends ConsumerStatefulWidget {
  const AutoMindApp({super.key, this.watchConnectivity = true});
  final bool watchConnectivity;
  @override
  ConsumerState<AutoMindApp> createState() => _AutoMindAppState();
}

class _AutoMindAppState extends ConsumerState<AutoMindApp> {
  StreamSubscription<List<ConnectivityResult>>? _net;

  @override
  void initState() {
    super.initState();
    if (widget.watchConnectivity) {
      // Retry pending uploads whenever the network changes (e.g. the phone
      // leaves the adapter's Wi-Fi and gets internet back).
      _net = Connectivity().onConnectivityChanged.listen((r) {
        if (!r.contains(ConnectivityResult.none)) ref.read(pendingUploadsProvider.notifier).sync();
      });
      WidgetsBinding.instance.addPostFrameCallback((_) => ref.read(pendingUploadsProvider.notifier).sync());
    }
  }

  @override
  void dispose() {
    _net?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final locale = ref.watch(settingsProvider.select((s) => s.locale));
    return MaterialApp.router(
      onGenerateTitle: (c) => AppLocalizations.of(c).appTitle,
      debugShowCheckedModeBanner: false,
      routerConfig: ref.watch(routerProvider),
      locale: Locale(locale),
      supportedLocales: const [Locale('ar'), Locale('en')],
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
    );
  }
}
