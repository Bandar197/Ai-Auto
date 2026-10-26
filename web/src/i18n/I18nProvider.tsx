"use client";

import { createContext, useContext, useMemo, type ReactNode } from "react";
import type { Dictionary } from "./ar";
import { dictionaries, dirOf, interpolate, type Locale } from "./config";
import { createFormatters, type Formatters } from "./format";

interface I18nValue {
  locale: Locale;
  dir: "rtl" | "ltr";
  dict: Dictionary;
  fmt: Formatters;
  t: typeof interpolate;
}

const I18nContext = createContext<I18nValue | null>(null);

export function I18nProvider({ locale, children }: { locale: Locale; children: ReactNode }) {
  const value = useMemo<I18nValue>(
    () => ({
      locale,
      dir: dirOf(locale),
      dict: dictionaries[locale],
      fmt: createFormatters(locale),
      t: interpolate,
    }),
    [locale],
  );
  return <I18nContext value={value}>{children}</I18nContext>;
}

export function useI18n(): I18nValue {
  const ctx = useContext(I18nContext);
  if (!ctx) throw new Error("useI18n must be used inside <I18nProvider>");
  return ctx;
}
