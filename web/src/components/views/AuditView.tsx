"use client";

import { useState } from "react";
import { useAuth } from "@/components/auth/AuthProvider";
import { Badge, type BadgeTone } from "@/components/ui/Badge";
import { Card } from "@/components/ui/Card";
import { PageHeader } from "@/components/ui/PageHeader";
import { Pagination } from "@/components/ui/Pagination";
import { EmptyState, ErrorState, LoadingState } from "@/components/ui/States";
import { useApiQuery } from "@/hooks/useApiQuery";
import { useI18n } from "@/i18n/I18nProvider";

const LIMIT = 50;
const outcomeTone: Record<string, BadgeTone> = { success: "success", failure: "danger", denied: "warning" };

export function AuditView() {
  const { api } = useAuth();
  const { dict, fmt } = useI18n();
  const [offset, setOffset] = useState(0);
  const logs = useApiQuery(`audit-${offset}`, (s) => api.auditLogs({ limit: LIMIT, offset }, s));
  const th = "whitespace-nowrap bg-surface-2 px-3 py-2 text-start text-xs font-semibold text-muted";
  const td = "border-t border-line px-3 py-2 align-top";
  const outcomes = dict.audit.outcomes as Record<string, string>;

  return (
    <>
      <PageHeader title={dict.audit.title} subtitle={dict.audit.subtitle} fetchedAt={logs.fetchedAt} />
      <Card>
        {logs.error ? (
          <ErrorState error={logs.error} onRetry={logs.reload} />
        ) : logs.loading && !logs.data ? (
          <LoadingState rows={6} />
        ) : !logs.data?.items?.length ? (
          <EmptyState />
        ) : (
          <>
            <div className="overflow-x-auto rounded-md border border-line">
              <table className="w-full min-w-[820px] text-sm">
                <thead>
                  <tr>
                    <th scope="col" className={th}>{dict.audit.occurredAt}</th>
                    <th scope="col" className={th}>{dict.audit.action}</th>
                    <th scope="col" className={th}>{dict.audit.outcome}</th>
                    <th scope="col" className={th}>{dict.audit.actor}</th>
                    <th scope="col" className={th}>{dict.audit.entity}</th>
                    <th scope="col" className={th}>{dict.audit.ip}</th>
                    <th scope="col" className={th}>{dict.audit.requestId}</th>
                  </tr>
                </thead>
                <tbody>
                  {logs.data.items.map((l) => (
                    <tr key={String(l.id)}>
                      <td className={`${td} whitespace-nowrap`}>{fmt.dateTime(l.occurred_at)}</td>
                      <td className={`${td} font-mono text-xs`} dir="ltr">{l.action}</td>
                      <td className={td}>
                        <Badge tone={outcomeTone[l.outcome] ?? "neutral"}>{outcomes[l.outcome] ?? l.outcome}</Badge>
                      </td>
                      <td className={`${td} font-mono text-xs`} dir="ltr">{l.actor_user_id ?? <span className="font-sans text-muted">{dict.audit.system}</span>}</td>
                      <td className={`${td} font-mono text-xs`} dir="ltr">
                        {l.entity_type ? `${l.entity_type}${l.entity_id ? `:${l.entity_id}` : ""}` : "—"}
                      </td>
                      <td className={`${td} font-mono text-xs`} dir="ltr">{l.ip_address || "—"}</td>
                      <td className={`${td} font-mono text-xs`} dir="ltr">{l.request_id || "—"}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
            <Pagination offset={offset} limit={LIMIT} total={logs.data.total} onChange={setOffset} />
          </>
        )}
      </Card>
    </>
  );
}
