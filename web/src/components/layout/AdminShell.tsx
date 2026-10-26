"use client";

import Link from "next/link";
import { usePathname, useRouter } from "next/navigation";
import { useEffect, useState, type ReactNode } from "react";
import { useAuth } from "@/components/auth/AuthProvider";
import { LoadingState } from "@/components/ui/States";
import { useI18n } from "@/i18n/I18nProvider";
import { localePath } from "@/i18n/config";
import { LanguageSwitcher } from "./LanguageSwitcher";

const NAV = [
  { key: "overview", path: "" },
  { key: "users", path: "users" },
  { key: "diagnostics", path: "diagnostics" },
  { key: "ecu", path: "ecu" },
  { key: "plans", path: "plans" },
  { key: "errors", path: "errors" },
  { key: "audit", path: "audit" },
] as const;

function NavIcon({ name }: { name: (typeof NAV)[number]["key"] }) {
  const paths: Record<typeof name, string> = {
    overview: "M3 11h5V3H3v8zm0 6h5v-4H3v4zm7 0h7V9h-7v8zm0-14v4h7V3h-7z",
    users: "M7 9a3 3 0 100-6 3 3 0 000 6zm6 0a2.5 2.5 0 100-5M1.5 17c0-3 2.5-5 5.5-5s5.5 2 5.5 5M13 12c2.5 0 5 1.6 5 5",
    diagnostics: "M2 10h3l2-5 3 10 2-5h6",
    ecu: "M6 6h8v8H6zM8 2v2m4-2v2m-4 12v2m4-2v2M2 8h2m-2 4h2m12-4h2m-2 4h2",
    plans: "M3 5h14v10H3zM3 8h14",
    errors: "M10 3l8 14H2L10 3zm0 5v4m0 2.5v.5",
    audit: "M5 2h7l4 4v12H5zM12 2v4h4M8 10h6M8 13h6",
  };
  return (
    <svg aria-hidden="true" viewBox="0 0 20 20" className="h-5 w-5 shrink-0" fill="none" stroke="currentColor" strokeWidth="1.6" strokeLinecap="round" strokeLinejoin="round">
      <path d={paths[name]} />
    </svg>
  );
}

export function AdminShell({ children }: { children: ReactNode }) {
  const { state, logout } = useAuth();
  const { dict, locale, fmt } = useI18n();
  const router = useRouter();
  const pathname = usePathname() ?? "";
  const [menuOpen, setMenuOpen] = useState(false);

  useEffect(() => {
    if (state.status === "unauthenticated") {
      router.replace(localePath(locale, "login"));
    }
  }, [state.status, router, locale]);

  if (state.status !== "authenticated") {
    return (
      <main className="mx-auto flex min-h-screen max-w-sm items-center px-4">
        <div className="w-full">
          <LoadingState label={dict.auth.checkingSession} />
          <p className="mt-2 text-center text-sm text-muted">{dict.auth.checkingSession}</p>
        </div>
      </main>
    );
  }

  const user = state.user;
  const isActive = (path: string) => {
    const href = localePath(locale, path);
    return path === "" ? pathname === href : pathname === href || pathname.startsWith(`${href}/`);
  };

  const nav = (
    <nav aria-label={dict.nav.main}>
      <ul className="space-y-1">
        {NAV.map((item) => {
          const active = isActive(item.path);
          return (
            <li key={item.key}>
              <Link
                href={localePath(locale, item.path)}
                aria-current={active ? "page" : undefined}
                onClick={() => setMenuOpen(false)}
                className={`flex items-center gap-3 rounded-md px-3 py-2 text-sm font-medium ${
                  active ? "bg-accent-soft text-accent" : "text-fg hover:bg-surface-2"
                }`}
              >
                <NavIcon name={item.key} />
                {dict.nav[item.key]}
              </Link>
            </li>
          );
        })}
      </ul>
    </nav>
  );

  const userBox = (
    <div className="border-t border-line pt-3 text-sm">
      <p className="text-xs text-muted">{dict.auth.signedInAs}</p>
      <p className="truncate font-medium" dir="ltr" title={user.email}>
        {user.email}
      </p>
      <p className="text-xs text-muted">
        {dict.roles[user.platform_role] ?? user.platform_role} · {fmt.date(user.created_at)}
      </p>
      <div className="mt-3 flex flex-wrap gap-2">
        <LanguageSwitcher />
        <button
          type="button"
          onClick={() => void logout()}
          className="rounded-md border border-line bg-surface px-3 py-1.5 text-sm font-medium hover:bg-surface-2"
        >
          {dict.auth.signOut}
        </button>
      </div>
    </div>
  );

  return (
    <div className="min-h-screen lg:flex">
      <a href="#main" className="sr-only focus:not-sr-only focus:absolute focus:start-2 focus:top-2 focus:z-50 focus:rounded-md focus:bg-surface focus:px-3 focus:py-2">
        {dict.common.skipToContent}
      </a>

      {/* Mobile top bar */}
      <header className="sticky top-0 z-30 flex items-center justify-between border-b border-line bg-surface px-4 py-3 lg:hidden">
        <Link href={localePath(locale)} className="font-bold">
          {dict.nav.brand} <span className="font-normal text-muted">· {dict.nav.console}</span>
        </Link>
        <button
          type="button"
          aria-expanded={menuOpen}
          aria-controls="mobile-nav"
          onClick={() => setMenuOpen((o) => !o)}
          className="rounded-md border border-line px-3 py-1.5 text-sm font-medium"
        >
          {menuOpen ? dict.common.closeMenu : dict.common.menu}
        </button>
      </header>
      {menuOpen ? (
        <div id="mobile-nav" className="border-b border-line bg-surface px-4 py-3 lg:hidden">
          {nav}
          <div className="mt-3">{userBox}</div>
        </div>
      ) : null}

      {/* Desktop sidebar */}
      <aside className="hidden w-64 shrink-0 flex-col gap-4 border-e border-line bg-surface p-4 lg:sticky lg:top-0 lg:flex lg:h-screen">
        <Link href={localePath(locale)} className="block px-3 pt-1">
          <span className="block text-lg font-bold">{dict.nav.brand}</span>
          <span className="block text-xs text-muted">{dict.nav.console}</span>
        </Link>
        <div className="flex-1 overflow-y-auto">{nav}</div>
        {userBox}
      </aside>

      <main id="main" tabIndex={-1} className="min-w-0 flex-1 px-4 py-5 sm:px-6 lg:px-8 lg:py-8">
        {children}
        <footer className="mt-10 text-xs text-muted">{dict.common.timezoneNote}</footer>
      </main>
    </div>
  );
}
