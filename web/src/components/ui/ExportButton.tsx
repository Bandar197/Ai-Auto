"use client";

import { useState } from "react";
import { useAuth } from "@/components/auth/AuthProvider";
import { useI18n } from "@/i18n/I18nProvider";
import { ApiError, isApiError } from "@/lib/errors";
import type { ExportDataset } from "@/lib/types";
import { errorMessage } from "./errorMessage";

/** Downloads `/admin/export/{dataset}.csv` through the authenticated client. */
export function ExportButton({ dataset }: { dataset: ExportDataset }) {
  const { api } = useAuth();
  const { dict, t } = useI18n();
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<ApiError | null>(null);

  async function onClick() {
    setBusy(true);
    setError(null);
    try {
      const { blob, filename } = await api.exportCsv(dataset);
      const url = URL.createObjectURL(blob);
      const a = document.createElement("a");
      a.href = url;
      a.download = filename ?? `automind-${dataset}-${new Date().toISOString().slice(0, 10)}.csv`;
      document.body.appendChild(a);
      a.click();
      a.remove();
      setTimeout(() => URL.revokeObjectURL(url), 1000);
    } catch (err) {
      setError(isApiError(err) ? err : new ApiError({ status: 0, code: "unknown_error", message: String(err) }));
    } finally {
      setBusy(false);
    }
  }

  return (
    <span className="inline-flex flex-col items-start gap-1">
      <button
        type="button"
        onClick={onClick}
        disabled={busy}
        aria-busy={busy}
        className="inline-flex items-center gap-1.5 rounded-md border border-line bg-surface px-3 py-1.5 text-sm font-medium hover:bg-surface-2 disabled:opacity-60"
      >
        <svg aria-hidden="true" viewBox="0 0 20 20" className="h-4 w-4" fill="none" stroke="currentColor" strokeWidth="1.8">
          <path d="M10 3v10m0 0l-4-4m4 4l4-4M4 15v2h12v-2" strokeLinecap="round" strokeLinejoin="round" />
        </svg>
        {busy ? dict.exports.downloading : t(dict.exports.button, { dataset: dict.exports[dataset] })}
      </button>
      {error ? (
        <span role="alert" className="text-xs text-danger">
          {errorMessage(dict, error)}
        </span>
      ) : null}
    </span>
  );
}
