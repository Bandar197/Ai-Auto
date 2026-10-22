# ZUKHR — زخر · اختيارات تستاهل

Salla Twilight React theme for the ZUKHR store. Salla stays the backend
(products, stock, customers, orders, payment, shipping, coupons); this
repository is the storefront only.

Built from the official **Raed** React starter (`salla theme create --type react`,
Salla CLI 3.2.x) on `@salla.sa/twilight-theme-engine` (TanStack Start, SSR).
See `AGENTS.md` for the engine rules and `FORKS.md` for engine components the
theme has copied.

## Run it

Requirements: Node.js 22.22.2+ (or 24.15+), pnpm 10, Salla CLI 3.x.

```bash
pnpm install
salla theme dev            # local dev against the bound store (writes .env)
salla theme dev --store    # bind the dev server to your own Salla store (needs login)
salla theme dev --editor   # the merchant theme editor around the dev server (needs login)
```

Open `/ar` (Arabic first) or `/en`, never `/`.

Checks before every push:

```bash
pnpm build && pnpm typecheck && pnpm test && pnpm check:manifest
```

Do **not** run `salla theme publish` until the design is approved.

## Where ZUKHR lives

| Area | Files |
| --- | --- |
| Brand tokens, fonts | `app/styles/01-settings/brand.scss`, `app/assets/fonts/` (Tajawal + Montserrat, OFL, self-hosted) |
| App shell (canvas, focus, buttons, sections) | `app/styles/02-generic/brand-base.scss` |
| Announcement bar | `app/components/zukhr/AnnouncementBar.tsx` |
| Header | `app/components/layout/Header.tsx`, `app/styles/04-components/zk-header.scss` |
| Home blocks | `app/components/zukhr/home/*`, `app/styles/04-components/zk-home.scss`, registered in `app/router.tsx` |
| Merchant settings + blocks | `twilight.json` (`announcement_*`, `header_show_*`, `home.zk-*`) |
| Dev home layout | `twilight.preview.json` (used by `salla theme dev` only) |

The store's own font and primary colour settings are overridden by the brand
tokens on purpose: ZUKHR's identity is fixed (Midnight Navy, Tajawal/Montserrat).

## Home page (Stage 1 skeleton)

Hero → Shop by category → ZUKHR Picks → Best sellers (Salla's most-sold list)
→ Campaign → Offers → Gifts → Why ZUKHR → Customer reviews (Salla store
reviews) → Stay in touch. Every section is a theme-editor block; product
sections only ever show real store products and stay hidden when empty.

## Git

Never commit `.env`, tokens or secrets (`.gitignore` covers `.env*`).
