/**
 * Typed errors for the `{error: {code, message, details}}` envelope described
 * in docs/API.md, plus client-side failure modes (network, bad JSON).
 */
export const KNOWN_ERROR_CODES = [
  "validation_error",
  "unauthorized",
  "forbidden",
  "not_found",
  "conflict",
  "rate_limited",
  "mfa_required",
  "policy_rejected",
  "plan_limit",
  "network_error",
  "upstream_unavailable",
  "server_error",
  "invalid_response",
  "unknown_error",
] as const;

export type KnownErrorCode = (typeof KNOWN_ERROR_CODES)[number];

export function isKnownErrorCode(code: string): code is KnownErrorCode {
  return (KNOWN_ERROR_CODES as readonly string[]).includes(code);
}

export class ApiError extends Error {
  readonly status: number;
  /** Code from the envelope (may be a code this client doesn't know yet). */
  readonly code: string;
  readonly details: Record<string, unknown>;
  readonly requestId: string | null;

  constructor(init: {
    status: number;
    code: string;
    message: string;
    details?: Record<string, unknown>;
    requestId?: string | null;
    cause?: unknown;
  }) {
    super(init.message, init.cause === undefined ? undefined : { cause: init.cause });
    this.name = "ApiError";
    this.status = init.status;
    this.code = init.code;
    this.details = init.details ?? {};
    this.requestId = init.requestId ?? null;
  }

  get isUnauthorized() {
    return this.status === 401 || this.code === "unauthorized";
  }

  get isMfaRequired() {
    return this.code === "mfa_required";
  }
}

export function isApiError(value: unknown): value is ApiError {
  return value instanceof ApiError;
}

export function codeForStatus(status: number): KnownErrorCode {
  if (status === 400 || status === 422) return "validation_error";
  if (status === 401) return "unauthorized";
  if (status === 403) return "forbidden";
  if (status === 404) return "not_found";
  if (status === 409) return "conflict";
  if (status === 429) return "rate_limited";
  if (status === 502 || status === 503 || status === 504) return "upstream_unavailable";
  if (status >= 500) return "server_error";
  return "unknown_error";
}

interface Envelope {
  error: { code: string; message?: unknown; details?: unknown };
}

export function isErrorEnvelope(body: unknown): body is Envelope {
  if (typeof body !== "object" || body === null || !("error" in body)) return false;
  const err = (body as { error: unknown }).error;
  return (
    typeof err === "object" &&
    err !== null &&
    typeof (err as { code?: unknown }).code === "string"
  );
}

/** Map a parsed body + status to an ApiError (envelope wins over status). */
export function errorFromBody(
  status: number,
  body: unknown,
  requestId: string | null = null,
): ApiError {
  if (isErrorEnvelope(body)) {
    const { code, message, details } = body.error;
    return new ApiError({
      status,
      code,
      message: typeof message === "string" && message ? message : code,
      details:
        typeof details === "object" && details !== null
          ? (details as Record<string, unknown>)
          : {},
      requestId,
    });
  }
  const code = codeForStatus(status);
  return new ApiError({ status, code, message: `HTTP ${status}`, requestId });
}

/** Read a failed Response and turn it into an ApiError. Never throws. */
export async function errorFromResponse(res: Response): Promise<ApiError> {
  const requestId = res.headers.get("x-request-id");
  let body: unknown = null;
  try {
    const text = await res.text();
    body = text ? JSON.parse(text) : null;
  } catch {
    body = null;
  }
  return errorFromBody(res.status, body, requestId);
}

export function networkError(cause: unknown): ApiError {
  return new ApiError({
    status: 0,
    code: "network_error",
    message: cause instanceof Error ? cause.message : "Network request failed",
    cause,
  });
}
