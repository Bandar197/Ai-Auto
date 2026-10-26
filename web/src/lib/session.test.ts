import { describe, expect, it, vi } from "vitest";
import { createSessionManager } from "./session";

const ok = (body: unknown) =>
  new Response(JSON.stringify(body), { status: 200, headers: { "Content-Type": "application/json" } });

describe("session manager", () => {
  it("keeps the access token in memory and never sees a refresh token", async () => {
    const fetchImpl = vi.fn<typeof fetch>(async () =>
      ok({ access_token: "a1", token_type: "bearer", expires_in: 900, user: { id: "u1" } }),
    );
    const s = createSessionManager(fetchImpl);
    const user = await s.login({ email: "a@b.co", password: "pw" });
    expect(user).toEqual({ id: "u1" });
    expect(s.getAccessToken()).toBe("a1");
    const [url, init] = fetchImpl.mock.calls[0];
    expect(url).toBe("/api/session");
    expect(JSON.parse(String(init?.body))).toEqual({ action: "login", email: "a@b.co", password: "pw" });
    expect(init?.credentials).toBe("same-origin");
  });

  it("shares one in-flight refresh between concurrent callers (rotating tokens)", async () => {
    let resolve!: (r: Response) => void;
    const fetchImpl = vi.fn<typeof fetch>(() => new Promise<Response>((r) => (resolve = r)));
    const s = createSessionManager(fetchImpl);
    const a = s.refresh();
    const b = s.refresh();
    resolve(ok({ access_token: "a2", token_type: "bearer", expires_in: 900 }));
    await expect(Promise.all([a, b])).resolves.toEqual(["a2", "a2"]);
    expect(fetchImpl).toHaveBeenCalledTimes(1);
  });

  it("returns null and clears the token when refresh is rejected", async () => {
    const fetchImpl = vi.fn<typeof fetch>(async () =>
      new Response(JSON.stringify({ error: { code: "unauthorized", message: "x" } }), { status: 401 }),
    );
    const s = createSessionManager(fetchImpl);
    await expect(s.refresh()).resolves.toBeNull();
    expect(s.getAccessToken()).toBeNull();
  });

  it("surfaces mfa_required from login as a typed error", async () => {
    const fetchImpl = vi.fn<typeof fetch>(async () =>
      new Response(JSON.stringify({ error: { code: "mfa_required", message: "code needed" } }), { status: 403 }),
    );
    const s = createSessionManager(fetchImpl);
    await expect(s.login({ email: "a@b.co", password: "pw" })).rejects.toMatchObject({
      code: "mfa_required",
      status: 403,
    });
  });
});
