# تشغيل التطبيق على الآيفون / Running the app on iPhone

Apple لا تسمح بتثبيت أي تطبيق على الآيفون إلا إذا كان موقّعا. الطريقة الموصى بها هي **TestFlight**، ولا تحتاج جهاز Mac لأن GitHub يبني التطبيق ويرفعه.
Apple only installs signed apps. The recommended path is **TestFlight**; no Mac is needed because GitHub builds and uploads the app.

## الخطوة 1 — حساب مطوّر Apple (مرة واحدة) / Apple Developer account (once)

1. سجّل في Apple Developer Program من https://developer.apple.com/programs/ (99 دولار سنويا). يمكن التسجيل كفرد أو كمنشأة (للمنشأة تحتاج رقم D-U-N-S).
2. بعد التفعيل افتح https://developer.apple.com/account → **Membership** وانسخ **Team ID** (10 أحرف).

## الخطوة 2 — إنشاء سجل التطبيق / Create the app record

1. افتح https://appstoreconnect.apple.com → **Apps** → **+** → **New App**.
2. Platform: iOS · Name: `AutoMind AI` (أو أوتومايند) · Primary language: Arabic · Bundle ID: `ai.automind.app` (إذا لم يظهر في القائمة: سجّله من developer.apple.com → Identifiers → **+** → App IDs → Bundle ID `ai.automind.app`، وفعّل لا شيء إضافي) · SKU: `automind-ios`.

## الخطوة 3 — مفتاح API لـ GitHub / API key for GitHub

1. App Store Connect → **Users and Access** → **Integrations** → **App Store Connect API** → **+**.
2. الاسم: `GitHub CI` · الصلاحية: **App Manager** → Generate.
3. نزّل ملف `AuthKey_XXXXXXXXXX.p8` (يُنزّل مرة واحدة فقط) وانسخ **Key ID** و **Issuer ID**.

## الخطوة 4 — أسرار المستودع / Repository secrets

في GitHub: المستودع → **Settings** → **Secrets and variables** → **Actions** → **New repository secret**، وأضف:

| Secret | القيمة |
|---|---|
| `APPLE_TEAM_ID` | Team ID من الخطوة 1 |
| `ASC_KEY_ID` | Key ID من الخطوة 3 |
| `ASC_ISSUER_ID` | Issuer ID من الخطوة 3 |
| `ASC_KEY_P8` | افتح ملف ‎.p8 بأي محرر نصوص والصق محتواه كاملا (مع سطري BEGIN/END) |

لا ترسل هذه القيم في المحادثة؛ ضعها مباشرة في GitHub.
Never paste these values into chat; put them straight into GitHub.

## الخطوة 5 — البناء والرفع / Build and upload

GitHub → **Actions** → **iOS** → **Run workflow** → فعّل `upload_testflight` → Run.
بعد نجاحه (15–25 دقيقة) تعالج Apple النسخة عادة خلال 10–30 دقيقة.

## الخطوة 6 — التثبيت على الآيفون / Install

1. App Store Connect → التطبيق → **TestFlight** → **Internal Testing** → أضف نفسك (بريد حساب Apple).
2. ثبّت تطبيق **TestFlight** من App Store على الآيفون، وافتح الدعوة، ثم **Install**.

## ملاحظات خاصة بالآيفون / iPhone notes

* **Wi-Fi ELM327**: اربط الآيفون بشبكة الجهاز (غالبا `WiFi_OBDII`)، وعند أول اتصال وافق على طلب **الشبكة المحلية**. قد يقول الآيفون "لا يوجد اتصال بالإنترنت" — اختر البقاء على الشبكة.
* **BLE ELM327** يعمل. أجهزة **Bluetooth Classic** (التي تظهر في إعدادات البلوتوث وتحتاج رمز 1234) **لا تعمل مع الآيفون** — قيد من Apple على كل التطبيقات.
* البديل بدون حساب مطوّر: جهاز Mac مع Xcode وحساب Apple مجاني، والتثبيت بالكابل — لكن التطبيق يتوقف بعد 7 أيام ويحتاج إعادة تثبيت.
