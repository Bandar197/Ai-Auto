"use client";

import { useCallback, useEffect, useRef, useState } from "react";
import { ApiError, isApiError } from "@/lib/errors";

export interface QueryState<T> {
  data: T | undefined;
  error: ApiError | null;
  loading: boolean;
  /** When the last successful response arrived. */
  fetchedAt: Date | null;
  reload(): void;
  /** Replace cached data locally (e.g. after a PATCH). */
  setData(updater: (prev: T | undefined) => T | undefined): void;
}

function toApiError(err: unknown): ApiError {
  if (isApiError(err)) return err;
  return new ApiError({
    status: 0,
    code: "unknown_error",
    message: err instanceof Error ? err.message : String(err),
  });
}

/**
 * Run `fetcher` whenever `key` changes; aborts stale requests. Data is only
 * ever what the API returned — nothing is synthesised on failure.
 */
export function useApiQuery<T>(
  key: string,
  fetcher: (signal: AbortSignal) => Promise<T>,
  enabled = true,
): QueryState<T> {
  const [data, setDataState] = useState<T | undefined>(undefined);
  const [error, setError] = useState<ApiError | null>(null);
  const [loading, setLoading] = useState<boolean>(enabled);
  const [fetchedAt, setFetchedAt] = useState<Date | null>(null);
  const [nonce, setNonce] = useState(0);
  const fetcherRef = useRef(fetcher);
  useEffect(() => {
    fetcherRef.current = fetcher;
  });

  useEffect(() => {
    if (!enabled) return;
    const controller = new AbortController();
    // eslint-disable-next-line react-hooks/set-state-in-effect -- start of an async fetch cycle
    setLoading(true);
    setError(null);
    fetcherRef
      .current(controller.signal)
      .then((result) => {
        if (controller.signal.aborted) return;
        setDataState(result);
        setFetchedAt(new Date());
      })
      .catch((err: unknown) => {
        if (controller.signal.aborted) return;
        setError(toApiError(err));
      })
      .finally(() => {
        if (!controller.signal.aborted) setLoading(false);
      });
    return () => controller.abort();
  }, [key, nonce, enabled]);

  const reload = useCallback(() => setNonce((n) => n + 1), []);
  const setData = useCallback(
    (updater: (prev: T | undefined) => T | undefined) => setDataState(updater),
    [],
  );

  return { data, error, loading, fetchedAt, reload, setData };
}
