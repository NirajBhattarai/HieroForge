"use client";

import { useState, useCallback, useEffect, useRef } from "react";
import {
  createPublicClient,
  http,
  parseUnits,
  formatUnits,
  getAddress,
  type Address,
} from "viem";
import { useHashPack } from "@/context/HashPackContext";
import {
  quoteExactInputSingle,
  quoteExactOutputSingle,
  quoteExactInput,
  NotEnoughLiquidityError,
  type QuotePathKey,
} from "@/lib/quote";
import { getFriendlyErrorMessage } from "@/lib/errors";
import { ErrorMessage } from "@/components/ErrorMessage";
import { TokenIcon } from "@/components/TokenIcon";
import { TokenSelector } from "@/components/ui/TokenSelector";
import { Skeleton } from "@/components/ui/Skeleton";
import type { PoolInfo } from "@/components/PoolPositions";
import {
  HEDERA_TESTNET,
  getTokenAddress,
  getTokenDecimals,
  getQuoterAddress,
  getRouterAddress,
  getPoolManagerAddress,
  DEFAULT_FEE,
  DEFAULT_TICK_SPACING,
  FEE_TIERS,
  feeTierToTickSpacing,
  HOOKS_ZERO,
  type TokenOption,
} from "@/constants";
import { buildPoolKey, getPoolId } from "@/lib/addLiquidity";
import { PoolManagerAbi } from "@/abis/PoolManager";
import { useTokens } from "@/hooks/useTokens";
import { useTokenBalance } from "@/hooks/useTokenBalance";
import { hederaContractExecute } from "@/lib/hederaContract";
import {
  buildSwapPoolKey,
  encodeSwapExactInSingle,
  encodeSwapExactOutSingle,
  encodeSwapExactIn,
  buildPath,
  type PathKey,
} from "@/lib/swap";
import { UniversalRouterAbi } from "@/abis/UniversalRouter";
import { ERC20Abi } from "@/abis/ERC20";

interface SwapCardProps {
  selectedPool: {
    poolId: string;
    currency0: string;
    currency1: string;
    fee: number;
    tickSpacing: number;
    symbol0: string;
    symbol1: string;
    hooks?: string;
  } | null;
}

type SwapMode = "exactIn" | "exactOut";

const SLIPPAGE_OPTIONS = [0.5, 1, 2, 5] as const;

export function SwapCard({ selectedPool }: SwapCardProps) {
  const { accountId, isConnected, hashConnectRef } = useHashPack();

  const { tokens: dynamicTokens, loading: tokensLoading } = useTokens();

  const resolveAddress = (tok: TokenOption): string =>
    (tok.address ?? getTokenAddress(tok.symbol)).toLowerCase();
  const resolveDecimals = (tok: TokenOption): number =>
    tok.decimals ?? getTokenDecimals(tok.symbol);

  const tokenOptions: TokenOption[] = dynamicTokens.map((t) => ({
    id: t.address,
    symbol: t.symbol,
    address: t.address,
    decimals: t.decimals,
    name: t.name,
  }));

  // Swap state
  const EMPTY_TOKEN: TokenOption = {
    id: "",
    symbol: "",
    address: "",
    decimals: 18,
  };
  const [amountIn, setAmountIn] = useState("");
  const [amountOut, setAmountOut] = useState("");
  const [quoteError, setQuoteError] = useState<string | null>(null);
  const [quoteLoading, setQuoteLoading] = useState(false);
  const [tokenIn, setTokenIn] = useState<TokenOption>(EMPTY_TOKEN);
  const [tokenOut, setTokenOut] = useState<TokenOption>(EMPTY_TOKEN);
  const [selectorOpen, setSelectorOpen] = useState<"in" | "out" | "mid" | null>(
    null,
  );

  // Multi-hop
  const [intermediateToken, setIntermediateToken] =
    useState<TokenOption | null>(null);
  const [multiHopEnabled, setMultiHopEnabled] = useState(false);

  // Track whether a valid pool exists for the current token pair
  const [hasPool, setHasPool] = useState(false);

  // Swap mode & slippage settings
  const [swapMode, setSwapMode] = useState<SwapMode>("exactIn");
  const [slippage, setSlippage] = useState(2);
  const [showSettings, setShowSettings] = useState(false);
  const [customSlippage, setCustomSlippage] = useState("");
  const [swapFee, setSwapFee] = useState(DEFAULT_FEE);
  const swapTickSpacing = feeTierToTickSpacing(swapFee);

  const addrIn = resolveAddress(tokenIn);
  const addrOut = resolveAddress(tokenOut);
  const { balanceFormatted: balanceIn, refetch: refetchBalanceIn } =
    useTokenBalance(addrIn || undefined, accountId, resolveDecimals(tokenIn));
  const { balanceFormatted: balanceOut, refetch: refetchBalanceOut } =
    useTokenBalance(addrOut || undefined, accountId, resolveDecimals(tokenOut));

  // When a pool is selected, auto-set tokenIn/tokenOut to the pool's tokens
  useEffect(() => {
    if (!selectedPool || tokenOptions.length === 0) {
      if (!selectedPool) {
        setHasPool(false);
        setAmountIn("");
        setAmountOut("");
      }
      return;
    }
    const c0 = selectedPool.currency0.toLowerCase();
    const c1 = selectedPool.currency1.toLowerCase();
    const match0 = tokenOptions.find(
      (t) => (t.address ?? "").toLowerCase() === c0,
    );
    const match1 = tokenOptions.find(
      (t) => (t.address ?? "").toLowerCase() === c1,
    );
    if (match0 && match1) {
      setTokenIn(match0);
      setTokenOut(match1);
      setSwapFee(selectedPool.fee);
      setHasPool(true);
    }
  }, [selectedPool?.poolId, tokenOptions.length]);

  // Fallback: when no pool is selected and tokens not set, auto-pick first two tokens
  useEffect(() => {
    if (
      tokenOptions.length < 2 ||
      tokenIn.symbol ||
      tokenOut.symbol ||
      selectedPool
    )
      return;
    // Just pick first two tokens; pool detection will happen via on-chain check
    setTokenIn(tokenOptions[0]!);
    setTokenOut(tokenOptions[1]!);
  }, [tokenOptions.length]);

  // Auto-detect pool when user changes tokenIn/tokenOut (Uniswap-style)
  const matchedPoolRef = useRef<PoolInfo | null>(null);
  useEffect(() => {
    const a0 = resolveAddress(tokenIn);
    const a1 = resolveAddress(tokenOut);
    if (!a0 || !a1 || a0 === a1) {
      setHasPool(false);
      matchedPoolRef.current = null;
      return;
    }
    // If selectedPool already matches, use it
    if (selectedPool) {
      const sortedC0 = a0 < a1 ? a0 : a1;
      const sortedC1 = a0 < a1 ? a1 : a0;
      if (
        selectedPool.currency0.toLowerCase() === sortedC0 &&
        selectedPool.currency1.toLowerCase() === sortedC1
      ) {
        setHasPool(true);
        matchedPoolRef.current = selectedPool as unknown as PoolInfo;
        return;
      }
    }
    // Otherwise, check on-chain directly across all fee tiers
    let cancelled = false;
    (async () => {
      const poolMgrAddr = getPoolManagerAddress();
      const client = publicClientRef.current;
      if (!poolMgrAddr || !client) {
        if (!cancelled) {
          setHasPool(false);
          matchedPoolRef.current = null;
        }
        return;
      }
      const sortedC0 = a0 < a1 ? a0 : a1;
      const sortedC1 = a0 < a1 ? a1 : a0;
      for (const tier of FEE_TIERS) {
        if (cancelled) return;
        try {
          const pk = buildPoolKey(
            sortedC0 as `0x${string}`,
            sortedC1 as `0x${string}`,
            tier.fee,
            feeTierToTickSpacing(tier.fee),
          );
          const poolId = getPoolId(pk);
          const state = (await client.readContract({
            address: poolMgrAddr as `0x${string}`,
            abi: PoolManagerAbi,
            functionName: "getPoolState",
            args: [poolId],
          })) as [boolean, bigint, number];
          if (state[0]) {
            if (!cancelled) {
              setSwapFee(tier.fee);
              setHasPool(true);
              matchedPoolRef.current = {
                poolId,
                currency0: pk.currency0,
                currency1: pk.currency1,
                fee: tier.fee,
                tickSpacing: feeTierToTickSpacing(tier.fee),
                symbol0: tokenIn.symbol,
                symbol1: tokenOut.symbol,
              } as unknown as PoolInfo;
              console.log(
                "[Swap] pool found on-chain:",
                poolId,
                "fee:",
                tier.fee,
              );
            }
            return;
          }
        } catch {
          // This fee tier doesn't have a pool, try next
        }
      }
      if (!cancelled) {
        setHasPool(false);
        matchedPoolRef.current = null;
      }
    })();
    return () => {
      cancelled = true;
    };
  }, [tokenIn.id, tokenOut.id, selectedPool?.poolId]);

  const quoterAddress = getQuoterAddress();
  const routerAddress = getRouterAddress();

  const [swapLoading, setSwapLoading] = useState(false);
  const [swapError, setSwapError] = useState<string | null>(null);
  const [swapTxId, setSwapTxId] = useState<string | null>(null);

  const publicClientRef = useRef<ReturnType<typeof createPublicClient> | null>(
    null,
  );
  if (!publicClientRef.current && typeof window !== "undefined") {
    publicClientRef.current = createPublicClient({
      chain: HEDERA_TESTNET,
      transport: http(HEDERA_TESTNET.rpcUrls.default.http[0]),
    });
  }

  // Quote — skip if no valid pool
  useEffect(() => {
    if (!hasPool) return;
    const primaryAmount = swapMode === "exactIn" ? amountIn : amountOut;
    if (
      !quoterAddress ||
      !primaryAmount ||
      primaryAmount === "." ||
      primaryAmount === "0" ||
      primaryAmount === "0."
    ) {
      if (
        primaryAmount === "" ||
        primaryAmount === "0" ||
        primaryAmount === "0."
      ) {
        if (swapMode === "exactIn") setAmountOut("");
        else setAmountIn("");
      }
      setQuoteError(null);
      setQuoteLoading(false);
      return;
    }
    const addrIn = resolveAddress(tokenIn);
    const addrOut = resolveAddress(tokenOut);
    if (!addrIn || !addrOut || addrIn === addrOut) {
      if (swapMode === "exactIn") setAmountOut("");
      else setAmountIn("");
      setQuoteError(null);
      setQuoteLoading(false);
      return;
    }

    const decimalsIn = resolveDecimals(tokenIn);
    const decimalsOut = resolveDecimals(tokenOut);
    const addrMid =
      intermediateToken && multiHopEnabled
        ? resolveAddress(intermediateToken)
        : null;

    let cancelled = false;
    setQuoteError(null);
    setQuoteLoading(true);
    const id = setTimeout(async () => {
      try {
        const client = publicClientRef.current;
        if (!client) {
          if (!cancelled) setQuoteLoading(false);
          return;
        }

        // Multi-hop path?
        if (addrMid && addrMid !== addrIn && addrMid !== addrOut) {
          // Multi-hop: In → Mid → Out
          const path: QuotePathKey[] = [
            {
              intermediateCurrency: addrMid,
              fee: swapFee,
              tickSpacing: swapTickSpacing,
              hooks: HOOKS_ZERO,
              hookData: "0x",
            },
            {
              intermediateCurrency: addrOut,
              fee: swapFee,
              tickSpacing: swapTickSpacing,
              hooks: HOOKS_ZERO,
              hookData: "0x",
            },
          ];

          if (swapMode === "exactIn") {
            let amountInWei: bigint;
            try {
              amountInWei = parseUnits(amountIn, decimalsIn);
            } catch {
              if (!cancelled) setAmountOut("");
              if (!cancelled) setQuoteLoading(false);
              return;
            }
            const amountOutWei = await quoteExactInput(
              client as import("viem").PublicClient,
              quoterAddress as `0x${string}`,
              addrIn,
              path,
              amountInWei,
            );
            if (!cancelled) {
              setAmountOut(formatUnits(amountOutWei, decimalsOut));
              setQuoteError(null);
            }
          } else {
            // exact-output multi-hop not implemented in quoter UI yet
            if (!cancelled) {
              setAmountIn("");
              setQuoteError("Exact output multi-hop not yet supported");
            }
          }
        } else {
          // Single-hop
          const currency0 = addrIn < addrOut ? addrIn : addrOut;
          const currency1 = addrIn < addrOut ? addrOut : addrIn;
          const zeroForOne = addrIn < addrOut;
          const useSelected =
            selectedPool &&
            selectedPool.currency0.toLowerCase() === currency0.toLowerCase() &&
            selectedPool.currency1.toLowerCase() === currency1.toLowerCase();
          const mp = matchedPoolRef.current;
          const useMatched =
            !useSelected &&
            mp &&
            mp.currency0.toLowerCase() === currency0.toLowerCase() &&
            mp.currency1.toLowerCase() === currency1.toLowerCase();
          const fee = useSelected
            ? selectedPool.fee
            : useMatched
              ? mp.fee
              : swapFee;
          const tickSpacing = useSelected
            ? selectedPool.tickSpacing
            : useMatched
              ? (mp.tickSpacing ?? feeTierToTickSpacing(fee))
              : swapTickSpacing;
          const hooks = useSelected
            ? (selectedPool.hooks ?? HOOKS_ZERO)
            : useMatched
              ? (mp.hooks ?? HOOKS_ZERO)
              : HOOKS_ZERO;
          const poolKey = { currency0, currency1, fee, tickSpacing, hooks };

          if (swapMode === "exactIn") {
            let amountInWei: bigint;
            try {
              amountInWei = parseUnits(amountIn, decimalsIn);
            } catch {
              if (!cancelled) setAmountOut("");
              if (!cancelled) setQuoteLoading(false);
              return;
            }
            const amountOutWei = await quoteExactInputSingle(
              client as import("viem").PublicClient,
              quoterAddress as `0x${string}`,
              poolKey,
              zeroForOne,
              amountInWei,
            );
            if (!cancelled) {
              setAmountOut(formatUnits(amountOutWei, decimalsOut));
              setQuoteError(null);
            }
          } else {
            let amountOutWei: bigint;
            try {
              amountOutWei = parseUnits(amountOut, decimalsOut);
            } catch {
              if (!cancelled) setAmountIn("");
              if (!cancelled) setQuoteLoading(false);
              return;
            }
            const amountInWei = await quoteExactOutputSingle(
              client as import("viem").PublicClient,
              quoterAddress as `0x${string}`,
              poolKey,
              zeroForOne,
              amountOutWei,
            );
            if (!cancelled) {
              setAmountIn(formatUnits(amountInWei, decimalsIn));
              setQuoteError(null);
            }
          }
        }
      } catch (err) {
        if (!cancelled) {
          if (swapMode === "exactIn") setAmountOut("");
          else setAmountIn("");
          setQuoteError(
            err instanceof NotEnoughLiquidityError
              ? err.message
              : getFriendlyErrorMessage(err, "quote"),
          );
        }
      }
      if (!cancelled) setQuoteLoading(false);
    }, 300);
    return () => {
      cancelled = true;
      clearTimeout(id);
    };
  }, [
    amountIn,
    amountOut,
    swapMode,
    tokenIn.symbol,
    tokenOut.symbol,
    intermediateToken?.symbol,
    multiHopEnabled,
    quoterAddress,
    selectedPool,
    swapFee,
    hasPool,
  ]);

  const flipTokens = () => {
    setTokenIn(tokenOut);
    setTokenOut(tokenIn);
    setAmountIn(amountOut);
    setAmountOut(amountIn);
    setSwapMode(swapMode === "exactIn" ? "exactOut" : "exactIn");
  };

  const handleSwap = useCallback(async () => {
    if (!accountId || !isConnected || !routerAddress || !amountIn || !amountOut)
      return;
    const hc = hashConnectRef.current;
    if (!hc) {
      setSwapError("HashConnect not initialized");
      return;
    }

    setSwapLoading(true);
    setSwapError(null);
    setSwapTxId(null);

    try {
      const addrIn = resolveAddress(tokenIn);
      const addrOut = resolveAddress(tokenOut);
      const decimalsIn = resolveDecimals(tokenIn);
      const decimalsOut = resolveDecimals(tokenOut);
      const amountInWei = parseUnits(amountIn, decimalsIn);
      const amountOutWei = parseUnits(amountOut, decimalsOut);

      const slippageBps = BigInt(Math.round(slippage * 100));
      const addrMid =
        intermediateToken && multiHopEnabled
          ? resolveAddress(intermediateToken)
          : null;
      const isMultiHop = addrMid && addrMid !== addrIn && addrMid !== addrOut;

      // Approve router for input token
      const approveAmount =
        swapMode === "exactIn"
          ? amountInWei
          : (amountInWei * (10000n + slippageBps)) / 10000n;

      console.log("[swap] Approving router to spend input token...");
      await hederaContractExecute({
        hashConnect: hc,
        accountId,
        contractId: addrIn,
        abi: ERC20Abi,
        functionName: "approve",
        args: [routerAddress, approveAmount],
        gas: 800_000,
      });

      let commands: `0x${string}`;
      let inputs: `0x${string}`[];

      if (isMultiHop) {
        // Multi-hop: In → Mid → Out
        const pathKeys = buildPath(
          [addrIn, addrMid!, addrOut],
          [swapFee, swapFee],
          [swapTickSpacing, swapTickSpacing],
        );
        const amountOutMinimum =
          (amountOutWei * (10000n - slippageBps)) / 10000n;
        ({ commands, inputs } = encodeSwapExactIn({
          currencyIn: getAddress(addrIn) as Address,
          path: pathKeys,
          amountIn: amountInWei,
          amountOutMinimum,
        }));
      } else if (swapMode === "exactIn") {
        // Single-hop exact input
        const sortedC0 = (addrIn < addrOut ? addrIn : addrOut).toLowerCase();
        const sortedC1 = (addrIn < addrOut ? addrOut : addrIn).toLowerCase();
        const useSelected =
          selectedPool &&
          selectedPool.currency0.toLowerCase() === sortedC0 &&
          selectedPool.currency1.toLowerCase() === sortedC1;
        const mp = matchedPoolRef.current;
        const useMatched =
          !useSelected &&
          mp &&
          mp.currency0.toLowerCase() === sortedC0 &&
          mp.currency1.toLowerCase() === sortedC1;
        const fee = useSelected
          ? selectedPool.fee
          : useMatched
            ? mp.fee
            : swapFee;
        const tickSpacing = useSelected
          ? selectedPool.tickSpacing
          : useMatched
            ? (mp.tickSpacing ?? feeTierToTickSpacing(fee))
            : swapTickSpacing;
        const hooks = useSelected
          ? (selectedPool.hooks ?? HOOKS_ZERO)
          : useMatched
            ? (mp.hooks ?? HOOKS_ZERO)
            : HOOKS_ZERO;
        const poolKey = buildSwapPoolKey(
          addrIn,
          addrOut,
          fee,
          tickSpacing,
          hooks as `0x${string}`,
        );
        const zeroForOne = addrIn.toLowerCase() < addrOut.toLowerCase();
        const amountOutMinimum =
          (amountOutWei * (10000n - slippageBps)) / 10000n;
        ({ commands, inputs } = encodeSwapExactInSingle({
          poolKey,
          zeroForOne,
          amountIn: amountInWei,
          amountOutMinimum,
        }));
      } else {
        // Single-hop exact output
        const sortedC0 = (addrIn < addrOut ? addrIn : addrOut).toLowerCase();
        const sortedC1 = (addrIn < addrOut ? addrOut : addrIn).toLowerCase();
        const useSelected =
          selectedPool &&
          selectedPool.currency0.toLowerCase() === sortedC0 &&
          selectedPool.currency1.toLowerCase() === sortedC1;
        const mp = matchedPoolRef.current;
        const useMatched =
          !useSelected &&
          mp &&
          mp.currency0.toLowerCase() === sortedC0 &&
          mp.currency1.toLowerCase() === sortedC1;
        const fee = useSelected
          ? selectedPool.fee
          : useMatched
            ? mp.fee
            : swapFee;
        const tickSpacing = useSelected
          ? selectedPool.tickSpacing
          : useMatched
            ? (mp.tickSpacing ?? feeTierToTickSpacing(fee))
            : swapTickSpacing;
        const hooks = useSelected
          ? (selectedPool.hooks ?? HOOKS_ZERO)
          : useMatched
            ? (mp.hooks ?? HOOKS_ZERO)
            : HOOKS_ZERO;
        const poolKey = buildSwapPoolKey(
          addrIn,
          addrOut,
          fee,
          tickSpacing,
          hooks as `0x${string}`,
        );
        const zeroForOne = addrIn.toLowerCase() < addrOut.toLowerCase();
        const amountInMaximum = (amountInWei * (10000n + slippageBps)) / 10000n;
        ({ commands, inputs } = encodeSwapExactOutSingle({
          poolKey,
          zeroForOne,
          amountOut: amountOutWei,
          amountInMaximum,
        }));
      }

      console.log("[swap] Executing swap via UniversalRouter...");
      const deadline = BigInt(Math.floor(Date.now() / 1000) + 120);

      const txId = await hederaContractExecute({
        hashConnect: hc,
        accountId,
        contractId: routerAddress,
        abi: UniversalRouterAbi,
        functionName: "execute",
        args: [commands, inputs, deadline],
        gas: isMultiHop ? 5_000_000 : 3_000_000,
      });

      console.log("[swap] Swap completed:", txId);
      setSwapTxId(txId);
      setAmountIn("");
      setAmountOut("");
      // Refresh balances after swap (mirror node may have ~3s delay)
      setTimeout(() => {
        refetchBalanceIn();
        refetchBalanceOut();
      }, 4000);
      setTimeout(() => {
        refetchBalanceIn();
        refetchBalanceOut();
      }, 8000);
    } catch (err) {
      console.error("[swap] Error:", err);
      setSwapError(getFriendlyErrorMessage(err, "swap"));
    } finally {
      setSwapLoading(false);
    }
  }, [
    accountId,
    isConnected,
    routerAddress,
    amountIn,
    amountOut,
    swapMode,
    slippage,
    tokenIn,
    tokenOut,
    intermediateToken,
    multiHopEnabled,
    selectedPool,
    swapFee,
    hashConnectRef,
    refetchBalanceIn,
    refetchBalanceOut,
  ]);

  const handleTokenSelect = (token: TokenOption) => {
    if (selectorOpen === "in") {
      if (token.id === tokenOut.id) {
        setTokenOut(tokenIn);
      }
      setTokenIn(token);
    } else if (selectorOpen === "out") {
      if (token.id === tokenIn.id) {
        setTokenIn(tokenOut);
      }
      setTokenOut(token);
    } else if (selectorOpen === "mid") {
      setIntermediateToken(token);
    }
    setSelectorOpen(null);
  };

  // Determine button state
  const getButtonState = () => {
    if (!isConnected) return { text: "Connect Wallet", disabled: true };
    if (!hasPool)
      return { text: "No pool found for this pair", disabled: true };
    if (!amountIn || parseFloat(amountIn) === 0)
      return { text: "Enter an amount", disabled: true };
    if (quoteLoading) return { text: "Fetching quote...", disabled: true };
    if (quoteError) return { text: "Swap", disabled: true };
    if (!amountOut) return { text: "Enter an amount", disabled: true };
    if (swapLoading) return { text: "Swapping...", disabled: true };
    if (!routerAddress)
      return { text: "Router not configured", disabled: true };
    return { text: "Swap", disabled: false };
  };

  const btnState = getButtonState();

  return (
    <>
      <div className="w-full max-w-[480px] mx-auto animate-[fadeIn_0.3s_ease-out]">
        {/* Card — glass-style with soft glow */}
        <div
          className="relative overflow-hidden rounded-2xl p-[1px] shadow-[0_8px_32px_rgba(0,0,0,0.4),0_0_0_1px_rgba(148,163,184,0.06)]"
          style={{
            background:
              "linear-gradient(135deg, rgba(56,189,248,0.12) 0%, rgba(30,41,59,0.4) 50%, rgba(56,189,248,0.06) 100%)",
          }}
        >
          <div className="relative rounded-2xl bg-surface-1/95 backdrop-blur-sm border border-white/[0.06] shadow-inner">
            <div className="p-4">
              {/* Header */}
              <div className="flex items-center justify-between px-1 pt-0.5 pb-2">
                <div className="flex items-center gap-3">
                  <h2 className="text-lg font-semibold text-text-primary tracking-tight">
                    Swap
                  </h2>
                </div>
                <button
                  type="button"
                  className="p-2 rounded-xl text-text-tertiary hover:text-text-secondary hover:bg-surface-3/80 transition-all duration-200 cursor-pointer"
                  title="Settings"
                  onClick={() => setShowSettings(!showSettings)}
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
                    <circle cx="12" cy="12" r="3" />
                    <path d="M19.4 15a1.65 1.65 0 00.33 1.82l.06.06a2 2 0 010 2.83 2 2 0 01-2.83 0l-.06-.06a1.65 1.65 0 00-1.82-.33 1.65 1.65 0 00-1 1.51V21a2 2 0 01-2 2 2 2 0 01-2-2v-.09A1.65 1.65 0 009 19.4a1.65 1.65 0 00-1.82.33l-.06.06a2 2 0 01-2.83 0 2 2 0 010-2.83l.06-.06A1.65 1.65 0 004.68 15a1.65 1.65 0 00-1.51-1H3a2 2 0 01-2-2 2 2 0 012-2h.09A1.65 1.65 0 004.6 9a1.65 1.65 0 00-.33-1.82l-.06-.06a2 2 0 010-2.83 2 2 0 012.83 0l.06.06A1.65 1.65 0 009 4.68a1.65 1.65 0 001-1.51V3a2 2 0 012-2 2 2 0 012 2v.09a1.65 1.65 0 001 1.51 1.65 1.65 0 001.82-.33l.06-.06a2 2 0 012.83 0 2 2 0 010 2.83l-.06.06A1.65 1.65 0 0019.32 9a1.65 1.65 0 001.51 1H21a2 2 0 012 2 2 2 0 01-2 2h-.09a1.65 1.65 0 00-1.51 1z" />
                  </svg>
                </button>
              </div>

              {/* Settings panel */}
              {showSettings && (
                <div className="mb-3 p-3 rounded-xl bg-surface-2/80 border border-white/[0.06] space-y-3 animate-[fadeIn_0.15s_ease-out]">
                  {/* Slippage */}
                  <div>
                    <span className="text-xs font-medium text-text-tertiary uppercase tracking-wider">
                      Slippage Tolerance
                    </span>
                    <div className="flex items-center gap-2 mt-1.5">
                      {SLIPPAGE_OPTIONS.map((s) => (
                        <button
                          key={s}
                          type="button"
                          onClick={() => {
                            setSlippage(s);
                            setCustomSlippage("");
                          }}
                          className={`px-3 py-1.5 text-xs font-medium rounded-lg transition-all cursor-pointer ${
                            slippage === s && !customSlippage
                              ? "bg-accent/20 text-accent border border-accent/30"
                              : "bg-surface-3/60 text-text-secondary border border-white/[0.06] hover:border-accent/20"
                          }`}
                        >
                          {s}%
                        </button>
                      ))}
                      <div className="relative flex-1 min-w-[70px]">
                        <input
                          type="text"
                          inputMode="decimal"
                          placeholder="Custom"
                          value={customSlippage}
                          onChange={(e) => {
                            const v = e.target.value;
                            setCustomSlippage(v);
                            const n = parseFloat(v);
                            if (Number.isFinite(n) && n > 0 && n <= 50)
                              setSlippage(n);
                          }}
                          className="w-full px-3 py-1.5 text-xs font-medium bg-surface-3/60 rounded-lg border border-white/[0.06] text-text-primary placeholder:text-text-disabled focus:outline-none focus:border-accent/30"
                        />
                        <span className="absolute right-2.5 top-1/2 -translate-y-1/2 text-xs text-text-tertiary">
                          %
                        </span>
                      </div>
                    </div>
                  </div>

                  {/* Multi-hop toggle */}
                  <div className="flex items-center justify-between">
                    <span className="text-xs font-medium text-text-tertiary uppercase tracking-wider">
                      Multi-hop Route
                    </span>
                    <button
                      type="button"
                      onClick={() => setMultiHopEnabled(!multiHopEnabled)}
                      className={`relative w-10 h-5 rounded-full transition-colors cursor-pointer ${
                        multiHopEnabled ? "bg-accent" : "bg-surface-3"
                      }`}
                    >
                      <span
                        className={`absolute top-0.5 left-0.5 w-4 h-4 rounded-full bg-white transition-transform ${
                          multiHopEnabled ? "translate-x-5" : ""
                        }`}
                      />
                    </button>
                  </div>

                  {/* Intermediate token picker */}
                  {multiHopEnabled && (
                    <div className="flex items-center gap-2">
                      <span className="text-xs text-text-tertiary">
                        Route through:
                      </span>
                      <button
                        type="button"
                        onClick={() => setSelectorOpen("mid")}
                        className="flex items-center gap-1.5 px-3 py-1.5 rounded-full bg-surface-3/80 border border-white/[0.08] hover:border-accent/30 transition-all cursor-pointer text-xs font-medium"
                      >
                        {intermediateToken ? (
                          <>
                            <TokenIcon
                              symbol={intermediateToken.symbol}
                              size={16}
                            />
                            <span className="text-text-primary">
                              {intermediateToken.symbol}
                            </span>
                          </>
                        ) : (
                          <span className="text-text-tertiary">
                            Select token
                          </span>
                        )}
                        <svg
                          width="10"
                          height="10"
                          viewBox="0 0 24 24"
                          fill="none"
                          stroke="currentColor"
                          strokeWidth="2.5"
                          className="text-text-tertiary"
                        >
                          <polyline points="6 9 12 15 18 9" />
                        </svg>
                      </button>
                    </div>
                  )}

                  {/* Fee tier selector */}
                  <div>
                    <span className="text-xs font-medium text-text-tertiary uppercase tracking-wider">
                      Fee Tier
                    </span>
                    <div className="flex items-center gap-2 mt-1.5">
                      {FEE_TIERS.map((tier) => (
                        <button
                          key={tier.fee}
                          type="button"
                          onClick={() => setSwapFee(tier.fee)}
                          className={`relative px-3 py-1.5 text-xs font-medium rounded-lg transition-all cursor-pointer ${
                            swapFee === tier.fee
                              ? "bg-accent/20 text-accent border border-accent/30"
                              : "bg-surface-3/60 text-text-secondary border border-white/[0.06] hover:border-accent/20"
                          }`}
                        >
                          {tier.label}
                          {"tag" in tier && tier.tag && (
                            <span className="absolute -top-1.5 -right-1.5 px-1 py-0.5 text-[8px] leading-none font-semibold rounded bg-accent/30 text-accent">
                              ★
                            </span>
                          )}
                        </button>
                      ))}
                    </div>
                  </div>
                </div>
              )}

              {/* You pay */}
              <div className="bg-surface-2/80 rounded-xl border border-white/[0.04] p-4 mb-1">
                <div className="flex items-center justify-between mb-2">
                  <span className="text-xs font-medium uppercase tracking-wider text-text-tertiary">
                    You pay
                  </span>
                </div>
                <div className="flex items-center gap-3">
                  <div className="flex-1 min-w-0 relative">
                    <input
                      type="text"
                      inputMode="decimal"
                      className="w-full bg-transparent text-3xl font-semibold text-text-primary placeholder:text-text-disabled outline-none disabled:cursor-not-allowed"
                      placeholder={hasPool ? "0" : ""}
                      value={hasPool ? amountIn : ""}
                      onChange={(e) => {
                        setAmountIn(e.target.value);
                        setSwapMode("exactIn");
                      }}
                      disabled={!hasPool}
                      aria-label="Amount to pay"
                    />
                    {swapMode === "exactOut" && quoteLoading && (
                      <div className="absolute inset-0 flex items-center">
                        <Skeleton className="h-9 w-40 rounded-lg" />
                      </div>
                    )}
                  </div>
                  <button
                    type="button"
                    onClick={() => setSelectorOpen("in")}
                    className="group flex items-center gap-2.5 pl-3 pr-3.5 py-2.5 rounded-full bg-surface-3/90 hover:bg-surface-4 border border-white/[0.08] hover:border-accent/30 transition-all duration-200 cursor-pointer shrink-0 shadow-sm"
                  >
                    <TokenIcon symbol={tokenIn.symbol} size={26} />
                    <span className="text-base font-semibold text-text-primary">
                      {tokenIn.symbol}
                    </span>
                    <svg
                      width="14"
                      height="14"
                      viewBox="0 0 24 24"
                      fill="none"
                      stroke="currentColor"
                      strokeWidth="2.5"
                      className="text-text-tertiary group-hover:text-text-secondary transition-colors"
                    >
                      <polyline points="6 9 12 15 18 9" />
                    </svg>
                  </button>
                </div>
                {isConnected && (
                  <p className="mt-2 text-xs text-text-tertiary">
                    Balance:{" "}
                    <span className="font-medium text-text-secondary">
                      {balanceIn} {tokenIn.symbol}
                    </span>
                  </p>
                )}
              </div>

              {/* Flip button */}
              <div className="flex justify-center -my-2 relative z-10">
                <button
                  type="button"
                  onClick={flipTokens}
                  className="w-10 h-10 flex items-center justify-center rounded-full bg-surface-1 border-2 border-surface-2 shadow-md text-text-tertiary hover:text-accent hover:border-accent/40 hover:bg-accent/10 transition-all duration-200 cursor-pointer group"
                  aria-label="Flip tokens"
                >
                  <svg
                    width="18"
                    height="18"
                    viewBox="0 0 24 24"
                    fill="none"
                    stroke="currentColor"
                    strokeWidth="2.5"
                    strokeLinecap="round"
                    strokeLinejoin="round"
                    className="transition-transform duration-200 group-hover:rotate-180"
                  >
                    <line x1="12" y1="5" x2="12" y2="19" />
                    <polyline points="19 12 12 19 5 12" />
                  </svg>
                </button>
              </div>

              {/* You receive */}
              <div className="bg-surface-2/80 rounded-xl border border-white/[0.04] p-4">
                <div className="flex items-center justify-between mb-2">
                  <span className="text-xs font-medium uppercase tracking-wider text-text-tertiary">
                    You receive
                  </span>
                </div>
                <div className="flex items-center gap-3">
                  <div className="flex-1 min-w-0 relative">
                    <input
                      type="text"
                      inputMode="decimal"
                      className="w-full bg-transparent text-3xl font-semibold text-text-primary placeholder:text-text-disabled outline-none disabled:cursor-not-allowed"
                      placeholder={hasPool ? "0" : ""}
                      value={hasPool ? amountOut : ""}
                      onChange={(e) => {
                        setAmountOut(e.target.value);
                        setSwapMode("exactOut");
                      }}
                      disabled={!hasPool}
                      aria-label="Amount to receive"
                      aria-invalid={!!quoteError}
                    />
                    {swapMode === "exactIn" && quoteLoading && (
                      <div className="absolute inset-0 flex items-center">
                        <Skeleton className="h-9 w-40 rounded-lg" />
                      </div>
                    )}
                  </div>
                  <button
                    type="button"
                    onClick={() => setSelectorOpen("out")}
                    className="group flex items-center gap-2.5 pl-3 pr-3.5 py-2.5 rounded-full bg-surface-3/90 hover:bg-surface-4 border border-white/[0.08] hover:border-accent/30 transition-all duration-200 cursor-pointer shrink-0 shadow-sm"
                  >
                    <TokenIcon symbol={tokenOut.symbol} size={26} />
                    <span className="text-base font-semibold text-text-primary">
                      {tokenOut.symbol}
                    </span>
                    <svg
                      width="14"
                      height="14"
                      viewBox="0 0 24 24"
                      fill="none"
                      stroke="currentColor"
                      strokeWidth="2.5"
                      className="text-text-tertiary group-hover:text-text-secondary transition-colors"
                    >
                      <polyline points="6 9 12 15 18 9" />
                    </svg>
                  </button>
                </div>
                {isConnected && (
                  <p className="mt-2 text-xs text-text-tertiary">
                    Balance:{" "}
                    <span className="font-medium text-text-secondary">
                      {balanceOut} {tokenOut.symbol}
                    </span>
                  </p>
                )}
              </div>

              {/* No pool message */}
              {!hasPool && tokenIn.symbol && tokenOut.symbol && (
                <div className="px-1 py-3 mt-2 text-center">
                  <span className="text-sm text-text-tertiary">
                    No pool found for {tokenIn.symbol}/{tokenOut.symbol}. Create
                    one in the Pool tab.
                  </span>
                </div>
              )}

              {/* Route & rate info */}
              {hasPool && amountIn && amountOut && !quoteError && (
                <div className="px-1 py-2 mt-2 space-y-1">
                  {/* Route display */}
                  {multiHopEnabled && intermediateToken && (
                    <div className="flex items-center gap-1.5 text-xs text-text-tertiary">
                      <span className="font-medium text-text-secondary">
                        Route:
                      </span>
                      <span className="flex items-center gap-1">
                        <TokenIcon symbol={tokenIn.symbol} size={14} />
                        {tokenIn.symbol}
                      </span>
                      <svg
                        width="12"
                        height="12"
                        viewBox="0 0 24 24"
                        fill="none"
                        stroke="currentColor"
                        strokeWidth="2"
                        className="text-accent"
                      >
                        <polyline points="9 18 15 12 9 6" />
                      </svg>
                      <span className="flex items-center gap-1">
                        <TokenIcon
                          symbol={intermediateToken.symbol}
                          size={14}
                        />
                        {intermediateToken.symbol}
                      </span>
                      <svg
                        width="12"
                        height="12"
                        viewBox="0 0 24 24"
                        fill="none"
                        stroke="currentColor"
                        strokeWidth="2"
                        className="text-accent"
                      >
                        <polyline points="9 18 15 12 9 6" />
                      </svg>
                      <span className="flex items-center gap-1">
                        <TokenIcon symbol={tokenOut.symbol} size={14} />
                        {tokenOut.symbol}
                      </span>
                    </div>
                  )}
                  <div className="flex items-center justify-between">
                    <span className="text-xs text-text-tertiary">
                      1 {tokenIn.symbol} ={" "}
                      {(parseFloat(amountOut) / parseFloat(amountIn)).toFixed(
                        6,
                      )}{" "}
                      {tokenOut.symbol}
                    </span>
                    <span className="text-xs text-text-tertiary">
                      ~{slippage}% slippage ·{" "}
                      {FEE_TIERS.find((t) => t.fee === swapFee)?.label ??
                        `${swapFee / 10000}%`}{" "}
                      fee
                    </span>
                  </div>
                </div>
              )}

              {/* Error / Success */}
              <div className="space-y-2 mt-2">
                {quoteError && (
                  <ErrorMessage id="quote-error-msg" message={quoteError} />
                )}
                {swapError && (
                  <ErrorMessage
                    message={swapError}
                    onDismiss={() => setSwapError(null)}
                  />
                )}
                {swapTxId && (
                  <div className="flex items-center gap-2 px-3.5 py-3 rounded-xl bg-success-muted text-success text-sm animate-[fadeIn_0.2s_ease-out]">
                    <svg
                      width="16"
                      height="16"
                      viewBox="0 0 24 24"
                      fill="none"
                      stroke="currentColor"
                      strokeWidth="2.5"
                    >
                      <polyline points="20 6 9 17 4 12" />
                    </svg>
                    <span>Swap successful!</span>
                    <a
                      href={`https://hashscan.io/testnet/transaction/${swapTxId}`}
                      target="_blank"
                      rel="noreferrer"
                      className="ml-auto underline hover:no-underline"
                    >
                      View TX
                    </a>
                  </div>
                )}
              </div>

              {/* Swap button */}
              <div className="mt-4">
                <button
                  type="button"
                  disabled={btnState.disabled}
                  onClick={handleSwap}
                  className={`
                    w-full py-4 text-base font-semibold rounded-xl
                    transition-all duration-200 cursor-pointer
                    ${
                      btnState.disabled
                        ? "bg-surface-3 text-text-disabled cursor-not-allowed"
                        : "bg-accent text-surface-0 hover:bg-accent-hover active:scale-[0.99] shadow-md hover:shadow-lg hover:shadow-accent/20"
                    }
                  `}
                >
                  {swapLoading ? (
                    <span className="flex items-center justify-center gap-2">
                      <svg
                        className="animate-spin h-5 w-5"
                        viewBox="0 0 24 24"
                        fill="none"
                      >
                        <circle
                          className="opacity-25"
                          cx="12"
                          cy="12"
                          r="10"
                          stroke="currentColor"
                          strokeWidth="4"
                        />
                        <path
                          className="opacity-75"
                          fill="currentColor"
                          d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4z"
                        />
                      </svg>
                      Swapping...
                    </span>
                  ) : (
                    btnState.text
                  )}
                </button>
              </div>
            </div>
          </div>
        </div>
      </div>

      {/* Token selector modal */}
      <TokenSelector
        open={selectorOpen !== null}
        onClose={() => setSelectorOpen(null)}
        onSelect={handleTokenSelect}
        tokens={tokenOptions}
        selectedToken={
          selectorOpen === "in"
            ? tokenIn
            : selectorOpen === "out"
              ? tokenOut
              : (intermediateToken ?? EMPTY_TOKEN)
        }
        excludeToken={
          selectorOpen === "mid"
            ? undefined
            : selectorOpen === "in"
              ? tokenOut
              : tokenIn
        }
      />
    </>
  );
}
