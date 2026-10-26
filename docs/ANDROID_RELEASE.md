# توقيع نسخة أندرويد / Android release signing

بدون مفتاح توقيع خاص بك، يبني GitHub النسخة موقّعة بمفتاح التطوير (للتجربة فقط).
للنشر على Google Play أو لتوزيع نسخة موثوقة، أنشئ مفتاحك مرة واحدة واحفظه بأمان — **إذا ضاع لا يمكنك تحديث التطبيق بنفس الاسم**.

## 1. إنشاء المفتاح (على اللابتوب) / Create the key

يحتاج Java (يأتي مع Android Studio). في PowerShell:

```powershell
keytool -genkeypair -v -keystore automind-upload.jks -keyalg RSA -keysize 4096 -validity 10000 -alias automind
```

اختر كلمة مرور قوية واحفظ الملف وكلمة المرور في مكان آمن (مدير كلمات مرور + نسخة احتياطية).

## 2. أسرار GitHub / GitHub secrets

حوّل الملف إلى نص:

```powershell
[Convert]::ToBase64String([IO.File]::ReadAllBytes("automind-upload.jks")) | Set-Clipboard
```

ثم في GitHub: المستودع → **Settings → Secrets and variables → Actions → Secrets → New repository secret**:

| Secret | القيمة |
|---|---|
| `ANDROID_KEYSTORE_BASE64` | النص المنسوخ |
| `ANDROID_KEYSTORE_PASSWORD` | كلمة مرور الملف |
| `ANDROID_KEY_ALIAS` | `automind` |
| `ANDROID_KEY_PASSWORD` | كلمة مرور المفتاح (نفسها إن لم تغيّرها) |

لا ترسل هذه القيم في المحادثة؛ ضعها مباشرة في GitHub.

## 3. النتيجة / Result

ملف `automind-android` في قسم Artifacts يصبح موقّعا بمفتاحك. الخطوة التالية للثقة الكاملة: النشر على **Google Play** (يفحصه Google Play Protect، ولا يظهر تحذير "تطبيق غير معروف").

## الحماية المفعّلة في نسخة أندرويد / Hardening

* كود Dart مشوّش (`--obfuscate`)، وكود Java/Kotlin مصغّر ومشوّش (R8).
* لا نسخ احتياطي لبيانات التطبيق (رموز الدخول والإعدادات والتسجيلات) إلى السحابة أو عند نقل الجهاز.
* رموز الدخول في Android Keystore (flutter_secure_storage).
* منع الاتصال غير المشفّر بالإنترنت؛ الخادم عبر HTTPS فقط.
