"use client";

import { useState, type ReactNode } from "react";
import { useAuth } from "@/components/auth/AuthProvider";
import {
  ConnectionsPerDayChart,
  DataModeChart,
  SessionsPerDayChart,
  TopDtcsChart,
} from "@/components/charts/Charts";
import { Card } from "@/components/ui/Card";
import { DaysSelect, type DayOption } from "@/components/ui/DaysSelect";
import { ExportButton } from "@/components/ui/ExportButton";
import { KpiTile } from "@/components/ui/KpiTile";
import { PageHeader } from "@/components/ui/PageHeader";
import { EmptyState, ErrorState, LoadingState } from "@/components/ui/States";
import { useApiQuery } from "@/hooks/useApiQuery";
import { useI18n } from "@/i18n/I18nProvider";
import type { DataMode, OverviewStats } from "@/lib/types";

const PLAN_NAMES: Record<string, { ar: string; en: string }> = {
  basic: { ar: "الأساسية", en: "Basic" },
  pro: { ar: "الاحترافية", en: "Pro" },
  garage_business: { ar: "باقة الورش", en: "Garage Business" },
};

function Section({ title, children }: { title: string; children: ReactNode }) {
  return (
    <section className="mb-6" aria-label={title}>
      <h2 className="mb-2 text-sm font-semibold uppercase tracking-wide text-muted">{title}</h2>
      <dl className="grid grid-cols-1 gap-3 min-[420px]:grid-cols-2 xl:grid-cols-4">{children}</dl>
    </section>
  );
}

export function KpiGrid({ stats }: { stats: OverviewStats }) {
  const { dict, fmt, locale, t } = useI18n();
  const o = dict.overview;
  const subs = Object.entries(stats.active_subscriptions_by_plan ?? {});
  const modes: DataMode[] = ["live", "demo", "replay"];
  const byMode = stats.sessions_by_mode ?? {};
  const modeTotal = modes.reduce((sum, m) => sum + (byMode[m] ?? 0), 0);

  return (
    <>
      <Section title={o.sectionUsers}>
        <KpiTile label={o.usersTotal} value={fmt.integer(stats.users_total)} />
        <KpiTile label={o.usersActive} value={fmt.integer(stats.users_active_30d)} />
        <KpiTile label={o.vehicles} value={fmt.integer(stats.vehicles_total)} />
        <KpiTile label={o.devices} value={fmt.integer(stats.devices_total)} />
      </Section>

      <Section title={o.sectionSessions}>
        <KpiTile label={o.sessionsToday} value={fmt.integer(stats.sessions_today)} hint={o.sessionsAllModesHint} />
        <KpiTile label={o.sessionsMonth} value={fmt.integer(stats.sessions_month)} hint={o.sessionsAllModesHint} />
        <KpiTile label={o.connectionSuccess} value={fmt.percent(stats.connection_success_rate_30d)} />
        <KpiTile label={o.diagnosisConfirmed} value={fmt.percent(stats.diagnosis_confirmed_rate)} />
      </Section>

      <div className="mb-6">
        <Card title={o.dataModeTitle} description={o.dataModeNote}>
          <dl className="mb-3 grid grid-cols-1 gap-3 min-[420px]:grid-cols-3">
            {modes.map((m) => {
              const value = byMode[m];
              const share = modeTotal > 0 && typeof value === "number" ? value / modeTotal : null;
              return (
                <div key={m} className="rounded-lg border border-line p-3" data-testid={`mode-${m}`}>
                  <dt className="flex items-center gap-2 text-sm font-medium">
                    <ModeDot mode={m} />
                    {dict.dataMode[m]}
                  </dt>
                  <dd className="tabular mt-1 text-2xl font-semibold">{fmt.integer(value)}</dd>
                  <dd className="text-xs text-muted">
                    {dict.dataMode[`${m}Hint` as const]}
                    {share !== null ? ` · ${t(o.dataModeShare, { percent: fmt.percent(share) })}` : ""}
                  </dd>
                </div>
              );
            })}
          </dl>
          <DataModeChart byMode={byMode} />
        </Card>
      </div>

      <Section title={o.sectionCommerce}>
        <KpiTile label={o.revenueMonth} value={fmt.sar(stats.revenue_month_sar)} />
        <KpiTile label={o.cancellations} value={fmt.integer(stats.cancelled_subscriptions_month)} />
        <div className="min-w-0 rounded-lg border border-line bg-surface p-3 min-[420px]:col-span-2 sm:p-4">
          <dt className="text-sm text-muted">{o.activeSubscriptions}</dt>
          <dd className="mt-2">
            {subs.length === 0 ? (
              <span className="text-sm text-muted">{dict.common.empty}</span>
            ) : (
              <ul className="grid grid-cols-1 gap-2 min-[420px]:grid-cols-3">
                {subs.map(([key, count]) => (
                  <li key={key} className="rounded-md bg-surface-2 px-3 py-2">
                    <span className="block text-xs text-muted">{PLAN_NAMES[key]?.[locale] ?? key}</span>
                    <span className="tabular text-xl font-semibold">{fmt.integer(count)}</span>
                  </li>
                ))}
              </ul>
            )}
          </dd>
        </div>
      </Section>

      <Section title={o.sectionMarketplace}>
        <KpiTile label={o.workshops} value={fmt.integer(stats.workshops_total)} />
        <KpiTile label={o.suppliers} value={fmt.integer(stats.suppliers_total)} />
        <KpiTile label={o.ordersMonth} value={fmt.integer(stats.orders_month)} />
      </Section>

      <Section title={o.sectionOps}>
        <KpiTile label={o.errors24h} value={fmt.integer(stats.errors_24h)} />
        <KpiTile
          label={o.aiRequests}
          value={fmt.integer(stats.ai_usage_month?.requests)}
          hint={`${o.aiInputTokens}: ${fmt.compact(stats.ai_usage_month?.input_tokens)} · ${o.aiOutputTokens}: ${fmt.compact(stats.ai_usage_month?.output_tokens)}`}
        />
        <KpiTile label={o.aiCost} value={fmt.usd(stats.ai_usage_month?.cost_usd)} />
      </Section>
    </>
  );
}

function ModeDot({ mode }: { mode: DataMode }) {
  // Shape + label carry identity, not colour alone.
  const shape = mode === "live" ? "rounded-full" : mode === "demo" ? "rounded-none" : "rounded-sm rotate-45";
  return <span aria-hidden="true" className={`inline-block h-2.5 w-2.5 bg-accent ${shape}`} />;
}

export function OverviewView() {
  const { api } = useAuth();
  const { dict } = useI18n();
  const [days, setDays] = useState<DayOption>(30);

  const overview = useApiQuery("overview", (s) => api.overview(s));
  const sessions = useApiQuery(`ts-sessions-${days}`, (s) => api.timeseries("sessions", days, s));
  const connections = useApiQuery(`ts-connections-${days}`, (s) => api.timeseries("connections", days, s));
  const topDtcs = useApiQuery(`top-dtcs-${days}`, (s) => api.topDtcs(days, 10, s));

  const reloadAll = () => {
    overview.reload();
    sessions.reload();
    connections.reload();
    topDtcs.reload();
  };

  return (
    <>
      <PageHeader
        title={dict.overview.title}
        subtitle={dict.overview.subtitle}
        fetchedAt={overview.fetchedAt}
        actions={
          <button
            type="button"
            onClick={reloadAll}
            className="rounded-md border border-line bg-surface px-3 py-1.5 text-sm font-medium hover:bg-surface-2"
          >
            {dict.common.refresh}
          </button>
        }
      />

      {overview.error ? (
        <div className="mb-6">
          <ErrorState error={overview.error} onRetry={overview.reload} />
        </div>
      ) : overview.loading && !overview.data ? (
        <LoadingState rows={6} />
      ) : overview.data ? (
        <KpiGrid stats={overview.data} />
      ) : null}

      <div className="mb-4 flex justify-end">
        <DaysSelect value={days} onChange={setDays} />
      </div>

      <div className="grid grid-cols-1 gap-4 xl:grid-cols-2">
        <Card title={dict.overview.sessionsPerDay} description={dict.overview.sessionsPerDayNote}>
          {sessions.error ? (
            <ErrorState compact error={sessions.error} onRetry={sessions.reload} />
          ) : sessions.loading && !sessions.data ? (
            <LoadingState />
          ) : sessions.data?.points?.length ? (
            <SessionsPerDayChart points={sessions.data.points} />
          ) : (
            <EmptyState />
          )}
        </Card>

        <Card title={dict.overview.connectionsPerDay}>
          {connections.error ? (
            <ErrorState compact error={connections.error} onRetry={connections.reload} />
          ) : connections.loading && !connections.data ? (
            <LoadingState />
          ) : connections.data?.points?.length ? (
            <ConnectionsPerDayChart points={connections.data.points} />
          ) : (
            <EmptyState />
          )}
        </Card>

        <Card title={dict.overview.topDtcs} className="xl:col-span-2">
          {topDtcs.error ? (
            <ErrorState compact error={topDtcs.error} onRetry={topDtcs.reload} />
          ) : topDtcs.loading && !topDtcs.data ? (
            <LoadingState />
          ) : topDtcs.data?.length ? (
            <TopDtcsChart items={topDtcs.data} />
          ) : (
            <EmptyState />
          )}
        </Card>

        <Card title={dict.overview.exportsTitle} className="xl:col-span-2">
          <div className="flex flex-wrap gap-3">
            <ExportButton dataset="sessions" />
            <ExportButton dataset="connections" />
            <ExportButton dataset="users" />
            <ExportButton dataset="top-dtcs" />
          </div>
        </Card>
      </div>
    </>
  );
}
