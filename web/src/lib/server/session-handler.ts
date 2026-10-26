/**
 * Server-only logic behind `POST /api/session`.
 *
 * Proxies `/auth/login`, `/auth/refresh` and `/auth/logout` to the backend and
 * keeps the (rotating) refresh token in an httpOnly, SameSite=Strict cookie
 * scoped to this endpoint. The browser only ever receives the access token.
 */
import { NextResponse, type NextRequest } from "next/server";
import { DEFAULT_API_BASE_URL } from "../config";
import { codeForStatus, isErrorEnvelope } from "../errors";
import type { Tokens, User } from "../types";

export const REFRESH_COOKIE = "am_admin_rt";
export const REFRESH_COOKIE_PATH = "/api/session";
const REFRESH_MAX_AGE_S = 30 * 24 * 60 * 60; // backend refresh tokens live 30 days
const UPSTREAM_TIMEOUT_MS = 10_000;

export interface SessionHandlerDeps {
  fetchImpl?: typeof fetch;
  backendBaseUrl?: string;
  secureCookies?: boolean;
}

/** Backend URL for server-to-server calls (may differ from the public one in Docker). */
export function backendBaseUrl(): string {
  return (
    process.env.API_INTERNAL_BASE_URL ||
    process.env.NEXT_PUBLIC_API_BASE_URL ||
    DEFAULT_API_BASE_URL
  ).replace(/\/+$/, "");
}

function secureCookiesDefault(): boolean {
  if (process.env.SESSION_COOKIE_SECURE === "false") return false;
  if (process.env.SESSION_COOKIE_SECURE === "true") return true;
  return process.env.NODE_ENV === "production";
}

function errorJson(status: number, code: string, message: string, requestId?: string | null) {
  const res = NextResponse.json({ error: { code, message, details: {} } }, { status });
  if (requestId) res.headers.set("X-Request-ID", requestId);
  return noStore(res);
}

function noStore(res: NextResponse): NextResponse {
  res.headers.set("Cache-Control", "no-store");
  return res;
}

/**
 * CSRF defence in depth (the cookie is already SameSite=Strict): require a JSON
 * body (forces a CORS preflight for cross-site callers) and, when the browser
 * sends an Origin header, require it to match this host.
 */
function isSameOriginJson(req: NextRequest): boolean {
  const contentType = req.headers.get("content-type") ?? "";
  if (!contentType.toLowerCase().startsWith("application/json")) return false;
  const origin = req.headers.get("origin");
  if (!origin) return true;
  const host = req.headers.get("x-forwarded-host") ?? req.headers.get("host");
  try {
    return new URL(origin).host === host;
  } catch {
    return false;
  }
}

interface Upstream {
  status: number;
  body: unknown;
  requestId: string | null;
}

async function callBackend(
  deps: Required<SessionHandlerDeps>,
  req: NextRequest,
  path: string,
  payload: Record<string, unknown>,
): Promise<Upstream> {
  const headers: Record<string, string> = {
    "Content-Type": "application/json",
    Accept: "application/json",
    "X-Request-ID": req.headers.get("x-request-id") ?? crypto.randomUUID(),
  };
  // Let the backend rate-limit / audit by the real client, not this proxy.
  const forwardedFor = req.headers.get("x-forwarded-for");
  if (forwardedFor) headers["X-Forwarded-For"] = forwardedFor;
  const ua = req.headers.get("user-agent");
  if (ua) headers["User-Agent"] = ua;
  const lang = req.headers.get("accept-language");
  if (lang) headers["Accept-Language"] = lang;

  const res = await deps.fetchImpl(`${deps.backendBaseUrl}${path}`, {
    method: "POST",
    headers,
    body: JSON.stringify(payload),
    cache: "no-store",
    signal: AbortSignal.timeout(UPSTREAM_TIMEOUT_MS),
  });
  const text = await res.text();
  let body: unknown = null;
  try {
    body = text ? JSON.parse(text) : null;
  } catch {
    body = null;
  }
  return { status: res.status, body, requestId: res.headers.get("x-request-id") };
}

/** Relay a backend failure using its envelope when present. */
function relayError(up: Upstream): NextResponse {
  if (isErrorEnvelope(up.body)) {
    const res = NextResponse.json(up.body, { status: up.status });
    if (up.requestId) res.headers.set("X-Request-ID", up.requestId);
    return noStore(res);
  }
  return errorJson(up.status, codeForStatus(up.status), `Upstream HTTP ${up.status}`, up.requestId);
}

function isTokens(value: unknown): value is Tokens {
  if (typeof value !== "object" || value === null) return false;
  const t = value as Record<string, unknown>;
  return typeof t.access_token === "string" && typeof t.refresh_token === "string";
}

function setRefreshCookie(res: NextResponse, token: string, secure: boolean) {
  res.cookies.set({
    name: REFRESH_COOKIE,
    value: token,
    httpOnly: true,
    secure,
    sameSite: "strict",
    path: REFRESH_COOKIE_PATH,
    maxAge: REFRESH_MAX_AGE_S,
  });
}

function clearRefreshCookie(res: NextResponse, secure: boolean) {
  res.cookies.set({
    name: REFRESH_COOKIE,
    value: "",
    httpOnly: true,
    secure,
    sameSite: "strict",
    path: REFRESH_COOKIE_PATH,
    maxAge: 0,
  });
}

function browserSession(tokens: Tokens, user?: User) {
  return {
    access_token: tokens.access_token,
    token_type: tokens.token_type ?? "bearer",
    expires_in: tokens.expires_in,
    ...(user ? { user } : {}),
  };
}

export async function handleSessionRequest(
  req: NextRequest,
  overrides: SessionHandlerDeps = {},
): Promise<NextResponse> {
  const deps: Required<SessionHandlerDeps> = {
    fetchImpl: overrides.fetchImpl ?? ((input, init) => globalThis.fetch(input, init)),
    backendBaseUrl: (overrides.backendBaseUrl ?? backendBaseUrl()).replace(/\/+$/, ""),
    secureCookies: overrides.secureCookies ?? secureCookiesDefault(),
  };

  if (!isSameOriginJson(req)) {
    return errorJson(403, "forbidden", "Cross-origin or non-JSON request rejected");
  }

  let input: Record<string, unknown>;
  try {
    const parsed: unknown = await req.json();
    if (typeof parsed !== "object" || parsed === null || Array.isArray(parsed)) throw new Error();
    input = parsed as Record<string, unknown>;
  } catch {
    return errorJson(400, "validation_error", "Body must be a JSON object");
  }

  try {
    switch (input.action) {
      case "login":
        return await login(deps, req, input);
      case "refresh":
        return await refresh(deps, req);
      case "logout":
        return await logout(deps, req);
      default:
        return errorJson(400, "validation_error", "Unknown action");
    }
  } catch {
    // Network failure or timeout talking to the backend.
    return errorJson(502, "upstream_unavailable", "The API server could not be reached");
  }
}

async function login(
  deps: Required<SessionHandlerDeps>,
  req: NextRequest,
  input: Record<string, unknown>,
): Promise<NextResponse> {
  const { email, password, totp_code } = input;
  if (typeof email !== "string" || !email || typeof password !== "string" || !password) {
    return errorJson(400, "validation_error", "email and password are required");
  }
  const payload: Record<string, unknown> = { email, password };
  if (typeof totp_code === "string" && totp_code.trim()) payload.totp_code = totp_code.trim();

  const up = await callBackend(deps, req, "/auth/login", payload);
  if (up.status < 200 || up.status >= 300) return relayError(up);

  const body = up.body as { user?: User; tokens?: unknown } | null;
  if (!body || !isTokens(body.tokens)) {
    return errorJson(502, "invalid_response", "Login response has no tokens");
  }
  const res = noStore(NextResponse.json(browserSession(body.tokens, body.user)));
  setRefreshCookie(res, body.tokens.refresh_token, deps.secureCookies);
  return res;
}

async function refresh(deps: Required<SessionHandlerDeps>, req: NextRequest): Promise<NextResponse> {
  const token = req.cookies.get(REFRESH_COOKIE)?.value;
  if (!token) return errorJson(401, "unauthorized", "No session");

  const up = await callBackend(deps, req, "/auth/refresh", { refresh_token: token });
  if (up.status < 200 || up.status >= 300) {
    const res = relayError(up);
    // A rejected refresh token is dead (rotation/re-use detection) — drop it.
    if (up.status === 401 || up.status === 403) clearRefreshCookie(res, deps.secureCookies);
    return res;
  }
  const body = up.body as { tokens?: unknown; user?: User } | null;
  if (!body || !isTokens(body.tokens)) {
    return errorJson(502, "invalid_response", "Refresh response has no tokens");
  }
  const res = noStore(NextResponse.json(browserSession(body.tokens, body.user)));
  setRefreshCookie(res, body.tokens.refresh_token, deps.secureCookies);
  return res;
}

async function logout(deps: Required<SessionHandlerDeps>, req: NextRequest): Promise<NextResponse> {
  const token = req.cookies.get(REFRESH_COOKIE)?.value;
  if (token) {
    try {
      await callBackend(deps, req, "/auth/logout", { refresh_token: token });
    } catch {
      /* still clear the local cookie */
    }
  }
  const res = noStore(new NextResponse(null, { status: 204 }));
  clearRefreshCookie(res, deps.secureCookies);
  return res;
}
