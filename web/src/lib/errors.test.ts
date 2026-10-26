import { describe, expect, it } from "vitest";
import { ApiError, codeForStatus, errorFromBody, errorFromResponse, isKnownErrorCode, networkError } from "./errors";

describe("error envelope mapping", () => {
  it("maps the {error:{code,message,details}} envelope", async () => {
    const res = new Response(
      JSON.stringify({ error: { code: "mfa_required", message: "TOTP code required", details: { field: "totp_code" } } }),
      { status: 403, headers: { "X-Request-ID": "req-123" } },
    );
    const err = await errorFromResponse(res);
    expect(err).toBeInstanceOf(ApiError);
    expect(err.status).toBe(403);
    expect(err.code).toBe("mfa_required");
    expect(err.isMfaRequired).toBe(true);
    expect(err.message).toBe("TOTP code required");
    expect(err.details).toEqual({ field: "totp_code" });
    expect(err.requestId).toBe("req-123");
  });

  it("keeps unknown codes from the server", () => {
    const err = errorFromBody(400, { error: { code: "vin_invalid", message: "bad VIN" } });
    expect(err.code).toBe("vin_invalid");
    expect(isKnownErrorCode(err.code)).toBe(false);
  });

  it("falls back to the HTTP status when the body is not an envelope", async () => {
    const err = await errorFromResponse(new Response("<html>Bad gateway</html>", { status: 502 }));
    expect(err.code).toBe("upstream_unavailable");
    expect(err.status).toBe(502);
  });

  it("handles empty bodies and malformed envelopes", async () => {
    expect((await errorFromResponse(new Response(null, { status: 404 }))).code).toBe("not_found");
    expect(errorFromBody(429, { error: "slow down" }).code).toBe("rate_limited");
    expect(errorFromBody(401, { error: { code: "unauthorized" } }).isUnauthorized).toBe(true);
  });

  it.each([
    [400, "validation_error"],
    [422, "validation_error"],
    [401, "unauthorized"],
    [403, "forbidden"],
    [404, "not_found"],
    [409, "conflict"],
    [429, "rate_limited"],
    [500, "server_error"],
    [503, "upstream_unavailable"],
    [418, "unknown_error"],
  ])("status %i -> %s", (status, code) => {
    expect(codeForStatus(status)).toBe(code);
  });

  it("wraps network failures", () => {
    const err = networkError(new TypeError("Failed to fetch"));
    expect(err.code).toBe("network_error");
    expect(err.status).toBe(0);
    expect(err.message).toBe("Failed to fetch");
  });
});
