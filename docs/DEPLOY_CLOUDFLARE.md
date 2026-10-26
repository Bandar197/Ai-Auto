# نشر خادم AutoMind على Cloudflare / Deploy the AutoMind API on Cloudflare

خادم AutoMind مكتوب بـ FastAPI (Python)، وهو خادم يعمل باستمرار — لا يعمل على Cloudflare Workers العادية، بل على **Cloudflare Containers** (تشغيل صورة Docker على شبكة Cloudflare، مع Worker أمامها). قاعدة البيانات تبقى على **Supabase**، و Redis **اختياري** (التطبيق يرجع تلقائياً لذاكرة مؤقتة داخلية إذا لم يوجد Redis).

The AutoMind API is a long-running FastAPI server, so it runs on **Cloudflare Containers** (a Docker image on Cloudflare's network, fronted by a Worker), not on plain Workers. The database stays on **Supabase**; Redis is optional (in-memory fallback).

> متطلب: خطة **Workers Paid** (‏5$ شهرياً + استهلاك). Containers تعمل على linux/amd64. راجع https://developers.cloudflare.com/containers/ لأحدث التفاصيل.

الملفات الجاهزة في المستودع / Files already in the repo:
- `wrangler.jsonc` (في جذر المستودع) — إعداد Cloudflare.
- `infra/cloudflare/worker/index.js` — Worker يمرّر الطلبات إلى الحاوية.
- `package.json` (الجذر) — أدوات النشر فقط (`wrangler`, `@cloudflare/containers`).
- `backend/Dockerfile` — صورة الخادم (جاهزة: تعمل كمستخدم غير جذر، منفذ 8000، فحص صحة).

---

## 1. المتطلبات / Prerequisites
- حساب Cloudflare مع خطة **Workers Paid**.
- Node.js 20+ على جهازك، والمستودع منسوخاً.
- قاعدة البيانات على Supabase (مشروعك الحالي، والهجرات مطبّقة بالفعل).

```bash
npm install            # من جذر المستودع (يثبّت wrangler)
npx wrangler login     # يفتح المتصفح لتسجيل الدخول في Cloudflare
```

## 2. رابط قاعدة بيانات Supabase / Supabase connection string
في Supabase: **Project → Settings → Database → Connection string → Direct** (ليس Pooled).
انسخه وحوّل بدايته إلى `postgresql+asyncpg://` (يستخدم التطبيق asyncpg). الشكل:

```
postgresql+asyncpg://postgres:[YOUR-DB-PASSWORD]@db.<project-ref>.supabase.co:5432/postgres
```

> للأمان: يُفضّل إنشاء مستخدم قاعدة بيانات بصلاحيات أقل بدل `postgres` (راجع رأس migration 3). والمخطط (schema) اسمه `automind` ومطبّق مسبقاً على مشروعك.

## 3. توليد الأسرار الإنتاجية / Generate production secrets
الخادم يرفض الإقلاع في وضع الإنتاج بأسرار افتراضية أو ضعيفة. ولّدها مرة واحدة:

```bash
openssl rand -base64 48   # AUTOMIND_JWT_SECRET  (≥ 32 حرفاً)
openssl rand -base64 32   # AUTOMIND_DATA_ENCRYPTION_KEY  (32 بايت base64)
openssl rand -base64 32   # AUTOMIND_BLIND_INDEX_KEY  (32 بايت base64 — مختلف عن السابق)
```
احفظها في مدير كلمات مرور. **لا تضعها في الكود أو في المحادثة.**

## 4. ضبط الأسرار في Cloudflare / Set the secrets
تُحقن في الحاوية كمتغيرات بيئة، ولا تُحفظ في الملفات:

```bash
npx wrangler secret put AUTOMIND_DATABASE_URL          # رابط Supabase من الخطوة 2
npx wrangler secret put AUTOMIND_JWT_SECRET
npx wrangler secret put AUTOMIND_DATA_ENCRYPTION_KEY
npx wrangler secret put AUTOMIND_BLIND_INDEX_KEY
npx wrangler secret put AUTOMIND_CORS_ORIGINS          # مثل https://admin.automind.sa (لوحة الإدارة)
# اختياري — ميزة شرح العطل بالذكاء الاصطناعي والفيديوهات:
npx wrangler secret put AUTOMIND_ANTHROPIC_API_KEY
npx wrangler secret put AUTOMIND_YOUTUBE_API_KEY
# اختياري — إن فعّلت Ollama بدل Anthropic، أو Redis مشترك (انظر الأسفل)
```

## 5. النشر / Deploy
```bash
npx wrangler deploy
```
يبني الصورة من `backend/Dockerfile` ويرفعها ويربط الـ Worker. بعد النجاح يعطيك رابطاً مثل
`https://automind-api.<حسابك>.workers.dev`. اختبر الصحة:

```bash
curl https://automind-api.<حسابك>.workers.dev/api/v1/health
```

> **إن فشل البناء بأنه لا يجد مجلد `shared`:** صورة الـ Dockerfile تحتاج جذر المستودع كسياق بناء (لذلك `wrangler.jsonc` في الجذر). إن بقيت المشكلة، ابنِ الصورة وارفعها لسجل حاويات (GitHub Container Registry أو Docker Hub) ثم أشِر إليها في `wrangler.jsonc` بـ `"image": "<registry>/automind-api:tag"` بدل مسار الـ Dockerfile.

## 6. نطاق مخصص / Custom domain (اختياري)
في لوحة Cloudflare: **Workers & Pages → automind-api → Settings → Domains & Routes → Add custom domain**،
مثل `api.automind.sa`. (نطاقك يجب أن يكون على Cloudflare DNS.)

## 7. توجيه التطبيق ولوحة الإدارة / Point the apps at the API
- **الجوال:** في شاشة الإعدادات، غيّر «عنوان الخادم» إلى `https://api.automind.sa/api/v1`.
- **لوحة الإدارة (web):** عند بنائها اضبط `NEXT_PUBLIC_API_BASE_URL=https://api.automind.sa/api/v1`، وأضف عنوان اللوحة إلى `AUTOMIND_CORS_ORIGINS` (الخطوة 4).

## 8. إنشاء حساب المدير / Create the first admin
الأمر يتصل بقاعدة البيانات مباشرة، فشغّله محلياً مرة واحدة موجّهاً إلى Supabase:

```bash
cd backend
pip install -e ".[dev]"
AUTOMIND_ENVIRONMENT=prod \
AUTOMIND_DATABASE_URL="postgresql+asyncpg://postgres:[PW]@db.<ref>.supabase.co:5432/postgres" \
AUTOMIND_DATA_ENCRYPTION_KEY="..." AUTOMIND_BLIND_INDEX_KEY="..." AUTOMIND_JWT_SECRET="..." \
automind create-admin --email you@example.com
```
يطبع رمز المصادقة الثنائية (TOTP) لإضافته في Google Authenticator.

## 9. Redis (اختياري) / scaling note
التطبيق يعمل بذاكرة مؤقتة داخلية إذا لم يوجد Redis — كافٍ لحاوية واحدة. إذا رفعت عدد الحاويات
(`instances`/`max_instances` في `wrangler.jsonc`) فأضف Redis مشتركاً (مثل Upstash) واضبط:

```bash
npx wrangler secret put AUTOMIND_REDIS_URL   # redis://...  (يفعّل حد الطلبات والكاش المشترك)
```

## ملاحظات / Notes
- Containers حالياً linux/amd64 فقط، وتخفض لصفر عند الخمول (أول طلب بعد الخمول أبطأ قليلاً).
- قاعدة البيانات والنسخ الاحتياطي يُداران من Supabase (فعّل PITR قبل الإطلاق التجاري).
- راجع `docs/SECURITY_PRIVACY.md` لقائمة ما قبل الإنتاج.
