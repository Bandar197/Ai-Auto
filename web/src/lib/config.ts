export const DEFAULT_API_BASE_URL = "http://localhost:8000/api/v1";

/**
 * Public API base URL used by the browser. `NEXT_PUBLIC_*` values are inlined
 * at build time, so set it before `next build` (see `.env.example`).
 */
export const API_BASE_URL: string = (
  process.env.NEXT_PUBLIC_API_BASE_URL || DEFAULT_API_BASE_URL
).replace(/\/+$/, "");

/** Same-origin route handler that owns the httpOnly refresh-token cookie. */
export const SESSION_ENDPOINT = "/api/session";

/** Roles allowed into the admin dashboard (see `users.platform_role`). */
export const STAFF_ROLES = ["support", "admin", "super_admin"] as const;
