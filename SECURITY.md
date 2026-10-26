# Security Policy / سياسة الأمان

## Reporting a vulnerability

**Please do not open a public issue, pull request or discussion for a security problem.**

Report it privately through GitHub: open the repository's **Security** tab →
**Report a vulnerability** (GitHub private vulnerability reporting). Include:

* what is affected (API endpoint, admin web page, mobile app screen, database policy, CI),
* steps to reproduce or a proof of concept, and the impact you see,
* any logs or request IDs (`X-Request-ID`) — **never** real customer data, VINs or credentials.

We aim to acknowledge a report within **3 business days**, give a first assessment within
**10 business days**, and keep you updated until it is fixed. Please give us reasonable time to
fix the issue before any disclosure; we are happy to credit you once it is resolved.

## Supported versions

AutoMind AI is pre-release. Only the latest code on `main` (and the latest published build of the
mobile app and admin web) receives security fixes. Older builds are not patched; please update.

## Scope

In scope: the backend API (`backend/`), the admin web (`web/`), the mobile app (`mobile/`), the
database schema and row-level security policies (`supabase/`), and this repository's CI.

Out of scope: denial of service by volume, social engineering, findings that need a rooted /
jailbroken device or physical access to an unlocked phone, and third-party services (Supabase,
GitHub, app stores) — report those to their owners.

### Vehicle-safety rules (always apply)

AutoMind is a diagnostic tool. By design it **must never**:

* send commands to **brakes, steering, airbags (SRS) or the immobilizer**, or bypass the immobilizer;
* **change or reset the odometer**, delete emissions equipment/monitoring, or reset SRS crash data;
* send undocumented or experimental commands to a vehicle.

Clearing trouble codes (OBD service 04) is only allowed with explicit consent, engine off and
speed 0, after server-side authorisation. **Any way to get around these rules is a high-severity
vulnerability** — please report it. Test only against the built-in ECU simulator (demo mode) or a
vehicle you own, parked and stationary; never on a public road.

---

## الإبلاغ عن ثغرة أمنية

**لا تفتح بلاغًا علنيًا (Issue) أو طلب دمج أو نقاشًا عامًا لأي مشكلة أمنية.**

أبلغ بشكل خاص عبر GitHub: افتح تبويب **Security** في المستودع ← **Report a vulnerability**
(الإبلاغ الخاص عن الثغرات). اذكر الجزء المتأثر، وخطوات إعادة إنتاج المشكلة وأثرها، ومعرّف الطلب
(`X-Request-ID`) إن وُجد — **دون** إرسال بيانات عملاء حقيقية أو أرقام هياكل (VIN) أو كلمات مرور.

نسعى للرد خلال **3 أيام عمل**، وتقديم تقييم أولي خلال **10 أيام عمل**، وإبقائك على اطلاع حتى
الإصلاح. نرجو منحنا وقتًا معقولًا قبل أي إفصاح علني، ويسعدنا ذكر اسمك بعد الإصلاح.

## الإصدارات المدعومة

المنتج في مرحلة ما قبل الإطلاق: تُصلح الثغرات في أحدث نسخة على الفرع `main` وأحدث إصدار منشور من
التطبيق ولوحة الإدارة فقط.

## النطاق وقواعد سلامة المركبة

يشمل النطاق: الخادم (API)، ولوحة الإدارة، وتطبيق الجوال، وقاعدة البيانات وسياسات الوصول، وخطوط CI.

AutoMind أداة تشخيص، ويجب ألا يقوم أبدًا بما يلي:

* إرسال أوامر إلى **الفرامل أو التوجيه أو الوسائد الهوائية أو نظام منع التشغيل (Immobilizer)** أو تجاوزه؛
* **تعديل عدّاد المسافة أو تصفيره**، أو حذف أنظمة الانبعاثات، أو مسح بيانات حوادث الوسائد الهوائية؛
* إرسال أوامر غير موثّقة أو تجريبية إلى المركبة.

مسح الأعطال (الخدمة 04) مسموح فقط بموافقة صريحة، والمحرك متوقف والسرعة صفر، وبعد تفويض من الخادم.
**أي طريقة لتجاوز هذه القواعد تُعد ثغرة عالية الخطورة** — يرجى الإبلاغ عنها. اختبر فقط على محاكي
وحدة التحكم المدمج (الوضع التجريبي) أو على مركبة تملكها وهي متوقفة، وليس على طريق عام أبدًا.
