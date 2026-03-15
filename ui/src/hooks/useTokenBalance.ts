"use client";

import { useState, useEffect, useRef, useCallback } from "react";
import { formatUnits } from "viem";

/**
 * HTS balance via Mirror Node (same data source as hedera-hts-demo's AccountInfoQuery).
 * GET /api/v1/accounts/{id} returns balance.tokens[] with token_id and balance — no SDK or RPC.
 */

const MIRROR_NODE_TESTNET = "https://testnet.mirrornode.hedera.com";

/** Convert Hedera token_id "0.0.XXXXX" to HTS EVM address 0x0000...hex(num) for matching. */
function tokenIdToAddress(tokenId: string): string {
  const m = String(tokenId)
    .trim()
    .match(/^(\d+)\.(\d+)\.(\d+)$/);
  if (!m) return "";
  const num = BigInt(m[3]!);
  return ("0x" + num.toString(16).padStart(40, "0")).toLowerCase();
}

/** Normalize token address for comparison (lowercase, 0x prefix). */
function normalizeTokenAddress(addr: string): string {
  const a = addr.trim().replace(/^0x/, "").toLowerCase();
  return a.length === 40 ? "0x" + a : "";
}

interface MirrorAccountBalance {
  balance?: number;
  timestamp?: string;
  tokens?: Array<{ token_id?: string; balance?: number | string }>;
}

/**
 * Fetch HTS token balance via Hedera Mirror Node (same concept as hedera-hts-demo AccountInfoQuery).
 * Account can be EVM address or Hedera account ID (0.0.X). No RPC or SDK required.
 */
export function useTokenBalance(
  tokenAddress: string | undefined,
  ownerAddress: string | undefined | null,
  decimals: number,
): {
  balanceFormatted: string;
  balanceWei: bigint;
  loading: boolean;
  error: string | null;
  refetch: () => void;
} {
  const [balanceWei, setBalanceWei] = useState<bigint>(0n);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [refreshCounter, setRefreshCounter] = useState(0);
  const refetch = useCallback(() => setRefreshCounter((c) => c + 1), []);

  const isTokenValid =
    !!tokenAddress && /^0x[0-9a-f]{40}$/i.test(tokenAddress.trim());
  const isOwnerValid =
    !!ownerAddress &&
    (/^0x[0-9a-f]{40}$/i.test(ownerAddress.trim()) ||
      /^\d+\.\d+\.\d+$/.test(ownerAddress.trim()));

  useEffect(() => {
    if (!isTokenValid || !isOwnerValid) {
      setBalanceWei(0n);
      setLoading(false);
      setError(null);
      return;
    }

    let cancelled = false;
    setLoading(true);
    setError(null);

    const token = normalizeTokenAddress(tokenAddress!.trim());
    const owner = ownerAddress!.trim();
    // Mirror Node: use Hedera account ID (0.0.X) when possible; otherwise lowercase EVM. 404 → 0 balance.
    const ownerForUrl = owner.startsWith("0x")
      ? "0x" + owner.replace(/^0x/, "").toLowerCase()
      : owner;
    const url = `${MIRROR_NODE_TESTNET}/api/v1/accounts/${encodeURIComponent(ownerForUrl)}?transactions=false`;

    fetch(url)
      .then((res) => {
        if (cancelled)
          return Promise.resolve(
            null as { balance?: MirrorAccountBalance } | null,
          );
        if (res.status === 404) return Promise.resolve(null);
        return res.json() as Promise<{
          balance?: MirrorAccountBalance;
          account?: string;
        } | null>;
      })
      .then((data) => {
        if (cancelled) return;
        if (!data) {
          setBalanceWei(0n);
          if (typeof console !== "undefined" && console.log) {
            console.log("[HTS balance] Mirror Node", {
              token: tokenAddress,
              owner,
              balanceWei: "0",
              balanceFormatted: "0",
              source: "mirror",
              note: "account not found or 404",
            });
          }
          return;
        }
        const balanceBlock = data.balance;
        const tokens = balanceBlock?.tokens;
        if (!Array.isArray(tokens)) {
          setBalanceWei(0n);
          if (typeof console !== "undefined" && console.log) {
            console.log("[HTS balance] Mirror Node", {
              token: tokenAddress,
              owner,
              balanceWei: "0",
              balanceFormatted: "0",
              source: "mirror",
            });
          }
          return;
        }
        const tokenNorm = token.toLowerCase();
        for (const t of tokens) {
          const tid = t?.token_id != null ? String(t.token_id) : "";
          if (!tid) continue;
          const addr = tokenIdToAddress(tid);
          if (addr && addr === tokenNorm) {
            const raw =
              t.balance != null
                ? typeof t.balance === "string"
                  ? BigInt(t.balance)
                  : BigInt(Number(t.balance))
                : 0n;
            setBalanceWei(raw);
            if (typeof console !== "undefined" && console.log) {
              const formatted = formatUnits(raw, decimals);
              console.log("[HTS balance] Mirror Node", {
                token: tokenAddress,
                owner,
                balanceWei: String(raw),
                balanceFormatted: formatted,
                decimals,
                source: "mirror",
              });
            }
            return;
          }
        }
        setBalanceWei(0n);
        if (typeof console !== "undefined" && console.log) {
          console.log("[HTS balance] Mirror Node", {
            token: tokenAddress,
            owner,
            balanceWei: "0",
            balanceFormatted: "0",
            source: "mirror",
          });
        }
      })
      .catch((err) => {
        if (!cancelled) {
          setBalanceWei(0n);
          setError(
            err instanceof Error ? err.message : "Failed to fetch balance",
          );
          if (typeof console !== "undefined" && console.warn) {
            console.warn("[HTS balance] Mirror Node failed", {
              token: tokenAddress,
              owner,
              error: err,
            });
          }
        }
      })
      .finally(() => {
        if (!cancelled) setLoading(false);
      });

    return () => {
      cancelled = true;
    };
  }, [
    tokenAddress,
    ownerAddress,
    isTokenValid,
    isOwnerValid,
    decimals,
    refreshCounter,
  ]);

  const balanceFormatted =
    loading || error
      ? loading
        ? "…"
        : "0"
      : (() => {
          try {
            return formatUnits(balanceWei, decimals);
          } catch {
            return "0";
          }
        })();

  return { balanceFormatted, balanceWei, loading, error, refetch };
}
