import 'dart:io' show Platform;

import 'package:shared_preferences/shared_preferences.dart';

/// User-adjustable settings persisted in SharedPreferences (no secrets here;
/// tokens live in flutter_secure_storage).
class AppSettings {
  const AppSettings({
    this.locale = 'ar',
    this.backendUrl = defaultBackendUrl,
    this.wifiHost = '192.168.0.10',
    this.wifiPort = 35000,
    this.protocol = '0',
    this.commandTimeoutMs = 2500,
    this.searchTimeoutMs = 10000,
    this.bleService = '',
    this.bleNotify = '',
    this.bleWrite = '',
    this.lastLink = 'wifi',
    this.lastBleDevice = '',
    this.lastClassicDevice = '',
    this.serialBaud = 38400,
    this.includeVin = false,
    this.captureSeconds = 45,
    this.onboardingDone = false,
    this.offlineMode = false,
    this.selectedVehicleId,
  });

  /// Android emulator → host machine. Change in Settings for a device.
  static const String defaultBackendUrl = 'http://10.0.2.2:8000/api/v1';

  /// Desktop builds (e.g. Windows) usually run next to a local backend.
  static const String desktopBackendUrl = 'http://localhost:8000/api/v1';

  static String get platformDefaultBackendUrl =>
      (Platform.isWindows || Platform.isLinux || Platform.isMacOS) ? desktopBackendUrl : defaultBackendUrl;

  final String locale;
  final String backendUrl;
  final String wifiHost;
  final int wifiPort;
  final String protocol;
  final int commandTimeoutMs;
  final int searchTimeoutMs;
  final String bleService;
  final String bleNotify;
  final String bleWrite;

  /// Last adapter link used: wifi | ble | classic.
  final String lastLink;

  /// Last BLE device id / Classic address or COM port (pre-selected next time).
  final String lastBleDevice;
  final String lastClassicDevice;

  /// Serial (COM) baud rate for desktop Classic/USB adapters.
  final int serialBaud;
  final bool includeVin;
  final int captureSeconds;
  final bool onboardingDone;
  final bool offlineMode;
  final String? selectedVehicleId;

  AppSettings copyWith({
    String? locale,
    String? backendUrl,
    String? wifiHost,
    int? wifiPort,
    String? protocol,
    int? commandTimeoutMs,
    int? searchTimeoutMs,
    String? bleService,
    String? bleNotify,
    String? bleWrite,
    String? lastLink,
    String? lastBleDevice,
    String? lastClassicDevice,
    int? serialBaud,
    bool? includeVin,
    int? captureSeconds,
    bool? onboardingDone,
    bool? offlineMode,
    String? selectedVehicleId,
    bool clearVehicle = false,
  }) =>
      AppSettings(
        locale: locale ?? this.locale,
        backendUrl: backendUrl ?? this.backendUrl,
        wifiHost: wifiHost ?? this.wifiHost,
        wifiPort: wifiPort ?? this.wifiPort,
        protocol: protocol ?? this.protocol,
        commandTimeoutMs: commandTimeoutMs ?? this.commandTimeoutMs,
        searchTimeoutMs: searchTimeoutMs ?? this.searchTimeoutMs,
        bleService: bleService ?? this.bleService,
        bleNotify: bleNotify ?? this.bleNotify,
        bleWrite: bleWrite ?? this.bleWrite,
        lastLink: lastLink ?? this.lastLink,
        lastBleDevice: lastBleDevice ?? this.lastBleDevice,
        lastClassicDevice: lastClassicDevice ?? this.lastClassicDevice,
        serialBaud: serialBaud ?? this.serialBaud,
        includeVin: includeVin ?? this.includeVin,
        captureSeconds: captureSeconds ?? this.captureSeconds,
        onboardingDone: onboardingDone ?? this.onboardingDone,
        offlineMode: offlineMode ?? this.offlineMode,
        selectedVehicleId: clearVehicle ? null : (selectedVehicleId ?? this.selectedVehicleId),
      );

  static AppSettings load(SharedPreferences p) => AppSettings(
        locale: p.getString('locale') ?? 'ar',
        backendUrl: p.getString('backendUrl') ?? platformDefaultBackendUrl,
        wifiHost: p.getString('wifiHost') ?? '192.168.0.10',
        wifiPort: p.getInt('wifiPort') ?? 35000,
        protocol: p.getString('protocol') ?? '0',
        commandTimeoutMs: p.getInt('commandTimeoutMs') ?? 2500,
        searchTimeoutMs: p.getInt('searchTimeoutMs') ?? 10000,
        bleService: p.getString('bleService') ?? '',
        bleNotify: p.getString('bleNotify') ?? '',
        bleWrite: p.getString('bleWrite') ?? '',
        lastLink: p.getString('lastLink') ?? 'wifi',
        lastBleDevice: p.getString('lastBleDevice') ?? '',
        lastClassicDevice: p.getString('lastClassicDevice') ?? '',
        serialBaud: p.getInt('serialBaud') ?? 38400,
        includeVin: p.getBool('includeVin') ?? false,
        captureSeconds: p.getInt('captureSeconds') ?? 45,
        onboardingDone: p.getBool('onboardingDone') ?? false,
        offlineMode: p.getBool('offlineMode') ?? false,
        selectedVehicleId: p.getString('selectedVehicleId'),
      );

  Future<void> save(SharedPreferences p) async {
    await p.setString('locale', locale);
    await p.setString('backendUrl', backendUrl);
    await p.setString('wifiHost', wifiHost);
    await p.setInt('wifiPort', wifiPort);
    await p.setString('protocol', protocol);
    await p.setInt('commandTimeoutMs', commandTimeoutMs);
    await p.setInt('searchTimeoutMs', searchTimeoutMs);
    await p.setString('bleService', bleService);
    await p.setString('bleNotify', bleNotify);
    await p.setString('bleWrite', bleWrite);
    await p.setString('lastLink', lastLink);
    await p.setString('lastBleDevice', lastBleDevice);
    await p.setString('lastClassicDevice', lastClassicDevice);
    await p.setInt('serialBaud', serialBaud);
    await p.setBool('includeVin', includeVin);
    await p.setInt('captureSeconds', captureSeconds);
    await p.setBool('onboardingDone', onboardingDone);
    await p.setBool('offlineMode', offlineMode);
    if (selectedVehicleId == null) {
      await p.remove('selectedVehicleId');
    } else {
      await p.setString('selectedVehicleId', selectedVehicleId!);
    }
  }
}
