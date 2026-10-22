import ar, { type Dictionary } from "./ar";
import en from "./en";

export const locales = ["ar", "en"] as const;
export type Locale = (typeof locales)[number];
export const defaultLocale: Locale = "ar";

export const dictionaries: Record<Locale, Dictionary> = { ar, en };

export function isLocale(value: string | undefined | null): value is Locale {
  return value === "ar" || value === "en";
}

export function dirOf(locale: Locale): "rtl" | "ltr" {
  return locale === "ar" ? "rtl" : "ltr";
}

/** BCP-47 tag used for Intl formatting. Latin digits keep tables scannable. */
export function intlLocaleOf(locale: Locale): string {
  return locale === "ar" ? "ar-SA-u-nu-latn" : "en-GB";
}

/** Replace `{name}` placeholders. Unknown placeholders are left as-is. */
export function interpolate(
  template: string,
  vars: Record<string, string | number> = {},
): string {
  return template.replace(/\{(\w[\w-]*)\}/g, (match, key: string) =>
    Object.prototype.hasOwnProperty.call(vars, key) ? String(vars[key]) : match,
  );
}

/** Prefix an app path with the locale segment: ("ar", "/users") -> "/ar/users". */
export function localePath(locale: Locale, path = ""): string {
  const clean = path.replace(/^\/+/, "");
  return clean ? `/${locale}/${clean}` : `/${locale}`;
}

/** Swap the locale segment of a pathname, keeping the rest of the path. */
export function switchLocalePath(pathname: string, target: Locale): string {
  const rest = pathname.replace(/^\/(ar|en)(?=\/|$)/, "");
  return `/${target}${rest}`;
}
