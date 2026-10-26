"use client";

import { useI18n } from "@/i18n/I18nProvider";
import { API_BASE_URL } from "@/lib/config";

/** Makes it explicit that figures come straight from the live API. */
export function LiveApiBadge({ fetchedAt }: { fetchedAt?: Date | null }) {
  const { dict, t, fmt } = useI18n();
  return (
    <p className="flex flex-wrap items-center gap-x-2 gap-y-1 text-xs text-muted">
      <span
        className="inline-flex items-center gap-1.5 rounded-full border border-success/40 bg-success-soft px-2 py-0.5 font-medium text-success"
        title={t(dict.common.liveApiNote, { api: API_BASE_URL })}
      >
        <span aria-hidden="true" className="h-1.5 w-1.5 rounded-full bg-success" />
        {dict.common.liveApiBadge}
      </span>
      <span dir="ltr" className="font-mono">{API_BASE_URL}</span>
      {fetchedAt ? <span>{t(dict.common.lastUpdated, { time: fmt.dateTime(fetchedAt.toISOString()) })}</span> : null}
    </p>
  );
}
