"use client";

import { useState, useEffect } from "react";
import { TokenPairIcon } from "./TokenIcon";
import { Badge } from "@/components/ui/Badge";
import type { PoolInfo } from "./PoolPositions";

function shortenAddr(addr: string): string {
  if (!addr || addr.length < 10) return addr;
  return `${addr.slice(0, 6)}...${addr.slice(-4)}`;
}

interface ExploreProps {
  onSelectPool: (pool: PoolInfo) => void;
}

export function Explore({ onSelectPool }: ExploreProps) {
  const [pools, setPools] = useState<PoolInfo[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [search, setSearch] = useState("");

  useEffect(() => {
    let cancelled = false;
    setLoading(true);
    setError(null);
    fetch("/api/pools")
      .then((res) => {
        if (!res.ok) throw new Error("Failed to load pools");
        return res.json();
      })
      .then(
        (
          data: Array<{
            poolId: string;
            currency0: string;
            currency1: string;
            fee: number;
            tickSpacing: number;
            symbol0?: string;
            symbol1?: string;
            decimals0?: number;
            decimals1?: number;
          }>,
        ) => {
          if (cancelled) return;
          setPools(
            data.map((p) => ({
              poolId: p.poolId,
              pair: [
                p.symbol0 ?? shortenAddr(p.currency0),
                p.symbol1 ?? shortenAddr(p.currency1),
              ].join(" / "),
              tickSpacing: p.tickSpacing,
              fee: p.fee,
              feeLabel: (p.fee / 10000).toFixed(2) + "%",
              symbol0: p.symbol0 ?? "",
              symbol1: p.symbol1 ?? "",
              currency0: p.currency0,
              currency1: p.currency1,
              decimals0: p.decimals0,
              decimals1: p.decimals1,
            })),
          );
        },
      )
      .catch((err) => {
        if (!cancelled)
          setError(err instanceof Error ? err.message : "Failed to load pools");
      })
      .finally(() => {
        if (!cancelled) setLoading(false);
      });
    return () => {
      cancelled = true;
    };
  }, []);

  const q = search.trim().toLowerCase();
  const filtered = q
    ? pools.filter(
        (p) =>
          p.pair.toLowerCase().includes(q) ||
          p.symbol0.toLowerCase().includes(q) ||
          p.symbol1.toLowerCase().includes(q) ||
          p.poolId.toLowerCase().includes(q),
      )
    : pools;

  return (
    <div className="max-w-4xl mx-auto px-4 py-8 animate-[fadeIn_0.3s_ease-out]">
      {/* Header */}
      <div className="mb-6">
        <h1 className="text-2xl font-bold text-text-primary mb-1">Top pools</h1>
        <p className="text-sm text-text-tertiary">
          Browse all liquidity pools. Select a pool to add liquidity.
        </p>
      </div>

      {/* Search */}
      <div className="relative mb-6">
        <svg
          className="absolute left-4 top-1/2 -translate-y-1/2 text-text-tertiary"
          width="18"
          height="18"
          viewBox="0 0 24 24"
          fill="none"
          stroke="currentColor"
          strokeWidth="2"
          strokeLinecap="round"
          strokeLinejoin="round"
        >
          <circle cx="11" cy="11" r="8" />
          <line x1="21" y1="21" x2="16.65" y2="16.65" />
        </svg>
        <input
          type="search"
          className="w-full pl-11 pr-4 py-3 bg-surface-1 border border-border rounded-[--radius-lg] text-text-primary placeholder:text-text-tertiary text-sm focus:outline-none focus:border-border-focus transition-colors"
          placeholder="Search tokens and pools"
          value={search}
          onChange={(e) => setSearch(e.target.value)}
          aria-label="Search pools"
        />
      </div>

      {/* Error */}
      {error && (
        <div className="flex items-center gap-2 px-4 py-3 rounded-[--radius-md] bg-error-muted text-error text-sm mb-4">
          {error}
        </div>
      )}

      {/* Loading */}
      {loading ? (
        <div className="space-y-3">
          {[...Array(5)].map((_, i) => (
            <div key={i} className="h-16 skeleton rounded-[--radius-lg]" />
          ))}
        </div>
      ) : filtered.length === 0 ? (
        /* Empty state */
        <div className="flex flex-col items-center justify-center py-20 text-center">
          <div className="w-16 h-16 rounded-full bg-surface-2 flex items-center justify-center mb-4">
            <svg
              width="28"
              height="28"
              viewBox="0 0 24 24"
              fill="none"
              stroke="currentColor"
              strokeWidth="1.5"
              className="text-text-tertiary"
            >
              <circle cx="11" cy="11" r="8" />
              <line x1="21" y1="21" x2="16.65" y2="16.65" />
            </svg>
          </div>
          <p className="text-text-secondary font-medium mb-1">
            {q ? "No pools match your search" : "No pools yet"}
          </p>
          <p className="text-xs text-text-tertiary">
            {q
              ? "Try a different search term."
              : "Create a pool from the Pool tab."}
          </p>
        </div>
      ) : (
        /* Table */
        <div className="bg-surface-1 border border-border rounded-[--radius-lg] overflow-hidden">
          {/* Table header */}
          <div className="grid grid-cols-[1fr_auto_auto_auto] gap-4 px-5 py-3 text-xs font-medium text-text-tertiary border-b border-border">
            <span>Pool</span>
            <span className="w-20 text-right">Fee</span>
            <span className="w-20 text-right hidden sm:block">TVL</span>
            <span className="w-20 text-right hidden sm:block">APR</span>
          </div>

          {/* Rows */}
          {filtered.map((pool) => (
            <button
              key={pool.poolId}
              type="button"
              className="w-full grid grid-cols-[1fr_auto_auto_auto] gap-4 items-center px-5 py-3.5 text-left hover:bg-surface-2 transition-colors duration-150 border-b border-border last:border-b-0 cursor-pointer"
              onClick={() => onSelectPool(pool)}
            >
              <div className="flex items-center gap-3 min-w-0">
                <TokenPairIcon
                  symbol0={pool.symbol0 || "?"}
                  symbol1={pool.symbol1 || "?"}
                  size={28}
                />
                <div className="flex flex-col min-w-0">
                  <span className="text-sm font-semibold text-text-primary truncate">
                    {pool.pair}
                  </span>
                  <span className="text-xs text-text-tertiary">v4</span>
                </div>
              </div>
              <div className="w-20 text-right">
                <Badge>{pool.feeLabel}</Badge>
              </div>
              <span className="w-20 text-right text-sm text-text-tertiary hidden sm:block">
                —
              </span>
              <span className="w-20 text-right text-sm text-text-tertiary hidden sm:block">
                —
              </span>
            </button>
          ))}
        </div>
      )}
    </div>
  );
}
