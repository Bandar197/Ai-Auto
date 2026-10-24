# مصادر أكواد الأعطال / DTC data sources & policy

## السياسة / Policy
- لا نولّد أكواداً وهمية ولا قاموساً مخترعاً لمجرد طلب «قاعدة كاملة».
- كل كود في القاعدة له مصدر موثّق وحالة تحقق. المعروض اليوم **عام قياسي فقط**.
- الأكواد الخاصة بالشركات (P1/B1/C1/U1 وغيرها) تُضاف فقط من **مصادر مرخّصة أو مواصفات** مع مراجعة بشرية وإصدار وتوثيق المصدر.

## المصدر الحالي / Current source
- الملف: `shared/kb/dtc_definitions.json` (633 كوداً).
- `source`: أوصاف الأكواد العامة وفق **SAE J2012 / ISO 15031-6** (المعاني العامة المنشورة). الأسباب الشائعة معرفة سيارات عامة، وليست بيانات شركة بعينها.
- العائلات المنهجية (لكل أسطوانة/بنك/حساس) مولّدة بنمط المعيار نفسه (`tools/gen_dtc_families.py`), والمنفردات القياسية في `tools/gen_dtc_discrete.py`. مدقّق: `tools/validate_kb.py`.

## حقول التوثيق المطلوبة لأي مصدر جديد / Required provenance for any new source
`source_type` (standard_specification | licensed_oem | verified_vehicle_trace | demo_only | unknown), `source_reference`, `model_year_range`, `market`, `protocol`, `verification_status`, `verified_by`, `verified_at`, `version`.

## ما ليس مصدراً / What is NOT a source
- `P0801` الظاهر في واجهة MotorData هو **مثال اختبار برمجي** لإثبات المحلّل (parser)، وليس عطل سيارة ولا إثبات قاعدة.
- معرّفات الوحدات الـ459 (`shared/diag/controller_identifiers.json`) أسماء مجموعات، **ليست أكواد أعطال**.
- `raw 3-byte` من UDS ليس تلقائياً كود P/B/C/U؛ يحتاج تحقق تنسيق قبل التطبيع.

## إضافة أكواد شركة لاحقاً / Adding manufacturer codes later
تُستورد عبر مسار مراجَع (`POST /diag/admin/dtc/import-reviewed` عند توفره) مع reviewer + approval + version، ولا تُعدَّل سجلات المصدر المعتمدة دون مراجعة جديدة.
