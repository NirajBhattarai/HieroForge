"use client";

import { useState, useEffect, useCallback } from "react";

export interface Position {
  positionId: string;
  tokenId: number;
  poolId: string;
  owner: string;
  tickLower: number;
  tickUpper: number;
  liquidity: string;
  currency0: string;
  currency1: string;
  symbol0?: string;
  symbol1?: string;
  fee: number;
  tickSpacing: number;
  decimals0?: number;
  decimals1?: number;
  hooks?: string;
  hookName?: string;
  createdAt?: string;
}

/**
 * Fetches positions for a given owner from /api/positions.
 * Pass the owner's EVM address (lowercase hex).
 */
export function usePositions(owner: string | null) {
  const [positions, setPositions] = useState<Position[]>([]);
  const [loading, setLoading] = useState(true);

  const fetchPositions = useCallback(() => {
    if (!owner) {
      setPositions([]);
      setLoading(false);
      return;
    }
    setLoading(true);
    fetch(`/api/positions?owner=${encodeURIComponent(owner)}`)
      .then((res) => (res.ok ? res.json() : []))
      .then((data: Position[]) => setPositions(data))
      .catch(() => setPositions([]))
      .finally(() => setLoading(false));
  }, [owner]);

  useEffect(() => {
    fetchPositions();
  }, [fetchPositions]);

  return { positions, loading, refetch: fetchPositions };
}
