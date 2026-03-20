"use client";

import { useEffect, useRef } from "react";
import { TokenIcon, TokenPairIcon } from "./TokenIcon";
import { Badge } from "@/components/ui/Badge";
import { Button } from "@/components/ui/Button";
import { useHashPack } from "@/context/HashPackContext";
import { useTokenBalance } from "@/hooks/useTokenBalance";
import { usePositionOnChain } from "@/hooks/usePositionOnChain";
import { getTokenDecimals, HOOKS_ZERO } from "@/constants";
import { tickToPrice } from "@/lib/priceUtils";
import { buildPoolKey, getPoolId } from "@/lib/addLiquidity";
import type { PoolInfo } from "./PoolPositions";
import { TWAPOracleCard, HookBadge } from "./TWAPOracleCard";

interface PositionDetailProps {
  pool: PoolInfo;
  onBack: () => void;
  onAddLiquidity: () => void;
  onRemoveLiquidity: () => void;
  onBurnPosition: () => void;
}

function formatFee(fee: number): string {
  return `${(fee / 10000).toFixed(2)}%`;
}

export function PositionDetail({
  pool,
  onBack,
  onAddLiquidity,
  onRemoveLiquidity,
  onBurnPosition,
}: PositionDetailProps) {
  const { symbol0, symbol1, fee } = pool;
  const { accountId, isConnected } = useHashPack();
  const { data: onChain, loading: onChainLoading, error: onChainError } =
    usePositionOnChain(pool.tokenId ?? null, { enabled: pool.tokenId != null });
  const syncedRef = useRef(false);

  const displayPool: PoolInfo = onChain
    ? {
        ...pool,
        liquidity: onChain.liquidity,
        tickLower: onChain.tickLower,
        tickUpper: onChain.tickUpper,
        currency0: onChain.currency0,
        currency1: onChain.currency1,
        fee: onChain.fee,
        tickSpacing: onChain.tickSpacing,
        hooks: onChain.hooks,
      }
    : pool;

  useEffect(() => {
    if (!onChain || syncedRef.current || !onChain.owner) return;
    syncedRef.current = true;
    const poolKey = buildPoolKey(
      onChain.currency0 as `0x${string}`,
      onChain.currency1 as `0x${string}`,
      onChain.fee,
      onChain.tickSpacing,
      (onChain.hooks || "0x0000000000000000000000000000000000000000") as `0x${string}`,
    );
    const poolId = getPoolId(poolKey);
    fetch("/api/positions", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        tokenId: onChain.tokenId,
        poolId,
        owner: onChain.owner.toLowerCase(),
        tickLower: onChain.tickLower,
        tickUpper: onChain.tickUpper,
        liquidity: onChain.liquidity,
        currency0: onChain.currency0,
        currency1: onChain.currency1,
        fee: onChain.fee,
        tickSpacing: onChain.tickSpacing,
        hooks: onChain.hooks,
        symbol0: pool.symbol0,
        symbol1: pool.symbol1,
        decimals0: pool.decimals0,
        decimals1: pool.decimals1,
      }),
    })
      .then(async (resp) => {
        if (!resp.ok) {
          const j = (await resp.json().catch(() => null)) as
            | { error?: string; persisted?: boolean }
            | null;
          console.warn(
            "[PositionDetail] failed to persist position:",
            resp.status,
            j?.error ?? "(no error body)",
          );
        }
      })
      .catch(() => {});
  }, [onChain, pool.symbol0, pool.symbol1, pool.decimals0, pool.decimals1]);

  // If the position disappears from on-chain (e.g. after burn), return to the list view
  // so the UI refreshes and removes the burned position.
  useEffect(() => {
    if (pool.tokenId == null) return;
    if (onChainLoading) return;
    if (onChain == null && !onChainError) {
      onBack();
    }
  }, [pool.tokenId, onChain, onChainLoading, onChainError, onBack]);

  const decimals0 = displayPool.decimals0 ?? getTokenDecimals(displayPool.symbol0);
  const decimals1 = displayPool.decimals1 ?? getTokenDecimals(displayPool.symbol1);
  const { balanceFormatted: balance0, loading: bal0Loading } = useTokenBalance(
    displayPool.currency0,
    accountId,
    decimals0,
  );
  const { balanceFormatted: balance1, loading: bal1Loading } = useTokenBalance(
    displayPool.currency1,
    accountId,
    decimals1,
  );

  return (
    <div className="max-w-6xl mx-auto px-3 sm:px-4 lg:px-6 py-6 sm:py-8 animate-[fadeIn_0.3s_ease-out]">
      {/* Back + actions */}
      <div className="flex flex-wrap items-center justify-between gap-3 mb-6">
        <button
          type="button"
          onClick={onBack}
          className="flex items-center gap-2 text-sm font-medium text-text-secondary hover:text-text-primary transition-colors cursor-pointer"
        >
          <svg
            width="18"
            height="18"
            viewBox="0 0 24 24"
            fill="none"
            stroke="currentColor"
            strokeWidth="2"
            strokeLinecap="round"
            strokeLinejoin="round"
          >
            <line x1="19" y1="12" x2="5" y2="12" />
            <polyline points="12 19 5 12 12 5" />
          </svg>
          Your positions
        </button>
        <div className="flex items-center gap-2">
          <Button variant="primary" size="sm" onClick={onAddLiquidity}>
            Add liquidity
          </Button>
          <Button variant="secondary" size="sm" onClick={onRemoveLiquidity}>
            Remove liquidity
          </Button>
          <Button variant="danger" size="sm" onClick={onBurnPosition}>
            Burn position
          </Button>
        </div>
      </div>

      {/* On-chain load error */}
      {onChainError && pool.tokenId != null && (
        <div className="rounded-xl border border-red-500/30 bg-red-500/10 p-3 mb-4 text-sm text-red-400">
          {onChainError}
        </div>
      )}

      {/* Pool identity + status */}
      <div className="rounded-2xl border border-white/[0.06] bg-surface-2/50 p-4 sm:p-5 mb-5 shadow-inner">
        <div className="flex flex-wrap items-center gap-2 sm:gap-3 mb-2">
          <TokenPairIcon symbol0={symbol0} symbol1={symbol1} size={32} />
          <span className="text-lg font-semibold text-text-primary">
            {symbol0} / {symbol1}
          </span>
          <Badge variant="accent">v4</Badge>
          <Badge>{formatFee(displayPool.fee)}</Badge>
          {displayPool.hooks && displayPool.hooks !== HOOKS_ZERO && (
            <HookBadge hookName={pool.hookName} />
          )}
        </div>
        <div className="flex flex-wrap items-center gap-3 text-xs text-text-tertiary">
          <span>Testnet</span>
          {onChainLoading && pool.tokenId != null ? (
            <span>Loading position from chain…</span>
          ) : (
            <span className="flex items-center gap-1.5">
              <span className="w-2 h-2 rounded-full bg-success" />
              In range
            </span>
          )}
        </div>
      </div>

      {/* Current rate (placeholder) */}
      <div className="text-sm text-text-secondary mb-5">
        — {symbol1} = 1 {symbol0} (rate from pool)
      </div>

      {/* TWAP Oracle (if hook is attached) */}
      {pool.hooks && pool.hooks !== HOOKS_ZERO && (
        <div className="mb-5">
          <TWAPOracleCard
            poolId={pool.poolId}
            hookAddress={pool.hooks}
            symbol0={symbol0}
            symbol1={symbol1}
          />
        </div>
      )}

      <div className="flex flex-col lg:flex-row gap-5 lg:gap-6">
        {/* Chart area */}
        <div className="flex-1 min-w-0 rounded-2xl border border-white/[0.06] bg-surface-2/50 overflow-hidden shadow-inner">
          <div className="p-4 border-b border-white/[0.06] flex flex-wrap items-center justify-between gap-2">
            <div className="flex gap-1">
              {["1D", "1W", "1M", "1Y", "All"].map((label, i) => (
                <button
                  key={label}
                  type="button"
                  className={`px-3 py-1.5 text-xs font-medium rounded-lg transition-colors cursor-pointer ${
                    i === 0
                      ? "bg-surface-1 text-text-primary"
                      : "text-text-tertiary hover:text-text-secondary"
                  }`}
                >
                  {label}
                </button>
              ))}
            </div>
            <div className="flex gap-1">
              <span className="px-3 py-1.5 text-xs font-medium rounded-lg bg-surface-1 text-text-primary">
                Chart
              </span>
              <span className="px-3 py-1.5 text-xs font-medium rounded-lg text-text-tertiary">
                NFT
              </span>
            </div>
          </div>
          <div className="h-64 sm:h-80 flex items-center justify-center bg-surface-1/30">
            <p className="text-sm text-text-tertiary">
              Price chart placeholder
            </p>
          </div>
        </div>

        {/* Position + Fees panel */}
        <aside className="w-full lg:w-80 shrink-0 space-y-4">
          <div className="rounded-2xl border border-white/[0.06] bg-surface-2/50 p-4 sm:p-5 shadow-inner">
            <h3 className="text-sm font-semibold text-text-primary mb-4 flex items-center gap-2">
              Position
              {displayPool.tokenId != null && (
                <Badge className="bg-accent/15 text-accent text-[10px] px-1.5 py-0.5">
                  #{displayPool.tokenId}
                </Badge>
              )}
            </h3>

            {/* Position-specific: tick range + liquidity (from chain when available) */}
            {displayPool.tokenId != null && (
              <div className="space-y-3 mb-4 pb-4 border-b border-white/[0.06]">
                <div>
                  <p className="text-xs text-text-tertiary mb-1">Price range</p>
                  <div className="flex items-center gap-2 text-sm">
                    <span className="text-text-primary font-semibold">
                      {displayPool.tickLower != null
                        ? tickToPrice(displayPool.tickLower).toFixed(6)
                        : onChainLoading ? "…" : "—"}
                    </span>
                    <span className="text-text-tertiary">↔</span>
                    <span className="text-text-primary font-semibold">
                      {displayPool.tickUpper != null
                        ? tickToPrice(displayPool.tickUpper).toFixed(6)
                        : onChainLoading ? "…" : "—"}
                    </span>
                    <span className="text-xs text-text-tertiary">
                      {symbol1}/{symbol0}
                    </span>
                  </div>
                </div>
                <div>
                  <p className="text-xs text-text-tertiary mb-1">Tick range</p>
                  <p className="text-sm text-text-secondary">
                    [{displayPool.tickLower ?? "—"}, {displayPool.tickUpper ?? "—"}]
                  </p>
                </div>
                <div>
                  <p className="text-xs text-text-tertiary mb-1">Liquidity</p>
                  <p className="text-sm font-semibold text-text-primary">
                    {displayPool.liquidity
                      ? BigInt(displayPool.liquidity).toLocaleString()
                      : onChainLoading ? "…" : "—"}
                  </p>
                </div>
              </div>
            )}

            {isConnected ? (
              <>
                <p className="text-xs text-text-tertiary mb-3">
                  Your token balances
                </p>
                <div className="space-y-3">
                  <div className="flex items-center justify-between">
                    <span className="flex items-center gap-2 text-sm text-text-secondary">
                      <TokenIcon symbol={symbol0} size={20} />
                      {symbol0}
                    </span>
                    <span className="text-sm font-semibold text-text-primary">
                      {bal0Loading ? "…" : balance0}
                    </span>
                  </div>
                  <div className="flex items-center justify-between">
                    <span className="flex items-center gap-2 text-sm text-text-secondary">
                      <TokenIcon symbol={symbol1} size={20} />
                      {symbol1}
                    </span>
                    <span className="text-sm font-semibold text-text-primary">
                      {bal1Loading ? "…" : balance1}
                    </span>
                  </div>
                </div>
              </>
            ) : (
              <>
                <p className="text-xs text-text-tertiary mb-3 flex items-center gap-1.5">
                  Connect wallet to view balances
                </p>
                <div className="space-y-2">
                  <div className="flex items-center justify-between text-sm">
                    <span className="flex items-center gap-2 text-text-secondary">
                      <TokenIcon symbol={symbol0} size={20} />
                      {symbol0}
                    </span>
                    <span className="text-text-tertiary">—</span>
                  </div>
                  <div className="flex items-center justify-between text-sm">
                    <span className="flex items-center gap-2 text-text-secondary">
                      <TokenIcon symbol={symbol1} size={20} />
                      {symbol1}
                    </span>
                    <span className="text-text-tertiary">—</span>
                  </div>
                </div>
              </>
            )}
          </div>

          <div className="rounded-2xl border border-white/[0.06] bg-surface-2/50 p-4 sm:p-5 shadow-inner">
            <h3 className="text-sm font-semibold text-text-primary mb-4">
              Fees earned
            </h3>
            <p className="text-2xl font-bold text-text-primary">$0</p>
            <p className="text-xs text-text-tertiary mt-1">
              You have no earnings yet
            </p>
          </div>

          <div className="pt-2">
            <p className="text-xs text-text-tertiary">
              Don&apos;t recognize this position?{" "}
              <button
                type="button"
                className="text-error hover:underline cursor-pointer"
              >
                Report as spam
              </button>
            </p>
          </div>
        </aside>
      </div>
    </div>
  );
}
