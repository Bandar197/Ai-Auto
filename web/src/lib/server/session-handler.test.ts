// @vitest-environment node
import { NextRequest } from "next/server";
import { describe, expect, it, vi } from "vitest";
import { REFRESH_COOKIE, handleSessionRequest } from "./session-handler";

const BACKEND = "http://backend.test/api/v1";

function request(body: unknown, init: { cookie?: string; origin?: string; contentType?: string } = {}) {
  const headers: Record<string, string> = {
    host: "admin.test",
    "content-type": init.contentType ?? "application/json",
  };
  if (init.origin) headers.origin = init.origin;
  if (init.cookie) headers.cookie = init.cookie;
  return new NextRequest("http://admin.test/api/session", {
    method: "POST",
    headers,
    body: JSON.stringify(body),
  });
}

const upstream = (status: number, body: unknown) =>
  new Response(body === null ? null : JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });

const tokens = { access_token: "acc", refresh_token: "ref-1", token_type: "bearer", expires_in: 900 };

describe("/api/session handler", () => {
  it("login: proxies to /auth/login, sets an httpOnly cookie and strips the refresh token", async () => {
    const fetchImpl = vi.fn<typeof fetch>(async () => upstream(200, { user: { id: "u1" }, tokens }));
    const res = await handleSessionRequest(
      request({ action: "login", email: "a@b.co", password: "pw", totp_code: " 123456 " }, { origin: "http://admin.test" }),
      { fetchImpl, backendBaseUrl: BACKEND, secureCookies: true },
    );
    expect(res.status).toBe(200);
    const body = await res.json();
    expect(body).toEqual({ access_token: "acc", token_type: "bearer", expires_in: 900, user: { id: "u1" } });
    expect(JSON.stringify(body)).not.toContain("ref-1");

    const [url, init] = fetchImpl.mock.calls[0];
    expect(url).toBe(`${BACKEND}/auth/login`);
    expect(JSON.parse(String(init?.body))).toEqual({ email: "a@b.co", password: "pw", totp_code: "123456" });

    const cookie = res.headers.get("set-cookie") ?? "";
    expect(cookie).toContain(`${REFRESH_COOKIE}=ref-1`);
    expect(cookie).toMatch(/HttpOnly/i);
    expect(cookie).toMatch(/Secure/i);
    expect(cookie).toMatch(/SameSite=strict/i);
    expect(cookie).toMatch(/Path=\/api\/session/i);
    expect(res.headers.get("cache-control")).toBe("no-store");
  });

  it("login: relays 403 mfa_required envelopes unchanged", async () => {
    const envelope = { error: { code: "mfa_required", message: "TOTP required", details: {} } };
    const fetchImpl = vi.fn<typeof fetch>(async () => upstream(403, envelope));
    const res = await handleSessionRequest(request({ action: "login", email: "a@b.co", password: "pw" }), {
      fetchImpl,
      backendBaseUrl: BACKEND,
    });
    expect(res.status).toBe(403);
    expect(await res.json()).toEqual(envelope);
    expect(res.headers.get("set-cookie")).toBeNull();
  });

  it("refresh: uses the cookie, rotates it, and returns only the access token", async () => {
    const fetchImpl = vi.fn<typeof fetch>(async () =>
      upstream(200, { tokens: { ...tokens, access_token: "acc-2", refresh_token: "ref-2" } }),
    );
    const res = await handleSessionRequest(request({ action: "refresh" }, { cookie: `${REFRESH_COOKIE}=ref-1` }), {
      fetchImpl,
      backendBaseUrl: BACKEND,
      secureCookies: false,
    });
    expect(res.status).toBe(200);
    expect(await res.json()).toEqual({ access_token: "acc-2", token_type: "bearer", expires_in: 900 });
    expect(JSON.parse(String(fetchImpl.mock.calls[0][1]?.body))).toEqual({ refresh_token: "ref-1" });
    expect(res.headers.get("set-cookie")).toContain(`${REFRESH_COOKIE}=ref-2`);
  });

  it("refresh: 401 without a cookie, and clears the cookie when the backend rejects it", async () => {
    const fetchImpl = vi.fn<typeof fetch>(async () =>
      upstream(401, { error: { code: "unauthorized", message: "reused token" } }),
    );
    const noCookie = await handleSessionRequest(request({ action: "refresh" }), { fetchImpl, backendBaseUrl: BACKEND });
    expect(noCookie.status).toBe(401);
    expect(fetchImpl).not.toHaveBeenCalled();

    const rejected = await handleSessionRequest(
      request({ action: "refresh" }, { cookie: `${REFRESH_COOKIE}=old` }),
      { fetchImpl, backendBaseUrl: BACKEND },
    );
    expect(rejected.status).toBe(401);
    expect(rejected.headers.get("set-cookie")).toMatch(new RegExp(`${REFRESH_COOKIE}=;`));
  });

  it("logout: revokes upstream and clears the cookie", async () => {
    const fetchImpl = vi.fn<typeof fetch>(async () => upstream(204, null));
    const res = await handleSessionRequest(request({ action: "logout" }, { cookie: `${REFRESH_COOKIE}=ref-1` }), {
      fetchImpl,
      backendBaseUrl: BACKEND,
    });
    expect(res.status).toBe(204);
    expect(fetchImpl.mock.calls[0][0]).toBe(`${BACKEND}/auth/logout`);
    expect(res.headers.get("set-cookie")).toMatch(/Max-Age=0/i);
  });

  it("rejects cross-origin and non-JSON requests", async () => {
    const fetchImpl = vi.fn<typeof fetch>();
    const cross = await handleSessionRequest(request({ action: "refresh" }, { origin: "https://evil.test" }), {
      fetchImpl,
      backendBaseUrl: BACKEND,
    });
    expect(cross.status).toBe(403);
    const form = await handleSessionRequest(request({ action: "refresh" }, { contentType: "text/plain" }), {
      fetchImpl,
      backendBaseUrl: BACKEND,
    });
    expect(form.status).toBe(403);
    expect(fetchImpl).not.toHaveBeenCalled();
  });

  it("returns 502 upstream_unavailable when the backend is unreachable", async () => {
    const fetchImpl = vi.fn<typeof fetch>(async () => {
      throw new TypeError("fetch failed");
    });
    const res = await handleSessionRequest(request({ action: "login", email: "a@b.co", password: "pw" }), {
      fetchImpl,
      backendBaseUrl: BACKEND,
    });
    expect(res.status).toBe(502);
    expect((await res.json()).error.code).toBe("upstream_unavailable");
  });
});
