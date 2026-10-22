# AutoMind AI — لوحة الإدارة / Admin dashboard

لوحة إدارة ويب لمنصة أوتومايند (Next.js App Router + TypeScript + Tailwind CSS + Recharts).
العربية هي اللغة الافتراضية (`/ar`، من اليمين لليسار) مع دعم الإنجليزية (`/en`).

Web admin dashboard for the AutoMind platform. Arabic is the default locale (`/ar`, RTL); English is at `/en`.

---

## العربية

### المتطلبات
- Node.js 22.12 أو أحدث، و npm.
- خادم الـ API (FastAPI في `backend/`) يعمل ويسمح بطلبات CORS من عنوان اللوحة مع ترويسة `Authorization`.

### التشغيل محليًا
```bash
cd web
cp .env.example .env.local      # عدّل NEXT_PUBLIC_API_BASE_URL عند الحاجة
npm ci
npm run dev                     # http://localhost:3000 ← يحوّل إلى /ar
```

### الإعدادات
| المتغير | الوصف |
|---|---|
| `NEXT_PUBLIC_API_BASE_URL` | عنوان الـ API كما يراه المتصفح (الافتراضي `http://localhost:8000/api/v1`). يُضمَّن وقت البناء ويُضاف أصله إلى سياسة CSP. |
| `API_INTERNAL_BASE_URL` | اختياري: عنوان الـ API من خادم Next.js (مثلًا داخل Docker) لمسار `/api/session`. |
| `SESSION_COOKIE_SECURE` | اختياري: `true`/`false` لفرض خاصية Secure على ملف تعريف الارتباط. |

### الأمان والجلسة
- رمز الوصول (access token) يُحفظ في الذاكرة فقط.
- رمز التحديث (refresh token) يُحفظ في ملف تعريف ارتباط `httpOnly` و`SameSite=Strict` عبر المسار `/api/session` الذي يمرّر `/auth/login` و`/auth/refresh` و`/auth/logout` إلى الخادم. لا يُخزَّن أبدًا في `localStorage`.
- عند استجابة `403 mfa_required` يظهر حقل رمز التحقق (TOTP).
- كل الأرقام تُقرأ مباشرة من الـ API؛ لا توجد بيانات تجريبية في الواجهة، وعند تعذّر الوصول للخادم تظهر رسالة خطأ واضحة.

### فحوص الجودة
```bash
npm run lint && npm run typecheck && npm test && npm run build
```

### Docker
```bash
docker build --build-arg NEXT_PUBLIC_API_BASE_URL=https://api.example.com/api/v1 -t automind-admin web/
docker run -p 3000:3000 -e API_INTERNAL_BASE_URL=http://backend:8000/api/v1 automind-admin
```

---

## English

### Requirements
- Node.js ≥ 22.12 and npm.
- The API (FastAPI in `backend/`) running and allowing CORS from the dashboard origin with the `Authorization` header.

### Run locally
```bash
cd web
cp .env.example .env.local      # adjust NEXT_PUBLIC_API_BASE_URL if needed
npm ci
npm run dev                     # http://localhost:3000 → redirects to /ar
```

### Configuration
| Variable | Purpose |
|---|---|
| `NEXT_PUBLIC_API_BASE_URL` | API base URL as seen by the browser (default `http://localhost:8000/api/v1`). Inlined at build time; its origin is added to the CSP `connect-src`. |
| `API_INTERNAL_BASE_URL` | Optional: API URL used by the Next.js server for `/api/session` (e.g. a Docker service name). |
| `SESSION_COOKIE_SECURE` | Optional: `true`/`false` to force the cookie's Secure flag (defaults to on in production). |

### Session & security
- The access token lives in memory only; the API client (`src/lib/api.ts`) attaches it, refreshes once on 401 and maps the `{error:{code,message}}` envelope to `ApiError`.
- The refresh token is kept in an `httpOnly`, `SameSite=Strict` cookie scoped to `/api/session`, a route handler that proxies `/auth/login`, `/auth/refresh` and `/auth/logout`. It is never stored in `localStorage`.
- A `403 mfa_required` response reveals the TOTP field on the login page.
- Security headers (CSP limited to self + the API origin, `X-Frame-Options: DENY`, `Referrer-Policy`, `Permissions-Policy`, HSTS, …) are set in `next.config.ts`.
- Every figure is read from the live API. The UI contains no sample data; when the API is unreachable it shows an error state. `data_mode` (live / demo / replay) is always broken out.

### Pages
Overview (KPIs + charts), Users (search, suspend/activate), Diagnostics (top DTCs), Plans (prices, features, limits), System errors, Audit log, and CSV exports via `/admin/export/{dataset}.csv`.

### Quality gates
```bash
npm run lint        # ESLint (next/core-web-vitals + typescript), zero warnings
npm run typecheck   # next typegen && tsc --noEmit
npm test            # Vitest + Testing Library
npm run build       # production build (output: standalone)
```

### Docker
See the commands above. The image is multi-stage, uses `output: "standalone"` and runs as a non-root user (`nextjs`, uid 1001) on port 3000.
