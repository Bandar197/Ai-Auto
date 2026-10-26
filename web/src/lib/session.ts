/**
 * Browser-side session manager.
 *
 * The access token is kept in a closure (memory only). The refresh token never
 * reaches JavaScript: `/api/session` stores it in an httpOnly cookie and
 * proxies login / refresh / logout to the backend.
 */
import { SESSION_ENDPOINT } from "./config";
import { ApiError, errorFromResponse, networkError } from "./errors";
import type { BrowserSession, User } from "./types";

export interface LoginInput {
  email: string;
  password: string;
  totp_code?: string;
}

export interface SessionManager {
  getAccessToken(): string | null;
  login(input: LoginInput): Promise<User | null>;
  /** Concurrent calls share one in-flight request (refresh tokens rotate). */
  refresh(): Promise<string | null>;
  logout(): Promise<void>;
  clear(): void;
}

export function createSessionManager(
  fetchImpl: typeof fetch = (input, init) => globalThis.fetch(input, init),
): SessionManager {
  let accessToken: string | null = null;
  let inflight: Promise<string | null> | null = null;

  async function call(body: Record<string, unknown>): Promise<Response> {
    try {
      return await fetchImpl(SESSION_ENDPOINT, {
        method: "POST",
        headers: { "Content-Type": "application/json", Accept: "application/json" },
        body: JSON.stringify(body),
        credentials: "same-origin",
        cache: "no-store",
      });
    } catch (cause) {
      throw networkError(cause);
    }
  }

  async function readSession(res: Response): Promise<BrowserSession> {
    const data = (await res.json().catch(() => null)) as BrowserSession | null;
    if (!data || typeof data.access_token !== "string") {
      throw new ApiError({
        status: res.status,
        code: "invalid_response",
        message: "Session response has no access token",
      });
    }
    return data;
  }

  return {
    getAccessToken: () => accessToken,

    async login(input) {
      const res = await call({ action: "login", ...input });
      if (!res.ok) throw await errorFromResponse(res);
      const session = await readSession(res);
      accessToken = session.access_token;
      return session.user ?? null;
    },

    refresh() {
      if (inflight) return inflight;
      inflight = (async () => {
        try {
          const res = await call({ action: "refresh" });
          if (!res.ok) {
            accessToken = null;
            return null;
          }
          const session = await readSession(res);
          accessToken = session.access_token;
          return accessToken;
        } catch {
          accessToken = null;
          return null;
        } finally {
          inflight = null;
        }
      })();
      return inflight;
    },

    async logout() {
      accessToken = null;
      try {
        await call({ action: "logout" });
      } catch {
        /* cookie is cleared server-side when reachable; nothing else to do */
      }
    },

    clear() {
      accessToken = null;
    },
  };
}
