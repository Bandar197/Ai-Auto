"use client";

import { useI18n } from "@/i18n/I18nProvider";

export function Pagination({
  offset,
  limit,
  total,
  onChange,
}: {
  offset: number;
  limit: number;
  total: number;
  onChange(offset: number): void;
}) {
  const { dict, t, fmt } = useI18n();
  if (total <= 0) return null;
  const from = Math.min(offset + 1, total);
  const to = Math.min(offset + limit, total);
  const btn =
    "rounded-md border border-line bg-surface px-3 py-1.5 text-sm font-medium hover:bg-surface-2 disabled:cursor-not-allowed disabled:opacity-50";
  return (
    <div className="mt-3 flex flex-wrap items-center justify-between gap-2">
      <p className="tabular text-sm text-muted" aria-live="polite">
        {t(dict.common.pageRange, { from: fmt.integer(from), to: fmt.integer(to), total: fmt.integer(total) })}
      </p>
      <div className="flex gap-2">
        <button type="button" className={btn} disabled={offset <= 0} onClick={() => onChange(Math.max(0, offset - limit))}>
          {dict.common.previous}
        </button>
        <button type="button" className={btn} disabled={offset + limit >= total} onClick={() => onChange(offset + limit)}>
          {dict.common.next}
        </button>
      </div>
    </div>
  );
}
