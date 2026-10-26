"use client";

import { useId, useState, type FormEvent } from "react";
import { useAuth } from "@/components/auth/AuthProvider";
import { Badge } from "@/components/ui/Badge";
import { Card } from "@/components/ui/Card";
import { PageHeader } from "@/components/ui/PageHeader";
import { EmptyState, ErrorState, LoadingState } from "@/components/ui/States";
import { errorMessage } from "@/components/ui/errorMessage";
import { useApiQuery } from "@/hooks/useApiQuery";
import { useI18n } from "@/i18n/I18nProvider";
import { ApiError, isApiError } from "@/lib/errors";
import type { Plan, PlanPatch } from "@/lib/types";

const KEY_RE = /^[a-z0-9_]+$/;

interface Draft {
  price_monthly: string;
  price_yearly: string;
  active: boolean;
  features: Record<string, unknown>;
  limits: Record<string, string>;
  /** Limits whose value isn't numeric; shown read-only and sent back unchanged. */
  otherLimits: Record<string, unknown>;
}

function toInput(v: unknown): string {
  if (v === null || v === undefined || v === "") return "";
  return String(v);
}

export function draftFromPlan(plan: Plan): Draft {
  const limits: Record<string, string> = {};
  const otherLimits: Record<string, unknown> = {};
  for (const [k, v] of Object.entries(plan.limits ?? {})) {
    if (typeof v === "number" || (typeof v === "string" && v.trim() !== "" && Number.isFinite(Number(v)))) {
      limits[k] = String(v);
    } else {
      otherLimits[k] = v;
    }
  }
  return {
    price_monthly: toInput(plan.price_monthly),
    price_yearly: toInput(plan.price_yearly),
    active: !!plan.active,
    features: { ...(plan.features ?? {}) },
    limits,
    otherLimits,
  };
}

function parseAmount(value: string): number | null | "invalid" {
  const trimmed = value.trim();
  if (!trimmed) return null;
  const n = Number(trimmed);
  return Number.isFinite(n) && n >= 0 ? n : "invalid";
}

/** Build the PATCH body; returns the list of invalid field keys instead when validation fails. */
export function patchFromDraft(draft: Draft): { patch: PlanPatch } | { invalid: string[] } {
  const invalid: string[] = [];
  const monthly = parseAmount(draft.price_monthly);
  const yearly = parseAmount(draft.price_yearly);
  if (monthly === "invalid") invalid.push("price_monthly");
  if (yearly === "invalid") invalid.push("price_yearly");
  const limits: Record<string, unknown> = { ...draft.otherLimits };
  for (const [k, v] of Object.entries(draft.limits)) {
    const parsed = parseAmount(v);
    if (parsed === "invalid") invalid.push(`limit:${k}`);
    else if (parsed !== null) limits[k] = parsed;
  }
  if (invalid.length) return { invalid };
  return {
    patch: {
      price_monthly: monthly as number | null,
      price_yearly: yearly as number | null,
      active: draft.active,
      features: draft.features,
      limits,
    },
  };
}

function AddKey({ label, onAdd, existing }: { label: string; onAdd(key: string): void; existing: string[] }) {
  const { dict } = useI18n();
  const id = useId();
  const [value, setValue] = useState("");
  const [error, setError] = useState(false);
  return (
    <div className="mt-2 flex flex-wrap items-end gap-2">
      <div>
        <label htmlFor={id} className="block text-xs text-muted">
          {dict.plans.newKeyLabel}
        </label>
        <input
          id={id}
          value={value}
          dir="ltr"
          placeholder={dict.plans.newKeyPlaceholder}
          aria-invalid={error}
          aria-describedby={error ? `${id}-err` : undefined}
          onChange={(e) => {
            setValue(e.target.value);
            setError(false);
          }}
          className="mt-0.5 w-44 rounded-md border border-line bg-surface px-2 py-1 font-mono text-sm"
        />
      </div>
      <button
        type="button"
        onClick={() => {
          const key = value.trim();
          if (!KEY_RE.test(key) || existing.includes(key)) {
            setError(true);
            return;
          }
          onAdd(key);
          setValue("");
        }}
        className="rounded-md border border-line px-3 py-1 text-sm font-medium hover:bg-surface-2"
      >
        {label}
      </button>
      {error ? (
        <p id={`${id}-err`} role="alert" className="w-full text-xs text-danger">
          {dict.plans.invalidKey}
        </p>
      ) : null}
    </div>
  );
}

function PlanEditor({ plan, onSaved }: { plan: Plan; onSaved(updated: Plan | undefined): void }) {
  const { api } = useAuth();
  const { dict, t, locale } = useI18n();
  const uid = useId();
  const [draft, setDraft] = useState<Draft>(() => draftFromPlan(plan));
  const [invalid, setInvalid] = useState<string[]>([]);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<ApiError | null>(null);
  const [saved, setSaved] = useState(false);
  const currency = plan.currency || "SAR";
  const name = locale === "ar" ? plan.name_ar : plan.name_en;

  async function onSubmit(e: FormEvent) {
    e.preventDefault();
    setSaved(false);
    setError(null);
    const result = patchFromDraft(draft);
    if ("invalid" in result) {
      setInvalid(result.invalid);
      return;
    }
    setInvalid([]);
    setSaving(true);
    try {
      const updated = await api.updatePlan(plan.key, result.patch);
      const fresh = updated && typeof updated === "object" && "key" in updated ? updated : undefined;
      if (fresh) setDraft(draftFromPlan(fresh));
      setSaved(true);
      onSaved(fresh);
    } catch (err) {
      setError(isApiError(err) ? err : new ApiError({ status: 0, code: "unknown_error", message: String(err) }));
    } finally {
      setSaving(false);
    }
  }

  const input = "mt-1 block w-full rounded-md border border-line bg-surface px-3 py-2 text-sm aria-[invalid=true]:border-danger";
  const isInvalid = (k: string) => invalid.includes(k);

  return (
    <Card
      title={
        <span className="flex flex-wrap items-center gap-2">
          {name}
          <span className="font-mono text-xs font-normal text-muted" dir="ltr">{plan.key}</span>
          {plan.audience ? (
            <Badge>{plan.audience === "business" ? dict.plans.audienceBusiness : dict.plans.audienceIndividual}</Badge>
          ) : null}
        </span>
      }
    >
      <form onSubmit={onSubmit} className="space-y-4" aria-label={name}>
        <div className="grid grid-cols-1 gap-3 sm:grid-cols-2">
          {(["price_monthly", "price_yearly"] as const).map((field) => (
            <div key={field}>
              <label htmlFor={`${uid}-${field}`} className="block text-sm font-medium">
                {t(field === "price_monthly" ? dict.plans.priceMonthly : dict.plans.priceYearly, { currency })}
              </label>
              <input
                id={`${uid}-${field}`}
                type="number"
                inputMode="decimal"
                min={0}
                step="0.01"
                dir="ltr"
                value={draft[field]}
                aria-invalid={isInvalid(field)}
                onChange={(e) => setDraft((d) => ({ ...d, [field]: e.target.value }))}
                className={`${input} tabular`}
              />
              {isInvalid(field) ? <p className="mt-1 text-xs text-danger">{dict.plans.invalidNumber}</p> : null}
            </div>
          ))}
        </div>

        <label className="flex items-center gap-2 text-sm font-medium">
          <input
            type="checkbox"
            checked={draft.active}
            onChange={(e) => setDraft((d) => ({ ...d, active: e.target.checked }))}
            className="h-4 w-4 accent-[var(--accent)]"
          />
          {dict.plans.active}
        </label>

        <fieldset className="rounded-md border border-line p-3">
          <legend className="px-1 text-sm font-semibold">{dict.plans.features}</legend>
          <ul className="grid grid-cols-1 gap-2 sm:grid-cols-2">
            {Object.entries(draft.features).map(([key, value]) => (
              <li key={key}>
                {typeof value === "boolean" ? (
                  <label className="flex items-center gap-2 text-sm">
                    <input
                      type="checkbox"
                      checked={value}
                      onChange={(e) =>
                        setDraft((d) => ({ ...d, features: { ...d.features, [key]: e.target.checked } }))
                      }
                      className="h-4 w-4 accent-[var(--accent)]"
                    />
                    <span className="font-mono text-xs" dir="ltr">{key}</span>
                  </label>
                ) : (
                  <span className="text-sm">
                    <span className="font-mono text-xs" dir="ltr">{key}</span>{" "}
                    <span className="text-xs text-muted">
                      = <code dir="ltr">{JSON.stringify(value)}</code> ({dict.plans.otherValue})
                    </span>
                  </span>
                )}
              </li>
            ))}
          </ul>
          <AddKey
            label={dict.plans.addFeature}
            existing={Object.keys(draft.features)}
            onAdd={(key) => setDraft((d) => ({ ...d, features: { ...d.features, [key]: true } }))}
          />
        </fieldset>

        <fieldset className="rounded-md border border-line p-3">
          <legend className="px-1 text-sm font-semibold">{dict.plans.limits}</legend>
          <p className="mb-2 text-xs text-muted">{dict.plans.unlimitedHint}</p>
          <div className="grid grid-cols-1 gap-3 sm:grid-cols-2">
            {Object.entries(draft.limits).map(([key, value]) => (
              <div key={key}>
                <label htmlFor={`${uid}-limit-${key}`} className="block font-mono text-xs" dir="ltr">
                  {key}
                </label>
                <input
                  id={`${uid}-limit-${key}`}
                  type="number"
                  inputMode="numeric"
                  min={0}
                  dir="ltr"
                  value={value}
                  aria-invalid={isInvalid(`limit:${key}`)}
                  onChange={(e) => setDraft((d) => ({ ...d, limits: { ...d.limits, [key]: e.target.value } }))}
                  className={`${input} tabular`}
                />
                {isInvalid(`limit:${key}`) ? <p className="mt-1 text-xs text-danger">{dict.plans.invalidNumber}</p> : null}
              </div>
            ))}
            {Object.entries(draft.otherLimits).map(([key, value]) => (
              <p key={key} className="text-sm">
                <span className="font-mono text-xs" dir="ltr">{key}</span>{" "}
                <code className="text-xs text-muted" dir="ltr">{JSON.stringify(value)}</code>
              </p>
            ))}
          </div>
          <AddKey
            label={dict.plans.addLimit}
            existing={[...Object.keys(draft.limits), ...Object.keys(draft.otherLimits)]}
            onAdd={(key) => setDraft((d) => ({ ...d, limits: { ...d.limits, [key]: "0" } }))}
          />
        </fieldset>

        <div aria-live="polite">
          {error ? (
            <p role="alert" className="rounded-md bg-danger-soft p-2 text-sm text-danger">
              {errorMessage(dict, error)}
            </p>
          ) : null}
          {saved ? <p className="rounded-md bg-success-soft p-2 text-sm text-success">{t(dict.plans.savedPlan, { name })}</p> : null}
        </div>

        <div className="flex flex-wrap gap-2">
          <button
            type="submit"
            disabled={saving}
            aria-busy={saving}
            className="rounded-md bg-accent px-4 py-2 text-sm font-semibold text-accent-fg hover:opacity-90 disabled:opacity-60"
          >
            {saving ? dict.common.saving : dict.common.save}
          </button>
          <button
            type="button"
            onClick={() => {
              setDraft(draftFromPlan(plan));
              setInvalid([]);
              setSaved(false);
              setError(null);
            }}
            className="rounded-md border border-line px-4 py-2 text-sm font-medium hover:bg-surface-2"
          >
            {dict.common.reset}
          </button>
        </div>
      </form>
    </Card>
  );
}

export function PlansView() {
  const { api } = useAuth();
  const { dict } = useI18n();
  const plans = useApiQuery("plans", (s) => api.plans(s));

  return (
    <>
      <PageHeader title={dict.plans.title} subtitle={dict.plans.subtitle} fetchedAt={plans.fetchedAt} />
      {plans.error ? (
        <ErrorState error={plans.error} onRetry={plans.reload} />
      ) : plans.loading && !plans.data ? (
        <LoadingState rows={6} />
      ) : !plans.data?.length ? (
        <EmptyState />
      ) : (
        <div className="grid grid-cols-1 gap-4 2xl:grid-cols-2">
          {[...plans.data]
            .sort((a, b) => (a.sort_order ?? 0) - (b.sort_order ?? 0))
            .map((plan) => (
              <PlanEditor
                key={plan.key}
                plan={plan}
                onSaved={(updated) => {
                  if (updated) {
                    plans.setData((prev) => prev?.map((p) => (p.key === updated.key ? updated : p)));
                  } else {
                    plans.reload();
                  }
                }}
              />
            ))}
        </div>
      )}
    </>
  );
}
