"use client";

import { useState, useCallback, useEffect, useRef } from "react";
import { createPublicClient, http, parseUnits, type PublicClient } from "viem";
import { TokenIcon, TokenPairIcon } from "./TokenIcon";
import { ErrorMessage } from "./ErrorMessage";
import { Button } from "@/components/ui/Button";
import { Badge } from "@/components/ui/Badge";
import { TokenSelector } from "@/components/ui/TokenSelector";

/** Detect if string looks like an address (0x... or 0.0.XXXXX) */
function isAddressLike(s: string): boolean {
  const t = s.trim();
  return /^0x[0-9a-f]{40}$/i.test(t) || /^0\.0\.\d+$/i.test(t);
}
import {
  buildPoolKey,
  getPoolId,
  encodeUnlockDataMint,
} from "@/lib/addLiquidity";
import {
  hederaContractExecute,
  hederaTokenTransfer,
  hederaContractMulticall,
} from "@/lib/hederaContract";

/** Gas limits for Hedera ContractExecuteTransaction */
const HEDERA_GAS_ERC20 = 1_200_000;
const HEDERA_GAS_MODIFY_LIQ = 5_000_000;
const HEDERA_GAS_INITIALIZE = 3_000_000;

import { tickToPrice, priceToTick, roundToTickSpacing } from "@/lib/priceUtils";
import { getFriendlyErrorMessage } from "@/lib/errors";
import { PoolManagerAbi, SQRT_PRICE_PRESETS } from "@/abis/PoolManager";
import { PositionManagerAbi, SQRT_PRICE_1_1 } from "@/abis/PositionManager";
import {
  DEFAULT_TOKENS,
  getTokenAddress,
  getTokenDecimals,
  getPoolManagerAddress,
  getPositionManagerAddress,
  getRpcUrl,
  HEDERA_TESTNET,
  DEFAULT_FEE,
  DEFAULT_TICK_SPACING,
  type TokenOption,
} from "@/constants";
import { useTokens, type DynamicToken } from "@/hooks/useTokens";
import { useTokenLookup } from "@/hooks/useTokenLookup";
import { useTokenBalance } from "@/hooks/useTokenBalance";
import { useHashPack } from "@/context/HashPackContext";
import type { PoolInfo } from "./PoolPositions";

/** Convert Hedera accountId (0.0.XXXXX) to EVM address for balance/contract calls. */
function accountIdToEvmAddress(accountId: string | null): string | null {
  if (!accountId) return null;
  const m = String(accountId)
    .trim()
    .match(/^(\d+)\.(\d+)\.(\d+)$/);
  if (!m) return null;
  return "0x" + BigInt(m[3]!).toString(16).padStart(40, "0");
}

type Step = 1 | 2;
type RangeMode = "full" | "custom";

interface NewPositionProps {
  onBack: () => void;
  /** Pre-selected pool from "View positions" click */
  preselectedPool?: PoolInfo | null;
}

const FEE_TIERS = [
  { fee: 500, label: "0.05%", desc: "Best for stable pairs" },
  { fee: 3000, label: "0.3%", desc: "Best for most pairs", tag: "Most used" },
  { fee: 10000, label: "1%", desc: "Best for exotic pairs" },
] as const;

function feeTierToTickSpacing(fee: number): number {
  if (fee === 500) return 10;
  if (fee === 10000) return 200;
  return 60;
}

/** Format fee number as display string */
function formatFee(f: number): string {
  return `${(f / 10000).toFixed(2)}%`;
}

// TokenSelectCombobox replaced by TokenSelector modal (see below)

export function NewPosition({ onBack, preselectedPool }: NewPositionProps) {
  const [step, setStep] = useState<Step>(1);

  // Dynamic token list from DynamoDB
  const {
    tokens: dynamicTokens,
    loading: tokensLoading,
    refetch: refetchTokens,
  } = useTokens();
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

  // Helper: resolve address from TokenOption (prefers .address field, falls back to static lookup)
  const resolveAddress = (tok: TokenOption): string =>
    (tok.address ?? getTokenAddress(tok.symbol)).toLowerCase();
  const resolveDecimals = (tok: TokenOption): number =>
    tok.decimals ?? getTokenDecimals(tok.symbol);

  // Step 1: pair + fee
  const [token0, setToken0] = useState<TokenOption>(DEFAULT_TOKENS[0]!);
  const [token1, setToken1] = useState<TokenOption>(DEFAULT_TOKENS[1]!);
  const [token0Addr, setToken0Addr] = useState("");
  const [token1Addr, setToken1Addr] = useState("");
  const [fee, setFee] = useState(DEFAULT_FEE);
  const [tickSpacing, setTickSpacing] = useState(DEFAULT_TICK_SPACING);
  const [showMoreFees, setShowMoreFees] = useState(false);

  // Token address auto-lookup
  const {
    token: resolved0,
    loading: lookup0Loading,
    error: lookup0Error,
  } = useTokenLookup(token0Addr);
  const {
    token: resolved1,
    loading: lookup1Loading,
    error: lookup1Error,
  } = useTokenLookup(token1Addr);

  // Step 2: price range + deposits
  const [rangeMode, setRangeMode] = useState<RangeMode>("custom");
  const [minPriceStr, setMinPriceStr] = useState("0.9980");
  const [maxPriceStr, setMaxPriceStr] = useState("1.0020");
  const [tickLower, setTickLower] = useState(-120);
  const [tickUpper, setTickUpper] = useState(120);
  const [amount0, setAmount0] = useState("1000");
  const [amount1, setAmount1] = useState("1000");
  const [liquidityAmount, setLiquidityAmount] = useState("100000000");
  const [initialPriceStr, setInitialPriceStr] = useState("1");
  const initialPrice = (() => {
    const p = parseFloat(initialPriceStr);
    return Number.isFinite(p) && p > 0 ? p : 1;
  })();

  // Pool state
  const [poolInitialized, setPoolInitialized] = useState<boolean | null>(null);

  // TX state
  const [pending, setPending] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [txHash, setTxHash] = useState<string | null>(null);
  const [saveSuccess, setSaveSuccess] = useState(false);
  const [savePending, setSavePending] = useState(false);

  const poolManagerAddress = getPoolManagerAddress();
  const positionManagerAddress = getPositionManagerAddress();

  const publicClientRef = useRef<PublicClient | null>(null);
  if (!publicClientRef.current && typeof window !== "undefined") {
    publicClientRef.current = createPublicClient({
      chain: HEDERA_TESTNET,
      transport: http(getRpcUrl()),
    }) as PublicClient;
  }

  const { accountId, isConnected, hashConnectRef } = useHashPack();
  const userEvmFromAccountId = accountIdToEvmAddress(accountId);

  const userEvmAddress = userEvmFromAccountId;
  // Prefer accountId (0.0.X) for balance so Mirror Node accepts it; fallback to EVM address
  const ownerForBalance = isConnected && accountId ? accountId : userEvmAddress;
  const addr0ForBalance = (token0Addr || resolveAddress(token0)).trim();
  const addr1ForBalance = (token1Addr || resolveAddress(token1)).trim();
  const { balanceFormatted: balance0Formatted, loading: balance0Loading } =
    useTokenBalance(addr0ForBalance, ownerForBalance, resolveDecimals(token0));
  const { balanceFormatted: balance1Formatted, loading: balance1Loading } =
    useTokenBalance(addr1ForBalance, ownerForBalance, resolveDecimals(token1));

  // Restore from preselected pool
  useEffect(() => {
    if (!preselectedPool) {
      // Set defaults from dynamic list when it loads
      if (tokenOptions.length >= 2) {
        setToken0(tokenOptions[0]!);
        setToken1(tokenOptions[1]!);
      }
      return;
    }
    const t0 =
      tokenOptions.find((t) => t.symbol === preselectedPool.symbol0) ??
      tokenOptions[0]!;
    const t1 =
      tokenOptions.find((t) => t.symbol === preselectedPool.symbol1) ??
      tokenOptions[1]!;
    setToken0(t0);
    setToken1(t1);
    setToken0Addr(preselectedPool.currency0);
    setToken1Addr(preselectedPool.currency1);
    setFee(preselectedPool.fee);
    setTickSpacing(preselectedPool.tickSpacing);
  }, [preselectedPool, tokenOptions.length]);

  // Update addresses when dropdowns change
  useEffect(() => {
    setToken0Addr(resolveAddress(token0));
  }, [token0]);
  useEffect(() => {
    setToken1Addr(resolveAddress(token1));
  }, [token1]);

  // Sync resolved on-chain token data back into token state
  useEffect(() => {
    if (resolved0) {
      const addr = resolved0.address.toLowerCase();
      if (
        token0.address?.toLowerCase() !== addr ||
        token0.symbol !== resolved0.symbol
      ) {
        setToken0({
          id: addr,
          symbol: resolved0.symbol,
          address: addr,
          decimals: resolved0.decimals,
          name: resolved0.name,
        });
        refetchTokens();
      }
      // Normalize address input to EVM hex (e.g. if user pasted 0.0.XXXXX)
      if (token0Addr.toLowerCase() !== addr) setToken0Addr(addr);
    }
  }, [resolved0]);
  useEffect(() => {
    if (resolved1) {
      const addr = resolved1.address.toLowerCase();
      if (
        token1.address?.toLowerCase() !== addr ||
        token1.symbol !== resolved1.symbol
      ) {
        setToken1({
          id: addr,
          symbol: resolved1.symbol,
          address: addr,
          decimals: resolved1.decimals,
          name: resolved1.name,
        });
        refetchTokens();
      }
      if (token1Addr.toLowerCase() !== addr) setToken1Addr(addr);
    }
  }, [resolved1]);

  // Check pool initialized state
  useEffect(() => {
    if (!poolManagerAddress || !publicClientRef.current) {
      setPoolInitialized(null);
      return;
    }
    const addr0 = token0Addr || resolveAddress(token0);
    const addr1 = token1Addr || resolveAddress(token1);
    // Skip if addresses aren't valid EVM hex yet (e.g. user typing 0.0.XXXXX)
    const isHex = (s: string) => /^0x[0-9a-f]{40}$/i.test(s);
    if (!addr0 || !addr1 || addr0 === addr1 || !isHex(addr0) || !isHex(addr1)) {
      setPoolInitialized(null);
      return;
    }
    const poolKey = buildPoolKey(
      addr0 as `0x${string}`,
      addr1 as `0x${string}`,
      fee,
      tickSpacing,
    );
    const poolId = getPoolId(poolKey);
    let cancelled = false;
    publicClientRef.current
      .readContract({
        address: poolManagerAddress as `0x${string}`,
        abi: PoolManagerAbi,
        functionName: "getPoolState",
        args: [poolId],
      })
      .then((value: unknown) => {
        if (!cancelled)
          setPoolInitialized((value as readonly [boolean, bigint, number])[0]);
      })
      .catch(() => {
        if (!cancelled) setPoolInitialized(false);
      });
    return () => {
      cancelled = true;
    };
  }, [
    poolManagerAddress,
    token0Addr,
    token1Addr,
    token0.symbol,
    token1.symbol,
    fee,
    tickSpacing,
  ]);

  const syncPriceToTicks = useCallback(() => {
    if (rangeMode === "full") return;
    const minP = parseFloat(minPriceStr);
    const maxP = parseFloat(maxPriceStr);
    if (!Number.isFinite(minP) || !Number.isFinite(maxP)) return;
    setTickLower(roundToTickSpacing(priceToTick(minP), tickSpacing));
    setTickUpper(roundToTickSpacing(priceToTick(maxP), tickSpacing));
  }, [minPriceStr, maxPriceStr, tickSpacing, rangeMode]);

  const setFullRange = () => {
    setRangeMode("full");
    setMinPriceStr("0");
    setMaxPriceStr("∞");
    setTickLower(-887220);
    setTickUpper(887220);
  };

  const setCustomRange = () => {
    setRangeMode("custom");
    const ref = initialPrice;
    const minP = ref * 0.95;
    const maxP = ref * 1.05;
    setMinPriceStr(minP.toFixed(4));
    setMaxPriceStr(maxP.toFixed(4));
    setTickLower(roundToTickSpacing(priceToTick(minP), tickSpacing));
    setTickUpper(roundToTickSpacing(priceToTick(maxP), tickSpacing));
  };

  const adjustMinPrice = (delta: number) => {
    if (rangeMode === "full") return;
    const p = parseFloat(minPriceStr) || initialPrice;
    const newP = Math.max(0, p * (1 + delta));
    setMinPriceStr(newP.toFixed(4));
    setTickLower(roundToTickSpacing(priceToTick(newP), tickSpacing));
  };
  const adjustMaxPrice = (delta: number) => {
    if (rangeMode === "full") return;
    const p = parseFloat(maxPriceStr) || initialPrice;
    const newP = p * (1 + delta);
    setMaxPriceStr(newP.toFixed(4));
    setTickUpper(roundToTickSpacing(priceToTick(newP), tickSpacing));
  };

  /** Percentage from initial price */
  const minPricePct = (): string => {
    if (rangeMode === "full") return "";
    const p = parseFloat(minPriceStr);
    if (!Number.isFinite(p)) return "";
    const pct = ((p - initialPrice) / initialPrice) * 100;
    return `${pct >= 0 ? "+" : ""}${pct.toFixed(2)}%`;
  };
  const maxPricePct = (): string => {
    if (rangeMode === "full") return "";
    const p = parseFloat(maxPriceStr);
    if (!Number.isFinite(p)) return "";
    const pct = ((p - initialPrice) / initialPrice) * 100;
    return `${pct >= 0 ? "+" : ""}${pct.toFixed(2)}%`;
  };

  /** Deposit math: equivalent amount at initial price (token1 per token0) */
  const amount1AtPrice = (a0: string): string => {
    const n = parseFloat(a0);
    if (!Number.isFinite(n) || n <= 0) return "—";
    return (n * initialPrice).toFixed(6);
  };
  const amount0AtPrice = (a1: string): string => {
    const n = parseFloat(a1);
    if (!Number.isFinite(n) || n <= 0 || initialPrice <= 0) return "—";
    return (n / initialPrice).toFixed(6);
  };

  const isValidHex = (s: string) => /^0x[0-9a-f]{40}$/i.test(s);

  const canContinue = () => {
    const a0 = token0Addr || resolveAddress(token0);
    const a1 = token1Addr || resolveAddress(token1);
    return a0 && a1 && a0 !== a1 && isValidHex(a0) && isValidHex(a1);
  };

  // Create pool only (PoolManager.initialize) — uses Hedera SDK + HashConnect
  const createPoolOnly = useCallback(async () => {
    if (!isConnected || !accountId) {
      setError("Connect HashPack first.");
      return;
    }
    const hc = hashConnectRef.current;
    if (!hc) {
      setError("HashPack not initialized. Refresh and try again.");
      return;
    }
    const addr0 = (token0Addr || resolveAddress(token0)).trim();
    const addr1 = (token1Addr || resolveAddress(token1)).trim();
    if (!addr0 || !addr1 || addr0 === addr1) {
      setError("Select two different tokens.");
      return;
    }
    if (!poolManagerAddress) {
      setError("PoolManager address not configured.");
      return;
    }

    setError(null);
    setPending(true);
    setTxHash(null);
    try {
      console.log("[Create pool] HashPack accountId:", accountId);
      const poolKey = buildPoolKey(
        addr0 as `0x${string}`,
        addr1 as `0x${string}`,
        fee,
        tickSpacing,
      );
      const sqrtPriceX96 = BigInt(
        SQRT_PRICE_PRESETS["1"] ?? "79228162514264337593543950336",
      );

      const txId = await hederaContractExecute({
        hashConnect: hc,
        accountId,
        contractId: poolManagerAddress,
        abi: PoolManagerAbi,
        functionName: "initialize",
        args: [poolKey, sqrtPriceX96],
        gas: HEDERA_GAS_INITIALIZE,
      });
      setTxHash(txId);
      setPoolInitialized(true);
      console.log("[Create pool] success:", txId);
    } catch (err: unknown) {
      const exactMessage = err instanceof Error ? err.message : String(err);
      console.error("[Create pool] exact error message:", exactMessage);
      console.error("[Create pool] full error:", {
        message: exactMessage,
        err,
      });
      setError(getFriendlyErrorMessage(err, "transaction"));
    } finally {
      setPending(false);
    }
  }, [
    poolManagerAddress,
    token0Addr,
    token1Addr,
    token0.symbol,
    token1.symbol,
    fee,
    tickSpacing,
    isConnected,
    accountId,
    hashConnectRef,
  ]);

  // Add liquidity: transfer tokens to PM, then multicall(initializePool + modifyLiquidities) in one tx.
  // Uses Hedera SDK ContractExecuteTransaction via HashConnect — no EVM JSON-RPC at all.
  const addLiquidity = useCallback(async () => {
    if (!positionManagerAddress) {
      setError("Set NEXT_PUBLIC_POSITION_MANAGER_ADDRESS in .env.local.");
      return;
    }
    if (!isConnected || !accountId) {
      setError("Connect HashPack first.");
      return;
    }
    const hc = hashConnectRef.current;
    if (!hc) {
      setError("HashPack not initialized. Refresh and try again.");
      return;
    }
    const addr0 = (token0Addr || resolveAddress(token0)).trim();
    const addr1 = (token1Addr || resolveAddress(token1)).trim();
    if (!addr0 || !addr1 || addr0 === addr1) {
      setError("Select two different tokens.");
      return;
    }

    const dec0 = resolveDecimals(token0);
    const dec1 = resolveDecimals(token1);
    let amount0Wei: bigint, amount1Wei: bigint, liquidityWei: bigint;
    try {
      amount0Wei = parseUnits(amount0 || "0", dec0);
      amount1Wei = parseUnits(amount1 || "0", dec1);
      liquidityWei = BigInt(liquidityAmount || "0");
    } catch {
      setError("Invalid amount.");
      return;
    }
    if (amount0Wei === 0n && amount1Wei === 0n) {
      setError("Enter amount for at least one token.");
      return;
    }
    if (liquidityWei === 0n) {
      setError("Enter liquidity amount.");
      return;
    }

    // Check user's HTS token balances before attempting transfer
    const pc = publicClientRef.current;
    if (pc) {
      try {
        const erc20Abi = [
          {
            type: "function",
            name: "balanceOf",
            inputs: [{ name: "account", type: "address" }],
            outputs: [{ name: "", type: "uint256" }],
            stateMutability: "view",
          },
        ] as const;
        const userAddr = accountIdToEvmAddress(accountId) as `0x${string}`;
        const [bal0, bal1] = await Promise.all([
          amount0Wei > 0n
            ? (pc.readContract({
                address: addr0 as `0x${string}`,
                abi: erc20Abi,
                functionName: "balanceOf",
                args: [userAddr],
              }) as Promise<bigint>)
            : Promise.resolve(0n),
          amount1Wei > 0n
            ? (pc.readContract({
                address: addr1 as `0x${string}`,
                abi: erc20Abi,
                functionName: "balanceOf",
                args: [userAddr],
              }) as Promise<bigint>)
            : Promise.resolve(0n),
        ]);
        console.log("[Add liquidity] user balances:", {
          token0: bal0.toString(),
          token1: bal1.toString(),
          need0: amount0Wei.toString(),
          need1: amount1Wei.toString(),
        });
        if (amount0Wei > 0n && bal0 < amount0Wei) {
          setError(
            `Insufficient ${token0.symbol} balance: have ${bal0.toString()} need ${amount0Wei.toString()}`,
          );
          return;
        }
        if (amount1Wei > 0n && bal1 < amount1Wei) {
          setError(
            `Insufficient ${token1.symbol} balance: have ${bal1.toString()} need ${amount1Wei.toString()}`,
          );
          return;
        }
      } catch (e) {
        console.warn("[Add liquidity] balance check failed (continuing):", e);
      }
    }

    setError(null);
    setPending(true);
    setTxHash(null);
    try {
      console.log("[Add liquidity] HashPack accountId:", accountId);
      const ownerEvmAddress = accountIdToEvmAddress(accountId);
      if (!ownerEvmAddress) {
        setError("Cannot derive EVM address from account ID.");
        setPending(false);
        return;
      }

      const poolKey = buildPoolKey(
        addr0 as `0x${string}`,
        addr1 as `0x${string}`,
        fee,
        tickSpacing,
      );
      const pmAddr = positionManagerAddress;
      const deadline = BigInt(Math.floor(Date.now() / 1000) + 3600);
      const unlockData = encodeUnlockDataMint(
        poolKey,
        tickLower,
        tickUpper,
        liquidityWei,
        amount0Wei,
        amount1Wei,
        ownerEvmAddress as `0x${string}`,
      );

      // Step 1: Transfer tokens to PositionManager via Hedera SDK (separate txs per token)
      for (const [currency, amountWei] of [
        [poolKey.currency0, amount0Wei],
        [poolKey.currency1, amount1Wei],
      ] as const) {
        if (amountWei > 0n) {
          console.log(
            "[Add liquidity] transferring",
            amountWei.toString(),
            "of",
            currency,
            "to PM",
          );
          await hederaTokenTransfer({
            hashConnect: hc,
            accountId,
            tokenAddress: currency,
            to: pmAddr,
            amount: amountWei,
            gas: HEDERA_GAS_ERC20,
          });
          console.log("[Add liquidity] transfer confirmed");
        }
      }

      // Step 2: Encode initializePool + modifyLiquidities calldata for multicall
      const { encodeFunctionData: encFn } = await import("viem");
      const initializeCalldata = encFn({
        abi: PositionManagerAbi,
        functionName: "initializePool",
        args: [poolKey, SQRT_PRICE_1_1],
      }) as `0x${string}`;
      const modifyCalldata = encFn({
        abi: PositionManagerAbi,
        functionName: "modifyLiquidities",
        args: [unlockData, deadline],
      }) as `0x${string}`;

      // Step 3: Single multicall: initializePool (no-op if already init) + modifyLiquidities
      console.log(
        "[Add liquidity] calling multicall(initializePool + modifyLiquidities)",
      );
      const txId = await hederaContractMulticall({
        hashConnect: hc,
        accountId,
        contractId: pmAddr,
        calls: [initializeCalldata, modifyCalldata],
        gas: HEDERA_GAS_MODIFY_LIQ,
      });
      setTxHash(txId);
      setPoolInitialized(true);
      console.log("[Add liquidity] multicall success:", txId);
    } catch (err: unknown) {
      const exactMessage = err instanceof Error ? err.message : String(err);
      const exactCode = (err as { code?: number })?.code;
      console.error("[Add liquidity] exact error message:", exactMessage);
      console.error("[Add liquidity] full error:", {
        message: exactMessage,
        code: exactCode,
        err,
      });
      setError(getFriendlyErrorMessage(err, "transaction"));
    } finally {
      setPending(false);
    }
  }, [
    positionManagerAddress,
    token0Addr,
    token1Addr,
    token0.symbol,
    token1.symbol,
    fee,
    tickSpacing,
    tickLower,
    tickUpper,
    amount0,
    amount1,
    liquidityAmount,
    isConnected,
    accountId,
    hashConnectRef,
  ]);

  // Save pool to DynamoDB
  const savePool = useCallback(async () => {
    const addr0 = (token0Addr || resolveAddress(token0)).trim();
    const addr1 = (token1Addr || resolveAddress(token1)).trim();
    if (!addr0 || !addr1 || addr0 === addr1) return;
    const poolKey = buildPoolKey(
      addr0 as `0x${string}`,
      addr1 as `0x${string}`,
      fee,
      tickSpacing,
    );
    const poolId = getPoolId(poolKey);
    setSavePending(true);
    setSaveSuccess(false);
    try {
      const res = await fetch("/api/pools", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          poolId,
          currency0: poolKey.currency0,
          currency1: poolKey.currency1,
          fee,
          tickSpacing,
          symbol0: token0.symbol,
          symbol1: token1.symbol,
        }),
      });
      if (!res.ok) throw new Error("Failed to save pool");
      setSaveSuccess(true);
    } catch {
      /* ignore */
    } finally {
      setSavePending(false);
    }
  }, [token0Addr, token1Addr, token0.symbol, token1.symbol, fee, tickSpacing]);

  const sym0 = resolved0?.symbol ?? token0.symbol;
  const sym1 = resolved1?.symbol ?? token1.symbol;

  // Token selector modal states
  const [token0SelectorOpen, setToken0SelectorOpen] = useState(false);
  const [token1SelectorOpen, setToken1SelectorOpen] = useState(false);

  const selectorTokens = tokenOptions;

  return (
    <div className="max-w-5xl mx-auto px-4 py-8 animate-[fadeIn_0.3s_ease-out]">
      <div className="flex flex-col lg:flex-row gap-8">
        {/* Left: Steps indicator */}
        <aside className="hidden lg:flex flex-col items-start gap-0 w-48 shrink-0 pt-2">
          <div className="flex items-center gap-3">
            <div
              className={`w-3 h-3 rounded-full shrink-0 ${step >= 1 ? "bg-accent" : "bg-surface-3"}`}
            />
            <div className="flex flex-col">
              <span className="text-xs font-semibold text-text-primary">
                Step 1
              </span>
              <span className="text-xs text-text-tertiary">
                Select pair & fees
              </span>
            </div>
          </div>
          <div
            className={`w-0.5 h-8 ml-[5px] ${step >= 2 ? "bg-accent" : "bg-border"}`}
          />
          <div className="flex items-center gap-3">
            <div
              className={`w-3 h-3 rounded-full shrink-0 ${step >= 2 ? "bg-accent" : "bg-surface-3"}`}
            />
            <div className="flex flex-col">
              <span className="text-xs font-semibold text-text-primary">
                Step 2
              </span>
              <span className="text-xs text-text-tertiary">
                Range & deposits
              </span>
            </div>
          </div>
        </aside>

        {/* Right: Content */}
        <div className="flex-1 min-w-0 space-y-5">
          {/* Pair header bar (step 2) */}
          {step === 2 && (
            <div className="flex items-center justify-between px-5 py-3 bg-surface-1 border border-border rounded-[--radius-xl]">
              <div className="flex items-center gap-3">
                <TokenPairIcon symbol0={sym0} symbol1={sym1} size={28} />
                <span className="text-sm font-semibold text-text-primary">
                  {sym0} / {sym1}
                </span>
                <Badge variant="accent">v4</Badge>
                <Badge>{formatFee(fee)}</Badge>
              </div>
              <button
                type="button"
                className="flex items-center gap-1.5 px-3 py-1.5 text-xs font-medium text-text-secondary hover:text-text-primary rounded-[--radius-md] hover:bg-surface-2 transition-colors cursor-pointer"
                onClick={() => setStep(1)}
              >
                <svg
                  width="12"
                  height="12"
                  fill="none"
                  viewBox="0 0 24 24"
                  stroke="currentColor"
                  strokeWidth="2"
                >
                  <path d="M11 4H4a2 2 0 00-2 2v14a2 2 0 002 2h14a2 2 0 002-2v-7" />
                  <path d="M18.5 2.5a2.121 2.121 0 013 3L12 15l-4 1 1-4 9.5-9.5z" />
                </svg>
                Edit
              </button>
            </div>
          )}

          {/* ========== STEP 1 ========== */}
          {step === 1 && (
            <div className="bg-surface-1 border border-border rounded-[--radius-xl] p-6 space-y-6">
              <div>
                <h3 className="text-base font-semibold text-text-primary mb-1">
                  Select pair
                </h3>
                <p className="text-sm text-text-tertiary">
                  Choose two HTS tokens for your pool. Paste a 0x or 0.0.XXXXX
                  address to resolve symbol and decimals.
                </p>
              </div>

              {/* Token pair selectors */}
              <div className="flex items-center gap-3">
                <button
                  type="button"
                  className="flex items-center gap-2 px-4 py-2.5 bg-surface-2 border border-border rounded-[--radius-full] hover:border-border-hover transition-colors cursor-pointer"
                  onClick={() => setToken0SelectorOpen(true)}
                >
                  <TokenIcon symbol={sym0} size={24} />
                  <span className="text-sm font-semibold text-text-primary">
                    {sym0}
                  </span>
                  <svg
                    width="12"
                    height="12"
                    viewBox="0 0 24 24"
                    fill="none"
                    stroke="currentColor"
                    strokeWidth="2.5"
                    className="text-text-tertiary"
                  >
                    <polyline points="6 9 12 15 18 9" />
                  </svg>
                </button>
                <button
                  type="button"
                  className="flex items-center gap-2 px-4 py-2.5 bg-surface-2 border border-border rounded-[--radius-full] hover:border-border-hover transition-colors cursor-pointer"
                  onClick={() => setToken1SelectorOpen(true)}
                >
                  <TokenIcon symbol={sym1} size={24} />
                  <span className="text-sm font-semibold text-text-primary">
                    {sym1}
                  </span>
                  <svg
                    width="12"
                    height="12"
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

              {/* Token selector modals */}
              <TokenSelector
                open={token0SelectorOpen}
                onClose={() => setToken0SelectorOpen(false)}
                onSelect={(t) => {
                  const found = tokenOptions.find(
                    (o) =>
                      o.symbol === t.symbol ||
                      o.address?.toLowerCase() === t.address?.toLowerCase(),
                  );
                  if (found) {
                    setToken0(found);
                    setToken0Addr(found.address ?? "");
                  } else if (isAddressLike(t.address ?? ""))
                    setToken0Addr(t.address ?? "");
                  setToken0SelectorOpen(false);
                }}
                tokens={selectorTokens}
                selectedToken={token0}
                excludeToken={token1}
              />
              <TokenSelector
                open={token1SelectorOpen}
                onClose={() => setToken1SelectorOpen(false)}
                onSelect={(t) => {
                  const found = tokenOptions.find(
                    (o) =>
                      o.symbol === t.symbol ||
                      o.address?.toLowerCase() === t.address?.toLowerCase(),
                  );
                  if (found) {
                    setToken1(found);
                    setToken1Addr(found.address ?? "");
                  } else if (isAddressLike(t.address ?? ""))
                    setToken1Addr(t.address ?? "");
                  setToken1SelectorOpen(false);
                }}
                tokens={selectorTokens}
                selectedToken={token1}
                excludeToken={token0}
              />

              {/* Paste addresses */}
              <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
                <div className="space-y-1.5">
                  <label className="text-xs font-medium text-text-secondary">
                    Token 0 address
                  </label>
                  <input
                    type="text"
                    className="w-full px-3 py-2 bg-surface-2 border border-border rounded-[--radius-md] text-sm text-text-primary placeholder:text-text-tertiary focus:outline-none focus:border-border-focus transition-colors font-mono"
                    placeholder="0x… or 0.0.XXXXX"
                    value={token0Addr}
                    onChange={(e) => setToken0Addr(e.target.value)}
                  />
                  <div className="min-h-[20px] text-xs">
                    {lookup0Loading && (
                      <span className="text-accent">Looking up token…</span>
                    )}
                    {lookup0Error && (
                      <span className="text-error">{lookup0Error}</span>
                    )}
                    {resolved0 && !lookup0Loading && (
                      <span className="text-success flex items-center gap-1">
                        <TokenIcon symbol={resolved0.symbol} size={12} />✓{" "}
                        {resolved0.symbol} — {resolved0.name} (
                        {resolved0.decimals} dec)
                        {resolved0.hederaId ? ` · ${resolved0.hederaId}` : ""}
                        {resolved0.isHts ? " · HTS" : ""}
                      </span>
                    )}
                  </div>
                </div>
                <div className="space-y-1.5">
                  <label className="text-xs font-medium text-text-secondary">
                    Token 1 address
                  </label>
                  <input
                    type="text"
                    className="w-full px-3 py-2 bg-surface-2 border border-border rounded-[--radius-md] text-sm text-text-primary placeholder:text-text-tertiary focus:outline-none focus:border-border-focus transition-colors font-mono"
                    placeholder="0x… or 0.0.XXXXX"
                    value={token1Addr}
                    onChange={(e) => setToken1Addr(e.target.value)}
                  />
                  <div className="min-h-[20px] text-xs">
                    {lookup1Loading && (
                      <span className="text-accent">Looking up token…</span>
                    )}
                    {lookup1Error && (
                      <span className="text-error">{lookup1Error}</span>
                    )}
                    {resolved1 && !lookup1Loading && (
                      <span className="text-success flex items-center gap-1">
                        <TokenIcon symbol={resolved1.symbol} size={12} />✓{" "}
                        {resolved1.symbol} — {resolved1.name} (
                        {resolved1.decimals} dec)
                        {resolved1.hederaId ? ` · ${resolved1.hederaId}` : ""}
                        {resolved1.isHts ? " · HTS" : ""}
                      </span>
                    )}
                  </div>
                </div>
              </div>

              {/* Fee tier */}
              <div>
                <h3 className="text-base font-semibold text-text-primary mb-1">
                  Fee tier
                </h3>
                <p className="text-sm text-text-tertiary mb-3">
                  The fee earned providing liquidity.
                </p>
              </div>

              <div className="space-y-3">
                <button
                  type="button"
                  className={`w-full flex items-center justify-between p-4 rounded-[--radius-lg] border cursor-pointer transition-all ${
                    fee === 3000
                      ? "bg-accent-muted border-accent"
                      : "bg-surface-2 border-border hover:border-border-hover"
                  }`}
                  onClick={() => {
                    setFee(3000);
                    setTickSpacing(60);
                  }}
                >
                  <div className="flex flex-col items-start">
                    <span className="text-sm font-semibold text-text-primary">
                      0.3% fee tier
                    </span>
                    <span className="text-xs text-text-tertiary">
                      The % you will earn in fees
                    </span>
                  </div>
                  {fee === 3000 && <Badge variant="accent">Selected</Badge>}
                </button>
                <button
                  type="button"
                  className="text-xs font-medium text-accent hover:text-accent-hover cursor-pointer"
                  onClick={() => setShowMoreFees(!showMoreFees)}
                >
                  {showMoreFees ? "Less" : "More"} options
                </button>
              </div>
              {showMoreFees && (
                <div className="grid grid-cols-3 gap-3">
                  {FEE_TIERS.map((tier) => (
                    <button
                      key={tier.fee}
                      type="button"
                      className={`flex flex-col items-start p-3 rounded-[--radius-lg] border cursor-pointer transition-all ${
                        fee === tier.fee
                          ? "bg-accent-muted border-accent"
                          : "bg-surface-2 border-border hover:border-border-hover"
                      }`}
                      onClick={() => {
                        setFee(tier.fee);
                        setTickSpacing(feeTierToTickSpacing(tier.fee));
                      }}
                    >
                      <span className="text-sm font-semibold text-text-primary">
                        {tier.label}
                      </span>
                      {"tag" in tier && tier.tag && (
                        <Badge variant="accent" className="mt-1">
                          {tier.tag}
                        </Badge>
                      )}
                      <span className="text-xs text-text-tertiary mt-0.5">
                        {tier.desc}
                      </span>
                    </button>
                  ))}
                </div>
              )}

              {poolInitialized !== null && (
                <div
                  className={`flex items-center gap-2 px-4 py-3 rounded-[--radius-md] text-sm ${
                    poolInitialized
                      ? "bg-success-muted text-success"
                      : "bg-accent-muted text-accent"
                  }`}
                >
                  {poolInitialized
                    ? "✓ Pool exists — you will add liquidity"
                    : "⚡ New pool — will be created at 1:1 price"}
                </div>
              )}

              <Button
                variant="primary"
                fullWidth
                disabled={!canContinue()}
                onClick={() => {
                  syncPriceToTicks();
                  setStep(2);
                }}
              >
                Continue
              </Button>
            </div>
          )}

          {/* ========== STEP 2 ========== */}
          {step === 2 && (
            <div className="space-y-5">
              {/* ---- Set initial price ---- */}
              <div className="bg-surface-1 border border-border rounded-[--radius-xl] p-6 space-y-4">
                <div>
                  <h3 className="text-base font-semibold text-text-primary mb-1">
                    Set initial price
                  </h3>
                  <p className="text-sm text-text-tertiary">
                    When creating a new pool, set the starting exchange rate.
                    This reflects the initial market price.
                  </p>
                </div>
                <div className="flex items-center gap-3">
                  <input
                    type="text"
                    className="flex-1 px-4 py-3 bg-surface-2 border border-border rounded-[--radius-lg] text-2xl font-bold text-text-primary placeholder:text-text-tertiary focus:outline-none focus:border-border-focus transition-colors"
                    placeholder="0"
                    value={initialPriceStr}
                    onChange={(e) => setInitialPriceStr(e.target.value)}
                    aria-label="Initial price"
                  />
                  <span className="text-sm text-text-secondary shrink-0">
                    {sym1} = 1 {sym0}
                  </span>
                </div>
                <p className="text-xs text-warning">
                  Market price not found. Please do your own research to avoid
                  loss of funds.
                </p>
              </div>

              {/* ---- Set Price Range ---- */}
              <div className="bg-surface-1 border border-border rounded-[--radius-xl] p-6 space-y-5">
                <h3 className="text-base font-semibold text-text-primary">
                  Set price range
                </h3>

                {/* Full/Custom toggle */}
                <div className="flex p-1 bg-surface-2 rounded-[--radius-full] w-fit">
                  <button
                    type="button"
                    className={`px-4 py-1.5 text-sm font-medium rounded-[--radius-full] transition-all cursor-pointer ${
                      rangeMode === "full"
                        ? "bg-surface-1 text-text-primary shadow-sm"
                        : "text-text-tertiary hover:text-text-secondary"
                    }`}
                    onClick={setFullRange}
                  >
                    Full range
                  </button>
                  <button
                    type="button"
                    className={`px-4 py-1.5 text-sm font-medium rounded-[--radius-full] transition-all cursor-pointer ${
                      rangeMode === "custom"
                        ? "bg-surface-1 text-text-primary shadow-sm"
                        : "text-text-tertiary hover:text-text-secondary"
                    }`}
                    onClick={setCustomRange}
                  >
                    Custom range
                  </button>
                </div>

                <p className="text-sm text-text-tertiary">
                  {rangeMode === "full"
                    ? "Full range ensures continuous participation across all prices — simpler but with potential for higher impermanent loss."
                    : "Custom range concentrates liquidity within specific bounds, enhancing capital efficiency but needing more active management."}
                </p>

                {/* Min / Max price boxes */}
                <div className="grid grid-cols-2 gap-4">
                  <div className="bg-surface-2 border border-border rounded-[--radius-lg] p-4 space-y-2">
                    <label className="text-xs font-medium text-text-secondary">
                      Min price
                    </label>
                    <div className="flex items-center gap-2">
                      {rangeMode === "full" ? (
                        <span className="text-2xl font-bold text-text-primary">
                          0
                        </span>
                      ) : (
                        <>
                          <button
                            type="button"
                            className="w-7 h-7 flex items-center justify-center rounded-[--radius-sm] bg-surface-3 text-text-secondary hover:text-text-primary hover:bg-surface-1 transition-colors cursor-pointer text-sm font-bold"
                            onClick={() => adjustMinPrice(-0.005)}
                          >
                            −
                          </button>
                          <input
                            type="text"
                            className="flex-1 min-w-0 px-2 py-1 bg-transparent text-center text-lg font-bold text-text-primary focus:outline-none"
                            value={minPriceStr}
                            onChange={(e) => {
                              setMinPriceStr(e.target.value);
                              setTimeout(syncPriceToTicks, 0);
                            }}
                            onBlur={syncPriceToTicks}
                          />
                          <button
                            type="button"
                            className="w-7 h-7 flex items-center justify-center rounded-[--radius-sm] bg-surface-3 text-text-secondary hover:text-text-primary hover:bg-surface-1 transition-colors cursor-pointer text-sm font-bold"
                            onClick={() => adjustMinPrice(0.005)}
                          >
                            +
                          </button>
                        </>
                      )}
                    </div>
                    <span className="text-xs text-text-tertiary">
                      {sym1} = 1 {sym0}
                    </span>
                    {rangeMode === "custom" && (
                      <span className="text-xs text-accent">
                        {minPricePct()}
                      </span>
                    )}
                  </div>

                  <div className="bg-surface-2 border border-border rounded-[--radius-lg] p-4 space-y-2">
                    <label className="text-xs font-medium text-text-secondary">
                      Max price
                    </label>
                    <div className="flex items-center gap-2">
                      {rangeMode === "full" ? (
                        <span className="text-2xl font-bold text-text-primary">
                          ∞
                        </span>
                      ) : (
                        <>
                          <button
                            type="button"
                            className="w-7 h-7 flex items-center justify-center rounded-[--radius-sm] bg-surface-3 text-text-secondary hover:text-text-primary hover:bg-surface-1 transition-colors cursor-pointer text-sm font-bold"
                            onClick={() => adjustMaxPrice(-0.005)}
                          >
                            −
                          </button>
                          <input
                            type="text"
                            className="flex-1 min-w-0 px-2 py-1 bg-transparent text-center text-lg font-bold text-text-primary focus:outline-none"
                            value={maxPriceStr}
                            onChange={(e) => {
                              setMaxPriceStr(e.target.value);
                              setTimeout(syncPriceToTicks, 0);
                            }}
                            onBlur={syncPriceToTicks}
                          />
                          <button
                            type="button"
                            className="w-7 h-7 flex items-center justify-center rounded-[--radius-sm] bg-surface-3 text-text-secondary hover:text-text-primary hover:bg-surface-1 transition-colors cursor-pointer text-sm font-bold"
                            onClick={() => adjustMaxPrice(0.005)}
                          >
                            +
                          </button>
                        </>
                      )}
                    </div>
                    <span className="text-xs text-text-tertiary">
                      {sym1} = 1 {sym0}
                    </span>
                    {rangeMode === "custom" && (
                      <span className="text-xs text-accent">
                        {maxPricePct()}
                      </span>
                    )}
                  </div>
                </div>
              </div>

              {/* ---- Deposit HTS tokens ---- */}
              <div className="bg-surface-1 border border-border rounded-[--radius-xl] p-6 space-y-5">
                <div>
                  <h3 className="text-base font-semibold text-text-primary mb-1">
                    Deposit HTS tokens
                  </h3>
                  <p className="text-sm text-text-tertiary">
                    Specify the token amounts for your liquidity contribution.
                  </p>
                </div>

                {/* Token 0 deposit */}
                <div className="bg-surface-2 border border-border rounded-[--radius-lg] p-4">
                  <div className="flex items-center gap-3">
                    <input
                      type="text"
                      className="flex-1 min-w-0 bg-transparent text-2xl font-bold text-text-primary placeholder:text-text-tertiary focus:outline-none"
                      placeholder="0"
                      value={amount0}
                      onChange={(e) => {
                        setAmount0(e.target.value);
                        setError(null);
                      }}
                    />
                    <div className="flex items-center gap-2 px-3 py-1.5 bg-surface-1 rounded-[--radius-full] shrink-0">
                      <TokenIcon symbol={sym0} size={20} />
                      <span className="text-sm font-semibold text-text-primary">
                        {sym0}
                      </span>
                    </div>
                  </div>
                  <div className="flex items-center justify-between mt-2">
                    <span className="text-xs text-text-tertiary">
                      {amount0 && parseFloat(amount0) > 0
                        ? `≈ ${amount1AtPrice(amount0)} ${sym1}`
                        : ""}
                    </span>
                    <span className="text-xs text-text-tertiary">
                      {balance0Loading ? "…" : balance0Formatted} {sym0}
                    </span>
                  </div>
                </div>

                {/* Token 1 deposit */}
                <div className="bg-surface-2 border border-border rounded-[--radius-lg] p-4">
                  <div className="flex items-center gap-3">
                    <input
                      type="text"
                      className="flex-1 min-w-0 bg-transparent text-2xl font-bold text-text-primary placeholder:text-text-tertiary focus:outline-none"
                      placeholder="0"
                      value={amount1}
                      onChange={(e) => {
                        setAmount1(e.target.value);
                        setError(null);
                      }}
                    />
                    <div className="flex items-center gap-2 px-3 py-1.5 bg-surface-1 rounded-[--radius-full] shrink-0">
                      <TokenIcon symbol={sym1} size={20} />
                      <span className="text-sm font-semibold text-text-primary">
                        {sym1}
                      </span>
                    </div>
                  </div>
                  <div className="flex items-center justify-between mt-2">
                    <span className="text-xs text-text-tertiary">
                      {amount1 && parseFloat(amount1) > 0
                        ? `≈ ${amount0AtPrice(amount1)} ${sym0}`
                        : ""}
                    </span>
                    <span className="text-xs text-text-tertiary">
                      {balance1Loading ? "…" : balance1Formatted} {sym1}
                    </span>
                  </div>
                </div>

                {/* Liquidity (L) */}
                <div className="space-y-1.5">
                  <label className="text-xs font-medium text-text-secondary">
                    Liquidity (L)
                  </label>
                  <input
                    type="text"
                    className="w-full px-3 py-2 bg-surface-2 border border-border rounded-[--radius-md] text-sm text-text-primary placeholder:text-text-tertiary focus:outline-none focus:border-border-focus transition-colors font-mono"
                    value={liquidityAmount}
                    onChange={(e) => {
                      setLiquidityAmount(e.target.value);
                      setError(null);
                    }}
                    placeholder="100000000"
                  />
                </div>

                {/* Errors / success */}
                {error && (
                  <ErrorMessage
                    message={error}
                    onDismiss={() => setError(null)}
                  />
                )}
                {txHash && (
                  <div className="flex items-center gap-2 px-4 py-3 rounded-[--radius-md] bg-success-muted text-success text-sm">
                    Transaction sent!{" "}
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

                {/* Actions */}
                <div className="flex flex-col sm:flex-row gap-3">
                  {!positionManagerAddress && poolManagerAddress && (
                    <Button
                      variant="secondary"
                      fullWidth
                      disabled={pending}
                      onClick={createPoolOnly}
                      loading={pending}
                    >
                      Create pool only
                    </Button>
                  )}
                  <Button
                    variant="primary"
                    fullWidth
                    disabled={
                      pending ||
                      (!amount0 && !amount1) ||
                      !positionManagerAddress
                    }
                    onClick={addLiquidity}
                    loading={pending}
                  >
                    {poolInitialized === false
                      ? "Create pool & add liquidity"
                      : "Add liquidity"}
                  </Button>
                </div>

                {!positionManagerAddress && (
                  <p className="text-xs text-warning text-center">
                    Set NEXT_PUBLIC_POSITION_MANAGER_ADDRESS in .env.local to
                    add liquidity.
                  </p>
                )}

                {/* Save to DynamoDB */}
                <div className="flex items-center gap-3 pt-2 border-t border-border">
                  <Button
                    variant="secondary"
                    size="sm"
                    disabled={savePending || !canContinue()}
                    onClick={savePool}
                    loading={savePending}
                  >
                    {saveSuccess ? "✓ Saved" : "Save pool to list"}
                  </Button>
                  <span className="text-xs text-text-tertiary">
                    Save to DynamoDB so you can load it later
                  </span>
                </div>
              </div>
            </div>
          )}
        </div>
      </div>
    </div>
  );
}
