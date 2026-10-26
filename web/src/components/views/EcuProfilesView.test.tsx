import { render, screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { afterEach, describe, expect, it, vi } from "vitest";
import { AuthProvider } from "@/components/auth/AuthProvider";
import { I18nProvider } from "@/i18n/I18nProvider";
import type { Locale } from "@/i18n/config";
import type { DiagEcuProfile, PlatformRole } from "@/lib/types";
import { EcuProfilesView } from "./EcuProfilesView";

const profile: DiagEcuProfile = {
  id: "11111111-1111-1111-1111-111111111111",
  make: "hyundai",
  model: "sonata",
  market: "SA",
  variant: null,
  year_from: 2011,
  year_to: 2014,
  controller_id: "hyundai_restraints_controller",
  protocol: "ISO 15765-4 (CAN 11/500)",
  tx_header: "7D0",
  rx_header: "7D8",
  read_request: "1902FF",
  id_bits: 11,
  category: "airbag",
  verification_status: "unverified",
  source_type: null,
  source_reference: null,
  model_year_range: null,
  notes: "candidate from deep discovery",
  submitted_by: "other-admin",
  reviewed_by: null,
  reviewed_at: null,
  version: 1,
  created_at: "2026-10-24T10:00:00Z",
  updated_at: "2026-10-24T10:00:00Z",
};

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });
}

function mockApi(role: PlatformRole = "admin", pending: DiagEcuProfile[] = [profile]) {
  return vi.spyOn(globalThis, "fetch").mockImplementation(async (input, init) => {
    const url = new URL(
      typeof input === "string" ? input : input instanceof URL ? input.href : input.url,
      "http://localhost",
    );
    if (url.pathname === "/api/session") return json({ access_token: "tok", token_type: "bearer", expires_in: 900 });
    if ((init?.headers as Record<string, string> | undefined)?.Authorization !== "Bearer tok")
      return json({ error: { code: "unauthorized", message: "missing token" } }, 401);
    if (url.pathname.endsWith("/me"))
      return json({ id: "admin-1", email: "ops@automind.test", full_name: "Ops", phone: null, locale: "en", platform_role: role, mfa_enabled: true, created_at: "2026-01-01T00:00:00Z" });
    if (url.pathname.endsWith("/diag/admin/profiles/pending-review")) return json(pending);
    if (url.pathname.endsWith("/approve"))
      return json({ ...profile, verification_status: "verified_vehicle_trace", source_type: "field", source_reference: "trace-99", reviewed_by: "admin-1", version: 2 });
    return json({ error: { code: "not_found", message: url.pathname } }, 404);
  });
}

function renderView(locale: Locale = "en") {
  return render(
    <I18nProvider locale={locale}>
      <AuthProvider>
        <EcuProfilesView />
      </AuthProvider>
    </I18nProvider>,
  );
}

afterEach(() => vi.restoreAllMocks());

describe("EcuProfilesView", () => {
  it("lists pending profiles for an admin", async () => {
    mockApi("admin");
    renderView("en");
    expect(await screen.findByText("hyundai sonata")).toBeInTheDocument();
    expect(screen.getByText("hyundai_restraints_controller")).toBeInTheDocument();
    expect(screen.getByText("1902FF")).toBeInTheDocument();
  });

  it("requires evidence before recording a decision", async () => {
    const fetchSpy = mockApi("admin");
    const user = userEvent.setup();
    renderView("en");

    await user.click(await screen.findByRole("button", { name: "Review" }));
    await user.click(screen.getByRole("button", { name: "Record decision" }));

    expect(await screen.findByText(/Enter the evidence type and reference/)).toBeInTheDocument();
    // No approval call was made without evidence.
    expect(fetchSpy.mock.calls.some(([u]) => String(u).endsWith("/approve"))).toBe(false);
  });

  it("records a decision with evidence, then drops the row", async () => {
    const fetchSpy = mockApi("admin");
    const user = userEvent.setup();
    renderView("en");

    await user.click(await screen.findByRole("button", { name: "Review" }));
    await user.type(screen.getByLabelText("Evidence type"), "verified_vehicle_trace");
    await user.type(screen.getByLabelText("Evidence reference"), "trace-99");
    await user.click(screen.getByRole("button", { name: "Record decision" }));

    expect(await screen.findByText(/Recorded decision for hyundai sonata/)).toBeInTheDocument();
    expect(screen.queryByText("hyundai sonata")).not.toBeInTheDocument();

    const call = fetchSpy.mock.calls.find(([u]) => String(u).endsWith("/approve"));
    expect(call).toBeTruthy();
    expect(call?.[1]?.method).toBe("POST");
    const body = JSON.parse((call?.[1]?.body as string) ?? "{}");
    expect(body).toMatchObject({
      verification_status: "verified_vehicle_trace",
      source_type: "verified_vehicle_trace",
      source_reference: "trace-99",
    });
  });

  it("does not expose approval to non-admin staff", async () => {
    const fetchSpy = mockApi("support");
    renderView("en");
    expect(await screen.findByText(/available to platform admins only/)).toBeInTheDocument();
    // The pending-review endpoint is never called for support.
    await waitFor(() =>
      expect(fetchSpy.mock.calls.some(([u]) => String(u).endsWith("/pending-review"))).toBe(false),
    );
  });
});
