import { render, screen, within } from "@testing-library/react";
import { afterEach, describe, expect, it, vi } from "vitest";
import { AuthProvider } from "@/components/auth/AuthProvider";
import { I18nProvider } from "@/i18n/I18nProvider";
import type { Locale } from "@/i18n/config";
import type { OverviewStats, Timeseries, TopDtc } from "@/lib/types";
import { OverviewView } from "./OverviewView";

// Mocked API responses — used only in this test.
const overview: OverviewStats = {
  users_total: 1234,
  users_active_30d: 456,
  vehicles_total: 789,
  devices_total: 321,
  sessions_today: 42,
  sessions_month: 987,
  sessions_by_mode: { live: 600, demo: 300, replay: 100 },
  connection_success_rate_30d: 0.875,
  diagnosis_confirmed_rate: 0.62,
  active_subscriptions_by_plan: { basic: 900, pro: 120, garage_business: 15 },
  revenue_month_sar: 12345.5,
  cancelled_subscriptions_month: 7,
  workshops_total: 11,
  suppliers_total: 5,
  orders_month: 64,
  errors_24h: 3,
  ai_usage_month: { requests: 2500, input_tokens: 1_200_000, output_tokens: 300_000, cost_usd: 18.4 },
};
const sessions: Timeseries = {
  metric: "sessions",
  points: [
    { date: "2026-10-20", value: 30 },
    { date: "2026-10-21", value: 42 },
  ],
};
const connections: Timeseries = {
  metric: "connections",
  points: [{ date: "2026-10-21", value: 50, success: 44, failure: 6 }],
};
const topDtcs: TopDtc[] = [
  { code: "P0300", count: 77, description_en: "Random/multiple cylinder misfire", description_ar: "احتراق غير منتظم في عدة أسطوانات" },
  { code: "P0171", count: 41, description_en: "System too lean (bank 1)", description_ar: null },
];

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });
}

function mockApi(overrides: { overview?: () => Response | Promise<Response> } = {}) {
  return vi.spyOn(globalThis, "fetch").mockImplementation(async (input, init) => {
    const url = new URL(typeof input === "string" ? input : input instanceof URL ? input.href : input.url, "http://localhost");
    if (url.pathname === "/api/session") return json({ access_token: "tok", token_type: "bearer", expires_in: 900 });
    // Like the real backend: everything else needs the bearer token.
    if ((init?.headers as Record<string, string> | undefined)?.Authorization !== "Bearer tok")
      return json({ error: { code: "unauthorized", message: "missing token" } }, 401);
    if (url.pathname.endsWith("/me"))
      return json({ id: "admin-1", email: "ops@automind.test", full_name: "Ops", phone: null, locale: "en", platform_role: "admin", mfa_enabled: true, created_at: "2026-01-01T00:00:00Z" });
    if (url.pathname.endsWith("/admin/stats/overview")) return overrides.overview ? overrides.overview() : json(overview);
    if (url.pathname.endsWith("/admin/stats/timeseries"))
      return json(url.searchParams.get("metric") === "connections" ? connections : sessions);
    if (url.pathname.endsWith("/admin/stats/top-dtcs")) return json(topDtcs);
    return json({ error: { code: "not_found", message: url.pathname } }, 404);
  });
}

function renderOverview(locale: Locale = "en") {
  return render(
    <I18nProvider locale={locale}>
      <AuthProvider>
        <OverviewView />
      </AuthProvider>
    </I18nProvider>,
  );
}

afterEach(() => vi.restoreAllMocks());

describe("OverviewView", () => {
  it("renders KPI tiles from the overview API response", async () => {
    const fetchSpy = mockApi();
    renderOverview("en");

    expect(await screen.findByText("1,234")).toBeInTheDocument();
    const tile = (label: string) => screen.getByText(label).closest("div") as HTMLElement;
    expect(within(tile("Total users")).getByText("1,234")).toBeInTheDocument();
    expect(within(tile("Active users (30 days)")).getByText("456")).toBeInTheDocument();
    expect(within(tile("Connection success rate (30 days)")).getByText("87.5%")).toBeInTheDocument();
    expect(within(tile("Revenue this month")).getByText(/12,345\.5/)).toBeInTheDocument();
    expect(within(tile("Revenue this month")).getByText(/SAR/)).toBeInTheDocument();
    expect(within(tile("AI cost (this month)")).getByText("US$18.40")).toBeInTheDocument();
    expect(screen.getByText("Garage Business")).toBeInTheDocument();

    // data_mode breakdown is shown separately, never merged silently.
    expect(within(screen.getByTestId("mode-live")).getByText("600")).toBeInTheDocument();
    expect(within(screen.getByTestId("mode-demo")).getByText("300")).toBeInTheDocument();
    expect(within(screen.getByTestId("mode-replay")).getByText("100")).toBeInTheDocument();
    expect(within(screen.getByTestId("mode-demo")).getByText(/30% of total/)).toBeInTheDocument();

    // Live-API labelling is visible.
    expect(screen.getAllByText("Live API data").length).toBeGreaterThan(0);

    // Requests carried the bearer token from /api/session.
    const overviewCall = fetchSpy.mock.calls.findLast(([u]) => String(u).endsWith("/admin/stats/overview"));
    expect((overviewCall?.[1]?.headers as Record<string, string>).Authorization).toBe("Bearer tok");

    // Top DTCs table view uses the English description.
    expect(await screen.findByText("Random/multiple cylinder misfire")).toBeInTheDocument();
  });

  it("uses Arabic DTC descriptions and labels in the Arabic locale", async () => {
    mockApi();
    renderOverview("ar");
    expect(await screen.findByText("إجمالي المستخدمين")).toBeInTheDocument();
    expect(await screen.findByText("احتراق غير منتظم في عدة أسطوانات")).toBeInTheDocument();
    // Missing Arabic description is reported, not invented.
    expect(screen.getAllByText("لا يوجد وصف في قاعدة المعرفة").length).toBeGreaterThan(0);
  });

  it("shows an error state (no fabricated numbers) when the API is unreachable", async () => {
    mockApi({
      overview: () => {
        throw new TypeError("Failed to fetch");
      },
    });
    renderOverview("en");
    expect(await screen.findByText(/Can't reach the API server/)).toBeInTheDocument();
    expect(screen.queryByText("Total users")).not.toBeInTheDocument();
  });
});
