"use client";

import { useI18n } from "@/i18n/I18nProvider";
import type { ApiError } from "@/lib/errors";
import { errorMessage } from "./errorMessage";

export function LoadingState({ label, rows = 3 }: { label?: string; rows?: number }) {
  const { dict } = useI18n();
  return (
    <div role="status" aria-live="polite" className="space-y-2 py-2">
      <span className="sr-only">{label ?? dict.common.loading}</span>
      {Array.from({ length: rows }, (_, i) => (
        <div key={i} aria-hidden="true" className="h-4 animate-pulse rounded bg-surface-2" style={{ width: `${90 - i * 15}%` }} />
      ))}
    </div>
  );
}

export function ErrorState({ error, onRetry, compact = false }: { error: ApiError; onRetry?: () => void; compact?: boolean }) {
  const { dict, t } = useI18n();
  return (
    <div role="alert" className={`rounded-lg border border-danger/40 bg-danger-soft text-fg ${compact ? "p-3" : "p-4"}`}>
      <p className="font-semibold text-danger">{dict.apiErrors.title}</p>
      <p className="mt-1 text-sm">{errorMessage(dict, error)}</p>
      <p className="mt-1 text-xs text-muted">
        <span dir="ltr" className="inline-block">{t(dict.apiErrors.code, { code: error.code })}{error.status ? ` · HTTP ${error.status}` : ""}</span>
        {error.requestId ? (
          <span dir="ltr" className="ms-2 inline-block">{t(dict.apiErrors.requestId, { id: error.requestId })}</span>
        ) : null}
      </p>
      {onRetry ? (
        <button type="button" onClick={onRetry} className="mt-3 rounded-md border border-line bg-surface px-3 py-1.5 text-sm font-medium hover:bg-surface-2">
          {dict.common.retry}
        </button>
      ) : null}
    </div>
  );
}

export function EmptyState({ message }: { message?: string }) {
  const { dict } = useI18n();
  return <p className="py-6 text-center text-sm text-muted">{message ?? dict.common.empty}</p>;
}
