"use client";

import { useState, useEffect, useCallback } from "react";
import { TokenIcon, TokenPairIcon } from "./TokenIcon";
import { Badge } from "@/components/ui/Badge";
import { Button } from "@/components/ui/Button";
import { useTokens } from "@/hooks/useTokens";

export interface PoolInfo {
  poolId: string;
  pair: string;
  tickSpacing: number;
  fee: number;
  feeLabel: string;
  symbol0: string;
  symbol1: string;
  currency0: string;
  currency1: string;
}

interface PoolPositionsProps {
  onCreatePosition: () => void;
  onSelectPool: (pool: PoolInfo) => void;
}

function shortenAddr(addr: string): string {
  if (!addr || addr.length < 10) return addr;
  return `${addr.slice(0, 6)}...${addr.slice(-4)}`;
}

export function PoolPositions({
  onCreatePosition,
  onSelectPool,
}: PoolPositionsProps) {
  const [pools, setPools] = useState<PoolInfo[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [loadPoolId, setLoadPoolId] = useState("");
  const [loadError, setLoadError] = useState<string | null>(null);
  const [showLoadById, setShowLoadById] = useState(false);
  const [infoBoxDismissed, setInfoBoxDismissed] = useState(false);

  const { tokens: dynamicTokens } = useTokens();
  const tokenByAddr = new Map(
    dynamicTokens.map((t) => [t.address.toLowerCase(), t]),
  );

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

  const handleLoadById = useCallback(async () => {
    const id = loadPoolId.trim();
    if (!id) {
      setLoadError("Enter a pool ID");
      return;
    }
    setLoadError(null);
    try {
      const res = await fetch(`/api/pools/${encodeURIComponent(id)}`);
      if (!res.ok) {
        if (res.status === 404) throw new Error("Pool not found in DynamoDB");
        throw new Error("Failed to load pool");
      }
      const p = (await res.json()) as {
        poolId: string;
        currency0: string;
        currency1: string;
        fee: number;
        tickSpacing: number;
        symbol0?: string;
        symbol1?: string;
      };
      const pool: PoolInfo = {
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
      };
      onSelectPool(pool);
    } catch (err) {
      setLoadError(err instanceof Error ? err.message : "Failed to load pool");
    }
  }, [loadPoolId, onSelectPool]);

  const hasPositions = pools.length > 0;
  const topPools = pools.slice(0, 8);

  return (
    <div className="max-w-6xl mx-auto px-4 py-8 animate-[fadeIn_0.3s_ease-out]">
      <div className="flex flex-col lg:flex-row gap-6">
        {/* Left column */}
        <div className="flex-1 min-w-0 space-y-5">
          {/* Rewards card */}
          <div className="bg-surface-1 border border-border rounded-[--radius-xl] overflow-hidden">
            <div className="h-1 bg-gradient-to-r from-accent to-purple-400" />
            <div className="p-5">
              <div className="flex items-center justify-between mb-3">
                <div className="flex items-center gap-3">
                  <div className="flex flex-col">
                    <span className="text-2xl font-bold text-text-primary">
                      0
                    </span>
                    <span className="flex items-center gap-1.5 text-sm text-text-secondary">
                      <TokenIcon symbol="FORGE" size={18} />
                      FORGE rewards earned
                    </span>
                  </div>
                </div>
                <Button variant="secondary" size="sm" disabled>
                  Collect rewards
                </Button>
              </div>
              <p className="text-xs text-text-tertiary">
                Eligible pools have token rewards so you can earn more.
              </p>
            </div>
          </div>

          {/* Your positions header */}
          <div className="flex items-center justify-between">
            <h2 className="text-lg font-semibold text-text-primary">
              Your positions
            </h2>
            <div className="flex items-center gap-2">
              <Button variant="primary" size="sm" onClick={onCreatePosition}>
                + New position
              </Button>
            </div>
          </div>

          {/* Filters */}
          <div className="flex items-center gap-2 flex-wrap">
            <button
              type="button"
              className="px-3 py-1.5 text-xs font-medium rounded-[--radius-full] bg-surface-2 text-text-secondary border border-border hover:border-border-hover transition-colors cursor-pointer"
            >
              Status
              <svg
                width="12"
                height="12"
                viewBox="0 0 24 24"
                fill="none"
                stroke="currentColor"
                strokeWidth="2.5"
                className="inline ml-1"
              >
                <polyline points="6 9 12 15 18 9" />
              </svg>
            </button>
            <button
              type="button"
              className="px-3 py-1.5 text-xs font-medium rounded-[--radius-full] bg-surface-2 text-text-secondary border border-border hover:border-border-hover transition-colors cursor-pointer"
            >
              Protocol
              <svg
                width="12"
                height="12"
                viewBox="0 0 24 24"
                fill="none"
                stroke="currentColor"
                strokeWidth="2.5"
                className="inline ml-1"
              >
                <polyline points="6 9 12 15 18 9" />
              </svg>
            </button>
            <button
              type="button"
              onClick={() => setShowLoadById(!showLoadById)}
              className="px-3 py-1.5 text-xs font-medium rounded-[--radius-full] bg-surface-2 text-text-secondary border border-border hover:border-border-hover transition-colors cursor-pointer ml-auto"
            >
              Load by ID
            </button>
          </div>

          {/* Load by pool ID */}
          {showLoadById && (
            <div className="bg-surface-1 border border-border rounded-[--radius-lg] p-4 animate-[fadeIn_0.15s_ease-out]">
              <div className="flex gap-2">
                <input
                  type="text"
                  className="flex-1 px-3 py-2 bg-surface-2 border border-border rounded-[--radius-md] text-sm text-text-primary placeholder:text-text-tertiary focus:outline-none focus:border-border-focus transition-colors"
                  placeholder="Pool ID (0x...)"
                  value={loadPoolId}
                  onChange={(e) => {
                    setLoadPoolId(e.target.value);
                    setLoadError(null);
                  }}
                  onKeyDown={(e) => e.key === "Enter" && handleLoadById()}
                />
                <Button variant="secondary" size="sm" onClick={handleLoadById}>
                  Load
                </Button>
              </div>
              {loadError && (
                <p className="text-xs text-error mt-2">{loadError}</p>
              )}
            </div>
          )}

          {/* Content */}
          {error && (
            <div className="flex items-center gap-2 px-4 py-3 rounded-[--radius-md] bg-error-muted text-error text-sm">
              {error}
            </div>
          )}

          {loading ? (
            <div className="space-y-3">
              {[...Array(3)].map((_, i) => (
                <div key={i} className="h-20 skeleton rounded-[--radius-lg]" />
              ))}
            </div>
          ) : !hasPositions ? (
            /* Empty state */
            <div className="bg-surface-1 border border-border rounded-[--radius-xl] flex flex-col items-center justify-center py-16 px-6">
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
                  <rect x="3" y="3" width="18" height="18" rx="2" />
                  <line x1="3" y1="9" x2="21" y2="9" />
                  <line x1="9" y1="21" x2="9" y2="9" />
                </svg>
              </div>
              <h3 className="text-base font-semibold text-text-primary mb-1">
                No positions
              </h3>
              <p className="text-sm text-text-tertiary text-center mb-6 max-w-xs">
                You don&apos;t have any liquidity positions. Create a new
                position to start earning fees and rewards.
              </p>
              <div className="flex gap-3">
                <Button
                  variant="secondary"
                  onClick={() => setShowLoadById(!showLoadById)}
                >
                  Explore pools
                </Button>
                <Button variant="primary" onClick={onCreatePosition}>
                  New position
                </Button>
              </div>
            </div>
          ) : (
            /* Position list */
            <div className="space-y-2">
              {pools.map((pool) => {
                const t0info = tokenByAddr.get(pool.currency0.toLowerCase());
                const t1info = tokenByAddr.get(pool.currency1.toLowerCase());
                return (
                  <button
                    key={pool.poolId}
                    type="button"
                    className="w-full flex items-center gap-4 p-4 bg-surface-1 border border-border rounded-[--radius-lg] hover:border-border-hover hover:bg-surface-2 transition-all duration-150 cursor-pointer text-left"
                    onClick={() => onSelectPool(pool)}
                  >
                    <TokenPairIcon
                      symbol0={pool.symbol0 || "?"}
                      symbol1={pool.symbol1 || "?"}
                      size={32}
                    />
                    <div className="flex flex-col min-w-0 flex-1">
                      <span className="text-sm font-semibold text-text-primary">
                        {pool.pair}
                      </span>
                      <span className="text-xs text-text-tertiary">
                        v4 · {pool.feeLabel}
                        {(t0info || t1info) && (
                          <>
                            {" "}
                            ·{" "}
                            {t0info
                              ? t0info.name
                              : shortenAddr(pool.currency0)}{" "}
                            /{" "}
                            {t1info ? t1info.name : shortenAddr(pool.currency1)}
                          </>
                        )}
                      </span>
                    </div>
                    <div className="flex flex-col items-end shrink-0">
                      <span className="text-sm text-text-tertiary">— APR</span>
                      <span className="text-xs text-text-disabled font-mono">
                        {pool.poolId.slice(0, 10)}...
                      </span>
                    </div>
                  </button>
                );
              })}
            </div>
          )}

          {/* Info box */}
          {!infoBoxDismissed && (
            <div className="flex items-start gap-3 p-4 bg-surface-1 border border-border rounded-[--radius-lg]">
              <span className="w-5 h-5 rounded-full bg-accent-muted text-accent flex items-center justify-center shrink-0 text-xs font-bold">
                i
              </span>
              <div className="flex-1 min-w-0">
                <p className="text-sm font-medium text-text-primary">
                  Looking for your closed positions?
                </p>
                <p className="text-xs text-text-tertiary mt-0.5">
                  You can see them by using the filter at the top of the page.
                </p>
              </div>
              <button
                type="button"
                onClick={() => setInfoBoxDismissed(true)}
                className="shrink-0 p-1 rounded-[--radius-sm] text-text-tertiary hover:text-text-primary hover:bg-surface-3 transition-colors cursor-pointer"
                aria-label="Dismiss"
              >
                <svg
                  width="14"
                  height="14"
                  viewBox="0 0 24 24"
                  fill="none"
                  stroke="currentColor"
                  strokeWidth="2"
                >
                  <line x1="18" y1="6" x2="6" y2="18" />
                  <line x1="6" y1="6" x2="18" y2="18" />
                </svg>
              </button>
            </div>
          )}

          {/* Footer link */}
          <p className="text-xs text-text-tertiary text-center">
            Some v2 positions aren&apos;t displayed automatically.{" "}
            <button
              type="button"
              className="text-accent hover:text-accent-hover underline cursor-pointer"
              onClick={() => setShowLoadById(true)}
            >
              Load pool by ID
            </button>
          </p>
        </div>

        {/* Right sidebar */}
        <aside className="w-full lg:w-80 shrink-0 space-y-5">
          {/* Top pools */}
          <div className="bg-surface-1 border border-border rounded-[--radius-xl] p-5">
            <h3 className="text-sm font-semibold text-text-primary mb-4">
              Top pools by TVL
            </h3>
            {loading ? (
              <div className="space-y-3">
                {[...Array(3)].map((_, i) => (
                  <div
                    key={i}
                    className="h-12 skeleton rounded-[--radius-md]"
                  />
                ))}
              </div>
            ) : topPools.length === 0 ? (
              <p className="text-sm text-text-tertiary py-4 text-center">
                No pools yet
              </p>
            ) : (
              <div className="space-y-1">
                {topPools.map((pool, idx) => (
                  <button
                    key={pool.poolId}
                    type="button"
                    className="w-full flex items-center gap-3 p-2.5 rounded-[--radius-md] hover:bg-surface-2 transition-colors cursor-pointer"
                    onClick={() => onSelectPool(pool)}
                  >
                    <span className="text-xs text-text-disabled w-4 text-right">
                      {idx + 1}
                    </span>
                    <TokenPairIcon
                      symbol0={pool.symbol0 || "?"}
                      symbol1={pool.symbol1 || "?"}
                      size={24}
                    />
                    <div className="flex flex-col min-w-0 flex-1">
                      <span className="text-sm font-medium text-text-primary truncate">
                        {pool.pair}
                      </span>
                      <span className="text-xs text-text-tertiary">
                        v4 · {pool.feeLabel}
                      </span>
                    </div>
                  </button>
                ))}
              </div>
            )}
          </div>

          {/* Learn card */}
          <div className="bg-surface-1 border border-border rounded-[--radius-xl] p-5">
            <h3 className="text-sm font-semibold text-text-primary mb-3">
              Learn about liquidity
            </h3>
            <div className="flex items-start gap-3 p-3 bg-surface-2 rounded-[--radius-md]">
              <div className="w-8 h-8 rounded-[--radius-sm] bg-accent-muted text-accent flex items-center justify-center shrink-0">
                <svg
                  width="16"
                  height="16"
                  viewBox="0 0 24 24"
                  fill="none"
                  stroke="currentColor"
                  strokeWidth="2"
                  strokeLinecap="round"
                  strokeLinejoin="round"
                >
                  <path d="M7 17L17 7" />
                  <path d="M17 7H7V17" />
                </svg>
              </div>
              <p className="text-xs text-text-secondary leading-relaxed">
                Providing liquidity on concentrated liquidity protocols lets you
                earn fees from every trade within your price range.
              </p>
            </div>
          </div>
        </aside>
      </div>
    </div>
  );
}
