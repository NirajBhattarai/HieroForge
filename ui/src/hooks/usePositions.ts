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
 * Fetches positions for one or more owners from /api/positions.
 * Pass EVM address(es) (lowercase hex). If multiple are provided, results are merged.
 */
export function usePositions(owners: string | string[] | null) {
  const [positions, setPositions] = useState<Position[]>([]);
  const [loading, setLoading] = useState(true);

  const fetchPositions = useCallback(() => {
    const ownerList = (
      Array.isArray(owners) ? owners : owners ? [owners] : []
    )
      .map((o) => o?.toLowerCase().trim())
      .filter(Boolean) as string[];
    const uniqueOwners = Array.from(new Set(ownerList));

    if (!uniqueOwners.length) {
      setPositions([]);
      setLoading(false);
      return;
    }
    setLoading(true);

    Promise.all(
      uniqueOwners.map((o) =>
        fetch(`/api/positions?owner=${encodeURIComponent(o)}`).then((res) =>
          res.ok ? (res.json() as Promise<Position[]>) : ([] as Position[]),
        ),
      ),
    )
      .then((lists) => {
        const merged = lists.flat();
        const byId = new Map<string, Position>();
        for (const p of merged) byId.set(String(p.positionId ?? p.tokenId), p);
        setPositions(Array.from(byId.values()));
      })
      .catch(() => setPositions([]))
      .finally(() => setLoading(false));
  }, [owners]);

  useEffect(() => {
    fetchPositions();
  }, [fetchPositions]);

  return { positions, loading, refetch: fetchPositions };
}
