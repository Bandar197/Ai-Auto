import type { Dictionary } from "@/i18n/ar";
import { isKnownErrorCode, type ApiError } from "@/lib/errors";

/** Localised text for an ApiError; falls back to the server's message. */
export function errorMessage(dict: Dictionary, err: ApiError): string {
  if (err.message === "not_staff") return dict.auth.notStaff;
  if (isKnownErrorCode(err.code)) return dict.apiErrors[err.code];
  return err.message || dict.apiErrors.unknown_error;
}
