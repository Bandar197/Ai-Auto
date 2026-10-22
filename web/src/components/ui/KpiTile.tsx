import type { ReactNode } from "react";

export function KpiTile({ label, value, hint }: { label: string; value: ReactNode; hint?: ReactNode }) {
  return (
    <div className="min-w-0 rounded-lg border border-line bg-surface p-3 sm:p-4">
      <dt className="text-sm text-muted">{label}</dt>
      <dd className="tabular mt-1 truncate text-2xl font-semibold" dir="auto">
        {value}
      </dd>
      {hint ? <dd className="mt-1 text-xs text-muted">{hint}</dd> : null}
    </div>
  );
}
