"use client";

import type { ReactNode } from "react";
import { LiveApiBadge } from "./LiveApiBadge";

export function PageHeader({
  title,
  subtitle,
  fetchedAt,
  actions,
}: {
  title: string;
  subtitle?: string;
  fetchedAt?: Date | null;
  actions?: ReactNode;
}) {
  return (
    <header className="mb-5 flex flex-wrap items-end justify-between gap-3">
      <div className="min-w-0">
        <h1 className="text-2xl font-bold">{title}</h1>
        {subtitle ? <p className="mt-1 text-sm text-muted">{subtitle}</p> : null}
        <div className="mt-2">
          <LiveApiBadge fetchedAt={fetchedAt} />
        </div>
      </div>
      {actions ? <div className="flex flex-wrap items-center gap-2">{actions}</div> : null}
    </header>
  );
}
