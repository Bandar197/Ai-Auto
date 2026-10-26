# تغطية التشخيص — موثّق مقابل غير مؤكد / Diagnostic coverage — verified vs unverified

> مبدأ: لا يُعرض أي نظام على أنه «سليم» إلا بعد قراءة ناجحة فعلية من وحدته. وكل عنوان وحدة غير قياسي يبقى **غير مؤكد** حتى يُثبت على سيارة حقيقية.
> Principle: no system is shown "healthy" without a real, interpretable read from its module. Every non-standard module address stays **unverified** until proven on a real vehicle.

## طبقات الثقة / Trust tiers
| الطبقة | المعنى | أمثلة |
|---|---|---|
| `standard_specification` | معيار عام منشور (SAE/ISO) | OBD-II الخدمات 03/07/0A/01، قاموس الأكواد العامة |
| `verified_vehicle_trace` | أُثبت بتسجيل فعلي من السيارة | عنوان وحدة بعد `uds-scan` ومقارنة بجهاز معتمد |
| `licensed_oem` | بيانات شركة مصنّعة مرخّصة | (لا يوجد حالياً) |
| `static_identifier` | اسم وحدة مستخرج، ليس عنواناً | الـ459 معرّف (`shared/diag/controller_identifiers.json`) |
| `demo_only` | محاكاة | سيناريوهات المحاكي |
| `unknown` / `unverified` | غير مثبت | عناوين `shared/obd/modules.json` بـ `verified:false` |

## ما هو مُغطّى فعلياً اليوم / What is actually covered today

### مؤكد (معيار قياسي) / Verified by public standard
- **أعطال المحرك/الانبعاثات/ناقل الحركة** عبر OBD-II (الخدمات 03 مخزّن، 07 معلّق، 0A دائم) من **كل وحدة تردّ** على العنونة القياسية — يعمل على أي سيارة + ELM327 متوافق.
- **قاموس الأكواد العامة**: 633 كوداً (`shared/kb/dtc_definitions.json`) بوصف ar/en وأسباب شائعة، مصدرها SAE J2012 / ISO 15031-6 فقط. الأكواد الخاصة بالشركات مستبعدة عمداً.
- القيم الحية (Mode 01) ومراقبات الجاهزية.

### غير مؤكد (يحتاج تحقق ميداني) / Unverified (needs field validation)
- **عناوين وحدات الإيرباق (SRS) / ABS / الهيكل** عبر UDS: موجودة في `shared/obd/modules.json` كـ **تقديرات `verified:false`** لكل شركة (كرايسلر/دودج، تويوتا، هونداي، فورد، شيفروليه…). لا يُعتمد أي عنوان حتى يُلتقط `request/response` فعلي من السيارة ويُقارن بجهاز معتمد.
- **كتالوج الـ459 معرّف وحدة**: أسماء مجموعات وحدات لكل شركة — **ليست عناوين CAN ولا دليل دعم**. تُعرض في التطبيق موسومة «مدخل كتالوج غير مؤكد».

### غير مدعوم / Not supported
- أوامر الكتابة/المسح/التفعيل في وضع الاكتشاف (UDS 0x14/0x2E/0x2F/0x31/0x11/0x27/0x10) — محظورة.
- ادعاء صحة نظام SRS عند تعذّر قراءته — بدلاً منه: «تعذّر التحقق من الإيرباق — يلزم فحص متخصص».

## مصفوفة الشركات (عناوين الوحدات) / Make matrix (module addresses)
جميعها `unverified` حتى الآن. المصدر: `shared/obd/modules.json`.

| الشركة | إيرباق | ABS | هيكل | الحالة |
|---|---|---|---|---|
| chrysler/dodge/jeep/ram | 29-bit تقديري | 29-bit تقديري | 29-bit تقديري | unverified |
| toyota/lexus | 11-bit تقديري | 11-bit تقديري | — | unverified |
| hyundai/kia | 11-bit تقديري | 11-bit تقديري | — | unverified |
| ford, chevrolet/gm | 11-bit تقديري | 11-bit تقديري | — | unverified |
| generic (كل السيارات) | 11-bit تقديري | 11-bit تقديري | 11-bit تقديري | unverified |

## كيف يرتقي عنوان من unverified إلى verified / Promotion path
1. وصّل السيارة وشغّل «الاكتشاف المتقدم» في التطبيق (أو `automind uds-scan --profile <make>`).
2. سجّل الوحدة التي ردّت: `request/response id`, `protocol`, الأكواد، `market/model/year/engine variant`, وإن أمكن `ECU part number`.
3. قارن النتيجة بجهاز فحص معتمد للشركة على سيارة آمنة.
4. عندها فقط يُحدّث المدخل إلى `verified_vehicle_trace` (في الخادم عبر اعتماد مشرف، أو في `modules.json`).
