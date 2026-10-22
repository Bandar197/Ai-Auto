# Vendored flutter_libserialport 0.6.0 (MIT; bundles libserialport, LGPL-3.0)

Upstream: https://github.com/jpnurmi/flutter_libserialport

Change: the Android platform is removed from `pubspec.yaml` and the `android/` and
`example/` folders are not copied. Upstream's Android build script uses `jcenter()`,
which current Gradle no longer supports, so the Android build failed.

The app does not use this plugin on Android: Bluetooth Classic there goes through
our own RFCOMM channel (`android/app/src/main/kotlin/ai/automind/app/BtClassicPlugin.kt`).
Windows, Linux and macOS are unchanged.

Remove this copy (and the `dependency_overrides` entry in `pubspec.yaml`) once upstream
fixes its Android build.
