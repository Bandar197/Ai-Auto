"use client";

import { useRouter } from "next/navigation";
import { useEffect, useRef, useState, type FormEvent } from "react";
import { useAuth } from "@/components/auth/AuthProvider";
import { LanguageSwitcher } from "@/components/layout/LanguageSwitcher";
import { errorMessage } from "@/components/ui/errorMessage";
import { useI18n } from "@/i18n/I18nProvider";
import { localePath } from "@/i18n/config";
import { ApiError, isApiError } from "@/lib/errors";

export function LoginView() {
  const { state, login } = useAuth();
  const { dict, locale } = useI18n();
  const router = useRouter();
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [totp, setTotp] = useState("");
  const [mfaStep, setMfaStep] = useState(false);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<ApiError | null>(null);
  const totpRef = useRef<HTMLInputElement>(null);

  useEffect(() => {
    if (state.status === "authenticated") router.replace(localePath(locale));
  }, [state.status, router, locale]);

  useEffect(() => {
    if (mfaStep) totpRef.current?.focus();
  }, [mfaStep]);

  async function onSubmit(e: FormEvent<HTMLFormElement>) {
    e.preventDefault();
    setBusy(true);
    setError(null);
    try {
      await login({ email: email.trim(), password, totp_code: mfaStep ? totp.trim() : undefined });
    } catch (err) {
      const apiErr = isApiError(err) ? err : new ApiError({ status: 0, code: "unknown_error", message: String(err) });
      if (apiErr.isMfaRequired) {
        // First 403 mfa_required just reveals the TOTP field; a second one means the code was wrong/missing.
        if (mfaStep) setError(apiErr);
        setMfaStep(true);
      } else {
        setError(apiErr);
      }
    } finally {
      setBusy(false);
    }
  }

  const notice =
    state.status !== "unauthenticated"
      ? null
      : state.reason === "not_staff"
        ? dict.auth.notStaff
        : state.reason === "expired"
          ? dict.apiErrors.unauthorized
          : null;
  const input =
    "mt-1 block w-full rounded-md border border-line bg-surface px-3 py-2 text-base text-fg placeholder:text-muted";

  return (
    <main className="flex min-h-screen items-center justify-center px-4 py-10">
      <div className="w-full max-w-sm">
        <div className="mb-6 flex items-center justify-between">
          <p className="text-lg font-bold">
            {dict.nav.brand} <span className="text-sm font-normal text-muted">· {dict.nav.console}</span>
          </p>
          <LanguageSwitcher />
        </div>
        <div className="rounded-xl border border-line bg-surface p-6 shadow-sm">
          <h1 className="text-xl font-bold">{dict.auth.title}</h1>
          <p className="mt-1 text-sm text-muted">{dict.auth.subtitle}</p>

          {notice ? (
            <p role="alert" className="mt-4 rounded-md border border-warning/40 bg-warning-soft p-3 text-sm text-warning">
              {notice}
            </p>
          ) : null}

          <form className="mt-5 space-y-4" onSubmit={onSubmit}>
            <div>
              <label htmlFor="email" className="block text-sm font-medium">
                {dict.auth.email}
              </label>
              <input
                id="email"
                name="email"
                type="email"
                autoComplete="username"
                required
                dir="ltr"
                value={email}
                onChange={(e) => setEmail(e.target.value)}
                className={input}
              />
            </div>
            <div>
              <label htmlFor="password" className="block text-sm font-medium">
                {dict.auth.password}
              </label>
              <input
                id="password"
                name="password"
                type="password"
                autoComplete="current-password"
                required
                dir="ltr"
                value={password}
                onChange={(e) => setPassword(e.target.value)}
                className={input}
              />
            </div>

            {mfaStep ? (
              <div>
                <p role="status" className="mb-2 rounded-md border border-accent/40 bg-accent-soft p-3 text-sm text-accent">
                  {dict.auth.mfaRequired}
                </p>
                <label htmlFor="totp" className="block text-sm font-medium">
                  {dict.auth.totp}
                </label>
                <input
                  ref={totpRef}
                  id="totp"
                  name="totp"
                  type="text"
                  inputMode="numeric"
                  autoComplete="one-time-code"
                  pattern="[0-9]{6}"
                  maxLength={6}
                  required
                  dir="ltr"
                  aria-describedby="totp-hint"
                  value={totp}
                  onChange={(e) => setTotp(e.target.value.replace(/\D/g, ""))}
                  className={`${input} tabular tracking-[0.3em]`}
                />
                <p id="totp-hint" className="mt-1 text-xs text-muted">
                  {dict.auth.totpHint}
                </p>
              </div>
            ) : null}

            {error ? (
              <p role="alert" className="rounded-md border border-danger/40 bg-danger-soft p-3 text-sm text-danger">
                {errorMessage(dict, error)}
              </p>
            ) : null}

            <button
              type="submit"
              disabled={busy}
              aria-busy={busy}
              className="w-full rounded-md bg-accent px-4 py-2.5 font-semibold text-accent-fg hover:opacity-90 disabled:opacity-60"
            >
              {busy ? dict.auth.signingIn : dict.auth.signIn}
            </button>
          </form>
        </div>
      </div>
    </main>
  );
}
