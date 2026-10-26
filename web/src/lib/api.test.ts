import { describe, expect, it, vi } from "vitest";
import { ApiClient, adminApi, buildUrl, filenameFromDisposition, type TokenProvider } from "./api";
import { ApiError } from "./errors";

const BASE = "https://api.example.test/api/v1";

function json(status: number, body: unknown, headers: Record<string, string> = {}) {
  return new Response(body === undefined ? null : JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json", ...headers },
  });
}

function setup(responses: Response[], refreshResult: string | null = "fresh-token") {
  let token: string | null = "stale-token";
  const fetchImpl = vi.fn<typeof fetch>(async () => {
    const next = responses.shift();
    if (!next) throw new Error("unexpected fetch");
    return next;
  });
  const auth = {
    getAccessToken: () => token,
    refresh: vi.fn(async (): Promise<string | null> => {
      token = refreshResult;
      return refreshResult;
    }),
    onAuthFailure: vi.fn((): void => undefined),
  } satisfies TokenProvider;
  const client = new ApiClient({ baseUrl: BASE, auth, fetchImpl });
  const authHeader = (call: number) =>
    (fetchImpl.mock.calls[call][1]?.headers as Record<string, string>).Authorization;
  return { client, fetchImpl, auth, authHeader };
}

describe("ApiClient auth + refresh", () => {
  it("attaches the bearer token", async () => {
    const { client, authHeader, auth } = setup([json(200, { ok: true })]);
    await expect(client.request("/me")).resolves.toEqual({ ok: true });
    expect(authHeader(0)).toBe("Bearer stale-token");
    expect(auth.refresh).not.toHaveBeenCalled();
  });

  it("refreshes once on 401 and retries with the new token", async () => {
    const { client, fetchImpl, auth, authHeader } = setup([
      json(401, { error: { code: "unauthorized", message: "expired" } }),
      json(200, { users_total: 3 }),
    ]);
    await expect(client.request("/admin/stats/overview")).resolves.toEqual({ users_total: 3 });
    expect(auth.refresh).toHaveBeenCalledTimes(1);
    expect(fetchImpl).toHaveBeenCalledTimes(2);
    expect(authHeader(0)).toBe("Bearer stale-token");
    expect(authHeader(1)).toBe("Bearer fresh-token");
    expect(auth.onAuthFailure).not.toHaveBeenCalled();
  });

  it("gives up without retrying when the refresh fails", async () => {
    const { client, fetchImpl, auth } = setup(
      [json(401, { error: { code: "unauthorized", message: "expired" } })],
      null,
    );
    const err = await client.request("/admin/users").catch((e: unknown) => e);
    expect(err).toBeInstanceOf(ApiError);
    expect((err as ApiError).code).toBe("unauthorized");
    expect((err as ApiError).status).toBe(401);
    expect(fetchImpl).toHaveBeenCalledTimes(1);
    expect(auth.onAuthFailure).toHaveBeenCalledTimes(1);
  });

  it("does not loop when the retried request is still 401", async () => {
    const { client, fetchImpl, auth } = setup([
      json(401, { error: { code: "unauthorized", message: "expired" } }),
      json(401, { error: { code: "unauthorized", message: "still expired" } }),
    ]);
    const err = (await client.request("/me").catch((e: unknown) => e)) as ApiError;
    expect(err.message).toBe("still expired");
    expect(auth.refresh).toHaveBeenCalledTimes(1);
    expect(fetchImpl).toHaveBeenCalledTimes(2);
    expect(auth.onAuthFailure).toHaveBeenCalledTimes(1);
  });

  it("does not refresh on other errors (e.g. 403 forbidden)", async () => {
    const { client, auth } = setup([json(403, { error: { code: "forbidden", message: "nope" } })]);
    const err = (await client.request("/admin/plans").catch((e: unknown) => e)) as ApiError;
    expect(err.code).toBe("forbidden");
    expect(auth.refresh).not.toHaveBeenCalled();
  });

  it("maps fetch failures to network_error", async () => {
    const auth: TokenProvider = { getAccessToken: () => null, refresh: async () => null };
    const client = new ApiClient({
      baseUrl: BASE,
      auth,
      fetchImpl: async () => {
        throw new TypeError("Failed to fetch");
      },
    });
    const err = (await client.request("/me").catch((e: unknown) => e)) as ApiError;
    expect(err).toBeInstanceOf(ApiError);
    expect(err.code).toBe("network_error");
    expect(err.status).toBe(0);
  });

  it("sends JSON bodies for PATCH and resolves 204 to undefined", async () => {
    const { client, fetchImpl } = setup([new Response(null, { status: 204 })]);
    await expect(adminApi(client).updateUser("u 1", { status: "suspended" })).resolves.toBeUndefined();
    const [url, init] = fetchImpl.mock.calls[0];
    expect(url).toBe(`${BASE}/admin/users/u%201`);
    expect(init?.method).toBe("PATCH");
    expect(init?.body).toBe(JSON.stringify({ status: "suspended" }));
    expect((init?.headers as Record<string, string>)["Content-Type"]).toBe("application/json");
  });

  it("downloads CSV exports with auth and the server filename (refreshing on 401)", async () => {
    const { client, authHeader } = setup([
      json(401, { error: { code: "unauthorized", message: "expired" } }),
      new Response("code,count\nP0300,4\n", {
        status: 200,
        headers: { "Content-Type": "text/csv", "Content-Disposition": 'attachment; filename="top-dtcs.csv"' },
      }),
    ]);
    const { blob, filename } = await adminApi(client).exportCsv("top-dtcs");
    expect(filename).toBe("top-dtcs.csv");
    expect(await blob.text()).toContain("P0300");
    expect(authHeader(1)).toBe("Bearer fresh-token");
  });

  it("throws invalid_response for non-JSON success bodies", async () => {
    const { client } = setup([new Response("<html>", { status: 200 })]);
    const err = (await client.request("/me").catch((e: unknown) => e)) as ApiError;
    expect(err.code).toBe("invalid_response");
  });
});

describe("helpers", () => {
  it("buildUrl skips empty query values", () => {
    expect(buildUrl(`${BASE}/`, "/admin/users", { q: "", limit: 20, offset: 0, x: undefined })).toBe(
      `${BASE}/admin/users?limit=20&offset=0`,
    );
  });

  it("parses Content-Disposition filenames", () => {
    expect(filenameFromDisposition('attachment; filename="users.csv"')).toBe("users.csv");
    expect(filenameFromDisposition("attachment; filename*=UTF-8''%D9%85.csv")).toBe("م.csv");
    expect(filenameFromDisposition(null)).toBeNull();
  });
});
