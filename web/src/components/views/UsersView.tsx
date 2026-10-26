"use client";

import { useEffect, useId, useState } from "react";
import { useAuth } from "@/components/auth/AuthProvider";
import { Badge, type BadgeTone } from "@/components/ui/Badge";
import { Card } from "@/components/ui/Card";
import { ExportButton } from "@/components/ui/ExportButton";
import { PageHeader } from "@/components/ui/PageHeader";
import { Pagination } from "@/components/ui/Pagination";
import { EmptyState, ErrorState, LoadingState } from "@/components/ui/States";
import { errorMessage } from "@/components/ui/errorMessage";
import { useApiQuery } from "@/hooks/useApiQuery";
import { useI18n } from "@/i18n/I18nProvider";
import { ApiError, isApiError } from "@/lib/errors";
import type { AdminUser, UserStatus } from "@/lib/types";

const LIMIT = 20;

const statusTone: Record<UserStatus, BadgeTone> = {
  active: "success",
  suspended: "danger",
  pending_deletion: "warning",
  deleted: "neutral",
};

export function UsersView() {
  const { api, state } = useAuth();
  const { dict, t, fmt } = useI18n();
  const searchId = useId();
  const [search, setSearch] = useState("");
  const [query, setQuery] = useState("");
  const [offset, setOffset] = useState(0);
  const [pendingId, setPendingId] = useState<string | null>(null);
  const [actionError, setActionError] = useState<ApiError | null>(null);
  const [notice, setNotice] = useState<string | null>(null);

  // Debounce the search box.
  useEffect(() => {
    const handle = setTimeout(() => {
      setQuery(search.trim());
      setOffset(0);
    }, 300);
    return () => clearTimeout(handle);
  }, [search]);

  const users = useApiQuery(`users-${query}-${offset}`, (s) =>
    api.users({ q: query || undefined, limit: LIMIT, offset }, s),
  );

  const selfId = state.status === "authenticated" ? state.user.id : null;

  async function toggleStatus(user: AdminUser) {
    const next: UserStatus = user.status === "active" ? "suspended" : "active";
    const question = t(next === "suspended" ? dict.users.confirmSuspend : dict.users.confirmActivate, {
      email: user.email,
    });
    if (!window.confirm(question)) return;
    setPendingId(user.id);
    setActionError(null);
    setNotice(null);
    try {
      const updated = await api.updateUser(user.id, { status: next });
      if (updated && typeof updated === "object" && "id" in updated) {
        users.setData((prev) =>
          prev ? { ...prev, items: prev.items.map((u) => (u.id === user.id ? { ...u, ...updated } : u)) } : prev,
        );
      } else {
        users.reload();
      }
      setNotice(t(dict.users.updated, { email: user.email }));
    } catch (err) {
      setActionError(isApiError(err) ? err : new ApiError({ status: 0, code: "unknown_error", message: String(err) }));
    } finally {
      setPendingId(null);
    }
  }

  const th = "whitespace-nowrap bg-surface-2 px-3 py-2 text-start text-xs font-semibold text-muted";
  const td = "border-t border-line px-3 py-2 align-middle";

  return (
    <>
      <PageHeader
        title={dict.users.title}
        subtitle={dict.users.subtitle}
        fetchedAt={users.fetchedAt}
        actions={<ExportButton dataset="users" />}
      />
      <Card>
        <div className="mb-3 flex flex-wrap items-end gap-3">
          <div className="w-full max-w-sm">
            <label htmlFor={searchId} className="block text-sm font-medium">
              {dict.users.searchLabel}
            </label>
            <input
              id={searchId}
              type="search"
              value={search}
              onChange={(e) => setSearch(e.target.value)}
              placeholder={dict.users.searchPlaceholder}
              dir="auto"
              className="mt-1 block w-full rounded-md border border-line bg-surface px-3 py-2 text-sm placeholder:text-muted"
            />
          </div>
        </div>

        <div aria-live="polite">
          {notice ? <p className="mb-2 rounded-md bg-success-soft p-2 text-sm text-success">{notice}</p> : null}
          {actionError ? (
            <p role="alert" className="mb-2 rounded-md bg-danger-soft p-2 text-sm text-danger">
              {errorMessage(dict, actionError)}
            </p>
          ) : null}
        </div>

        {users.error ? (
          <ErrorState error={users.error} onRetry={users.reload} />
        ) : users.loading && !users.data ? (
          <LoadingState rows={5} />
        ) : !users.data?.items?.length ? (
          <EmptyState />
        ) : (
          <>
            <div className="overflow-x-auto rounded-md border border-line">
              <table className="w-full min-w-[760px] text-sm">
                <thead>
                  <tr>
                    <th scope="col" className={th}>{dict.users.name}</th>
                    <th scope="col" className={th}>{dict.users.role}</th>
                    <th scope="col" className={th}>{dict.users.status}</th>
                    <th scope="col" className={th}>{dict.users.vehicles}</th>
                    <th scope="col" className={th}>{dict.users.sessions}</th>
                    <th scope="col" className={th}>{dict.users.createdAt}</th>
                    <th scope="col" className={th}>{dict.users.lastLogin}</th>
                    <th scope="col" className={th}>{dict.common.actions}</th>
                  </tr>
                </thead>
                <tbody>
                  {users.data.items.map((u) => {
                    const canToggle = (u.status === "active" || u.status === "suspended") && u.id !== selfId;
                    return (
                      <tr key={u.id}>
                        <td className={td}>
                          <span className="block font-medium">{u.full_name || "—"}</span>
                          <span className="block text-xs text-muted" dir="ltr">{u.email}</span>
                        </td>
                        <td className={td}>
                          <Badge tone={u.platform_role === "user" ? "neutral" : "accent"}>
                            {dict.roles[u.platform_role] ?? u.platform_role}
                          </Badge>
                        </td>
                        <td className={td}>
                          <Badge tone={statusTone[u.status] ?? "neutral"}>{dict.statuses[u.status] ?? u.status}</Badge>
                        </td>
                        <td className={`${td} tabular`}>{fmt.integer(u.vehicles)}</td>
                        <td className={`${td} tabular`}>{fmt.integer(u.sessions)}</td>
                        <td className={`${td} whitespace-nowrap`}>{fmt.date(u.created_at)}</td>
                        <td className={`${td} whitespace-nowrap`}>
                          {u.last_login_at ? fmt.dateTime(u.last_login_at) : <span className="text-muted">{dict.users.never}</span>}
                        </td>
                        <td className={td}>
                          {canToggle ? (
                            <button
                              type="button"
                              onClick={() => void toggleStatus(u)}
                              disabled={pendingId === u.id}
                              aria-busy={pendingId === u.id}
                              aria-label={`${u.status === "active" ? dict.users.suspend : dict.users.activate} — ${u.email}`}
                              className={`rounded-md border px-3 py-1 text-xs font-semibold disabled:opacity-60 ${
                                u.status === "active"
                                  ? "border-danger/50 text-danger hover:bg-danger-soft"
                                  : "border-success/50 text-success hover:bg-success-soft"
                              }`}
                            >
                              {pendingId === u.id
                                ? dict.common.saving
                                : u.status === "active"
                                  ? dict.users.suspend
                                  : dict.users.activate}
                            </button>
                          ) : null}
                        </td>
                      </tr>
                    );
                  })}
                </tbody>
              </table>
            </div>
            <Pagination offset={offset} limit={LIMIT} total={users.data.total} onChange={setOffset} />
          </>
        )}
      </Card>
    </>
  );
}
