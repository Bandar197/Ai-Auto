"use client";

import {
  createContext,
  useCallback,
  useContext,
  useEffect,
  useMemo,
  useState,
  type ReactNode,
} from "react";
import { ApiClient, adminApi, type AdminApi } from "@/lib/api";
import { API_BASE_URL, STAFF_ROLES } from "@/lib/config";
import { ApiError } from "@/lib/errors";
import { createSessionManager, type LoginInput, type SessionManager } from "@/lib/session";
import type { User } from "@/lib/types";

export type AuthState =
  | { status: "loading" }
  | { status: "authenticated"; user: User }
  | { status: "unauthenticated"; reason?: "not_staff" | "expired" };

interface AuthValue {
  state: AuthState;
  api: AdminApi;
  login(input: LoginInput): Promise<void>;
  logout(): Promise<void>;
}

const AuthContext = createContext<AuthValue | null>(null);

export function isStaff(user: Pick<User, "platform_role"> | null | undefined): boolean {
  return !!user && (STAFF_ROLES as readonly string[]).includes(user.platform_role);
}

export function notStaffError(): ApiError {
  return new ApiError({ status: 403, code: "forbidden", message: "not_staff" });
}

export function AuthProvider({
  children,
  session: injectedSession,
}: {
  children: ReactNode;
  session?: SessionManager;
}) {
  const [state, setState] = useState<AuthState>({ status: "loading" });
  const [session] = useState<SessionManager>(() => injectedSession ?? createSessionManager());

  const api = useMemo(
    () =>
      adminApi(
        new ApiClient({
          baseUrl: API_BASE_URL,
          auth: {
            getAccessToken: () => session.getAccessToken(),
            refresh: () => session.refresh(),
            onAuthFailure: () => {
              session.clear();
              setState({ status: "unauthenticated", reason: "expired" });
            },
          },
        }),
      ),
    [session],
  );

  // Restore the session from the httpOnly refresh cookie on first load.
  useEffect(() => {
    let cancelled = false;
    (async () => {
      const token = await session.refresh();
      if (cancelled) return;
      if (!token) {
        setState({ status: "unauthenticated" });
        return;
      }
      try {
        const me = await api.me();
        if (cancelled) return;
        if (!isStaff(me)) {
          await session.logout();
          setState({ status: "unauthenticated", reason: "not_staff" });
          return;
        }
        setState({ status: "authenticated", user: me });
      } catch {
        if (!cancelled) setState({ status: "unauthenticated" });
      }
    })();
    return () => {
      cancelled = true;
    };
  }, [api, session]);

  const login = useCallback(
    async (input: LoginInput) => {
      const user = (await session.login(input)) ?? (await api.me());
      if (!isStaff(user)) {
        await session.logout();
        throw notStaffError();
      }
      setState({ status: "authenticated", user });
    },
    [api, session],
  );

  const logout = useCallback(async () => {
    await session.logout();
    setState({ status: "unauthenticated" });
  }, [session]);

  const value = useMemo(() => ({ state, api, login, logout }), [state, api, login, logout]);
  return <AuthContext value={value}>{children}</AuthContext>;
}

export function useAuth(): AuthValue {
  const ctx = useContext(AuthContext);
  if (!ctx) throw new Error("useAuth must be used inside <AuthProvider>");
  return ctx;
}
