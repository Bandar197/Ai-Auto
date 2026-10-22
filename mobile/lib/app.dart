import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'l10n/app_localizations.dart';
import 'router.dart';
import 'state/providers.dart';

const String appFont = 'IBMPlexSansArabic';

ThemeData buildTheme(Brightness b) {
  final scheme = ColorScheme.fromSeed(seedColor: const Color(0xFF00A88F), brightness: b);
  return ThemeData(
    colorScheme: scheme,
    useMaterial3: true,
    fontFamily: appFont,
    appBarTheme: const AppBarTheme(centerTitle: false),
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
