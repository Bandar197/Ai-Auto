"use client";

import { useId } from "react";
import { useI18n } from "@/i18n/I18nProvider";

export const DAY_OPTIONS = [7, 30, 90] as const;
export type DayOption = (typeof DAY_OPTIONS)[number];

export function DaysSelect({ value, onChange }: { value: DayOption; onChange(v: DayOption): void }) {
  const { dict } = useI18n();
  const id = useId();
  const labels: Record<DayOption, string> = { 7: dict.common.days7, 30: dict.common.days30, 90: dict.common.days90 };
  return (
    <div className="flex items-center gap-2">
      <label htmlFor={id} className="text-sm text-muted">
        {dict.common.period}
      </label>
      <select
        id={id}
        value={value}
        onChange={(e) => onChange(Number(e.target.value) as DayOption)}
        className="rounded-md border border-line bg-surface px-2 py-1.5 text-sm"
      >
        {DAY_OPTIONS.map((d) => (
          <option key={d} value={d}>
            {labels[d]}
          </option>
        ))}
      </select>
    </div>
  );
}
