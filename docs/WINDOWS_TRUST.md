# جعل ويندوز يثق في التطبيق / Making Windows trust the app

## لماذا يظهر التحذير؟ / Why the warning appears

ويندوز (SmartScreen وبرامج مكافحة الفيروسات) يحذّر من أي برنامج **غير موقّع رقميا** أو جديد بلا سمعة، حتى لو كان سليما.
التوقيع الرقمي يثبت من نشر البرنامج وأنه لم يُعدّل بعد النشر.
Windows warns about any program that is **not digitally signed** or has no reputation yet, even when it is clean.

| الطريقة | التكلفة | النتيجة |
|---|---|---|
| **Microsoft Store** (الموصى بها) | التسجيل مجاني للأفراد والشركات | مايكروسوفت تفحص التطبيق وتوقّعه بشهادتها؛ لا تحذير SmartScreen؛ تحديثات تلقائية |
| شهادة توقيع كود (OV) من جهة معتمدة (مثل Sectigo أو DigiCert أو Certum) | مدفوعة سنويا، والمفتاح يكون على جهاز آمن أو خدمة سحابية | الملف موقّع باسمك؛ التحذير يختفي تدريجيا مع اكتساب السمعة |
| Azure Artifact Signing | اشتراك شهري | متاح حاليا للأفراد في أمريكا وكندا فقط، وللشركات في أمريكا وكندا والاتحاد الأوروبي وبريطانيا — غير متاح لفرد في السعودية حاليا |

## الطريقة الموصى بها: Microsoft Store

GitHub يبني حزمة المتجر تلقائيا مع كل تحديث (ملف `automind-windows-store` في قسم Artifacts).

1. سجّل حساب مطوّر مجانا: https://storedeveloper.microsoft.com
2. في Partner Center: **Apps and games → New product → MSIX or PWA app** واحجز الاسم `AutoMind AI`.
3. افتح **Product management → Product identity** وانسخ ثلاث قيم:
   `Package/Identity/Name` و `Package/Identity/Publisher` و `Package/Properties/PublisherDisplayName`.
4. في GitHub: المستودع → **Settings → Secrets and variables → Actions → Variables** (متغيرات وليست أسرارا، لأنها ليست سرية) وأضف:

   | Variable | القيمة |
   |---|---|
   | `MSIX_IDENTITY_NAME` | Package/Identity/Name |
   | `MSIX_PUBLISHER` | Package/Identity/Publisher (يبدأ بـ `CN=`) |
   | `MSIX_PUBLISHER_DISPLAY_NAME` | PublisherDisplayName |

5. شغّل CI من جديد (أو ادفع أي تحديث)، ثم نزّل `automind-windows-store` وفيه `AutoMindAI.msix`.
6. في Partner Center: **Submissions → Start submission → Packages** وارفع الملف، واملأ وصف المتجر وسياسة الخصوصية والتصنيف العمري، ثم **Submit**. المراجعة عادة من يوم إلى 3 أيام.
7. بعد القبول ثبّت التطبيق من متجر مايكروسوفت — بدون أي تحذير.

> رقم الإصدار يزيد تلقائيا مع كل تشغيل لـ CI (`1.0.<رقم التشغيل>.0`)، وهذا ما يطلبه المتجر لكل رفع جديد.

## الحماية داخل ملف ويندوز / Hardening in the Windows build

* بيانات الناشر داخل الملف التنفيذي: الشركة والمنتج `AutoMind AI` ووصف واضح (يقلل الإنذارات الكاذبة).
* كود Dart مشوّش (`--obfuscate`) ورموز التصحيح محفوظة منفصلة.
* لا مفاتيح أو أسرار داخل التطبيق؛ رموز الدخول مشفّرة بتشفير ويندوز المرتبط بحسابك (DPAPI عبر flutter_secure_storage).
* الاتصال بالخادم عبر HTTPS فقط (HTTP مسموح فقط لنفس الجهاز أو الشبكة المحلية للتجربة).
