import { intlLocaleOf, type Locale } from "./config";

export const DISPLAY_TIME_ZONE = "Asia/Riyadh";

function isNum(value: unknown): value is number {
  return typeof value === "number" && Number.isFinite(value);
}

export function createFormatters(locale: Locale, empty = "—") {
  const tag = intlLocaleOf(locale);
  const integer = new Intl.NumberFormat(tag, { maximumFractionDigits: 0 });
  const decimal = new Intl.NumberFormat(tag, { maximumFractionDigits: 2 });
  const compact = new Intl.NumberFormat(tag, { notation: "compact", maximumFractionDigits: 1 });
  const percent = new Intl.NumberFormat(tag, { style: "percent", maximumFractionDigits: 1 });
  const sar = new Intl.NumberFormat(tag, { style: "currency", currency: "SAR", maximumFractionDigits: 2 });
  const usd = new Intl.NumberFormat(tag, { style: "currency", currency: "USD", maximumFractionDigits: 2 });
  const dateTime = new Intl.DateTimeFormat(tag, {
    dateStyle: "medium",
    timeStyle: "short",
    timeZone: DISPLAY_TIME_ZONE,
  });
  const date = new Intl.DateTimeFormat(tag, { dateStyle: "medium", timeZone: DISPLAY_TIME_ZONE });
  const shortDate = new Intl.DateTimeFormat(tag, { day: "numeric", month: "short", timeZone: "UTC" });

  const parse = (value: string | null | undefined): Date | null => {
    if (!value) return null;
    const d = new Date(value);
    return Number.isNaN(d.getTime()) ? null : d;
  };

  return {
    integer: (v: number | null | undefined) => (isNum(v) ? integer.format(v) : empty),
    decimal: (v: number | null | undefined) => (isNum(v) ? decimal.format(v) : empty),
    compact: (v: number | null | undefined) => (isNum(v) ? compact.format(v) : empty),
    /** `v` is a ratio in [0, 1] as returned by the stats API. */
    percent: (v: number | null | undefined) => (isNum(v) ? percent.format(v) : empty),
    sar: (v: number | null | undefined) => (isNum(v) ? sar.format(v) : empty),
    usd: (v: number | null | undefined) => (isNum(v) ? usd.format(v) : empty),
    dateTime: (v: string | null | undefined) => {
      const d = parse(v);
      return d ? dateTime.format(d) : empty;
    },
    date: (v: string | null | undefined) => {
      const d = parse(v);
      return d ? date.format(d) : empty;
    },
    /** For `YYYY-MM-DD` buckets from the timeseries endpoint (calendar days, UTC). */
    day: (v: string | null | undefined) => {
      const d = parse(v);
      return d ? shortDate.format(d) : (v ?? empty);
    },
  };
}

export type Formatters = ReturnType<typeof createFormatters>;
