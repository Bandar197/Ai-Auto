"use client";

import { useId, useState } from "react";
import { useAuth } from "@/components/auth/AuthProvider";
import { TopDtcsTable } from "@/components/charts/Charts";
import { Card } from "@/components/ui/Card";
import { DaysSelect, type DayOption } from "@/components/ui/DaysSelect";
import { ExportButton } from "@/components/ui/ExportButton";
import { PageHeader } from "@/components/ui/PageHeader";
import { EmptyState, ErrorState, LoadingState } from "@/components/ui/States";
import { useApiQuery } from "@/hooks/useApiQuery";
import { useI18n } from "@/i18n/I18nProvider";

const LIMITS = [10, 25, 50, 100] as const;

export function DiagnosticsView() {
  const { api } = useAuth();
  const { dict, t } = useI18n();
  const limitId = useId();
  const [days, setDays] = useState<DayOption>(30);
  const [limit, setLimit] = useState<number>(25);
  const top = useApiQuery(`diag-top-${days}-${limit}`, (s) => api.topDtcs(days, limit, s));

  return (
    <>
      <PageHeader
        title={dict.diagnostics.title}
        subtitle={dict.diagnostics.subtitle}
        fetchedAt={top.fetchedAt}
        actions={<ExportButton dataset="top-dtcs" />}
      />
      <Card
        title={dict.overview.topDtcs}
        description={t(dict.common.lastNDays, { days })}
        actions={
          <>
            <DaysSelect value={days} onChange={setDays} />
            <div className="flex items-center gap-2">
              <label htmlFor={limitId} className="text-sm text-muted">
                {dict.diagnostics.limit}
              </label>
              <select
                id={limitId}
                value={limit}
                onChange={(e) => setLimit(Number(e.target.value))}
                className="rounded-md border border-line bg-surface px-2 py-1.5 text-sm"
              >
                {LIMITS.map((l) => (
                  <option key={l} value={l}>
                    {l}
                  </option>
                ))}
              </select>
            </div>
          </>
        }
      >
        {top.error ? (
          <ErrorState error={top.error} onRetry={top.reload} />
        ) : top.loading && !top.data ? (
          <LoadingState rows={6} />
        ) : !top.data?.length ? (
          <EmptyState />
        ) : (
          <div className="overflow-x-auto rounded-md border border-line">
            <TopDtcsTable items={top.data} />
          </div>
        )}
      </Card>
    </>
  );
}
