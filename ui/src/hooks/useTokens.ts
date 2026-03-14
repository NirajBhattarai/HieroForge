"use client";

import { useState, useEffect } from "react";
import { registerTokens } from "@/lib/tokenRegistry";

export interface DynamicToken {
  address: string;
  symbol: string;
  name: string;
  decimals: number;
  logoUrl?: string;
  isHts?: boolean;
}

/**
 * Fetches the token list from /api/tokens (backed by DynamoDB).
 * Also populates the global token registry so getTokenAddress / getTokenDecimals work.
 * Returns the list, a loading flag, and a refetch function.
 */
export function useTokens() {
  const [tokens, setTokens] = useState<DynamicToken[]>([]);
  const [loading, setLoading] = useState(true);

  const fetchTokens = () => {
    setLoading(true);
    fetch("/api/tokens")
      .then((res) => (res.ok ? res.json() : []))
      .then((data: DynamicToken[]) => {
        setTokens(data);
        // Populate the global registry so getTokenAddress/getTokenDecimals work everywhere
        registerTokens(
          data.map((t) => ({
            address: t.address,
            symbol: t.symbol,
            decimals: t.decimals,
            name: t.name,
          })),
        );
      })
      .catch(() => setTokens([]))
      .finally(() => setLoading(false));
  };

  useEffect(() => {
    fetchTokens();
  }, []);

  return { tokens, loading, refetch: fetchTokens };
}
