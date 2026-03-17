"use client";

import { useState, useEffect, useCallback } from "react";
import {
  fetchPositionOnChain,
  type PositionOnChain,
} from "@/lib/positionOnChain";

export interface UsePositionOnChainResult {
  data: PositionOnChain | null;
  loading: boolean;
  error: string | null;
  refetch: () => Promise<void>;
}

/**
 * Fetch position from on-chain (PositionManager) when tokenId is set.
 * Use for display and for remove/burn modals so liquidity and ticks are from chain.
 */
export function usePositionOnChain(
  tokenId: number | string | null | undefined,
  options?: { enabled?: boolean },
): UsePositionOnChainResult {
  const enabled = options?.enabled ?? true;
  const [data, setData] = useState<PositionOnChain | null>(null);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const refetch = useCallback(async () => {
    if (tokenId == null || tokenId === "" || !enabled) {
      setData(null);
      setError(null);
      return;
    }
    setLoading(true);
    setError(null);
    try {
      const result = await fetchPositionOnChain(String(tokenId));
      setData(result);
    } catch (e) {
      setError(e instanceof Error ? e.message : "Failed to load position");
      setData(null);
    } finally {
      setLoading(false);
    }
  }, [tokenId, enabled]);

  useEffect(() => {
    if (tokenId == null || tokenId === "" || !enabled) {
      setData(null);
      setError(null);
      setLoading(false);
      return;
    }
    refetch();
  }, [tokenId, enabled, refetch]);

  return { data, loading, error, refetch };
}
