"use client";

import { useState, useCallback } from "react";
import { TokenIcon, TokenPairIcon } from "./TokenIcon";
import { Badge } from "@/components/ui/Badge";
import { Button } from "@/components/ui/Button";
import { ErrorMessage } from "./ErrorMessage";
import { useHashPack } from "@/context/HashPackContext";
import { useTokenBalance } from "@/hooks/useTokenBalance";
import { getTokenDecimals, getPositionManagerAddress } from "@/constants";
import {
  encodeUnlockDataDecrease,
  encodeUnlockDataBurn,
} from "@/lib/addLiquidity";
import { hederaContractMulticall } from "@/lib/hederaContract";
import { PositionManagerAbi } from "@/abis/PositionManager";
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

const PERCENT_OPTIONS = [25, 50, 75, 100] as const;

const HEDERA_GAS_MODIFY_LIQ = 5_000_000;

export function RemoveLiquidityModal({
  pool,
  onClose,
  onReview,
}: RemoveLiquidityModalProps) {
  const { accountId, isConnected, hashConnectRef } = useHashPack();
  const [percent, setPercent] = useState(0);
  const [tokenId, setTokenId] = useState("");
  const [positionLiquidity, setPositionLiquidity] = useState("");
  const [pending, setPending] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [txHash, setTxHash] = useState<string | null>(null);

  const decimals0 = pool.decimals0 ?? getTokenDecimals(pool.symbol0);
  const decimals1 = pool.decimals1 ?? getTokenDecimals(pool.symbol1);
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

  let liquidityAmount = "";
  let liquidityWei: bigint = 0n;
  try {
    const total = BigInt(positionLiquidity.trim() || "0");
    if (total > 0n && percent > 0) {
      liquidityWei = (total * BigInt(percent)) / 100n;
      liquidityAmount = liquidityWei.toString();
    }
  } catch {
    liquidityWei = 0n;
    liquidityAmount = "";
  }

  // Estimate amounts to receive based on percent
  const bal0Num = parseFloat(balance0) || 0;
  const bal1Num = parseFloat(balance1) || 0;
  const estimated0 =
    bal0Num > 0
      ? ((bal0Num * percent) / 100).toFixed(decimals0 > 6 ? 6 : decimals0)
      : "0";
  const estimated1 =
    bal1Num > 0
      ? ((bal1Num * percent) / 100).toFixed(decimals1 > 6 ? 6 : decimals1)
      : "0";

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
    if (!tokenId.trim()) {
      setError("Enter the position token ID.");
      return;
    }
    if (!positionLiquidity.trim()) {
      setError("Enter your position total liquidity.");
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
      const posTokenId = BigInt(tokenId.trim());
      const deadline = BigInt(Math.floor(Date.now() / 1000) + 3600);

      let unlockData: `0x${string}`;
      if (percent === 100) {
        // Use BURN_POSITION to fully remove and burn the NFT
        unlockData = encodeUnlockDataBurn(posTokenId, 0n, 0n);
      } else {
        // Use DECREASE_LIQUIDITY for partial removal
        unlockData = encodeUnlockDataDecrease(posTokenId, liquidityWei, 0n, 0n);
      }

      const { encodeFunctionData: encFn } = await import("viem");
      const modifyCalldata = encFn({
        abi: PositionManagerAbi,
        functionName: "modifyLiquidities",
        args: [unlockData, deadline],
      }) as `0x${string}`;

      const txId = await hederaContractMulticall({
        hashConnect: hc,
        accountId,
        contractId: positionManagerAddress,
        calls: [modifyCalldata],
        gas: HEDERA_GAS_MODIFY_LIQ,
      });

      setTxHash(txId);
    } catch (err: unknown) {
      setError(getFriendlyErrorMessage(err, "transaction"));
    } finally {
      setPending(false);
    }
  }, [
    positionManagerAddress,
    pool,
    percent,
    tokenId,
    positionLiquidity,
    liquidityWei,
    isConnected,
    accountId,
    hashConnectRef,
  ]);

  const buttonText = !isConnected
    ? "Connect wallet"
    : !hasSelection
      ? "Select amount"
      : !tokenId.trim()
        ? "Enter position token ID"
        : !positionLiquidity.trim()
          ? "Enter total position liquidity"
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
    !!tokenId.trim() &&
    !!positionLiquidity.trim() &&
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

      {/* Position token ID + liquidity inputs */}
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
              The NFT token ID of your position from the mint transaction
            </p>
          </div>
          <div className="space-y-1.5">
            <label className="text-xs font-medium text-text-secondary uppercase tracking-wider">
              Position total liquidity
            </label>
            <input
              type="text"
              className="w-full px-3 py-2.5 bg-surface-2 border border-white/[0.08] rounded-xl text-sm text-text-primary placeholder:text-text-tertiary focus:outline-none focus:border-accent/40 focus:ring-1 focus:ring-accent/20 transition-colors font-mono"
              placeholder="e.g. 100000000"
              value={positionLiquidity}
              onChange={(e) => {
                setPositionLiquidity(e.target.value);
                setError(null);
              }}
            />
            <p className="text-xs text-text-tertiary">
              Multicall will remove{" "}
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
