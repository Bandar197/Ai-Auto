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

## أكواد الشركات المصنعة (مضافة) / Manufacturer codes (added 2026-10)
- الملف: `shared/kb/dtc_oem.json` — 6543 كوداً خاصاً لـ31 ماركة (P1xxx وP30–P33 وB1/B2 وC1/C2 وU1/U2 فقط).
- المصدر: مشروع [Wal33D/dtc-database](https://github.com/Wal33D/dtc-database) (`data/source-data/*_codes.txt`) — رخصة **MIT**، الإشعار في `THIRD_PARTY_NOTICES.md`. `source_type`: بيانات مجتمعية (**غير موثّقة من الشركة**)؛ `verified: false` على كل ملف ماركة، والتطبيق يكتب ذلك بجانب كل وصف.
- مُستبعد: `infiniti_codes.txt` (مطابق حرفياً لملف Honda = بيانات خاطئة) و`other_codes.txt` (بلا ماركة) والملفات العامة (b/c/u/p) لأن القاعدة العامة تُدار منفصلة.
- **هيونداي: لا توجد بيانات في المصدر.** كود هيونداي خاص يُعرض «خاص بالشركة — غير موجود في القاعدة المحلية» ولا يُستعار وصف ماركة أخرى (ولا كيا).
- العربية: 151 كوداً من قوالب مصطلحات مراجعة (`tools/import_oem_dtcs.py`)، و6389 **ترجمة بالذكاء الاصطناعي** بقاموس ورشة موحّد (`tools/apply_oem_translations.py`، `ar_by: "ai"`)، موسومة في التطبيق. 3 اختصارات بلا ترجمة.
- لإضافة مصدر مرخّص (مثل أكواد هيونداي): `python3 tools/import_oem_dtcs.py FILE --make hyundai --source "..." --license "..." [--verified]` ثم `tools/sync_shared.sh`.
- AndrOBD **لم يُستخدم** (رخصة GPL-3.0).

## هيونداي (من كتاب الصيانة) / Hyundai (from the shop manual) — 2026-10-27
- 3 أكواد إيرباق موثّقة من كتاب صيانة سوناتا YF 2012 (نسخة المالك): `B1762` خطأ ترميز وحدة الإيرباق، `B1683` تجاوز الحد الأقصى لمرات الترميز، `B1102` جهد البطارية منخفض. `verified: true`.
- أُخذ المعنى فقط وكُتب بصياغتنا؛ لا يُنسخ نص الكتاب ولا صفحاته إلى التطبيق أو المستودع.
- الكتاب المرسل لا يحتوي قائمة أكواد المحرك أو الفرامل أو الهيكل، ولا أوامر تحكم (يحيل إلى جهاز GDS → Actuation Test).
- Facts only (code meanings), own wording; the manual is not stored in the repo. It contains no full DTC tables and no raw control commands (it points to GDS → Actuation Test).
- تحديث: وصل الكتاب كاملاً بنص قابل للبحث (3 أجزاء، 1307 صفحة). نتيجة البحث: لا توجد فيه جداول أكواد للمحرك أو الفرامل أو الهيكل، ولا أوامر تحكم. الأكواد الخاصة الموجودة فقط: B1762، B1683، B1102 (أقل من 9 فولت)، وP0630 (عام: رقم الهيكل غير مبرمج في كمبيوتر المحرك).
