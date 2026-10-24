# النشر والصيانة

## المكونات المنشورة حالياً

- الواجهة: GitHub Pages من المستودع `Bandar197/Bandar197.github.io` (فرع `main`). يُنشر تلقائياً بعد كل دفع.
- الخادم: مشروع Supabase `kdjexepmmkilhkjqflau` (اسمه baloot-majlis).
- النسخة السابقة «بلوت المجلس» محفوظة على `/majlis/`.

## نشر نسخة جديدة من الواجهة

```bash
git clone https://github.com/Bandar197/Bandar197.github.io.git pages
rsync -a --delete --exclude .git --exclude majlis diwaniya/web/ pages/
cp pages/index.html pages/404.html     # روابط مباشرة مثل /u/name و /room/code
touch pages/.nojekyll
cd pages && git add -A && git commit -m "Deploy" && git push
```

## نشر الخادم

```bash
supabase link --project-ref <ref>
supabase db push                                   # يطبق supabase/migrations بالترتيب
supabase functions deploy api --no-verify-jwt      # الدالة تتحقق من المستخدم بنفسها
```

قبل تطبيق `20261023000400_diwaniya_server_settings.sql` غيّر فيه بريد المالك ورابط المشروع (القيم الحالية في المستودع أمثلة).

## إعدادات لوحة Supabase (مرة واحدة)

1. **Authentication → URL Configuration**
   - Site URL: `https://bandar197.github.io`
   - Redirect URLs: `https://bandar197.github.io/welcome` و`https://bandar197.github.io/reset` و`https://bandar197.github.io/settings`
2. **Authentication → Emails → SMTP Settings**: اربط مزود بريد (مثل Resend أو Brevo أو SendGrid). خدمة البريد المدمجة في Supabase للتجربة فقط: ترسل لأعضاء فريق المشروع وبحد منخفض جداً، فلا تصل رسائل التأكيد والاستعادة للاعبين بدونها.
3. **Authentication → Sign In / Providers → Email**: أبقِ «Confirm email» مفعّلاً.
4. **Google (اختياري)**: فعّل المزود بمعرّف OAuth من Google Cloud، ثم غيّر `GOOGLE_ENABLED` إلى `true` في `web/js/config.js` وانشر الواجهة.
5. **حدود المحاولات**: Authentication → Rate Limits (الافتراضي مناسب؛ الواجهة تضيف مهلة بعد ٣ محاولات فاشلة).

## الأسرار

- مفتاح service-role متاح للدالة تلقائياً عبر `SUPABASE_SERVICE_ROLE_KEY` ولا يظهر في المستودع.
- سر المهمة المجدولة محفوظ في Supabase Vault باسم `diwaniya_cron_secret`، والدالة تتحقق منه عبر `cron_secret_ok`.
- بريد المالك في جدول `app_settings` (لا يصل له العملاء). أول دخول بهذا البريد يمنح دور المالك ويُسجل في سجل التدقيق.

## الصيانة

- أخطاء الخادم: جدول `server_errors`، وتظهر في لوحة الإدارة.
- سجل الإجراءات الإدارية: `audit_log`.
- المهمة المجدولة: `select * from cron.job;` و`select * from cron.job_run_details order by start_time desc limit 20;`
- موسم جديد: من لوحة الإدارة، أو `admin_season_start`.
- حذف حساب تجريبي: سجّل دخوله واستدعِ `delete_account` مع `confirm` = اسم المستخدم (يحذف الصورة والحساب ويسجل ذلك).
