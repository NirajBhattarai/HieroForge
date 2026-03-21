"use client";

import { useState, useCallback, useEffect, useMemo } from "react";
import { parseUnits, createPublicClient, http, getAddress } from "viem";
import { TokenIcon, TokenPairIcon } from "./TokenIcon";
import { Badge } from "@/components/ui/Badge";
import { Button } from "@/components/ui/Button";
import { ErrorMessage } from "./ErrorMessage";
import { useHashPack } from "@/context/HashPackContext";
import { useTokenBalance } from "@/hooks/useTokenBalance";
import {
  getTokenDecimals,
  getPositionManagerAddress,
  getPoolManagerAddress,
  getRpcUrl,
  HEDERA_TESTNET,
  HOOKS_ZERO,
} from "@/constants";
import {
  buildPoolKey,
  getPoolId,
  encodeUnlockDataIncrease,
  encodeUnlockDataIncreaseFromDeltas,
} from "@/lib/addLiquidity";
import { encodePriceSqrt, sqrtPriceX96ToPrice } from "@/lib/priceUtils";
import {
  getSqrtPriceAtTick,
  maxLiquidityForAmounts,
  amountsForLiquidity,
  clampTick,
} from "@/lib/sqrtPriceMath";
import {
  hederaTokenTransfer,
  hederaTokenApprove,
  hederaContractMulticall,
} from "@/lib/hederaContract";
import { PositionManagerAbi } from "@/abis/PositionManager";
import { PoolManagerAbi } from "@/abis/PoolManager";
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
  const [useFromDeltas, setUseFromDeltas] = useState(false);
  /** Current pool price (token1 per token0) from chain; used to auto-calc the other amount when user types one */
  const [poolPrice, setPoolPrice] = useState<number | null>(null);

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
  const poolManagerAddress = getPoolManagerAddress();
  const parsedInitialPrice = parseFloat(pool.initialPrice ?? "");
  const referencePrice =
    Number.isFinite(parsedInitialPrice) && parsedInitialPrice > 0
      ? parsedInitialPrice
      : 1;
  /** Price used for auto-calculation: live pool price when available, else initial/reference */
  const effectivePrice = poolPrice != null && poolPrice > 0 ? poolPrice : referencePrice;

  const hooksForPool = useMemo(() => {
    const h = pool.hooks?.trim();
    if (h && /^0x[a-fA-F0-9]{40}$/.test(h))
      return getAddress(h as `0x${string}`);
    return HOOKS_ZERO as `0x${string}`;
  }, [pool.hooks]);

  // Fetch on-chain sqrtPriceX96 when modal opens so we can show "rate from pool" and auto-calc the other token amount
  useEffect(() => {
    if (!poolManagerAddress || !pool.currency0 || !pool.currency1) return;
    let cancelled = false;
    const poolKey = buildPoolKey(
      pool.currency0 as `0x${string}`,
      pool.currency1 as `0x${string}`,
      pool.fee,
      pool.tickSpacing,
      hooksForPool,
    );
    const poolId = getPoolId(poolKey);
    const pc = createPublicClient({
      chain: HEDERA_TESTNET,
      transport: http(getRpcUrl()),
    });
    pc.readContract({
      address: poolManagerAddress as `0x${string}`,
      abi: PoolManagerAbi,
      functionName: "getPoolState",
      args: [poolId],
    })
      .then((state) => {
        if (cancelled) return;
        const [initialized, sqrtPriceX96] = state as [boolean, bigint, number];
        if (initialized && sqrtPriceX96 > 0n) {
          const price = sqrtPriceX96ToPrice(sqrtPriceX96, decimals0, decimals1);
          if (Number.isFinite(price) && price > 0) setPoolPrice(price);
        }
      })
      .catch(() => {});
    return () => {
      cancelled = true;
    };
  }, [
    poolManagerAddress,
    pool.currency0,
    pool.currency1,
    pool.fee,
    pool.tickSpacing,
    hooksForPool,
    decimals0,
    decimals1,
  ]);

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

  /** Must match the on-chain position's tick range (increase liquidity only). */
  const tickLower = useMemo(() => {
    if (pool.tokenId != null && pool.tickLower != null) {
      return clampTick(pool.tickLower, pool.tickSpacing);
    }
    return clampTick(-887220, pool.tickSpacing);
  }, [pool.tokenId, pool.tickLower, pool.tickSpacing]);
  const tickUpper = useMemo(() => {
    if (pool.tokenId != null && pool.tickUpper != null) {
      return clampTick(pool.tickUpper, pool.tickSpacing);
    }
    return clampTick(887220, pool.tickSpacing);
  }, [pool.tokenId, pool.tickUpper, pool.tickSpacing]);

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
    setAmount1(formatEquivalent(n * effectivePrice, decimals1));
  };

  const updateFromAmount1 = (value: string) => {
    setAmount1(value);
    const n = parseFloat(value);
    if (!Number.isFinite(n) || n <= 0 || effectivePrice <= 0) {
      setAmount0("");
      return;
    }
    setAmount0(formatEquivalent(n / effectivePrice, decimals0));
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

    if (amount0Wei === 0n && amount1Wei === 0n) {
      setError("Enter amount for at least one token.");
      return;
    }

    if (pool.tokenId == null) {
      setError("Select an existing position or create one first.");
      return;
    }
    if (pool.tickLower == null || pool.tickUpper == null) {
      setError(
        "This position is missing tick range data. Open it from Your positions or refresh.",
      );
      return;
    }

    setError(null);
    setPending(true);
    setTxHash(null);

    try {
      const poolKey = buildPoolKey(
        pool.currency0 as `0x${string}`,
        pool.currency1 as `0x${string}`,
        pool.fee,
        pool.tickSpacing,
        hooksForPool,
      );

      const pmAddr = positionManagerAddress;
      const poolMgr = getPoolManagerAddress();
      const deadline = BigInt(Math.floor(Date.now() / 1000) + 3600);

      let onChainSqrtPrice: bigint | null = null;
      if (poolMgr) {
        try {
          const { createPublicClient, http } = await import("viem");
          const pc = createPublicClient({
            chain: HEDERA_TESTNET,
            transport: http(getRpcUrl()),
          });
          const poolId = getPoolId(poolKey);
          const state = (await pc.readContract({
            address: poolMgr as `0x${string}`,
            abi: PoolManagerAbi,
            functionName: "getPoolState",
            args: [poolId],
          })) as [boolean, bigint, number];
          if (state[0] && state[1] > 0n) {
            onChainSqrtPrice = state[1];
          }
          console.log(
            "[AddLiq modal] sqrtPriceX96:",
            onChainSqrtPrice?.toString(),
          );
        } catch (e) {
          console.warn("[AddLiq modal] getPoolState failed:", e);
        }
      }

      const sqrtPriceX96ForInit = encodePriceSqrt(
        referencePrice,
        decimals0,
        decimals1,
      );
      const sqrtPriceX96 = onChainSqrtPrice ?? sqrtPriceX96ForInit;

      // BigInt liquidity computation
      const sqrtPA = getSqrtPriceAtTick(tickLower);
      const sqrtPB = getSqrtPriceAtTick(tickUpper);

      const liquidityBigInt = maxLiquidityForAmounts(
        sqrtPriceX96,
        sqrtPA,
        sqrtPB,
        amount0Wei,
        amount1Wei,
      );

      if (liquidityBigInt === 0n) {
        setError("Computed liquidity is zero. Adjust amounts.");
        setPending(false);
        return;
      }

      // Compute exact amounts + 1% slippage buffer
      const exact = amountsForLiquidity(
        sqrtPriceX96,
        sqrtPA,
        sqrtPB,
        liquidityBigInt,
      );
      const amount0Max = exact.amount0 + exact.amount0 / 100n + 1n;
      const amount1Max = exact.amount1 + exact.amount1 / 100n + 1n;

      console.log(
        "[AddLiq modal] BigInt math:",
        "L:",
        liquidityBigInt.toString(),
        "exact0:",
        exact.amount0.toString(),
        "exact1:",
        exact.amount1.toString(),
        "max0:",
        amount0Max.toString(),
        "max1:",
        amount1Max.toString(),
      );

      const tokenIdBn = BigInt(pool.tokenId);
      const unlockData = useFromDeltas
        ? encodeUnlockDataIncreaseFromDeltas(
            tokenIdBn,
            liquidityBigInt,
            amount0Max,
            amount1Max,
            poolKey.currency0,
            poolKey.currency1,
          )
        : encodeUnlockDataIncrease(
            tokenIdBn,
            liquidityBigInt,
            amount0Max,
            amount1Max,
          );

      // Plain INCREASE: PM settles from its ERC20 balance (transfer to PM first).
      // INCREASE_FROM_DELTAS + SETTLE_PAIR: approve PM so it can transferFrom your wallet.
      if (useFromDeltas) {
        for (const [currency, amtWei] of [
          [poolKey.currency0, amount0Max],
          [poolKey.currency1, amount1Max],
        ] as const) {
          if (amtWei > 0n) {
            await hederaTokenApprove({
              hashConnect: hc,
              accountId,
              tokenAddress: currency,
              spender: pmAddr,
              amount: amtWei,
              gas: HEDERA_GAS_ERC20,
            });
          }
        }
      } else {
        for (const [currency, amtWei] of [
          [poolKey.currency0, amount0Max],
          [poolKey.currency1, amount1Max],
        ] as const) {
          if (amtWei > 0n) {
            await hederaTokenTransfer({
              hashConnect: hc,
              accountId,
              tokenAddress: currency,
              to: pmAddr,
              amount: amtWei,
              gas: HEDERA_GAS_ERC20,
            });
          }
        }
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
        contractId: pmAddr,
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
    pool.tokenId,
    pool.tickLower,
    pool.tickUpper,
    hooksForPool,
    tickLower,
    tickUpper,
    amount0,
    amount1,
    decimals0,
    decimals1,
    referencePrice,
    useFromDeltas,
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
            : "Add to position";

  const canSubmit =
    isConnected &&
    pool.tokenId != null &&
    hasAmount &&
    !amount0Exceeds &&
    !amount1Exceeds &&
    !pending &&
    !!positionManagerAddress;

  if (pool.tokenId == null) {
    return (
      <div className="space-y-4">
        <p className="text-sm text-text-secondary leading-relaxed">
          Liquidity is always tied to a position NFT. Create a position first
          (you choose the price range); then you can add more liquidity to it
          here.
        </p>
        <div className="flex flex-wrap gap-2">
          {onOpenFullFlow && (
            <Button
              variant="primary"
              onClick={() => {
                onClose();
                onOpenFullFlow();
              }}
            >
              Create position
            </Button>
          )}
          <Button variant="secondary" onClick={onClose}>
            Close
          </Button>
        </div>
      </div>
    );
  }

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
        <Badge className="bg-accent/15 text-accent text-[10px]">
          Position #{pool.tokenId}
        </Badge>
        <span className="flex items-center gap-1.5 text-xs text-text-tertiary ml-auto">
          <span className="w-2 h-2 rounded-full bg-success" />
          In range
        </span>
      </div>
      {pool.tickLower != null && pool.tickUpper != null && (
        <p className="text-xs text-text-tertiary px-0.5">
          Deposits use this position&apos;s ticks [{pool.tickLower}, {pool.tickUpper}].
          For a different range, create another position.
        </p>
      )}

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

      {/* FROM_DELTAS toggle */}
      <div className="flex items-center justify-between px-1 py-2 rounded-xl bg-surface-2/50 border border-white/[0.04]">
        <div className="pl-2">
          <span className="text-xs font-medium text-text-secondary">
            Use FROM_DELTAS
          </span>
          <p className="text-[10px] text-text-tertiary mt-0.5">
            SETTLE_PAIR pulls via transferFrom — approves PositionManager (no pre-transfer)
          </p>
        </div>
        <button
          type="button"
          onClick={() => setUseFromDeltas(!useFromDeltas)}
          className={`relative w-10 h-5 rounded-full transition-colors cursor-pointer mr-2 ${
            useFromDeltas ? "bg-accent" : "bg-surface-3"
          }`}
        >
          <span
            className={`absolute top-0.5 left-0.5 w-4 h-4 rounded-full bg-white transition-transform ${
              useFromDeltas ? "translate-x-5" : ""
            }`}
          />
        </button>
      </div>

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
