"use client";

import { useState, useCallback, useEffect, useMemo } from "react";
import { createPublicClient, http } from "viem";
import { formatUnits } from "viem";
import { TokenIcon, TokenPairIcon } from "./TokenIcon";
import { Badge } from "@/components/ui/Badge";
import { Button } from "@/components/ui/Button";
import { ErrorMessage } from "./ErrorMessage";
import { useHashPack } from "@/context/HashPackContext";
import { useTokenBalance } from "@/hooks/useTokenBalance";
import { usePositionOnChain } from "@/hooks/usePositionOnChain";
import {
  getPositionManagerAddress,
  getPoolManagerAddress,
  getRpcUrl,
  HEDERA_TESTNET,
} from "@/constants";
import {
  encodeUnlockDataDecrease,
  encodeUnlockDataBurn,
} from "@/lib/addLiquidity";
import { hederaContractMulticall } from "@/lib/hederaContract";
import { PositionManagerAbi } from "@/abis/PositionManager";
import { PoolManagerAbi } from "@/abis/PoolManager";
import { amountsForLiquidity, getSqrtPriceAtTick } from "@/lib/sqrtPriceMath";
import { getFriendlyErrorMessage } from "@/lib/errors";
import type { PoolInfo } from "./PoolPositions";

interface RemoveLiquidityModalProps {
  pool: PoolInfo;
  onClose: () => void;
  onReview?: (percent: number) => void;
}

function formatFee(fee: number): string {
  return `${(fee / 10000).toFixed(2)}%`;
}

/** Hedera accountId (0.0.X) → long-zero EVM address (0x...padStart(40)). */
function accountIdToEvmAddress(accountId: string | null): string | null {
  if (!accountId) return null;
  const m = String(accountId).trim().match(/^(\d+)\.(\d+)\.(\d+)$/);
  if (!m) return null;
  return ("0x" + BigInt(m[3]!).toString(16).padStart(40, "0")).toLowerCase();
}

const PERCENT_OPTIONS = [10, 25, 50, 75, 100] as const;

const HEDERA_GAS_MODIFY_LIQ = 5_000_000;

export function RemoveLiquidityModal({
  pool,
  onClose,
  onReview,
}: RemoveLiquidityModalProps) {
  const { accountId, isConnected, hashConnectRef } = useHashPack();
  const [percent, setPercent] = useState(0);
  const [tokenId, setTokenId] = useState(
    pool.tokenId != null ? String(pool.tokenId) : "",
  );
  const [pending, setPending] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [txHash, setTxHash] = useState<string | null>(null);
  const [sqrtPriceX96, setSqrtPriceX96] = useState<bigint | null>(null);

  const publicClient = useMemo(
    () =>
      createPublicClient({
        chain: HEDERA_TESTNET,
        transport: http(getRpcUrl()),
      }),
    [],
  );

  // Resolved tokenId: modal input or pool's tokenId — we fetch this position from chain
  const resolvedTokenId = tokenId.trim() || (pool.tokenId != null ? String(pool.tokenId) : null);
  const { data: onChain, loading: onChainLoading } = usePositionOnChain(resolvedTokenId, {
    enabled: !!resolvedTokenId && !!pool,
  });
  const onChainLiquidity = onChain?.liquidity != null ? BigInt(onChain.liquidity) : null;

  useEffect(() => {
    if (!pool.poolId || !publicClient) {
      setSqrtPriceX96(null);
      return;
    }
    const poolIdHex =
      pool.poolId.startsWith("0x") ? pool.poolId : `0x${pool.poolId}`;
    const poolIdBytes32 =
      poolIdHex.length === 66
        ? (poolIdHex as `0x${string}`)
        : (`0x${(poolIdHex.slice(2) || "").padEnd(64, "0")}` as `0x${string}`);
    publicClient
      .readContract({
        address: getPoolManagerAddress() as `0x${string}`,
        abi: PoolManagerAbi,
        functionName: "getPoolState",
        args: [poolIdBytes32],
      })
      .then((value: unknown) => {
        const result = value as [boolean, bigint, number];
        setSqrtPriceX96(result[1]);
      })
      .catch(() => setSqrtPriceX96(null));
  }, [pool.poolId, publicClient]);

  // HTS tokens use 4 decimals; prefer pool/API decimals, else 4
  const decimals0 = pool.decimals0 ?? 4;
  const decimals1 = pool.decimals1 ?? 4;
  const { balanceFormatted: balance0 } = useTokenBalance(
    pool.currency0,
    accountId,
    decimals0,
  );
  const { balanceFormatted: balance1 } = useTokenBalance(
    pool.currency1,
    accountId,
    decimals1,
  );

  const positionManagerAddress = getPositionManagerAddress();
  const hasSelection = percent > 0;

  // Use only on-chain liquidity as source of truth
  const liquidityWei =
    onChainLiquidity != null && percent > 0
      ? (onChainLiquidity * BigInt(percent)) / 100n
      : 0n;
  const liquidityAmount = liquidityWei > 0n ? liquidityWei.toString() : "";

  const tickLower = onChain?.tickLower ?? pool.tickLower;
  const tickUpper = onChain?.tickUpper ?? pool.tickUpper;
  const hasTicks =
    typeof tickLower === "number" && typeof tickUpper === "number";

  const { estimated0, estimated1 } = useMemo(() => {
    if (
      !sqrtPriceX96 ||
      !hasTicks ||
      liquidityWei <= 0n
    ) {
      return { estimated0: "0", estimated1: "0" };
    }
    try {
      const sqrtPA = getSqrtPriceAtTick(tickLower!);
      const sqrtPB = getSqrtPriceAtTick(tickUpper!);
      const { amount0, amount1 } = amountsForLiquidity(
        sqrtPriceX96,
        sqrtPA,
        sqrtPB,
        liquidityWei,
      );
      const e0 = formatUnits(amount0, decimals0);
      const e1 = formatUnits(amount1, decimals1);
      const toDisplay = (s: string, d: number) => {
        const n = parseFloat(s);
        if (Number.isNaN(n)) return "0";
        return n.toFixed(Math.min(d, 6));
      };
      return {
        estimated0: toDisplay(e0, decimals0),
        estimated1: toDisplay(e1, decimals1),
      };
    } catch {
      return { estimated0: "0", estimated1: "0" };
    }
  }, [
    sqrtPriceX96,
    hasTicks,
    tickLower,
    tickUpper,
    liquidityWei,
    decimals0,
    decimals1,
  ]);

  const removeLiquidity = useCallback(async () => {
    if (!positionManagerAddress) {
      setError("PositionManager address not configured.");
      return;
    }
    if (!isConnected || !accountId) {
      setError("Connect HashPack first.");
      return;
    }
    const hc = hashConnectRef.current;
    if (!hc) {
      setError("HashPack not initialized.");
      return;
    }
    if (!resolvedTokenId) {
      setError("Enter the position token ID.");
      return;
    }
    if (onChainLiquidity == null) {
      setError("Load position from chain first.");
      return;
    }
    if (liquidityWei <= 0n) {
      setError("Liquidity to remove must be greater than zero.");
      return;
    }

    setError(null);
    setPending(true);
    setTxHash(null);

    try {
      const posTokenId = BigInt(resolvedTokenId);
      const deadline = BigInt(Math.floor(Date.now() / 1000) + 3600);

      // Partial (10%, 25%, 50%, 75%): only DECREASE_LIQUIDITY — position keeps the rest.
      // 100%: BURN_POSITION — removes all remaining liquidity and burns the NFT.
      let unlockData: `0x${string}`;
      if (percent === 100) {
        unlockData = encodeUnlockDataBurn(posTokenId, 0n, 0n);
      } else {
        unlockData = encodeUnlockDataDecrease(posTokenId, liquidityWei, 0n, 0n);
      }

      const { encodeFunctionData: encFn } = await import("viem");
      const modifyCalldata = encFn({
        abi: PositionManagerAbi,
        functionName: "modifyLiquidities",
        args: [unlockData, deadline],
      }) as `0x${string}`;

      console.log("[RemoveLiquidity] tokenId:", posTokenId.toString(), "percent:", percent, "liquidityWei:", liquidityWei.toString(), "unlockData (first 80 chars):", unlockData.slice(0, 80) + "...");

      const txId = await hederaContractMulticall({
        hashConnect: hc,
        accountId,
        contractId: positionManagerAddress,
        calls: [modifyCalldata],
        gas: HEDERA_GAS_MODIFY_LIQ,
      });

      setTxHash(txId);

      // If 100% removal (burn), delete position record from DynamoDB
      if (percent === 100 && pool.tokenId != null) {
        try {
          const positionId = `${pool.currency0}-${pool.currency1}-${pool.fee}-${pool.tickSpacing}-${pool.hooks ?? "0x0000000000000000000000000000000000000000"}-${pool.tokenId}`;
          await fetch(
            `/api/positions?positionId=${encodeURIComponent(positionId)}`,
            {
              method: "DELETE",
            },
          );
        } catch {
          // Non-critical – position was burned on-chain regardless
        }
      }
    } catch (err: unknown) {
      setError(getFriendlyErrorMessage(err, "transaction"));
    } finally {
      setPending(false);
    }
  }, [
    positionManagerAddress,
    pool,
    percent,
    resolvedTokenId,
    onChainLiquidity,
    liquidityWei,
    isConnected,
    accountId,
    hashConnectRef,
  ]);

  const buttonText = !isConnected
    ? "Connect wallet"
    : !hasSelection
      ? "Select amount"
      : !resolvedTokenId
        ? "Enter position token ID"
        : onChainLoading
          ? "Loading position…"
          : onChainLiquidity == null
            ? "Position not found on chain"
            : liquidityWei <= 0n
              ? "Liquidity to remove is too low"
              : pending
                ? "Removing…"
                : percent === 100
                  ? "Remove all & burn position"
                  : `Remove ${percent}% liquidity`;

  const canSubmit =
    isConnected &&
    hasSelection &&
    !!resolvedTokenId &&
    onChainLiquidity != null &&
    liquidityWei > 0n &&
    !pending &&
    !!positionManagerAddress;

  return (
    <div className="space-y-4">
      {/* Pool info */}
      <div className="flex flex-wrap items-center gap-2 rounded-xl bg-surface-2/80 border border-white/[0.06] p-3">
        <TokenPairIcon
          symbol0={pool.symbol0}
          symbol1={pool.symbol1}
          size={28}
        />
        <span className="font-semibold text-text-primary">
          {pool.symbol0} / {pool.symbol1}
        </span>
        <Badge variant="accent">v4</Badge>
        <Badge>{formatFee(pool.fee)}</Badge>
        <span className="flex items-center gap-1.5 text-xs text-text-tertiary ml-auto">
          <span className="w-2 h-2 rounded-full bg-success" />
          In range
        </span>
      </div>

      {/* Position owner vs your account (helps debug Unauthorized) */}
      {onChain?.owner != null && isConnected && accountId && (
        <div className="rounded-xl border border-white/[0.06] bg-surface-2/30 p-3">
          <p className="text-xs font-medium text-text-tertiary uppercase tracking-wider mb-1.5">
            Who can remove
          </p>
          <p className="text-xs text-text-secondary font-mono break-all">
            On-chain owner: {onChain.owner}
          </p>
          <p className="text-xs text-text-secondary font-mono break-all mt-1">
            You: {accountId} → EVM (long-zero): {accountIdToEvmAddress(accountId) ?? "—"}
          </p>
          {onChain.owner.toLowerCase() !== accountIdToEvmAddress(accountId) ? (
            <p className="text-xs text-amber-500 mt-2">
              These differ. Only the on-chain owner can remove. If you see Unauthorized, use the same wallet that created this position.
            </p>
          ) : (
            <p className="text-xs text-text-tertiary mt-2">
              Your account’s long-zero matches the owner. If you still get Unauthorized, Hedera may be using your wallet’s ECDSA alias as the tx sender; the position must have been created with the same sender type.
            </p>
          )}
        </div>
      )}

      {/* Current balances */}
      <div className="rounded-xl border border-white/[0.06] bg-surface-2/30 p-4">
        <p className="text-xs font-medium text-text-tertiary uppercase tracking-wider mb-2">
          Your current balances
        </p>
        <div className="flex flex-col gap-1.5 text-sm">
          <div className="flex items-center justify-between">
            <span className="flex items-center gap-2 text-text-secondary">
              <TokenIcon symbol={pool.symbol0} size={18} />
              {pool.symbol0}
            </span>
            <span className="font-semibold text-text-primary">{balance0}</span>
          </div>
          <div className="flex items-center justify-between">
            <span className="flex items-center gap-2 text-text-secondary">
              <TokenIcon symbol={pool.symbol1} size={18} />
              {pool.symbol1}
            </span>
            <span className="font-semibold text-text-primary">{balance1}</span>
          </div>
        </div>
      </div>

      {/* Withdrawal amount */}
      <div>
        <p className="text-xs font-medium text-text-tertiary uppercase tracking-wider mb-2">
          Withdrawal amount
        </p>
        <p className="text-4xl font-bold text-text-primary mb-4">{percent}%</p>
        {/* Slider */}
        <input
          type="range"
          min="0"
          max="100"
          value={percent}
          onChange={(e) => setPercent(Number(e.target.value))}
          className="w-full h-2 bg-surface-3 rounded-lg appearance-none cursor-pointer accent-accent mb-3"
        />
        <div className="flex flex-wrap gap-2">
          {PERCENT_OPTIONS.map((p) => (
            <button
              key={p}
              type="button"
              onClick={() => setPercent(p)}
              className={`
                flex-1 min-w-[60px] px-4 py-2.5 rounded-xl text-sm font-medium
                transition-all cursor-pointer
                ${
                  percent === p
                    ? "bg-accent/15 text-accent border border-accent/30"
                    : "bg-surface-2/80 text-text-secondary border border-white/[0.08] hover:border-accent/20 hover:text-text-primary"
                }
              `}
            >
              {p === 100 ? "Max" : `${p}%`}
            </button>
          ))}
        </div>
      </div>

      {/* Estimated amounts to receive */}
      {hasSelection && (
        <div className="rounded-xl border border-white/[0.06] bg-surface-2/50 p-4 space-y-2">
          <p className="text-xs font-medium text-text-tertiary uppercase tracking-wider">
            Estimated to receive
          </p>
          <div className="flex flex-col gap-2">
            <div className="flex items-center justify-between">
              <span className="flex items-center gap-2 text-sm text-text-secondary">
                <TokenIcon symbol={pool.symbol0} size={20} />
                {pool.symbol0}
              </span>
              <span className="text-lg font-semibold text-text-primary">
                {estimated0}
              </span>
            </div>
            <div className="flex items-center justify-between">
              <span className="flex items-center gap-2 text-sm text-text-secondary">
                <TokenIcon symbol={pool.symbol1} size={20} />
                {pool.symbol1}
              </span>
              <span className="text-lg font-semibold text-text-primary">
                {estimated1}
              </span>
            </div>
          </div>
        </div>
      )}

      {/* Position token ID + on-chain liquidity (read-only from chain) */}
      {hasSelection && (
        <div className="space-y-3">
          <div className="space-y-1.5">
            <label className="text-xs font-medium text-text-secondary uppercase tracking-wider">
              Position Token ID
            </label>
            <input
              type="text"
              className="w-full px-3 py-2.5 bg-surface-2 border border-white/[0.08] rounded-xl text-sm text-text-primary placeholder:text-text-tertiary focus:outline-none focus:border-accent/40 focus:ring-1 focus:ring-accent/20 transition-colors font-mono"
              placeholder="e.g. 1"
              value={tokenId}
              onChange={(e) => {
                setTokenId(e.target.value);
                setError(null);
              }}
            />
            <p className="text-xs text-text-tertiary">
              NFT token ID — liquidity is loaded from chain
            </p>
          </div>
          <div className="space-y-1.5">
            <label className="text-xs font-medium text-text-secondary uppercase tracking-wider">
              Position liquidity (on-chain)
            </label>
            <div className="w-full px-3 py-2.5 bg-surface-2/80 border border-white/[0.08] rounded-xl text-sm font-mono text-text-primary">
              {onChainLoading
                ? "Loading…"
                : onChainLiquidity != null
                  ? onChainLiquidity.toString()
                  : resolvedTokenId
                    ? "Not found"
                    : "—"}
            </div>
            <p className="text-xs text-text-tertiary">
              Removing{" "}
              <span className="font-mono text-text-secondary">
                {liquidityAmount || "0"}
              </span>{" "}
              liquidity ({percent}%).
            </p>
          </div>
        </div>
      )}

      {/* Error / Success */}
      {error && (
        <ErrorMessage message={error} onDismiss={() => setError(null)} />
      )}
      {txHash && (
        <div className="flex items-center gap-2 px-4 py-3 rounded-xl bg-success-muted text-success text-sm">
          Liquidity removed!{" "}
          <a
            href={`https://hashscan.io/testnet/transaction/${txHash}`}
            target="_blank"
            rel="noreferrer"
            className="underline hover:no-underline"
          >
            View on HashScan →
          </a>
        </div>
      )}

      <Button
        variant="primary"
        fullWidth
        disabled={!canSubmit}
        onClick={removeLiquidity}
        loading={pending}
      >
        {buttonText}
      </Button>
    </div>
  );
}
