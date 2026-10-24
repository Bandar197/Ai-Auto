"use client";

import { useId, useState } from "react";
import { useAuth } from "@/components/auth/AuthProvider";
import { Badge } from "@/components/ui/Badge";
import { Card } from "@/components/ui/Card";
import { PageHeader } from "@/components/ui/PageHeader";
import { EmptyState, ErrorState, LoadingState } from "@/components/ui/States";
import { errorMessage } from "@/components/ui/errorMessage";
import { useApiQuery } from "@/hooks/useApiQuery";
import { useI18n } from "@/i18n/I18nProvider";
import { ApiError, isApiError } from "@/lib/errors";
import type { DiagDecisionStatus, DiagEcuProfile } from "@/lib/types";

const ADMIN_ROLES = ["admin", "super_admin"] as const;
const DECISIONS: readonly DiagDecisionStatus[] = [
  "verified_vehicle_trace",
  "licensed_oem",
  "standard_specification",
  "demo_only",
  "rejected",
] as const;

function vehicleLabel(p: DiagEcuProfile): string {
  return [p.make, p.model, p.variant].filter(Boolean).join(" ") || p.make;
}

function yearsLabel(p: DiagEcuProfile): string {
  if (p.model_year_range) return p.model_year_range;
  if (p.year_from == null && p.year_to == null) return "—";
  return `${p.year_from ?? "—"}–${p.year_to ?? "—"}`;
}

export function EcuProfilesView() {
  const { api, state } = useAuth();
  const { dict, t } = useI18n();
  const isAdmin =
    state.status === "authenticated" &&
    (ADMIN_ROLES as readonly string[]).includes(state.user.platform_role);

  const [openId, setOpenId] = useState<string | null>(null);
  const [status, setStatus] = useState<DiagDecisionStatus>("verified_vehicle_trace");
  const [sourceType, setSourceType] = useState("");
  const [sourceReference, setSourceReference] = useState("");
  const [pendingId, setPendingId] = useState<string | null>(null);
  const [actionError, setActionError] = useState<ApiError | null>(null);
  const [formError, setFormError] = useState<string | null>(null);
  const [notice, setNotice] = useState<string | null>(null);

  const pending = useApiQuery(
    "ecu-pending",
    (s) => api.ecuPendingProfiles(s),
    isAdmin,
  );

  const statusId = useId();
  const typeId = useId();
  const refId = useId();

  function openReview(p: DiagEcuProfile) {
    setOpenId(p.id);
    setStatus("verified_vehicle_trace");
    setSourceType("");
    setSourceReference("");
    setFormError(null);
    setActionError(null);
    setNotice(null);
  }

  async function submitReview(p: DiagEcuProfile) {
    if (!sourceType.trim() || !sourceReference.trim()) {
      setFormError(dict.ecu.needEvidence);
      return;
    }
    setPendingId(p.id);
    setActionError(null);
    setFormError(null);
    setNotice(null);
    try {
      await api.ecuReviewProfile(p.id, {
        verification_status: status,
        source_type: sourceType.trim(),
        source_reference: sourceReference.trim(),
      });
      // The row leaves the pending list once reviewed.
      pending.setData((prev) => prev?.filter((x) => x.id !== p.id));
      setOpenId(null);
      setNotice(
        t(dict.ecu.reviewed, {
          vehicle: vehicleLabel(p),
          status: dict.ecu.statusValues[status],
        }),
      );
    } catch (err) {
      setActionError(
        isApiError(err) ? err : new ApiError({ status: 0, code: "unknown_error", message: String(err) }),
      );
    } finally {
      setPendingId(null);
    }
  }

  const th = "whitespace-nowrap bg-surface-2 px-3 py-2 text-start text-xs font-semibold text-muted";
  const td = "border-t border-line px-3 py-2 align-middle";
  const field = "mt-1 block w-full rounded-md border border-line bg-surface px-3 py-2 text-sm placeholder:text-muted";
  const COLS = 7;

  return (
    <>
      <PageHeader title={dict.ecu.title} subtitle={dict.ecu.subtitle} fetchedAt={pending.fetchedAt} />
      <Card title={dict.ecu.pendingTitle} description={dict.ecu.pendingDescription}>
        <div aria-live="polite">
          {notice ? <p className="mb-2 rounded-md bg-success-soft p-2 text-sm text-success">{notice}</p> : null}
          {actionError ? (
            <p role="alert" className="mb-2 rounded-md bg-danger-soft p-2 text-sm text-danger">
              {errorMessage(dict, actionError)}
            </p>
          ) : null}
        </div>

        {!isAdmin ? (
          <EmptyState message={dict.ecu.adminsOnly} />
        ) : pending.error ? (
          <ErrorState error={pending.error} onRetry={pending.reload} />
        ) : pending.loading && !pending.data ? (
          <LoadingState rows={4} />
        ) : !pending.data?.length ? (
          <EmptyState />
        ) : (
          <div className="overflow-x-auto rounded-md border border-line">
            <table className="w-full min-w-[840px] text-sm">
              <thead>
                <tr>
                  <th scope="col" className={th}>{dict.ecu.vehicle}</th>
                  <th scope="col" className={th}>{dict.ecu.years}</th>
                  <th scope="col" className={th}>{dict.ecu.controller}</th>
                  <th scope="col" className={th}>{dict.ecu.protocol}</th>
                  <th scope="col" className={th}>{dict.ecu.headers}</th>
                  <th scope="col" className={th}>{dict.ecu.request}</th>
                  <th scope="col" className={th}>{dict.common.actions}</th>
                </tr>
              </thead>
              <tbody>
                {pending.data.map((p) => {
                  const open = openId === p.id;
                  const busy = pendingId === p.id;
                  return (
                    <ReviewRow
                      key={p.id}
                      profile={p}
                      open={open}
                      busy={busy}
                      td={td}
                      field={field}
                      cols={COLS}
                      statusId={statusId}
                      typeId={typeId}
                      refId={refId}
                      status={status}
                      sourceType={sourceType}
                      sourceReference={sourceReference}
                      formError={open ? formError : null}
                      onOpen={() => openReview(p)}
                      onCancel={() => setOpenId(null)}
                      onStatus={setStatus}
                      onSourceType={setSourceType}
                      onSourceReference={setSourceReference}
                      onSubmit={() => void submitReview(p)}
                    />
                  );
                })}
              </tbody>
            </table>
          </div>
        )}
      </Card>
    </>
  );
}

interface ReviewRowProps {
  profile: DiagEcuProfile;
  open: boolean;
  busy: boolean;
  td: string;
  field: string;
  cols: number;
  statusId: string;
  typeId: string;
  refId: string;
  status: DiagDecisionStatus;
  sourceType: string;
  sourceReference: string;
  formError: string | null;
  onOpen(): void;
  onCancel(): void;
  onStatus(value: DiagDecisionStatus): void;
  onSourceType(value: string): void;
  onSourceReference(value: string): void;
  onSubmit(): void;
}

function ReviewRow(props: ReviewRowProps) {
  const { profile: p, open, busy, td, field, cols } = props;
  const { dict, fmt } = useI18n();
  const headers = `${p.tx_header ?? "—"} / ${p.rx_header ?? "—"}`;

  return (
    <>
      <tr>
        <td className={td}>
          <span className="block font-medium">{vehicleLabel(p)}</span>
          {p.market ? <span className="block text-xs text-muted">{p.market}</span> : null}
        </td>
        <td className={`${td} tabular whitespace-nowrap`} dir="ltr">{yearsLabel(p)}</td>
        <td className={td}>
          {p.controller_id ? (
            <span dir="ltr">{p.controller_id}</span>
          ) : (
            <span className="text-muted">—</span>
          )}
          {p.category ? <Badge tone="neutral">{p.category}</Badge> : null}
        </td>
        <td className={td} dir="ltr">{p.protocol ?? "—"}</td>
        <td className={`${td} whitespace-nowrap`} dir="ltr">{headers}</td>
        <td className={td} dir="ltr">{p.read_request ?? "—"}</td>
        <td className={td}>
          <button
            type="button"
            onClick={props.onOpen}
            disabled={busy}
            aria-expanded={open}
            className="rounded-md border border-accent/50 px-3 py-1 text-xs font-semibold text-accent hover:bg-accent-soft disabled:opacity-60"
          >
            {dict.ecu.review}
          </button>
        </td>
      </tr>
      {open ? (
        <tr>
          <td className="border-t border-line bg-surface-2 px-3 py-3" colSpan={cols}>
            {p.notes ? (
              <p className="mb-3 text-sm">
                <span className="font-semibold text-muted">{dict.ecu.submittedBy}: </span>
                <span dir="ltr">{p.submitted_by ?? "—"}</span>
                <span className="mx-2 text-muted">·</span>
                {p.notes}
              </p>
            ) : (
              <p className="mb-3 text-sm">
                <span className="font-semibold text-muted">{dict.ecu.submittedBy}: </span>
                <span dir="ltr">{p.submitted_by ?? "—"}</span>
                <span className="mx-2 text-muted">·</span>
                {fmt.dateTime(p.created_at)}
              </p>
            )}
            <div className="grid gap-3 sm:grid-cols-3">
              <div>
                <label htmlFor={props.statusId} className="block text-sm font-medium">
                  {dict.ecu.decisionStatus}
                </label>
                <select
                  id={props.statusId}
                  value={props.status}
                  onChange={(e) => props.onStatus(e.target.value as DiagDecisionStatus)}
                  className={field}
                >
                  {DECISIONS.map((d) => (
                    <option key={d} value={d}>
                      {dict.ecu.statusValues[d]}
                    </option>
                  ))}
                </select>
              </div>
              <div>
                <label htmlFor={props.typeId} className="block text-sm font-medium">
                  {dict.ecu.sourceType}
                </label>
                <input
                  id={props.typeId}
                  type="text"
                  value={props.sourceType}
                  onChange={(e) => props.onSourceType(e.target.value)}
                  placeholder={dict.ecu.sourceTypePlaceholder}
                  dir="auto"
                  className={field}
                />
              </div>
              <div>
                <label htmlFor={props.refId} className="block text-sm font-medium">
                  {dict.ecu.sourceReference}
                </label>
                <input
                  id={props.refId}
                  type="text"
                  value={props.sourceReference}
                  onChange={(e) => props.onSourceReference(e.target.value)}
                  placeholder={dict.ecu.sourceReferencePlaceholder}
                  dir="auto"
                  className={field}
                />
              </div>
            </div>
            {props.formError ? (
              <p role="alert" className="mt-2 text-sm text-danger">{props.formError}</p>
            ) : null}
            <div className="mt-3 flex gap-2">
              <button
                type="button"
                onClick={props.onSubmit}
                disabled={busy}
                aria-busy={busy}
                className="rounded-md border border-success/50 px-3 py-1.5 text-sm font-semibold text-success hover:bg-success-soft disabled:opacity-60"
              >
                {busy ? dict.common.saving : dict.ecu.approve}
              </button>
              <button
                type="button"
                onClick={props.onCancel}
                disabled={busy}
                className="rounded-md border border-line bg-surface px-3 py-1.5 text-sm font-medium hover:bg-surface-2 disabled:opacity-60"
              >
                {dict.ecu.cancel}
              </button>
            </div>
          </td>
        </tr>
      ) : null}
    </>
  );
}
