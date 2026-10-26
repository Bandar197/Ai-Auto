"use client";

import { useState } from "react";
import { useAuth } from "@/components/auth/AuthProvider";
import { Badge } from "@/components/ui/Badge";
import { Card } from "@/components/ui/Card";
import { PageHeader } from "@/components/ui/PageHeader";
import { Pagination } from "@/components/ui/Pagination";
import { EmptyState, ErrorState, LoadingState } from "@/components/ui/States";
import { useApiQuery } from "@/hooks/useApiQuery";
import { useI18n } from "@/i18n/I18nProvider";

const LIMIT = 50;

export function ErrorsView() {
  const { api } = useAuth();
  const { dict, fmt } = useI18n();
  const [offset, setOffset] = useState(0);
  const errors = useApiQuery(`errors-${offset}`, (s) => api.errors({ limit: LIMIT, offset }, s));
  const th = "whitespace-nowrap bg-surface-2 px-3 py-2 text-start text-xs font-semibold text-muted";
  const td = "border-t border-line px-3 py-2 align-top";

  return (
    <>
      <PageHeader title={dict.errors.title} subtitle={dict.errors.subtitle} fetchedAt={errors.fetchedAt} />
      <Card>
        {errors.error ? (
          <ErrorState error={errors.error} onRetry={errors.reload} />
        ) : errors.loading && !errors.data ? (
          <LoadingState rows={6} />
        ) : !errors.data?.items?.length ? (
          <EmptyState />
        ) : (
          <>
            <div className="overflow-x-auto rounded-md border border-line">
              <table className="w-full min-w-[720px] text-sm">
                <thead>
                  <tr>
                    <th scope="col" className={th}>{dict.errors.occurredAt}</th>
                    <th scope="col" className={th}>{dict.errors.component}</th>
                    <th scope="col" className={th}>{dict.errors.code}</th>
                    <th scope="col" className={th}>{dict.errors.message}</th>
                    <th scope="col" className={th}>{dict.errors.requestId}</th>
                  </tr>
                </thead>
                <tbody>
                  {errors.data.items.map((e) => (
                    <tr key={String(e.id)}>
                      <td className={`${td} whitespace-nowrap`}>{fmt.dateTime(e.occurred_at)}</td>
                      <td className={td}><Badge>{e.component}</Badge></td>
                      <td className={`${td} font-mono text-xs`} dir="ltr">{e.error_code}</td>
                      <td className={`${td} max-w-md break-words`} dir="auto">{e.message || "—"}</td>
                      <td className={`${td} font-mono text-xs`} dir="ltr">{e.request_id || "—"}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
            <Pagination offset={offset} limit={LIMIT} total={errors.data.total} onChange={setOffset} />
          </>
        )}
      </Card>
    </>
  );
}
