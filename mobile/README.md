# AutoMind AI — Mobile (Flutter) · أوتومايند — تطبيق الجوال

Arabic-first (RTL) OBD-II diagnostics app for iOS and Android. It talks to a
real ELM327 adapter (Wi-Fi TCP or Bluetooth LE), records the session,
uploads it to the AutoMind backend for diagnosis, and works offline.

تطبيق تشخيص سيارات عبر منفذ OBD-II، عربي أولًا (من اليمين لليسار) لنظامي iOS
وأندرويد. يتصل بقارئ ELM327 حقيقي (Wi-Fi أو بلوتوث LE)، يسجّل الجلسة، ويرفعها
إلى خادم أوتومايند للتشخيص، ويعمل بدون إنترنت.

---

## English

### Architecture

```
lib/
  obd/            Pure-Dart OBD engine (no Flutter imports — enforced by test/obd/engine_purity_test.dart)
    transport/    ObdTransport, TcpTransport (dart:io), DemoTransport (in-process emulator), BLE GATT profiles
    elm327/       Serial command queue, prompt/timeout handling, response cleaning, typed ELM errors
    protocol/     Frame parser: CAN 11/29-bit, legacy J1850/ISO 9141/KWP (+checksum), headers-off, ISO-TP
    decode/       PID table (assets/shared/obd/pids.json) + decoder/encoder, DTC decode/encode
    services/     Supported-PID walk, mode 01/02/03/07/0A/09, ATRV
    client/       ObdClient: init sequence, AdapterState + EcuState, retry/backoff, link-loss + auto-reconnect,
                  connection log (POST /connections), approval-gated clear DTCs (service 04)
    live/         LivePoller (round-robin over supported PIDs, sample rate)
    recording/    Recording v1 model, Recorder, ReplaySource (1x/2x/4x, pause, seek, re-decode from raw)
    emulator/     ELM327 emulator + scenario signal model (parity with backend/automind/simulator)
  platform/       BleTransport (flutter_blue_plus) — the only Flutter-dependent transport
  core/           Settings, API client (dio + refresh-once interceptor), token store (flutter_secure_storage),
                  local file store, offline upload queue, bundled DTC knowledge base
  state/          Riverpod providers and controllers (connection, scan)
  features/       Screens (onboarding, login/register, home, connect, scan, report, live data, history,
                  vehicles, maintenance, settings, clear DTCs)
  ui/             Shared widgets (DEMO/REPLAY banners + watermark, status chips, health gauge)
  l10n/           ARB files (ar default, en) — generated from tool/gen_arb.py
assets/shared/    Mirror of ../shared (run ../tools/sync_shared.sh; a test fails on drift)
```

State management: **Riverpod 3**. Navigation: **go_router**. HTTP: **dio**.

### Data modes (product rules)

* **Live** — only from a real adapter. Nothing is ever faked.
* **Demo** — in-process simulator *or* any adapter answering `AT@1` with
  `AUTOMIND SIMULATOR` (the team's PC simulator). Labelled DEMO everywhere
  (banner, report watermark, exports, upload `data_mode`). Never live.
* **Replay** — a saved recording played back; labelled “REPLAY of a live/demo
  recording”. The recording's original `data_mode` is never changed.
* Only PIDs reported as supported (01 00/20/40… bitmasks) are requested.
* Clearing DTCs (service 04) requires: server approval
  (`POST /control/operations`), live engine-off (0 rpm) + vehicle stopped
  (0 km/h), and an explicit confirmation dialog. The result is reported with
  `PATCH /control/operations/{id}`. Offline → refused. No other ECU write is
  possible: `Elm327.send()` rejects every service except 01/02/03/07/09/0A.

### Setup

```bash
export PATH=/path/to/flutter/bin:$PATH     # Flutter 3.47.x / Dart 3.13
cd mobile
../tools/sync_shared.sh                     # copy shared contracts into assets/shared
flutter pub get                             # also generates lib/l10n/app_localizations*.dart
flutter analyze
flutter test
```

Edit translations in `tool/gen_arb.py`, then `python3 tool/gen_arb.py && flutter gen-l10n`.
Launcher icons: `python3 tool/make_icon.py assets/icon && dart run flutter_launcher_icons`.

### Running against the backend

Settings → *Backend URL* (default `http://10.0.2.2:8000/api/v1`, i.e. the host
machine from the Android emulator). On a phone use the PC's LAN IP, e.g.
`http://192.168.1.20:8000/api/v1`, or the production HTTPS URL. No API keys are
stored in the app; access/refresh tokens are kept in the Keychain/Keystore via
`flutter_secure_storage`. The app can be used without an account: scans are
stored locally and queued until you log in.

### Running against the PC simulator

```bash
# on the PC (backend repo)
automind simulate --host 0.0.0.0 --port 35000 --scenario p0106_map_sensor
#   --protocol 7 (CAN 29-bit) | 3 (ISO 9141) …  --ignition-off  --engine-off  --drop-after N
```

In the app: Connect → Live → Wi-Fi → enter the PC's IP and port 35000. The
simulator identifies itself (`AT@1` → `AUTOMIND SIMULATOR`), so the session is
forced to **DEMO** and shown as “Simulator”.

Cross-check the Dart engine against the Python simulator from the command line:

```bash
automind simulate --host 127.0.0.1 --port 35091 --scenario p0106_map_sensor &
AUTOMIND_SIM=127.0.0.1:35091 AUTOMIND_SIM_SCENARIO=p0106_map_sensor flutter test test/integration
```

### Testing with a real ELM327 Wi-Fi adapter

1. Plug the adapter into the OBD-II port, ignition ON (engine running for live data).
2. Join the adapter's Wi-Fi network (often `WiFi_OBDII`, `V-LINK`…).
3. Connect → Live → Wi-Fi → `192.168.0.10` port `35000` (pre-filled) → Connect.
4. The status shows two links separately: phone ↔ adapter and adapter ↔ car.
5. While on the adapter's Wi-Fi the phone usually has **no internet**: the scan
   is saved on the phone and uploaded automatically when connectivity returns
   (or pull to refresh on Home/History).

BLE adapters: Connect → Live → Bluetooth LE → Scan. Supported GATT layouts:
FFF0 (FFF1 notify / FFF2 write), FFE0 (FFE1), 18F0 (2AF0 / 2AF1); custom UUIDs
in Settings → Adapter.

### Building

**Android** (needs Android SDK 36 + build-tools, JDK 17+):

```bash
flutter build apk --debug          # build/app/outputs/flutter-apk/app-debug.apk
flutter build appbundle --release  # configure signing first (android/key.properties)
```

App id `ai.automind.app`, label “AutoMind AI” / “أوتومايند” (values-ar), minSdk 23.
Permissions: INTERNET, ACCESS_NETWORK_STATE, ACCESS_WIFI_STATE,
BLUETOOTH_SCAN (`neverForLocation`), BLUETOOTH_CONNECT (+ legacy BLUETOOTH/ADMIN/
FINE_LOCATION for Android ≤ 11 only).

**iOS** (macOS + Xcode 16+, CocoaPods):

```bash
cd mobile && flutter pub get
cd ios && pod install && cd ..
open ios/Runner.xcworkspace        # set your Team / signing for bundle id ai.automind.app
flutter build ios --release        # or: flutter build ipa
```

Minimum iOS 15. Info.plist includes `NSBluetoothAlwaysUsageDescription`,
`NSLocalNetworkUsageDescription` and `NSAllowsLocalNetworking`.

### Known limitations

* **Bluetooth Classic (SPP)** adapters are not supported. iOS does not allow SPP
  for normal apps (MFi only); on Android SPP is a possible future transport
  (`ObdTransport` makes it a drop-in addition).
* The APK could not be built in the CI sandbox used to create this app (Android
  SDK download host blocked); `flutter analyze` and `flutter test` pass.
  iOS was not built (needs macOS).
* The iOS home-screen name is “AutoMind AI” in all languages; an Arabic
  `InfoPlist.strings` needs to be added in Xcode (Android already has `values-ar`).
* Mode 01 requests are single-PID (multi-PID CAN requests are a future optimisation).
* VINs containing I/O/Q are accepted with a warning (some simulators use them).

---

## العربية

### البنية

* `lib/obd/` محرك OBD بلغة Dart خالصة بدون Flutter (يتحقق اختبار من ذلك): طبقات
  النقل (TCP، المحاكي الداخلي، ملفات تعريف BLE)، طبقة أوامر ELM327، محلل الإطارات
  (CAN 11/29 بت، J1850/ISO 9141/KWP مع checksum، تجميع ISO-TP)، فك ترميز PID
  والأكواد، الخدمات، عميل الاتصال مع إعادة المحاولة وإعادة الاتصال، المسجّل
  وإعادة التشغيل، ومحاكي ELM327 مطابق لمحاكي بايثون.
* `lib/platform/` ناقل البلوتوث LE.
* `lib/core/` الإعدادات، عميل API مع تحديث الرمز تلقائيًا، التخزين الآمن للرموز،
  التخزين المحلي، قائمة الرفع بدون إنترنت، قاعدة معرفة الأكواد.
* `lib/state/` و `lib/features/` إدارة الحالة (Riverpod) والشاشات.

### أوضاع البيانات

* **مباشر**: من قارئ حقيقي فقط، دون أي بيانات مزيفة.
* **تجريبي**: المحاكي الداخلي أو أي قارئ يرد على `AT@1` بـ `AUTOMIND SIMULATOR`
  (محاكي الفريق على الحاسوب) — يُعلَّم دائمًا بأنه تجريبي ولا يُعتبر مباشرًا أبدًا.
* **إعادة تشغيل**: تسجيل محفوظ يُعرض مع وضعه الأصلي.
* لا يُطلب أي حساس إلا إذا أبلغت السيارة أنه مدعوم.
* مسح الأكواد يتطلب موافقة الخادم، والمحرك مطفأ والسيارة متوقفة، وتأكيدًا صريحًا من
  المستخدم، ثم يُبلَّغ الخادم بالنتيجة. لا يُسمح بأي أمر كتابة آخر إلى وحدة التحكم.

### التشغيل

```bash
cd mobile
../tools/sync_shared.sh
flutter pub get
flutter analyze && flutter test
flutter run
```

* **مع الخادم**: من الإعدادات ← عنوان الخادم (مثل `http://192.168.1.20:8000/api/v1`).
* **مع محاكي الحاسوب**: شغّل `automind simulate --host 0.0.0.0 --port 35000` ثم من
  التطبيق: اتصال ← مباشر ← Wi-Fi ← عنوان IP للحاسوب والمنفذ 35000. ستظهر الجلسة
  كـ«تجريبي — محاكي».
* **مع قارئ ELM327 Wi-Fi حقيقي**: شغّل مفتاح الإشعال، اتصل بشبكة القارئ، ثم أدخل
  `192.168.0.10` والمنفذ `35000`. غالبًا ينقطع الإنترنت أثناء الاتصال بشبكة القارئ؛
  يُحفظ الفحص على الجوال ويُرفع تلقائيًا عند عودة الإنترنت.

### البناء

* أندرويد: `flutter build apk --debug` (يتطلب Android SDK 36).
* iOS: على macOS مع Xcode: `cd ios && pod install` ثم `flutter build ios` (الحد الأدنى iOS 15).

### القيود المعروفة

* قارئات البلوتوث الكلاسيكي (SPP) غير مدعومة (ممنوعة على iOS، ومستقبلية على أندرويد).
* لم يُبنَ ملف APK في بيئة الإنشاء بسبب حجب خادم تنزيل Android SDK.
* اسم التطبيق على الشاشة الرئيسية في iOS بالإنجليزية حاليًا (يلزم إضافة
  `InfoPlist.strings` عربي عبر Xcode).
