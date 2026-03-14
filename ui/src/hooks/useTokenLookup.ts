"use client";

import { useState, useEffect, useRef } from "react";

export interface ResolvedToken {
  address: string;
  symbol: string;
  name: string;
  decimals: number;
  isHts?: boolean;
  hederaId?: string;
}

/**
 * Given a token address string, resolves its on-chain metadata (symbol, name, decimals)
 * via /api/tokens/lookup. Auto-saves the token to DynamoDB.
 * Returns { token, loading, error }.
 */
/** Convert Hedera native ID (0.0.XXXXX) to EVM address. */
function hederaIdToEvmAddress(id: string): string | null {
  const match = id.match(/^(\d+)\.(\d+)\.(\d+)$/);
  if (!match) return null;
  const entityNum = BigInt(match[3]!);
  return "0x" + entityNum.toString(16).padStart(40, "0");
}

export function useTokenLookup(address: string) {
  const [token, setToken] = useState<ResolvedToken | null>(null);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const lastAddr = useRef("");

  useEffect(() => {
    let trimmed = address.trim();

    // Auto-convert Hedera native IDs (0.0.XXXXX) to EVM hex
    const evmFromHedera = hederaIdToEvmAddress(trimmed);
    if (evmFromHedera) trimmed = evmFromHedera;
    trimmed = trimmed.toLowerCase();

    // Must be a valid 0x address (42 chars)
    if (!trimmed || !/^0x[0-9a-f]{40}$/i.test(trimmed)) {
      setToken(null);
      setError(null);
      setLoading(false);
      return;
    }

    // Don't re-fetch if same address
    if (trimmed === lastAddr.current && token?.address === trimmed) return;
    lastAddr.current = trimmed;

    let cancelled = false;
    setLoading(true);
    setError(null);

    const base = typeof window !== "undefined" ? window.location.origin : "";
    const lookupUrl = `${base}/api/tokens/lookup?address=${encodeURIComponent(trimmed)}`;

    const timer = setTimeout(() => {
      fetch(lookupUrl)
        .then(async (res) => {
          if (res.status === 404) {
            if (!cancelled) {
              setToken(null);
              setError("Token not found");
            }
            return null;
          }
          if (!res.ok) {
            const body = await res.json().catch(() => null);
            throw new Error(body?.error ?? "Lookup failed");
          }
          return res.json() as Promise<ResolvedToken>;
        })
        .then((data) => {
          if (cancelled) return;
          if (data) {
            setToken(data);
            setError(null);
          }
        })
        .catch((err) => {
          if (!cancelled) {
            setToken(null);
            setError(err instanceof Error ? err.message : "Lookup failed");
          }
        })
        .finally(() => {
          if (!cancelled) setLoading(false);
        });
    }, 400);

    return () => {
      cancelled = true;
      clearTimeout(timer);
    };
  }, [address]);

  return { token, loading, error };
}
