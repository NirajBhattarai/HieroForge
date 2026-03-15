"use client";

import { useState, useEffect, useCallback } from "react";
import { TokenIcon, TokenPairIcon } from "./TokenIcon";
import { Badge } from "@/components/ui/Badge";
import { Button } from "@/components/ui/Button";
import { useTokens } from "@/hooks/useTokens";
import { useTokenBalance } from "@/hooks/useTokenBalance";
import { usePositions, type Position } from "@/hooks/usePositions";
import { useHashPack } from "@/context/HashPackContext";
import { getTokenDecimals } from "@/constants";
import { tickToPrice } from "@/lib/priceUtils";

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
  decimals0?: number;
  decimals1?: number;
  initialPrice?: string;
  hooks?: string;
  hookName?: string;
  /** Position-specific fields (set when this represents an individual position) */
  tokenId?: number;
  tickLower?: number;
  tickUpper?: number;
  liquidity?: string;
}

interface PoolPositionsProps {
  onCreatePosition: () => void;
  onSelectPool: (pool: PoolInfo) => void;
}

function shortenAddr(addr: string): string {
  if (!addr || addr.length < 10) return addr;
  return `${addr.slice(0, 6)}...${addr.slice(-4)}`;
}

/** Individual position/pool card with tick range and liquidity display */
function PoolCard({
  pool,
  t0name,
  t1name,
  onClick,
}: {
  pool: PoolInfo;
  t0name?: string;
  t1name?: string;
  onClick: () => void;
}) {
  const { accountId, isConnected } = useHashPack();
  const decimals0 = pool.decimals0 ?? getTokenDecimals(pool.symbol0);
  const decimals1 = pool.decimals1 ?? getTokenDecimals(pool.symbol1);
  const { balanceFormatted: bal0 } = useTokenBalance(
    pool.currency0,
    accountId,
    decimals0,
  );
  const { balanceFormatted: bal1 } = useTokenBalance(
    pool.currency1,
    accountId,
    decimals1,
  );

  const hasPosition = pool.tokenId != null;
  const priceLow =
    pool.tickLower != null ? tickToPrice(pool.tickLower).toFixed(6) : null;
  const priceHigh =
    pool.tickUpper != null ? tickToPrice(pool.tickUpper).toFixed(6) : null;

  return (
    <button
      key={hasPosition ? `pos-${pool.tokenId}` : pool.poolId}
      type="button"
      className="w-full flex flex-col gap-2 p-4 rounded-xl bg-surface-2/50 border border-white/[0.06] hover:border-accent/20 hover:bg-surface-2/80 transition-all duration-200 cursor-pointer text-left shadow-sm hover:shadow-md"
      onClick={onClick}
    >
      <div className="flex items-center gap-3 sm:gap-4">
        <TokenPairIcon
          symbol0={pool.symbol0 || "?"}
          symbol1={pool.symbol1 || "?"}
          size={32}
        />
        <div className="flex flex-col min-w-0 flex-1">
          <span className="text-sm font-semibold text-text-primary">
            {pool.pair}
            {hasPosition && (
              <span className="ml-2 text-xs font-normal text-text-tertiary">
                #{pool.tokenId}
              </span>
            )}
          </span>
          <span className="text-xs text-text-tertiary truncate">
            v4 · {pool.feeLabel}
            {hasPosition && priceLow && priceHigh && (
              <>
                {" · "}
                <span className="text-text-secondary">
                  {priceLow} ↔ {priceHigh}
                </span>
              </>
            )}
            {!hasPosition && (t0name || t1name) && (
              <>
                {" · "}
                {t0name || shortenAddr(pool.currency0)} /{" "}
                {t1name || shortenAddr(pool.currency1)}
              </>
            )}
          </span>
        </div>
        <div className="flex items-center gap-1.5 shrink-0">
          <span className="w-2 h-2 rounded-full bg-success" />
          <span className="text-xs text-success font-medium">In range</span>
        </div>
      </div>
      {/* Position info row */}
      {hasPosition && pool.liquidity && (
        <div className="flex items-center gap-3 ml-11 text-xs">
          <span className="text-text-secondary">
            Liquidity:{" "}
            <span className="font-mono text-text-primary">
              {BigInt(pool.liquidity) > 1_000_000n
                ? `${(Number(pool.liquidity) / 1e6).toFixed(2)}M`
                : pool.liquidity}
            </span>
          </span>
          {priceLow && priceHigh && (
            <>
              <span className="text-text-disabled">·</span>
              <span className="text-text-secondary">
                Range:{" "}
                <span className="font-mono text-text-primary">
                  [{pool.tickLower}, {pool.tickUpper}]
                </span>
              </span>
            </>
          )}
        </div>
      )}
      {/* Balance row (for pool-level cards without position data) */}
      {!hasPosition && isConnected && (
        <div className="flex items-center gap-3 ml-11 text-xs">
          <span className="flex items-center gap-1.5 text-text-secondary">
            <TokenIcon symbol={pool.symbol0 || "?"} size={14} />
            <span className="font-medium text-text-primary">{bal0 || "0"}</span>
            {pool.symbol0}
          </span>
          <span className="text-text-disabled">·</span>
          <span className="flex items-center gap-1.5 text-text-secondary">
            <TokenIcon symbol={pool.symbol1 || "?"} size={14} />
            <span className="font-medium text-text-primary">{bal1 || "0"}</span>
            {pool.symbol1}
          </span>
        </div>
      )}
    </button>
  );
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
  const [poolFilter, setPoolFilter] = useState<"all" | "mine" | "positions">(
    "positions",
  );

  const { accountId, isConnected } = useHashPack();

  // Derive deployer EVM address from Hedera accountId for filtering
  const deployerEvmAddress = (() => {
    if (!accountId) return null;
    const m = String(accountId).match(/^(\d+)\.(\d+)\.(\d+)$/);
    if (!m) return null;
    return "0x" + BigInt(m[3]!).toString(16).padStart(40, "0");
  })();

  const { tokens: dynamicTokens } = useTokens();
  const tokenByAddr = new Map(
    dynamicTokens.map((t) => [t.address.toLowerCase(), t]),
  );

  // Fetch positions for current user
  const {
    positions: userPositions,
    loading: positionsLoading,
    refetch: refetchPositions,
  } = usePositions(deployerEvmAddress);

  useEffect(() => {
    // For "positions" tab, we use the usePositions hook instead
    if (poolFilter === "positions") {
      if (!positionsLoading) {
        setPools(
          userPositions.map((p) => ({
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
            hooks: p.hooks,
            hookName: p.hookName,
            tokenId: p.tokenId,
            tickLower: p.tickLower,
            tickUpper: p.tickUpper,
            liquidity: p.liquidity,
          })),
        );
        setLoading(false);
      } else {
        setLoading(true);
      }
      return;
    }

    let cancelled = false;
    setLoading(true);
    setError(null);

    const url =
      poolFilter === "mine" && deployerEvmAddress
        ? `/api/pools?deployedBy=${encodeURIComponent(deployerEvmAddress)}`
        : "/api/pools";

    fetch(url)
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
            deployedBy?: string;
            initialPrice?: string;
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
              initialPrice: p.initialPrice,
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
  }, [poolFilter, deployerEvmAddress, userPositions, positionsLoading]);

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
        if (res.status === 404) throw new Error("Pool not found on-chain");
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
        decimals0?: number;
        decimals1?: number;
        initialPrice?: string;
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
        decimals0: p.decimals0,
        decimals1: p.decimals1,
        initialPrice: p.initialPrice,
      };
      onSelectPool(pool);
    } catch (err) {
      setLoadError(err instanceof Error ? err.message : "Failed to load pool");
    }
  }, [loadPoolId, onSelectPool]);

  const hasPositions = pools.length > 0;
  const topPools = pools.slice(0, 8);

  return (
    <div className="max-w-6xl mx-auto px-3 sm:px-4 lg:px-6 py-6 sm:py-8 animate-[fadeIn_0.3s_ease-out]">
      <div className="flex flex-col lg:flex-row gap-5 lg:gap-6">
        {/* Left column */}
        <div className="flex-1 min-w-0 space-y-4 sm:space-y-5">
          {/* Rewards card — glass style */}
          <div className="rounded-2xl border border-white/[0.06] bg-surface-2/50 overflow-hidden shadow-inner">
            <div className="h-1 bg-gradient-to-r from-accent via-accent/80 to-purple-400" />
            <div className="p-4 sm:p-5">
              <div className="flex flex-wrap items-center justify-between gap-3 mb-3">
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
          <div className="flex flex-wrap items-center justify-between gap-3">
            <h2 className="text-base sm:text-lg font-semibold text-text-primary">
              Your positions
            </h2>
            <Button variant="primary" size="sm" onClick={onCreatePosition}>
              New position
            </Button>
          </div>

          {/* Filters — pill style */}
          <div className="flex items-center gap-2 flex-wrap">
            {isConnected && (
              <button
                type="button"
                onClick={() => setPoolFilter("positions")}
                className={`px-3 py-2 text-xs font-medium rounded-full border transition-all cursor-pointer ${
                  poolFilter === "positions"
                    ? "bg-accent/15 text-accent border-accent/30"
                    : "bg-surface-2/80 text-text-secondary border-white/[0.08] hover:border-accent/30 hover:text-text-primary"
                }`}
              >
                My positions
              </button>
            )}
            <button
              type="button"
              onClick={() => setPoolFilter("all")}
              className={`px-3 py-2 text-xs font-medium rounded-full border transition-all cursor-pointer ${
                poolFilter === "all"
                  ? "bg-accent/15 text-accent border-accent/30"
                  : "bg-surface-2/80 text-text-secondary border-white/[0.08] hover:border-accent/30 hover:text-text-primary"
              }`}
            >
              All pools
            </button>
            {isConnected && (
              <button
                type="button"
                onClick={() => setPoolFilter("mine")}
                className={`px-3 py-2 text-xs font-medium rounded-full border transition-all cursor-pointer ${
                  poolFilter === "mine"
                    ? "bg-accent/15 text-accent border-accent/30"
                    : "bg-surface-2/80 text-text-secondary border-white/[0.08] hover:border-accent/30 hover:text-text-primary"
                }`}
              >
                My pools
              </button>
            )}
            <button
              type="button"
              onClick={() => setShowLoadById(!showLoadById)}
              className="px-3 py-2 text-xs font-medium rounded-full bg-surface-2/80 text-text-secondary border border-white/[0.08] hover:border-accent/30 hover:text-text-primary transition-all cursor-pointer ml-auto"
            >
              Load by ID
            </button>
          </div>

          {/* Load by pool ID */}
          {showLoadById && (
            <div className="rounded-xl border border-white/[0.06] bg-surface-2/50 p-4 animate-[fadeIn_0.15s_ease-out] shadow-inner">
              <div className="flex gap-2">
                <input
                  type="text"
                  className="flex-1 min-w-0 px-3 py-2.5 bg-surface-2 border border-white/[0.08] rounded-xl text-sm text-text-primary placeholder:text-text-tertiary focus:outline-none focus:border-accent/40 focus:ring-1 focus:ring-accent/20 transition-colors"
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
            <div className="flex items-center gap-2 px-4 py-3 rounded-xl bg-error-muted text-error text-sm">
              {error}
            </div>
          )}

          {loading ? (
            <div className="space-y-3">
              {[...Array(3)].map((_, i) => (
                <div
                  key={i}
                  className="h-20 rounded-xl bg-surface-2/80 border border-white/[0.06] animate-pulse"
                />
              ))}
            </div>
          ) : !hasPositions ? (
            /* Empty state */
            <div className="rounded-2xl border border-white/[0.06] bg-surface-2/50 flex flex-col items-center justify-center py-12 sm:py-16 px-4 sm:px-6 shadow-inner">
              <div className="w-14 h-14 sm:w-16 sm:h-16 rounded-full bg-surface-3/80 border border-white/[0.06] flex items-center justify-center mb-4">
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
              <div className="flex flex-wrap gap-3 justify-center">
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
                  <PoolCard
                    key={
                      pool.tokenId != null ? `pos-${pool.tokenId}` : pool.poolId
                    }
                    pool={pool}
                    t0name={t0info?.name}
                    t1name={t1info?.name}
                    onClick={() => onSelectPool(pool)}
                  />
                );
              })}
            </div>
          )}

          {/* Info box */}
          {!infoBoxDismissed && (
            <div className="flex items-start gap-3 p-4 rounded-xl bg-surface-2/50 border border-white/[0.06]">
              <span className="w-6 h-6 rounded-full bg-accent/15 text-accent flex items-center justify-center shrink-0 text-xs font-bold">
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
                className="shrink-0 p-1.5 rounded-lg text-text-tertiary hover:text-text-primary hover:bg-surface-3/80 transition-colors cursor-pointer"
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
          <p className="text-xs text-text-tertiary text-center pt-1">
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
        <aside className="w-full lg:w-80 shrink-0 space-y-4 sm:space-y-5">
          {/* Top pools */}
          <div className="rounded-2xl border border-white/[0.06] bg-surface-2/50 p-4 sm:p-5 shadow-inner">
            <h3 className="text-sm font-semibold text-text-primary mb-4">
              Top pools by TVL
            </h3>
            {loading ? (
              <div className="space-y-2">
                {[...Array(3)].map((_, i) => (
                  <div
                    key={i}
                    className="h-12 rounded-xl bg-surface-2/80 animate-pulse"
                  />
                ))}
              </div>
            ) : topPools.length === 0 ? (
              <p className="text-sm text-text-tertiary py-4 text-center">
                No pools yet
              </p>
            ) : (
              <div className="space-y-0.5">
                {topPools.map((pool, idx) => (
                  <button
                    key={pool.poolId}
                    type="button"
                    className="w-full flex items-center gap-3 p-2.5 rounded-xl hover:bg-surface-3/60 transition-colors cursor-pointer"
                    onClick={() => onSelectPool(pool)}
                  >
                    <span className="text-xs text-text-disabled w-4 text-right shrink-0">
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
          <div className="rounded-2xl border border-white/[0.06] bg-surface-2/50 p-4 sm:p-5 shadow-inner">
            <h3 className="text-sm font-semibold text-text-primary mb-3">
              Learn about liquidity
            </h3>
            <div className="flex items-start gap-3 p-3 rounded-xl bg-surface-3/50 border border-white/[0.04]">
              <div className="w-8 h-8 rounded-lg bg-accent/15 text-accent flex items-center justify-center shrink-0">
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
