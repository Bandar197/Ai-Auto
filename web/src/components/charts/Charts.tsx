"use client";

import type { ReactNode } from "react";
import {
  Bar,
  BarChart,
  CartesianGrid,
  Legend,
  Line,
  LineChart,
  Tooltip,
  XAxis,
  YAxis,
} from "recharts";
import { useI18n } from "@/i18n/I18nProvider";
import type { DataMode, TimeseriesPoint, TopDtc } from "@/lib/types";

const axisTick = { fill: "var(--muted)", fontSize: 12 };
const tooltipStyle = {
  contentStyle: {
    background: "var(--surface)",
    border: "1px solid var(--line)",
    borderRadius: 8,
    color: "var(--fg)",
    fontSize: 13,
  },
  labelStyle: { color: "var(--fg)", fontWeight: 600 },
  itemStyle: { color: "var(--fg)" },
  cursor: { fill: "var(--surface-2)", stroke: "var(--line)" },
};

/** Chart + an accessible table view of the same rows. */
function ChartFrame({ label, chart, table }: { label: string; chart: ReactNode; table: ReactNode }) {
  const { dict } = useI18n();
  return (
    <figure className="m-0">
      {/* Charts keep a left-to-right time/value axis in both languages. */}
      <div dir="ltr" role="img" aria-label={label} className="w-full">
        {chart}
      </div>
      <details className="mt-2 text-sm">
        <summary className="cursor-pointer text-muted hover:text-fg">{dict.common.showTable}</summary>
        <div className="mt-2 max-h-72 overflow-auto rounded-md border border-line">{table}</div>
      </details>
    </figure>
  );
}

const th = "sticky top-0 bg-surface-2 px-3 py-2 text-start font-medium";
const td = "border-t border-line px-3 py-1.5";

export function SessionsPerDayChart({ points }: { points: TimeseriesPoint[] }) {
  const { dict, fmt } = useI18n();
  const data = points.map((p) => ({ date: p.date, label: fmt.day(p.date), value: p.value }));
  return (
    <ChartFrame
      label={dict.overview.sessionsPerDay}
      chart={
        <LineChart responsive data={data} style={{ width: "100%", height: 260 }} margin={{ top: 8, right: 12, bottom: 0, left: 0 }}>
          <CartesianGrid stroke="var(--grid)" vertical={false} />
          <XAxis dataKey="label" tick={axisTick} tickLine={false} axisLine={{ stroke: "var(--line)" }} minTickGap={16} />
          <YAxis tick={axisTick} tickLine={false} axisLine={false} allowDecimals={false} width={44} />
          <Tooltip {...tooltipStyle} cursor={{ stroke: "var(--muted)", strokeDasharray: "3 3" }} formatter={(v) => [fmt.integer(Number(v)), dict.overview.sessions]} />
          <Line type="monotone" dataKey="value" name={dict.overview.sessions} stroke="var(--series-1)" strokeWidth={2} dot={false} activeDot={{ r: 5, strokeWidth: 2, stroke: "var(--surface)" }} isAnimationActive={false} />
        </LineChart>
      }
      table={
        <table className="w-full text-sm">
          <thead>
            <tr>
              <th scope="col" className={th}>{dict.overview.date}</th>
              <th scope="col" className={th}>{dict.overview.sessions}</th>
            </tr>
          </thead>
          <tbody>
            {data.map((d) => (
              <tr key={d.date}>
                <td className={td}>{d.label}</td>
                <td className={`${td} tabular`}>{fmt.integer(d.value)}</td>
              </tr>
            ))}
          </tbody>
        </table>
      }
    />
  );
}

export function ConnectionsPerDayChart({ points }: { points: TimeseriesPoint[] }) {
  const { dict, fmt } = useI18n();
  // success/failure are optional in the contract; missing values stay missing (no zero-filling).
  const data = points.map((p) => ({
    date: p.date,
    label: fmt.day(p.date),
    success: p.success ?? null,
    failure: p.failure ?? null,
  }));
  return (
    <ChartFrame
      label={dict.overview.connectionsPerDay}
      chart={
        <BarChart responsive data={data} style={{ width: "100%", height: 260 }} margin={{ top: 8, right: 12, bottom: 0, left: 0 }}>
          <CartesianGrid stroke="var(--grid)" vertical={false} />
          <XAxis dataKey="label" tick={axisTick} tickLine={false} axisLine={{ stroke: "var(--line)" }} minTickGap={16} />
          <YAxis tick={axisTick} tickLine={false} axisLine={false} allowDecimals={false} width={44} />
          <Tooltip {...tooltipStyle} formatter={(v, name) => [fmt.integer(Number(v)), String(name)]} />
          <Legend wrapperStyle={{ fontSize: 13, color: "var(--fg)" }} />
          <Bar dataKey="success" name={dict.overview.success} stackId="c" fill="var(--series-1)" stroke="var(--surface)" strokeWidth={1} isAnimationActive={false} />
          <Bar dataKey="failure" name={dict.overview.failure} stackId="c" fill="var(--series-2)" stroke="var(--surface)" strokeWidth={1} radius={[4, 4, 0, 0]} isAnimationActive={false} />
        </BarChart>
      }
      table={
        <table className="w-full text-sm">
          <thead>
            <tr>
              <th scope="col" className={th}>{dict.overview.date}</th>
              <th scope="col" className={th}>{dict.overview.success}</th>
              <th scope="col" className={th}>{dict.overview.failure}</th>
            </tr>
          </thead>
          <tbody>
            {data.map((d) => (
              <tr key={d.date}>
                <td className={td}>{d.label}</td>
                <td className={`${td} tabular`}>{fmt.integer(d.success)}</td>
                <td className={`${td} tabular`}>{fmt.integer(d.failure)}</td>
              </tr>
            ))}
          </tbody>
        </table>
      }
    />
  );
}

const MODES: DataMode[] = ["live", "demo", "replay"];

export function DataModeChart({ byMode }: { byMode: Partial<Record<DataMode, number>> }) {
  const { dict, fmt } = useI18n();
  const data = MODES.map((m) => ({ mode: m, label: dict.dataMode[m], value: byMode[m] ?? null }));
  return (
    <ChartFrame
      label={dict.overview.dataModeTitle}
      chart={
        <BarChart responsive layout="vertical" data={data} style={{ width: "100%", height: 150 }} margin={{ top: 4, right: 24, bottom: 4, left: 4 }}>
          <CartesianGrid stroke="var(--grid)" horizontal={false} />
          <XAxis type="number" tick={axisTick} tickLine={false} axisLine={false} allowDecimals={false} />
          <YAxis type="category" dataKey="label" tick={axisTick} tickLine={false} axisLine={false} width={84} />
          <Tooltip {...tooltipStyle} formatter={(v) => [fmt.integer(Number(v)), dict.overview.sessions]} />
          <Bar dataKey="value" name={dict.overview.sessions} fill="var(--series-1)" radius={[0, 4, 4, 0]} barSize={18} isAnimationActive={false} />
        </BarChart>
      }
      table={
        <table className="w-full text-sm">
          <tbody>
            {data.map((d) => (
              <tr key={d.mode}>
                <th scope="row" className={`${td} text-start font-medium`}>{d.label}</th>
                <td className={`${td} tabular`}>{fmt.integer(d.value)}</td>
              </tr>
            ))}
          </tbody>
        </table>
      }
    />
  );
}

export function dtcDescription(dtc: TopDtc, locale: "ar" | "en"): string | null {
  return (locale === "ar" ? dtc.description_ar : dtc.description_en) ?? null;
}

export function TopDtcsChart({ items }: { items: TopDtc[] }) {
  const { dict, fmt, locale } = useI18n();
  const data = items.map((d) => ({ ...d, description: dtcDescription(d, locale) ?? dict.dtc.noDescription }));
  return (
    <ChartFrame
      label={dict.overview.topDtcs}
      chart={
        <BarChart responsive layout="vertical" data={data} style={{ width: "100%", height: Math.max(160, data.length * 30 + 30) }} margin={{ top: 4, right: 24, bottom: 4, left: 4 }}>
          <CartesianGrid stroke="var(--grid)" horizontal={false} />
          <XAxis type="number" tick={axisTick} tickLine={false} axisLine={false} allowDecimals={false} />
          <YAxis type="category" dataKey="code" tick={{ ...axisTick, fontFamily: "ui-monospace, monospace" }} tickLine={false} axisLine={false} width={64} />
          <Tooltip
            {...tooltipStyle}
            labelFormatter={(code, payload) => {
              const row = payload?.[0]?.payload as { description?: string } | undefined;
              return row?.description ? `${String(code)} — ${row.description}` : String(code);
            }}
            formatter={(v) => [fmt.integer(Number(v)), dict.dtc.count]}
          />
          <Bar dataKey="count" name={dict.dtc.count} fill="var(--series-1)" radius={[0, 4, 4, 0]} barSize={16} isAnimationActive={false} />
        </BarChart>
      }
      table={<TopDtcsTable items={items} />}
    />
  );
}

export function TopDtcsTable({ items }: { items: TopDtc[] }) {
  const { dict, fmt, locale } = useI18n();
  return (
    <table className="w-full text-sm">
      <thead>
        <tr>
          <th scope="col" className={`${th} w-10`}>{dict.dtc.rank}</th>
          <th scope="col" className={th}>{dict.dtc.code}</th>
          <th scope="col" className={th}>{dict.dtc.description}</th>
          <th scope="col" className={th}>{dict.dtc.count}</th>
        </tr>
      </thead>
      <tbody>
        {items.map((d, i) => {
          const desc = dtcDescription(d, locale);
          return (
            <tr key={d.code}>
              <td className={`${td} tabular text-muted`}>{i + 1}</td>
              <td className={`${td} font-mono`} dir="ltr">{d.code}</td>
              <td className={td}>{desc ?? <span className="text-muted">{dict.dtc.noDescription}</span>}</td>
              <td className={`${td} tabular`}>{fmt.integer(d.count)}</td>
            </tr>
          );
        })}
      </tbody>
    </table>
  );
}
