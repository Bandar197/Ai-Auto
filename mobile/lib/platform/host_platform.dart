import 'dart:io' show Platform;

/// The OS the app runs on (injectable for widget tests).
enum HostPlatform { android, ios, windows, macos, linux, other }

HostPlatform detectHostPlatform() {
  if (Platform.isAndroid) return HostPlatform.android;
  if (Platform.isIOS) return HostPlatform.ios;
  if (Platform.isWindows) return HostPlatform.windows;
  if (Platform.isMacOS) return HostPlatform.macos;
  if (Platform.isLinux) return HostPlatform.linux;
  return HostPlatform.other;
}

/// Adapter link types offered in the Connect screen.
enum AdapterLink { wifi, ble, classic }

extension HostPlatformX on HostPlatform {
  bool get isDesktop => this == HostPlatform.windows || this == HostPlatform.macos || this == HostPlatform.linux;

  /// universal_ble supports Android, iOS, macOS, Windows and Linux (BlueZ).
  bool get supportsBle => this != HostPlatform.other;

  /// Classic SPP: Android via our RFCOMM channel, desktop via a COM/serial port
  /// (pair in the OS first). iOS forbids SPP for normal apps (MFi only).
  bool get supportsClassic => this == HostPlatform.android || isDesktop;

  bool supports(AdapterLink l) => switch (l) {
        AdapterLink.wifi => true,
        AdapterLink.ble => supportsBle,
        AdapterLink.classic => supportsClassic,
      };
}
