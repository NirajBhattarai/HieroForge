"use client";

import { useState, useCallback, useEffect, useRef } from "react";
import { createPublicClient, http, parseUnits, formatUnits } from "viem";
import { useHashPack } from "@/context/HashPackContext";
import { quoteExactInputSingle, NotEnoughLiquidityError } from "@/lib/quote";
import { getFriendlyErrorMessage } from "@/lib/errors";
import { ErrorMessage } from "@/components/ErrorMessage";
import { TokenIcon } from "@/components/TokenIcon";
import { TokenSelector } from "@/components/ui/TokenSelector";
import { Skeleton } from "@/components/ui/Skeleton";
import type { PoolInfo } from "@/components/PoolPositions";
import {
  HEDERA_TESTNET,
  DEFAULT_TOKENS,
  getTokenAddress,
  getTokenDecimals,
  getQuoterAddress,
  getRouterAddress,
  DEFAULT_FEE,
  DEFAULT_TICK_SPACING,
  type TokenOption,
} from "@/constants";
import { useTokens } from "@/hooks/useTokens";
import { hederaContractExecute } from "@/lib/hederaContract";
import { buildSwapPoolKey, encodeSwapExactInSingle } from "@/lib/swap";
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
  } | null;
}

export function SwapCard({ selectedPool }: SwapCardProps) {
  const { accountId, isConnected, hashConnectRef } = useHashPack();

  const { tokens: dynamicTokens, loading: tokensLoading } = useTokens();
  const tokenOptions: TokenOption[] =
    dynamicTokens.length > 0
      ? dynamicTokens.map((t) => ({
          id: t.address,
          symbol: t.symbol,
          address: t.address,
          decimals: t.decimals,
          name: t.name,
        }))
      : DEFAULT_TOKENS;

  const resolveAddress = (tok: TokenOption): string =>
    (tok.address ?? getTokenAddress(tok.symbol)).toLowerCase();
  const resolveDecimals = (tok: TokenOption): number =>
    tok.decimals ?? getTokenDecimals(tok.symbol);

  // Swap state
  const [amountIn, setAmountIn] = useState("");
  const [amountOut, setAmountOut] = useState("");
  const [quoteError, setQuoteError] = useState<string | null>(null);
  const [quoteLoading, setQuoteLoading] = useState(false);
  const [tokenIn, setTokenIn] = useState<TokenOption>(DEFAULT_TOKENS[0]!);
  const [tokenOut, setTokenOut] = useState<TokenOption>(DEFAULT_TOKENS[1]!);

  // Token selector modal state
  const [selectorOpen, setSelectorOpen] = useState<"in" | "out" | null>(null);

  useEffect(() => {
    if (tokenOptions.length >= 2) {
      setTokenIn(tokenOptions[0]!);
      setTokenOut(tokenOptions[1]!);
    }
  }, [tokenOptions.length]);

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

  // Quote
  useEffect(() => {
    if (
      !quoterAddress ||
      !amountIn ||
      amountIn === "." ||
      amountIn === "0" ||
      amountIn === "0."
    ) {
      if (amountIn === "" || amountIn === "0" || amountIn === "0.")
        setAmountOut("");
      setQuoteError(null);
      setQuoteLoading(false);
      return;
    }
    const addrIn = resolveAddress(tokenIn);
    const addrOut = resolveAddress(tokenOut);
    if (!addrIn || !addrOut || addrIn === addrOut) {
      setAmountOut("");
      setQuoteError(null);
      setQuoteLoading(false);
      return;
    }

    const currency0 = addrIn < addrOut ? addrIn : addrOut;
    const currency1 = addrIn < addrOut ? addrOut : addrIn;
    const zeroForOne = addrIn < addrOut;
    const useSelected =
      selectedPool &&
      selectedPool.currency0.toLowerCase() === currency0.toLowerCase() &&
      selectedPool.currency1.toLowerCase() === currency1.toLowerCase();
    const fee = useSelected ? selectedPool.fee : DEFAULT_FEE;
    const tickSpacing = useSelected
      ? selectedPool.tickSpacing
      : DEFAULT_TICK_SPACING;
    const poolKey = { currency0, currency1, fee, tickSpacing };
    const decimalsIn = resolveDecimals(tokenIn);
    const decimalsOut = resolveDecimals(tokenOut);

    let cancelled = false;
    setQuoteError(null);
    setQuoteLoading(true);
    const id = setTimeout(async () => {
      try {
        let amountInWei: bigint;
        try {
          amountInWei = parseUnits(amountIn, decimalsIn);
        } catch {
          if (!cancelled) setAmountOut("");
          if (!cancelled) setQuoteLoading(false);
          return;
        }
        const client = publicClientRef.current;
        if (!client) {
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
      } catch (err) {
        if (!cancelled) {
          setAmountOut("");
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
  }, [amountIn, tokenIn.symbol, tokenOut.symbol, quoterAddress, selectedPool]);

  const flipTokens = () => {
    setTokenIn(tokenOut);
    setTokenOut(tokenIn);
    setAmountIn(amountOut);
    setAmountOut("");
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
      const quotedOutWei = parseUnits(amountOut, decimalsOut);
      const amountOutMinimum = (quotedOutWei * 98n) / 100n;

      const useSelected =
        selectedPool &&
        selectedPool.currency0.toLowerCase() ===
          (addrIn < addrOut ? addrIn : addrOut).toLowerCase() &&
        selectedPool.currency1.toLowerCase() ===
          (addrIn < addrOut ? addrOut : addrIn).toLowerCase();
      const fee = useSelected ? selectedPool.fee : DEFAULT_FEE;
      const tickSpacing = useSelected
        ? selectedPool.tickSpacing
        : DEFAULT_TICK_SPACING;

      const poolKey = buildSwapPoolKey(addrIn, addrOut, fee, tickSpacing);
      const zeroForOne = addrIn.toLowerCase() < addrOut.toLowerCase();

      console.log("[swap] Approving router to spend input token...");
      await hederaContractExecute({
        hashConnect: hc,
        accountId,
        contractId: addrIn,
        abi: ERC20Abi,
        functionName: "approve",
        args: [routerAddress, amountInWei],
        gas: 800_000,
      });

      console.log("[swap] Executing swap via UniversalRouter...");
      const { commands, inputs } = encodeSwapExactInSingle({
        poolKey,
        zeroForOne,
        amountIn: amountInWei,
        amountOutMinimum,
      });

      const deadline = BigInt(Math.floor(Date.now() / 1000) + 120);

      const txId = await hederaContractExecute({
        hashConnect: hc,
        accountId,
        contractId: routerAddress,
        abi: UniversalRouterAbi,
        functionName: "execute",
        args: [commands, inputs, deadline],
        gas: 3_000_000,
      });

      console.log("[swap] Swap completed:", txId);
      setSwapTxId(txId);
      setAmountIn("");
      setAmountOut("");
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
    tokenIn,
    tokenOut,
    selectedPool,
    hashConnectRef,
  ]);

  const handleTokenSelect = (token: TokenOption) => {
    if (selectorOpen === "in") {
      if (token.id === tokenOut.id) {
        setTokenOut(tokenIn);
      }
      setTokenIn(token);
    } else {
      if (token.id === tokenIn.id) {
        setTokenIn(tokenOut);
      }
      setTokenOut(token);
    }
    setSelectorOpen(null);
  };

  // Determine button state
  const getButtonState = () => {
    if (!isConnected) return { text: "Connect Wallet", disabled: true };
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
        {/* Card */}
        <div className="bg-surface-1 border border-border rounded-[--radius-xl] p-1.5 shadow-lg">
          {/* Header */}
          <div className="flex items-center justify-between px-3 pt-2 pb-1">
            <h2 className="text-base font-semibold text-text-primary">Swap</h2>
            {/* Settings gear */}
            <button
              type="button"
              className="p-1.5 rounded-[--radius-sm] text-text-tertiary hover:text-text-secondary hover:bg-surface-3 transition-colors cursor-pointer"
              title="Settings"
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

          {/* You pay */}
          <div className="bg-surface-2 rounded-[--radius-lg] p-4 mx-1">
            <div className="flex items-center justify-between mb-2">
              <span className="text-xs font-medium text-text-tertiary">
                You pay
              </span>
            </div>
            <div className="flex items-center gap-3">
              <input
                type="text"
                inputMode="decimal"
                className="flex-1 bg-transparent text-3xl font-medium text-text-primary placeholder:text-text-disabled outline-none min-w-0"
                placeholder="0"
                value={amountIn}
                onChange={(e) => setAmountIn(e.target.value)}
                aria-label="Amount to pay"
              />
              <button
                type="button"
                onClick={() => setSelectorOpen("in")}
                className="flex items-center gap-2 px-3 py-2 bg-surface-3 hover:bg-surface-4 rounded-[--radius-full] transition-colors cursor-pointer shrink-0 border border-border"
              >
                <TokenIcon symbol={tokenIn.symbol} size={24} />
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
                  className="text-text-tertiary"
                >
                  <polyline points="6 9 12 15 18 9" />
                </svg>
              </button>
            </div>
          </div>

          {/* Flip button */}
          <div className="flex justify-center -my-3 relative z-10">
            <button
              type="button"
              onClick={flipTokens}
              className="w-9 h-9 flex items-center justify-center bg-surface-1 border-4 border-surface-1 rounded-[--radius-sm] text-text-tertiary hover:text-text-primary hover:bg-surface-3 transition-all duration-200 cursor-pointer group"
              aria-label="Flip tokens"
            >
              <svg
                width="16"
                height="16"
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
          <div className="bg-surface-2 rounded-[--radius-lg] p-4 mx-1">
            <div className="flex items-center justify-between mb-2">
              <span className="text-xs font-medium text-text-tertiary">
                You receive
              </span>
            </div>
            <div className="flex items-center gap-3">
              {quoteLoading ? (
                <Skeleton className="h-9 w-40 flex-1" />
              ) : (
                <input
                  type="text"
                  inputMode="decimal"
                  className="flex-1 bg-transparent text-3xl font-medium text-text-primary placeholder:text-text-disabled outline-none min-w-0"
                  placeholder="0"
                  value={amountOut}
                  readOnly={!!quoterAddress}
                  onChange={(e) => setAmountOut(e.target.value)}
                  aria-label="Amount to receive"
                  aria-invalid={!!quoteError}
                />
              )}
              <button
                type="button"
                onClick={() => setSelectorOpen("out")}
                className="flex items-center gap-2 px-3 py-2 bg-surface-3 hover:bg-surface-4 rounded-[--radius-full] transition-colors cursor-pointer shrink-0 border border-border"
              >
                <TokenIcon symbol={tokenOut.symbol} size={24} />
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
                  className="text-text-tertiary"
                >
                  <polyline points="6 9 12 15 18 9" />
                </svg>
              </button>
            </div>
          </div>

          {/* Rate info */}
          {amountIn && amountOut && !quoteError && (
            <div className="flex items-center justify-between px-4 py-2 mx-1 mt-1">
              <span className="text-xs text-text-tertiary">
                1 {tokenIn.symbol} ={" "}
                {(parseFloat(amountOut) / parseFloat(amountIn)).toFixed(6)}{" "}
                {tokenOut.symbol}
              </span>
              <span className="text-xs text-text-tertiary">~2% slippage</span>
            </div>
          )}

          {/* Error / Success */}
          <div className="px-1 space-y-2 mt-1">
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
              <div className="flex items-center gap-2 px-3.5 py-3 rounded-[--radius-md] bg-success-muted text-success text-sm animate-[fadeIn_0.2s_ease-out]">
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
          <div className="p-1 mt-1">
            <button
              type="button"
              disabled={btnState.disabled}
              onClick={handleSwap}
              className={`
                w-full py-4 text-base font-semibold rounded-[--radius-lg]
                transition-all duration-200 cursor-pointer
                ${
                  btnState.disabled
                    ? "bg-surface-3 text-text-disabled cursor-not-allowed"
                    : "bg-accent text-surface-0 hover:bg-accent-hover active:scale-[0.99] shadow-sm"
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

      {/* Token selector modal */}
      <TokenSelector
        open={selectorOpen !== null}
        onClose={() => setSelectorOpen(null)}
        onSelect={handleTokenSelect}
        tokens={tokenOptions}
        selectedToken={selectorOpen === "in" ? tokenIn : tokenOut}
        excludeToken={selectorOpen === "in" ? tokenOut : tokenIn}
      />
    </>
  );
}
