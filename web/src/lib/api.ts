/**
 * Small typed client for the AutoMind REST API.
 *
 * - attaches `Authorization: Bearer <access token>` (token lives in memory only)
 * - on a 401 it asks the token provider to refresh **once** and retries
 * - maps the `{error: {code, message}}` envelope to `ApiError`
 */
import { ApiError, errorFromResponse, networkError } from "./errors";
import type {
  AdminUser,
  AdminUserPatch,
  AuditLog,
  DiagEcuProfile,
  DiagProfileReview,
  ExportDataset,
  OverviewStats,
  Page,
  Plan,
  PlanPatch,
  SystemError,
  Timeseries,
  TimeseriesMetric,
  TopDtc,
  User,
} from "./types";

export interface TokenProvider {
  getAccessToken(): string | null;
  /** Obtain a fresh access token, or `null` if the session is gone. */
  refresh(): Promise<string | null>;
  /** Called when the session can't be recovered (refresh failed / still 401). */
  onAuthFailure?(): void;
}

export type QueryValue = string | number | boolean | null | undefined;

export interface RequestOptions {
  method?: "GET" | "POST" | "PATCH" | "PUT" | "DELETE";
  query?: Record<string, QueryValue>;
  body?: unknown;
  signal?: AbortSignal;
  headers?: Record<string, string>;
}

export interface ApiClientOptions {
  baseUrl: string;
  auth: TokenProvider;
  fetchImpl?: typeof fetch;
}

export interface Download {
  blob: Blob;
  filename: string | null;
}

export function buildUrl(baseUrl: string, path: string, query?: Record<string, QueryValue>): string {
  const base = baseUrl.replace(/\/+$/, "");
  const suffix = path.startsWith("/") ? path : `/${path}`;
  const params = new URLSearchParams();
  for (const [key, value] of Object.entries(query ?? {})) {
    if (value === undefined || value === null || value === "") continue;
    params.set(key, String(value));
  }
  const qs = params.toString();
  return `${base}${suffix}${qs ? `?${qs}` : ""}`;
}

/** Extract `filename` from a Content-Disposition header (RFC 6266, basic). */
export function filenameFromDisposition(header: string | null): string | null {
  if (!header) return null;
  const star = /filename\*\s*=\s*(?:UTF-8'')?([^;]+)/i.exec(header);
  if (star) {
    try {
      return decodeURIComponent(star[1].trim().replace(/^"|"$/g, ""));
    } catch {
      /* fall through */
    }
  }
  const plain = /filename\s*=\s*("?)([^";]+)\1/i.exec(header);
  return plain ? plain[2].trim() : null;
}

export class ApiClient {
  private readonly baseUrl: string;
  private readonly auth: TokenProvider;
  private readonly fetchImpl: typeof fetch;

  constructor(options: ApiClientOptions) {
    this.baseUrl = options.baseUrl;
    this.auth = options.auth;
    // Bind so a bare `fetch` keeps its `window` receiver.
    const f = options.fetchImpl ?? globalThis.fetch;
    this.fetchImpl = ((input, init) => f(input, init)) as typeof fetch;
  }

  /** JSON request. Resolves to `undefined` for 204 / empty bodies. */
  async request<T>(path: string, options: RequestOptions = {}): Promise<T> {
    const res = await this.send(path, options, "application/json");
    if (res.status === 204) return undefined as T;
    const text = await res.text();
    if (!text) return undefined as T;
    try {
      return JSON.parse(text) as T;
    } catch (cause) {
      throw new ApiError({
        status: res.status,
        code: "invalid_response",
        message: "Response body is not valid JSON",
        requestId: res.headers.get("x-request-id"),
        cause,
      });
    }
  }

  /** Binary download (e.g. CSV export) with the same auth/refresh behaviour. */
  async download(path: string, options: RequestOptions = {}): Promise<Download> {
    const res = await this.send(path, options, "text/csv, */*");
    return {
      blob: await res.blob(),
      filename: filenameFromDisposition(res.headers.get("content-disposition")),
    };
  }

  private async send(path: string, options: RequestOptions, accept: string): Promise<Response> {
    const first = await this.fetchOnce(path, options, accept, this.auth.getAccessToken());
    if (first.status !== 401) {
      if (!first.ok) throw await errorFromResponse(first);
      return first;
    }

    // 401: try exactly one refresh, then one retry.
    const unauthorized = await errorFromResponse(first);
    let fresh: string | null = null;
    try {
      fresh = await this.auth.refresh();
    } catch {
      fresh = null;
    }
    if (!fresh) {
      this.auth.onAuthFailure?.();
      throw unauthorized;
    }

    const retry = await this.fetchOnce(path, options, accept, fresh);
    if (retry.ok) return retry;
    const err = await errorFromResponse(retry);
    if (retry.status === 401) this.auth.onAuthFailure?.();
    throw err;
  }

  private async fetchOnce(
    path: string,
    options: RequestOptions,
    accept: string,
    token: string | null,
  ): Promise<Response> {
    const headers: Record<string, string> = { Accept: accept, ...options.headers };
    if (token) headers.Authorization = `Bearer ${token}`;
    let body: BodyInit | undefined;
    if (options.body !== undefined) {
      headers["Content-Type"] = "application/json";
      body = JSON.stringify(options.body);
    }
    try {
      return await this.fetchImpl(buildUrl(this.baseUrl, path, options.query), {
        method: options.method ?? "GET",
        headers,
        body,
        signal: options.signal,
        credentials: "omit",
        cache: "no-store",
      });
    } catch (cause) {
      if (cause instanceof DOMException && cause.name === "AbortError") throw cause;
      throw networkError(cause);
    }
  }
}

/** Typed wrappers for the endpoints the dashboard uses. */
export function adminApi(client: ApiClient) {
  return {
    me: (signal?: AbortSignal) => client.request<User>("/me", { signal }),
    overview: (signal?: AbortSignal) =>
      client.request<OverviewStats>("/admin/stats/overview", { signal }),
    timeseries: (metric: TimeseriesMetric, days: number, signal?: AbortSignal) =>
      client.request<Timeseries>("/admin/stats/timeseries", { query: { metric, days }, signal }),
    topDtcs: (days: number, limit: number, signal?: AbortSignal) =>
      client.request<TopDtc[]>("/admin/stats/top-dtcs", { query: { days, limit }, signal }),
    users: (params: { q?: string; limit: number; offset: number }, signal?: AbortSignal) =>
      client.request<Page<AdminUser>>("/admin/users", { query: params, signal }),
    updateUser: (id: string, patch: AdminUserPatch) =>
      client.request<AdminUser | undefined>(`/admin/users/${encodeURIComponent(id)}`, {
        method: "PATCH",
        body: patch,
      }),
    errors: (params: { limit: number; offset: number }, signal?: AbortSignal) =>
      client.request<Page<SystemError>>("/admin/errors", { query: params, signal }),
    auditLogs: (params: { limit: number; offset: number }, signal?: AbortSignal) =>
      client.request<Page<AuditLog>>("/admin/audit-logs", { query: params, signal }),
    plans: async (signal?: AbortSignal): Promise<Plan[]> => {
      // Accept either a bare array or a page envelope.
      const res = await client.request<Plan[] | Page<Plan>>("/admin/plans", { signal });
      return Array.isArray(res) ? res : (res?.items ?? []);
    },
    updatePlan: (key: string, patch: PlanPatch) =>
      client.request<Plan | undefined>(`/admin/plans/${encodeURIComponent(key)}`, {
        method: "PATCH",
        body: patch,
      }),
    exportCsv: (dataset: ExportDataset) => client.download(`/admin/export/${dataset}.csv`),
    ecuPendingProfiles: (signal?: AbortSignal) =>
      client.request<DiagEcuProfile[]>("/diag/admin/profiles/pending-review", { signal }),
    ecuReviewProfile: (id: string, body: DiagProfileReview) =>
      client.request<DiagEcuProfile>(`/diag/admin/profiles/${encodeURIComponent(id)}/approve`, {
        method: "POST",
        body,
      }),
  };
}

export type AdminApi = ReturnType<typeof adminApi>;
