"use client";

import { useState, useCallback } from "react";
import { parseUnits } from "viem";
import { TokenIcon, TokenPairIcon } from "./TokenIcon";
import { Badge } from "@/components/ui/Badge";
import { Button } from "@/components/ui/Button";
import { ErrorMessage } from "./ErrorMessage";
import { useHashPack } from "@/context/HashPackContext";
import { useTokenBalance } from "@/hooks/useTokenBalance";
import { getTokenDecimals, getPositionManagerAddress } from "@/constants";
import { buildPoolKey, encodeUnlockDataMint } from "@/lib/addLiquidity";
import {
  encodePriceSqrt,
  computeLiquidityFromAmount,
  liquidityToWei,
  tickToPrice,
} from "@/lib/priceUtils";
import {
  hederaTokenTransfer,
  hederaContractMulticall,
} from "@/lib/hederaContract";
import { PositionManagerAbi } from "@/abis/PositionManager";
import { getFriendlyErrorMessage } from "@/lib/errors";
import type { PoolInfo } from "./PoolPositions";

/** Gas limits for Hedera ContractExecuteTransaction */
const HEDERA_GAS_ERC20 = 1_200_000;
const HEDERA_GAS_MODIFY_LIQ = 5_000_000;

interface AddLiquidityModalProps {
  pool: PoolInfo;
  onClose: () => void;
  onOpenFullFlow?: () => void;
}

function formatFee(fee: number): string {
  return `${(fee / 10000).toFixed(2)}%`;
}

function accountIdToEvmAddress(accountId: string | null): string | null {
  if (!accountId) return null;
  const m = String(accountId)
    .trim()
    .match(/^(\d+)\.(\d+)\.(\d+)$/);
  if (!m) return null;
  return "0x" + BigInt(m[3]!).toString(16).padStart(40, "0");
}

export function AddLiquidityModal({
  pool,
  onClose,
  onOpenFullFlow,
}: AddLiquidityModalProps) {
  const { accountId, isConnected, hashConnectRef } = useHashPack();
  const [amount0, setAmount0] = useState("");
  const [amount1, setAmount1] = useState("");
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
  const parsedInitialPrice = parseFloat(pool.initialPrice ?? "");
  const referencePrice =
    Number.isFinite(parsedInitialPrice) && parsedInitialPrice > 0
      ? parsedInitialPrice
      : 1;

  const amount0Num = parseFloat(amount0) || 0;
  const amount1Num = parseFloat(amount1) || 0;
  const hasAmount = amount0Num > 0 || amount1Num > 0;

  const amount0Exceeds =
    amount0Num > 0 &&
    parseFloat(balance0) > 0 &&
    amount0Num > parseFloat(balance0);
  const amount1Exceeds =
    amount1Num > 0 &&
    parseFloat(balance1) > 0 &&
    amount1Num > parseFloat(balance1);

  const tickLower = -887220;
  const tickUpper = 887220;

  const formatEquivalent = (value: number, decimals: number): string => {
    if (!Number.isFinite(value) || value <= 0) return "";
    const maxDigits = Math.min(Math.max(decimals, 0), 8);
    return value.toFixed(maxDigits).replace(/\.?0+$/, "");
  };

  const updateFromAmount0 = (value: string) => {
    setAmount0(value);
    const n = parseFloat(value);
    if (!Number.isFinite(n) || n <= 0) {
      setAmount1("");
      return;
    }
    setAmount1(formatEquivalent(n * referencePrice, decimals1));
  };

  const updateFromAmount1 = (value: string) => {
    setAmount1(value);
    const n = parseFloat(value);
    if (!Number.isFinite(n) || n <= 0 || referencePrice <= 0) {
      setAmount0("");
      return;
    }
    setAmount0(formatEquivalent(n / referencePrice, decimals0));
  };

  const handleMaxToken0 = () => updateFromAmount0(balance0);
  const handleMaxToken1 = () => updateFromAmount1(balance1);

  const addLiquidity = useCallback(async () => {
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

    let amount0Wei: bigint, amount1Wei: bigint;
    try {
      amount0Wei = parseUnits(amount0 || "0", decimals0);
      amount1Wei = parseUnits(amount1 || "0", decimals1);
    } catch {
      setError("Invalid amount.");
      return;
    }

    const priceLower = tickToPrice(tickLower);
    const priceUpper = tickToPrice(tickUpper);
    const liqFrom0 =
      amount0Num > 0
        ? computeLiquidityFromAmount(
            referencePrice,
            priceLower,
            priceUpper,
            amount0Num,
            0,
          ).liquidity
        : 0;
    const liqFrom1 =
      amount1Num > 0
        ? computeLiquidityFromAmount(
            referencePrice,
            priceLower,
            priceUpper,
            amount1Num,
            1,
          ).liquidity
        : 0;
    const liquidityHuman =
      liqFrom0 > 0 && liqFrom1 > 0
        ? Math.min(liqFrom0, liqFrom1)
        : liqFrom0 > 0
          ? liqFrom0
          : liqFrom1;
    const liquidityWei = liquidityToWei(liquidityHuman, decimals0, decimals1);

    if (amount0Wei === 0n && amount1Wei === 0n) {
      setError("Enter amount for at least one token.");
      return;
    }
    if (liquidityWei === 0n) {
      setError("Unable to compute liquidity from provided amounts.");
      return;
    }

    setError(null);
    setPending(true);
    setTxHash(null);

    try {
      const ownerEvmAddress = accountIdToEvmAddress(accountId);
      if (!ownerEvmAddress) {
        setError("Cannot derive EVM address.");
        setPending(false);
        return;
      }

      const poolKey = buildPoolKey(
        pool.currency0 as `0x${string}`,
        pool.currency1 as `0x${string}`,
        pool.fee,
        pool.tickSpacing,
      );

      const pmAddr = positionManagerAddress;
      const deadline = BigInt(Math.floor(Date.now() / 1000) + 3600);
      const sqrtPriceX96 = encodePriceSqrt(
        referencePrice,
        decimals0,
        decimals1,
      );

      const unlockData = encodeUnlockDataMint(
        poolKey,
        tickLower,
        tickUpper,
        liquidityWei,
        amount0Wei,
        amount1Wei,
        ownerEvmAddress as `0x${string}`,
      );

      // Transfer tokens to PositionManager
      for (const [currency, amountWei] of [
        [poolKey.currency0, amount0Wei],
        [poolKey.currency1, amount1Wei],
      ] as const) {
        if (amountWei > 0n) {
          await hederaTokenTransfer({
            hashConnect: hc,
            accountId,
            tokenAddress: currency,
            to: pmAddr,
            amount: amountWei,
            gas: HEDERA_GAS_ERC20,
          });
        }
      }

      // Multicall: initializePool (no-op if exists) + modifyLiquidities
      const { encodeFunctionData: encFn } = await import("viem");
      const initializeCalldata = encFn({
        abi: PositionManagerAbi,
        functionName: "initializePool",
        args: [poolKey, sqrtPriceX96],
      }) as `0x${string}`;
      const modifyCalldata = encFn({
        abi: PositionManagerAbi,
        functionName: "modifyLiquidities",
        args: [unlockData, deadline],
      }) as `0x${string}`;

      const txId = await hederaContractMulticall({
        hashConnect: hc,
        accountId,
        contractId: pmAddr,
        calls: [initializeCalldata, modifyCalldata],
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
    amount0,
    amount1,
    amount0Num,
    amount1Num,
    decimals0,
    decimals1,
    referencePrice,
    isConnected,
    accountId,
    hashConnectRef,
  ]);

  const buttonText = !isConnected
    ? "Connect wallet"
    : !hasAmount
      ? "Enter an amount"
      : amount0Exceeds
        ? `Insufficient ${pool.symbol0}`
        : amount1Exceeds
          ? `Insufficient ${pool.symbol1}`
          : pending
            ? "Adding liquidity…"
            : "Add liquidity";

  const canSubmit =
    isConnected &&
    hasAmount &&
    !amount0Exceeds &&
    !amount1Exceeds &&
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

      {/* Token 0 input */}
      <div
        className={`rounded-xl border ${amount0Exceeds ? "border-error/40" : "border-white/[0.06]"} bg-surface-2/50 p-4`}
      >
        <div className="flex flex-wrap items-center gap-2 sm:gap-3">
          <input
            type="text"
            inputMode="decimal"
            className="flex-1 min-w-[80px] bg-transparent text-xl font-semibold text-text-primary placeholder:text-text-tertiary focus:outline-none"
            placeholder="0"
            value={amount0}
            onChange={(e) => {
              updateFromAmount0(e.target.value);
              setError(null);
            }}
          />
          <div className="flex items-center gap-2 px-3 py-2 bg-surface-3/80 rounded-full shrink-0 border border-white/[0.06]">
            <TokenIcon symbol={pool.symbol0} size={22} />
            <span className="text-sm font-semibold text-text-primary">
              {pool.symbol0}
            </span>
          </div>
        </div>
        {isConnected && (
          <div className="flex items-center justify-between mt-2 text-xs">
            {amount0Exceeds ? (
              <span className="text-error">Exceeds balance</span>
            ) : (
              <span className="text-text-tertiary" />
            )}
            <button
              type="button"
              className="text-text-tertiary hover:text-accent transition-colors cursor-pointer"
              onClick={handleMaxToken0}
            >
              Balance:{" "}
              <span className="font-medium text-text-secondary">
                {balance0}
              </span>{" "}
              {pool.symbol0}
              <span className="ml-1.5 text-accent font-medium">MAX</span>
            </button>
          </div>
        )}
      </div>

      {/* Plus icon */}
      <div className="flex justify-center -my-1">
        <div className="w-8 h-8 rounded-full bg-surface-2 border border-white/[0.06] flex items-center justify-center">
          <svg
            width="14"
            height="14"
            viewBox="0 0 24 24"
            fill="none"
            stroke="currentColor"
            strokeWidth="2.5"
            className="text-text-tertiary"
          >
            <line x1="12" y1="5" x2="12" y2="19" />
            <line x1="5" y1="12" x2="19" y2="12" />
          </svg>
        </div>
      </div>

      {/* Token 1 input */}
      <div
        className={`rounded-xl border ${amount1Exceeds ? "border-error/40" : "border-white/[0.06]"} bg-surface-2/50 p-4`}
      >
        <div className="flex flex-wrap items-center gap-2 sm:gap-3">
          <input
            type="text"
            inputMode="decimal"
            className="flex-1 min-w-[80px] bg-transparent text-xl font-semibold text-text-primary placeholder:text-text-tertiary focus:outline-none"
            placeholder="0"
            value={amount1}
            onChange={(e) => {
              updateFromAmount1(e.target.value);
              setError(null);
            }}
          />
          <div className="flex items-center gap-2 px-3 py-2 bg-surface-3/80 rounded-full shrink-0 border border-white/[0.06]">
            <TokenIcon symbol={pool.symbol1} size={22} />
            <span className="text-sm font-semibold text-text-primary">
              {pool.symbol1}
            </span>
          </div>
        </div>
        {isConnected && (
          <div className="flex items-center justify-between mt-2 text-xs">
            {amount1Exceeds ? (
              <span className="text-error">Exceeds balance</span>
            ) : (
              <span className="text-text-tertiary" />
            )}
            <button
              type="button"
              className="text-text-tertiary hover:text-accent transition-colors cursor-pointer"
              onClick={handleMaxToken1}
            >
              Balance:{" "}
              <span className="font-medium text-text-secondary">
                {balance1}
              </span>{" "}
              {pool.symbol1}
              <span className="ml-1.5 text-accent font-medium">MAX</span>
            </button>
          </div>
        )}
      </div>

      {/* Error / Success */}
      {error && (
        <ErrorMessage message={error} onDismiss={() => setError(null)} />
      )}
      {txHash && (
        <div className="flex items-center gap-2 px-4 py-3 rounded-xl bg-success-muted text-success text-sm">
          Liquidity added!{" "}
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
        onClick={addLiquidity}
        loading={pending}
      >
        {buttonText}
      </Button>

      {/* Link to full flow */}
      {onOpenFullFlow && (
        <button
          type="button"
          className="w-full text-center text-xs text-accent hover:text-accent-hover cursor-pointer py-1"
          onClick={() => {
            onClose();
            onOpenFullFlow();
          }}
        >
          Advanced options (custom range, initial price) →
        </button>
      )}
    </div>
  );
}
