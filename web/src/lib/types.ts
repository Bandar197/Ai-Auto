/** Response shapes from docs/API.md (Auth + Admin sections). */

export type DataMode = "live" | "demo" | "replay";
export type PlatformRole = "user" | "support" | "admin" | "super_admin";
export type UserStatus = "active" | "suspended" | "pending_deletion" | "deleted";

export interface User {
  id: string;
  email: string;
  full_name: string | null;
  phone: string | null;
  locale: "ar" | "en";
  platform_role: PlatformRole;
  mfa_enabled: boolean;
  created_at: string;
}

export interface Tokens {
  access_token: string;
  refresh_token: string;
  token_type: "bearer";
  expires_in: number;
}

/** What `/api/session` returns to the browser (never the refresh token). */
export interface BrowserSession {
  access_token: string;
  token_type: "bearer";
  expires_in: number;
  user?: User;
}

export interface Page<T> {
  items: T[];
  total: number;
  limit: number;
  offset: number;
}

export interface OverviewStats {
  users_total: number;
  users_active_30d: number;
  vehicles_total: number;
  devices_total: number;
  sessions_today: number;
  sessions_month: number;
  sessions_by_mode: Record<DataMode, number>;
  /** Ratio 0..1 */
  connection_success_rate_30d: number | null;
  /** Ratio 0..1 */
  diagnosis_confirmed_rate: number | null;
  active_subscriptions_by_plan: Record<string, number>;
  revenue_month_sar: number;
  cancelled_subscriptions_month: number;
  workshops_total: number;
  suppliers_total: number;
  orders_month: number;
  errors_24h: number;
  ai_usage_month: {
    requests: number;
    input_tokens: number;
    output_tokens: number;
    cost_usd: number;
  };
}

export type TimeseriesMetric = "sessions" | "connections" | "signups" | "revenue";

export interface TimeseriesPoint {
  date: string;
  value: number;
  success?: number;
  failure?: number;
}

export interface Timeseries {
  metric: TimeseriesMetric;
  points: TimeseriesPoint[];
}

export interface TopDtc {
  code: string;
  count: number;
  description_en: string | null;
  description_ar: string | null;
}

export interface AdminUser {
  id: string;
  email: string;
  full_name: string | null;
  platform_role: PlatformRole;
  status: UserStatus;
  created_at: string;
  last_login_at: string | null;
  vehicles: number;
  sessions: number;
}

export interface AdminUserPatch {
  status?: UserStatus;
  platform_role?: PlatformRole;
}

/** Mirrors `automind.subscription_plans`. */
export interface Plan {
  key: string;
  name_en: string;
  name_ar: string;
  audience?: "individual" | "business";
  price_monthly: number | string | null;
  price_yearly: number | string | null;
  currency?: string;
  features: Record<string, unknown>;
  limits: Record<string, unknown>;
  active: boolean;
  sort_order?: number;
}

export interface PlanPatch {
  price_monthly?: number | null;
  price_yearly?: number | null;
  active?: boolean;
  features?: Record<string, unknown>;
  limits?: Record<string, unknown>;
}

/** Mirrors `automind.system_errors`. */
export interface SystemError {
  id: number | string;
  occurred_at: string;
  component: string;
  error_code: string;
  message: string | null;
  request_id: string | null;
  user_id?: string | null;
  context?: Record<string, unknown>;
}

/** Mirrors `automind.audit_logs`. */
export interface AuditLog {
  id: number | string;
  occurred_at: string;
  actor_user_id: string | null;
  actor_org_id?: string | null;
  action: string;
  entity_type: string | null;
  entity_id: string | null;
  outcome: "success" | "failure" | "denied" | string;
  ip_address: string | null;
  user_agent?: string | null;
  request_id: string | null;
  metadata?: Record<string, unknown>;
}

export type ExportDataset = "users" | "sessions" | "connections" | "top-dtcs";

/** Trust tiers for an ECU access profile (mirrors the DB check constraint). */
export type DiagProfileStatus =
  | "unverified"
  | "verified_vehicle_trace"
  | "licensed_oem"
  | "standard_specification"
  | "demo_only"
  | "rejected";

/** A verification decision carries a status other than `unverified`. */
export type DiagDecisionStatus = Exclude<DiagProfileStatus, "unverified">;

/** Mirrors `automind.diag_ecu_profiles` (docs/API.md, diag section). */
export interface DiagEcuProfile {
  id: string;
  make: string;
  model: string | null;
  market: string | null;
  variant: string | null;
  year_from: number | null;
  year_to: number | null;
  controller_id: string | null;
  protocol: string | null;
  tx_header: string | null;
  rx_header: string | null;
  read_request: string | null;
  id_bits: 11 | 29 | null;
  category: string | null;
  verification_status: DiagProfileStatus;
  source_type: string | null;
  source_reference: string | null;
  model_year_range: string | null;
  notes: string | null;
  submitted_by: string | null;
  reviewed_by: string | null;
  reviewed_at: string | null;
  version: number;
  created_at: string;
  updated_at: string;
}

/** Decision recorded when approving or rejecting a profile (always with evidence). */
export interface DiagProfileReview {
  verification_status: DiagDecisionStatus;
  source_type: string;
  source_reference: string;
}
