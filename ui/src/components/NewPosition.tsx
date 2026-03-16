"use client";

import { useState, useCallback, useEffect, useRef, useMemo } from "react";
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

import {
  tickToPrice,
  priceToTick,
  roundToTickSpacing,
  encodePriceSqrt,
  sqrtPriceX96ToPrice,
  computeLiquidityFromAmount,
  liquidityToWei,
  clampTick,
} from "@/lib/priceUtils";
import {
  getSqrtPriceAtTick,
  maxLiquidityForAmounts,
  amountsForLiquidity,
} from "@/lib/sqrtPriceMath";
import { getFriendlyErrorMessage } from "@/lib/errors";
import { PoolManagerAbi } from "@/abis/PoolManager";
import { PositionManagerAbi } from "@/abis/PositionManager";
import {
  getTokenAddress,
  getTokenDecimals,
  getPoolManagerAddress,
  getPositionManagerAddress,
  getRpcUrl,
  HEDERA_TESTNET,
  DEFAULT_FEE,
  DEFAULT_TICK_SPACING,
  FEE_TIERS,
  feeTierToTickSpacing,
  AVAILABLE_HOOKS,
  getHookAddress,
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
  const tokenOptions: TokenOption[] = dynamicTokens.map((t) => ({
    id: t.address,
    symbol: t.symbol,
    address: t.address,
    decimals: t.decimals,
    name: t.name,
  }));

  // Helper: resolve address from TokenOption (prefers .address field, falls back to static lookup)
  const resolveAddress = (tok: TokenOption): string =>
    (tok.address ?? getTokenAddress(tok.symbol)).toLowerCase();
  const resolveDecimals = (tok: TokenOption): number =>
    tok.decimals ?? getTokenDecimals(tok.symbol);

  // Step 1: pair + fee
  const EMPTY_TOKEN: TokenOption = {
    id: "",
    symbol: "",
    address: "",
    decimals: 18,
  };
  const [token0, setToken0] = useState<TokenOption>(EMPTY_TOKEN);
  const [token1, setToken1] = useState<TokenOption>(EMPTY_TOKEN);

  // Initialize token0/token1 when dynamic tokens load
  useEffect(() => {
    if (tokenOptions.length >= 2 && !token0.symbol && !token1.symbol) {
      setToken0(tokenOptions[0]!);
      setToken1(tokenOptions[1]!);
    }
  }, [tokenOptions.length]);
  const [token0Addr, setToken0Addr] = useState("");
  const [token1Addr, setToken1Addr] = useState("");
  const [fee, setFee] = useState(DEFAULT_FEE);
  const [tickSpacing, setTickSpacing] = useState(DEFAULT_TICK_SPACING);
  const [showMoreFees, setShowMoreFees] = useState(false);
  const [selectedHook, setSelectedHook] = useState("none");

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
  const [amount0, setAmount0] = useState("");
  const [amount1, setAmount1] = useState("");
  /** Which token amount the user last typed — drives auto-calculation of the other */
  const [lastEditedToken, setLastEditedToken] = useState<0 | 1>(0);
  const [liquidityAmount, setLiquidityAmount] = useState("0");
  const [initialPriceStr, setInitialPriceStr] = useState("1");
  /** When true, display price as "token1 = 1 token0"; when false, "token0 = 1 token1" */
  const [priceQuotePerToken0, setPriceQuotePerToken0] = useState(true);
  const initialPrice = (() => {
    const p = parseFloat(initialPriceStr);
    return Number.isFinite(p) && p > 0 ? p : 1;
  })();

  // TX state
  const [pending, setPending] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [txHash, setTxHash] = useState<string | null>(null);
  const [saveSuccess, setSaveSuccess] = useState(false);
  const [savePending, setSavePending] = useState(false);

  /** Step 2: whether pool (pair + fee + hook) exists on-chain; null = loading */
  const [poolExistsOnChain, setPoolExistsOnChain] = useState<boolean | null>(
    null,
  );
  /** Step 2: current pool sqrtPriceX96 when pool exists (for range/deposit math) */
  const [onChainSqrtPriceStep2, setOnChainSqrtPriceStep2] = useState<
    bigint | null
  >(null);

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

  // When leaving Step 2, reset pool check state so we re-fetch next time
  useEffect(() => {
    if (step !== 2) {
      setPoolExistsOnChain(null);
      setOnChainSqrtPriceStep2(null);
    }
  }, [step]);

  // When Step 2 is shown, check on-chain if pool (pair + fee + hook) already exists
  useEffect(() => {
    if (step !== 2 || !poolManagerAddress) return;
    const addr0 = (token0Addr || resolveAddress(token0)).trim();
    const addr1 = (token1Addr || resolveAddress(token1)).trim();
    if (!addr0 || !addr1 || addr0 === addr1) {
      setPoolExistsOnChain(false);
      return;
    }
    setPoolExistsOnChain(null);
    setOnChainSqrtPriceStep2(null);
    const hookAddr = getHookAddress(selectedHook) as `0x${string}`;
    const poolKey = buildPoolKey(
      addr0 as `0x${string}`,
      addr1 as `0x${string}`,
      fee,
      tickSpacing,
      hookAddr,
    );
    const poolId = getPoolId(poolKey);
    const pc = publicClientRef.current;
    if (!pc) {
      setPoolExistsOnChain(false);
      return;
    }
    let cancelled = false;
    pc.readContract({
      address: poolManagerAddress as `0x${string}`,
      abi: PoolManagerAbi,
      functionName: "getPoolState",
      args: [poolId],
    })
      .then((state) => {
        if (cancelled) return;
        const [initialized, sqrtPriceX96] = state as [boolean, bigint, number];
        setPoolExistsOnChain(!!initialized);
        if (initialized && sqrtPriceX96 > 0n) {
          setOnChainSqrtPriceStep2(sqrtPriceX96);
        } else {
          setOnChainSqrtPriceStep2(null);
        }
      })
      .catch(() => {
        if (!cancelled) setPoolExistsOnChain(false);
      });
    return () => {
      cancelled = true;
    };
  }, [
    step,
    poolManagerAddress,
    token0Addr,
    token1Addr,
    token0,
    token1,
    fee,
    tickSpacing,
    selectedHook,
  ]);

  /** Step 2: use on-chain price when pool exists, else user's initial price (for range/deposit display and math) */
  const effectivePriceForStep2 = useMemo(() => {
    if (
      poolExistsOnChain !== true ||
      onChainSqrtPriceStep2 == null ||
      onChainSqrtPriceStep2 <= 0n
    ) {
      return initialPrice;
    }
    const addr0 = (token0Addr || resolveAddress(token0)).trim();
    const addr1 = (token1Addr || resolveAddress(token1)).trim();
    if (!addr0 || !addr1 || addr0 === addr1) return initialPrice;
    const hookAddr = getHookAddress(selectedHook) as `0x${string}`;
    const poolKey = buildPoolKey(
      addr0 as `0x${string}`,
      addr1 as `0x${string}`,
      fee,
      tickSpacing,
      hookAddr,
    );
    const tokensFlipped =
      poolKey.currency0.toLowerCase() !== addr0.toLowerCase();
    const dec0 = resolveDecimals(token0);
    const dec1 = resolveDecimals(token1);
    const poolDec0 = tokensFlipped ? dec1 : dec0;
    const poolDec1 = tokensFlipped ? dec0 : dec1;
    const rawPrice = sqrtPriceX96ToPrice(
      onChainSqrtPriceStep2,
      poolDec0,
      poolDec1,
    );
    return tokensFlipped ? 1 / rawPrice : rawPrice;
  }, [
    poolExistsOnChain,
    onChainSqrtPriceStep2,
    initialPrice,
    token0Addr,
    token1Addr,
    token0,
    token1,
    selectedHook,
    fee,
    tickSpacing,
    resolveAddress,
    resolveDecimals,
  ]);

  const syncPriceToTicks = useCallback(() => {
    if (rangeMode === "full") return;
    const minP = parseFloat(minPriceStr);
    const maxP = parseFloat(maxPriceStr);
    if (!Number.isFinite(minP) || !Number.isFinite(maxP)) return;
    setTickLower(
      clampTick(
        roundToTickSpacing(priceToTick(minP), tickSpacing),
        tickSpacing,
      ),
    );
    setTickUpper(
      clampTick(
        roundToTickSpacing(priceToTick(maxP), tickSpacing),
        tickSpacing,
      ),
    );
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
    const ref = effectivePriceForStep2;
    const minP = ref * 0.95;
    const maxP = ref * 1.05;
    setMinPriceStr(minP.toFixed(4));
    setMaxPriceStr(maxP.toFixed(4));
    setTickLower(
      clampTick(
        roundToTickSpacing(priceToTick(minP), tickSpacing),
        tickSpacing,
      ),
    );
    setTickUpper(
      clampTick(
        roundToTickSpacing(priceToTick(maxP), tickSpacing),
        tickSpacing,
      ),
    );
  };

  const adjustMinPrice = (delta: number) => {
    if (rangeMode === "full") return;
    const p = parseFloat(minPriceStr) || effectivePriceForStep2;
    const newP = Math.max(0, p * (1 + delta));
    setMinPriceStr(newP.toFixed(4));
    setTickLower(
      clampTick(
        roundToTickSpacing(priceToTick(newP), tickSpacing),
        tickSpacing,
      ),
    );
  };
  const adjustMaxPrice = (delta: number) => {
    if (rangeMode === "full") return;
    const p = parseFloat(maxPriceStr) || effectivePriceForStep2;
    const newP = p * (1 + delta);
    setMaxPriceStr(newP.toFixed(4));
    setTickUpper(
      clampTick(
        roundToTickSpacing(priceToTick(newP), tickSpacing),
        tickSpacing,
      ),
    );
  };

  /** Percentage from effective price (initial or on-chain) */
  const minPricePct = (): string => {
    if (rangeMode === "full") return "";
    const p = parseFloat(minPriceStr);
    if (!Number.isFinite(p)) return "";
    const pct = ((p - effectivePriceForStep2) / effectivePriceForStep2) * 100;
    return `${pct >= 0 ? "+" : ""}${pct.toFixed(2)}%`;
  };
  const maxPricePct = (): string => {
    if (rangeMode === "full") return "";
    const p = parseFloat(maxPriceStr);
    if (!Number.isFinite(p)) return "";
    const pct = ((p - effectivePriceForStep2) / effectivePriceForStep2) * 100;
    return `${pct >= 0 ? "+" : ""}${pct.toFixed(2)}%`;
  };

  /** Deposit math: equivalent amount at effective price (token1 per token0) */
  const amount1AtPrice = (a0: string): string => {
    const n = parseFloat(a0);
    if (!Number.isFinite(n) || n <= 0) return "—";
    return (n * effectivePriceForStep2).toFixed(6);
  };
  const amount0AtPrice = (a1: string): string => {
    const n = parseFloat(a1);
    if (!Number.isFinite(n) || n <= 0 || effectivePriceForStep2 <= 0) return "—";
    return (n / effectivePriceForStep2).toFixed(6);
  };

  // Compute actual price boundaries from ticks (matches what the contract sees)
  const priceLower = useMemo(() => tickToPrice(tickLower), [tickLower]);
  const priceUpper = useMemo(() => tickToPrice(tickUpper), [tickUpper]);

  // Determine which tokens are needed based on current price vs tick range
  const depositMode = useMemo(() => {
    if (effectivePriceForStep2 <= priceLower) return "token0Only" as const;
    if (effectivePriceForStep2 >= priceUpper) return "token1Only" as const;
    return "both" as const;
  }, [effectivePriceForStep2, priceLower, priceUpper]);

  // Recalculate paired amount whenever the driving input, price, or range changes.
  // We track which token the user is editing via lastEditedToken and only re-derive
  // the *other* token's amount to avoid circular overwrites.
  const recalcPairedAmount = useCallback(
    (inputToken: 0 | 1, inputAmountStr: string) => {
      const inputAmt = parseFloat(inputAmountStr);
      if (!Number.isFinite(inputAmt) || inputAmt <= 0) {
        if (inputToken === 0) setAmount1("");
        else setAmount0("");
        setLiquidityAmount("0");
        return;
      }

      const result = computeLiquidityFromAmount(
        effectivePriceForStep2,
        priceLower,
        priceUpper,
        inputAmt,
        inputToken,
      );
      const dec0 = resolveDecimals(token0);
      const dec1 = resolveDecimals(token1);
      const liqWei = liquidityToWei(result.liquidity, dec0, dec1);
      setLiquidityAmount(liqWei.toString());

      if (inputToken === 0) {
        if (depositMode === "token0Only") {
          setAmount1("");
        } else {
          const newA1 =
            result.amount1 > 0
              ? parseFloat(result.amount1.toFixed(Math.min(dec1, 8))).toString()
              : "0";
          setAmount1(newA1);
        }
      } else {
        if (depositMode === "token1Only") {
          setAmount0("");
        } else {
          const newA0 =
            result.amount0 > 0
              ? parseFloat(result.amount0.toFixed(Math.min(dec0, 8))).toString()
              : "0";
          setAmount0(newA0);
        }
      }
    },
    [effectivePriceForStep2, priceLower, priceUpper, depositMode, token0, token1],
  );

  // Re-run calculation when price range or effective price changes (use the last-edited token as driver)
  useEffect(() => {
    const driverAmt = lastEditedToken === 0 ? amount0 : amount1;
    if (driverAmt && parseFloat(driverAmt) > 0) {
      recalcPairedAmount(lastEditedToken, driverAmt);
    }
    // Only react to range/price changes, not to amount changes (amounts are handled by onChange)
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [effectivePriceForStep2, priceLower, priceUpper, depositMode]);

  // When deposit mode changes (range adjusted), clear the disabled token's amount
  useEffect(() => {
    if (depositMode === "token0Only" && amount1 !== "") {
      setAmount1("");
      setLastEditedToken(0);
    }
    if (depositMode === "token1Only" && amount0 !== "") {
      setAmount0("");
      setLastEditedToken(1);
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [depositMode]);

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
      const hookAddr = getHookAddress(selectedHook) as `0x${string}`;
      const poolKey = buildPoolKey(
        addr0 as `0x${string}`,
        addr1 as `0x${string}`,
        fee,
        tickSpacing,
        hookAddr,
      );
      const dec0 = resolveDecimals(token0);
      const dec1 = resolveDecimals(token1);
      const sqrtPriceX96 = encodePriceSqrt(initialPrice, dec0, dec1);

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
    initialPrice,
    isConnected,
    accountId,
    hashConnectRef,
    selectedHook,
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
    let amount0Wei: bigint, amount1Wei: bigint;
    try {
      amount0Wei = parseUnits(amount0 || "0", dec0);
      amount1Wei = parseUnits(amount1 || "0", dec1);
    } catch {
      setError("Invalid amount.");
      return;
    }
    if (amount0Wei === 0n && amount1Wei === 0n) {
      setError("Enter amount for at least one token.");
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

      const hookAddr = getHookAddress(selectedHook) as `0x${string}`;
      const poolKey = buildPoolKey(
        addr0 as `0x${string}`,
        addr1 as `0x${string}`,
        fee,
        tickSpacing,
        hookAddr,
      );

      // Detect if buildPoolKey flipped token order (currency0 < currency1 canonical sort)
      const tokensFlipped =
        poolKey.currency0.toLowerCase() !== addr0.toLowerCase();
      // Map user amounts to pool's canonical order
      const poolAmount0Wei = tokensFlipped ? amount1Wei : amount0Wei;
      const poolAmount1Wei = tokensFlipped ? amount0Wei : amount1Wei;
      const poolDec0 = tokensFlipped ? dec1 : dec0;
      const poolDec1 = tokensFlipped ? dec0 : dec1;
      console.log(
        "[Add liquidity] tokensFlipped:",
        tokensFlipped,
        "poolAmount0:",
        poolAmount0Wei.toString(),
        "poolAmount1:",
        poolAmount1Wei.toString(),
      );

      const pmAddr = positionManagerAddress;
      const deadline = BigInt(Math.floor(Date.now() / 1000) + 3600);

      // Read on-chain pool state to get actual sqrtPriceX96
      const { encodeFunctionData: encFn } = await import("viem");
      const poolId = getPoolId(poolKey);
      let onChainSqrtPrice: bigint | null = null;
      let alreadyInitialized = false;
      const pcState = publicClientRef.current;
      if (pcState && poolManagerAddress) {
        try {
          const state = (await pcState.readContract({
            address: poolManagerAddress as `0x${string}`,
            abi: PoolManagerAbi,
            functionName: "getPoolState",
            args: [poolId],
          })) as [boolean, bigint, number];
          alreadyInitialized = state[0];
          if (alreadyInitialized && state[1] > 0n) {
            onChainSqrtPrice = state[1];
          }
          console.log(
            "[Add liquidity] pool initialized:",
            alreadyInitialized,
            "sqrtPriceX96:",
            onChainSqrtPrice?.toString(),
          );
        } catch {
          console.warn(
            "[Add liquidity] getPoolState check failed, will include initializePool",
          );
        }
      }

      // Use on-chain price or compute from initialPrice
      const sqrtPriceX96ForInit = encodePriceSqrt(
        initialPrice,
        poolDec0,
        poolDec1,
      );
      const sqrtPriceX96 = onChainSqrtPrice ?? sqrtPriceX96ForInit;

      // Compute BigInt sqrtPrices at tick boundaries
      const clampedTickLower = clampTick(tickLower, tickSpacing);
      const clampedTickUpper = clampTick(tickUpper, tickSpacing);
      const sqrtPA = getSqrtPriceAtTick(clampedTickLower);
      const sqrtPB = getSqrtPriceAtTick(clampedTickUpper);

      // Compute maximum liquidity from user's deposit amounts (BigInt precision)
      const liquidityBigInt = maxLiquidityForAmounts(
        sqrtPriceX96,
        sqrtPA,
        sqrtPB,
        poolAmount0Wei,
        poolAmount1Wei,
      );

      if (liquidityBigInt === 0n) {
        setError("Computed liquidity is zero. Adjust amounts or price range.");
        setPending(false);
        return;
      }

      // Compute exact amounts the contract will require (round up)
      const exact = amountsForLiquidity(
        sqrtPriceX96,
        sqrtPA,
        sqrtPB,
        liquidityBigInt,
      );
      // Add 1% slippage buffer for amount caps
      const amount0Max = exact.amount0 + exact.amount0 / 100n + 1n;
      const amount1Max = exact.amount1 + exact.amount1 / 100n + 1n;

      console.log(
        "[Add liquidity] BigInt math:",
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

      const unlockData = encodeUnlockDataMint(
        poolKey,
        clampedTickLower,
        clampedTickUpper,
        liquidityBigInt,
        amount0Max,
        amount1Max,
        ownerEvmAddress as `0x${string}`,
      );

      // Read nextTokenId before mint so we know the NFT tokenId that will be assigned
      let mintedTokenId: number | null = null;
      const pcForTokenId = publicClientRef.current;
      if (pcForTokenId) {
        try {
          const nxt = (await pcForTokenId.readContract({
            address: pmAddr as `0x${string}`,
            abi: PositionManagerAbi,
            functionName: "nextTokenId",
          })) as bigint;
          mintedTokenId = Number(nxt);
          console.log(
            "[Add liquidity] nextTokenId (will be minted):",
            mintedTokenId,
          );
        } catch (e) {
          console.warn("[Add liquidity] could not read nextTokenId:", e);
        }
      }

      // Step 1: Transfer tokens to PositionManager (use buffered max amounts)
      const transferPairs: [string, bigint, string][] = [];
      if (amount0Max > 0n) {
        transferPairs.push([
          poolKey.currency0,
          amount0Max,
          tokensFlipped ? token1.symbol : token0.symbol,
        ]);
      }
      if (amount1Max > 0n) {
        transferPairs.push([
          poolKey.currency1,
          amount1Max,
          tokensFlipped ? token0.symbol : token1.symbol,
        ]);
      }
      for (const [currency, amtWei, symbol] of transferPairs) {
        console.log(
          "[Add liquidity] transferring",
          amtWei.toString(),
          "of",
          currency,
          `(${symbol})`,
          "to PM",
        );
        try {
          await hederaTokenTransfer({
            hashConnect: hc,
            accountId,
            tokenAddress: currency,
            to: pmAddr,
            amount: amtWei,
            gas: HEDERA_GAS_ERC20,
          });
          console.log("[Add liquidity] transfer confirmed for", symbol);
        } catch (transferErr) {
          throw new Error(
            `Failed to transfer ${symbol} to PositionManager: insufficient balance or token not associated. ` +
              `Needed ${amtWei.toString()} units. Check your ${symbol} balance.`,
          );
        }
      }

      // Step 2: Build multicall
      const calls: `0x${string}`[] = [];
      if (!alreadyInitialized) {
        calls.push(
          encFn({
            abi: PositionManagerAbi,
            functionName: "initializePool",
            args: [poolKey, sqrtPriceX96ForInit],
          }) as `0x${string}`,
        );
      }
      const modifyCalldata = encFn({
        abi: PositionManagerAbi,
        functionName: "modifyLiquidities",
        args: [unlockData, deadline],
      }) as `0x${string}`;
      calls.push(modifyCalldata);

      // Step 3: multicall (initializePool only if needed + modifyLiquidities)
      console.log(
        `[Add liquidity] calling multicall with ${calls.length} subcall(s)${alreadyInitialized ? " (pool already initialized, skipping init)" : ""}`,
      );
      const txId = await hederaContractMulticall({
        hashConnect: hc,
        accountId,
        contractId: pmAddr,
        calls,
        gas: HEDERA_GAS_MODIFY_LIQ,
      });
      setTxHash(txId);
      console.log("[Add liquidity] multicall success:", txId);

      // Ensure pool is in DynamoDB so it appears in Explore and Pools list (covers both existing and newly initialized pool)
      try {
        await fetch("/api/pools/ensure", {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({
            poolId,
            deployedBy: ownerEvmAddress?.toLowerCase(),
          }),
        });
      } catch (e) {
        console.warn("[Add liquidity] failed to ensure pool in DB:", e);
      }

      // Save position to DynamoDB so it shows up in "Your positions" (covers both existing and newly initialized pool; single multicall handles both)
      if (mintedTokenId != null) {
        try {
          await fetch("/api/positions", {
            method: "POST",
            headers: { "Content-Type": "application/json" },
            body: JSON.stringify({
              tokenId: mintedTokenId,
              poolId,
              owner: ownerEvmAddress.toLowerCase(),
              tickLower: clampedTickLower,
              tickUpper: clampedTickUpper,
              liquidity: liquidityBigInt.toString(),
              currency0: poolKey.currency0,
              currency1: poolKey.currency1,
              symbol0: tokensFlipped ? token1.symbol : token0.symbol,
              symbol1: tokensFlipped ? token0.symbol : token1.symbol,
              fee,
              tickSpacing,
              decimals0: poolDec0,
              decimals1: poolDec1,
              hooks: hookAddr,
              hookName: AVAILABLE_HOOKS.find((h) => h.id === selectedHook)
                ?.name,
            }),
          });
          console.log(
            "[Add liquidity] position saved, tokenId:",
            mintedTokenId,
          );
        } catch (e) {
          console.warn("[Add liquidity] failed to save position to DB:", e);
        }
      }
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
    poolManagerAddress,
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
    initialPrice,
    isConnected,
    accountId,
    hashConnectRef,
    selectedHook,
  ]);

  // Save pool to DynamoDB
  const savePool = useCallback(async () => {
    const addr0 = (token0Addr || resolveAddress(token0)).trim();
    const addr1 = (token1Addr || resolveAddress(token1)).trim();
    if (!addr0 || !addr1 || addr0 === addr1) return;
    const hookAddr = getHookAddress(selectedHook) as `0x${string}`;
    const poolKey = buildPoolKey(
      addr0 as `0x${string}`,
      addr1 as `0x${string}`,
      fee,
      tickSpacing,
      hookAddr,
    );
    const poolId = getPoolId(poolKey);

    // Derive deployer EVM address from Hedera accountId
    let deployedBy: string | undefined;
    if (accountId) {
      const m = String(accountId).match(/^(\d+)\.(\d+)\.(\d+)$/);
      if (m) {
        deployedBy = "0x" + BigInt(m[3]!).toString(16).padStart(40, "0");
      }
    }

    const dec0 = resolveDecimals(token0);
    const dec1 = resolveDecimals(token1);
    const flipped = poolKey.currency0.toLowerCase() !== addr0.toLowerCase();

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
          symbol0: flipped ? token1.symbol : token0.symbol,
          symbol1: flipped ? token0.symbol : token1.symbol,
          deployedBy,
          initialPrice: initialPriceStr,
          sqrtPriceX96: String(
            encodePriceSqrt(
              initialPrice,
              flipped ? dec1 : dec0,
              flipped ? dec0 : dec1,
            ),
          ),
          decimals0: flipped ? dec1 : dec0,
          decimals1: flipped ? dec0 : dec1,
          hooks: hookAddr,
          hookName: AVAILABLE_HOOKS.find((h) => h.id === selectedHook)?.name,
        }),
      });
      if (!res.ok) throw new Error("Failed to save pool");
      setSaveSuccess(true);
    } catch {
      /* ignore */
    } finally {
      setSavePending(false);
    }
  }, [
    token0Addr,
    token1Addr,
    token0,
    token1,
    fee,
    tickSpacing,
    accountId,
    initialPriceStr,
    initialPrice,
    selectedHook,
  ]);

  const sym0 = resolved0?.symbol ?? token0.symbol;
  const sym1 = resolved1?.symbol ?? token1.symbol;

  // Token selector modal states
  const [token0SelectorOpen, setToken0SelectorOpen] = useState(false);
  const [token1SelectorOpen, setToken1SelectorOpen] = useState(false);

  const selectorTokens = tokenOptions;

  return (
    <div className="max-w-4xl mx-auto animate-[fadeIn_0.3s_ease-out]">
      <div className="flex flex-col lg:flex-row gap-6 lg:gap-8">
        {/* Steps: horizontal on mobile, sidebar on lg */}
        <aside className="flex lg:flex-col items-center lg:items-start gap-0 w-full lg:w-44 shrink-0">
          <div className="flex items-center gap-2 sm:gap-3 flex-1 lg:flex-initial lg:flex-col lg:items-start lg:pt-1">
            <div
              className={`w-3 h-3 rounded-full shrink-0 ${step >= 1 ? "bg-accent ring-2 ring-accent/30" : "bg-surface-3"}`}
            />
            <div className="flex flex-col">
              <span className="text-xs font-semibold text-text-primary">
                Step 1
              </span>
              <span className="text-xs text-text-tertiary hidden sm:inline">
                Select pair & fees
              </span>
            </div>
          </div>
          <div
            className={`w-8 sm:w-12 lg:w-0.5 lg:h-8 lg:ml-[5px] h-0.5 lg:h-8 flex-shrink-0 ${step >= 2 ? "bg-accent" : "bg-border"}`}
          />
          <div className="flex items-center gap-2 sm:gap-3 flex-1 lg:flex-initial lg:flex-col lg:items-start">
            <div
              className={`w-3 h-3 rounded-full shrink-0 ${step >= 2 ? "bg-accent ring-2 ring-accent/30" : "bg-surface-3"}`}
            />
            <div className="flex flex-col">
              <span className="text-xs font-semibold text-text-primary">
                Step 2
              </span>
              <span className="text-xs text-text-tertiary hidden sm:inline">
                Range & deposits
              </span>
            </div>
          </div>
        </aside>

        {/* Content */}
        <div className="flex-1 min-w-0 space-y-4 sm:space-y-5">
          {/* Pair header bar (step 2) — responsive */}
          {step === 2 && (
            <div className="flex flex-wrap items-center justify-between gap-3 px-4 sm:px-5 py-3 rounded-xl bg-surface-2/80 border border-white/[0.06]">
              <div className="flex items-center gap-2 sm:gap-3 flex-wrap">
                <TokenPairIcon symbol0={sym0} symbol1={sym1} size={28} />
                <span className="text-sm font-semibold text-text-primary">
                  {sym0} / {sym1}
                </span>
                <Badge variant="accent">v4</Badge>
                <Badge>{formatFee(fee)}</Badge>
              </div>
              <button
                type="button"
                className="flex items-center gap-1.5 px-3 py-2 text-xs font-medium text-text-secondary hover:text-text-primary rounded-xl hover:bg-surface-3/80 transition-colors cursor-pointer"
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
            <div className="rounded-2xl border border-white/[0.06] bg-surface-2/50 p-4 sm:p-5 md:p-6 space-y-5 sm:space-y-6 shadow-inner">
              <div>
                <h3 className="text-base sm:text-lg font-semibold text-text-primary mb-1">
                  Select pair
                </h3>
                <p className="text-sm text-text-tertiary">
                  Choose two HTS tokens for your pool. Paste a 0x or 0.0.XXXXX
                  address to resolve symbol and decimals.
                </p>
              </div>

              {/* Token pair selectors — styled like SwapCard */}
              <div className="flex flex-wrap items-center gap-2 sm:gap-3">
                <button
                  type="button"
                  className="group flex items-center gap-2.5 pl-3 pr-3.5 py-2.5 rounded-full bg-surface-3/90 hover:bg-surface-4 border border-white/[0.08] hover:border-accent/30 transition-all duration-200 cursor-pointer shrink-0 shadow-sm"
                  onClick={() => setToken0SelectorOpen(true)}
                >
                  <TokenIcon symbol={sym0} size={26} />
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
                    className="text-text-tertiary group-hover:text-text-secondary transition-colors"
                  >
                    <polyline points="6 9 12 15 18 9" />
                  </svg>
                </button>
                <button
                  type="button"
                  className="group flex items-center gap-2.5 pl-3 pr-3.5 py-2.5 rounded-full bg-surface-3/90 hover:bg-surface-4 border border-white/[0.08] hover:border-accent/30 transition-all duration-200 cursor-pointer shrink-0 shadow-sm"
                  onClick={() => setToken1SelectorOpen(true)}
                >
                  <TokenIcon symbol={sym1} size={26} />
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
                    className="text-text-tertiary group-hover:text-text-secondary transition-colors"
                  >
                    <polyline points="6 9 12 15 18 9" />
                  </svg>
                </button>
              </div>
              {isConnected && (
                <p className="text-xs text-text-tertiary">
                  Balance:{" "}
                  <span className="font-medium text-text-secondary">
                    {balance0Loading ? "…" : balance0Formatted} {sym0}
                  </span>
                  {" · "}
                  <span className="font-medium text-text-secondary">
                    {balance1Loading ? "…" : balance1Formatted} {sym1}
                  </span>
                </p>
              )}

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
                  } else if (isAddressLike(t.address ?? "")) {
                    setToken0({
                      id: t.address ?? "",
                      symbol: t.symbol,
                      address: t.address,
                      decimals: t.decimals,
                      name: t.name,
                    });
                    setToken0Addr(t.address ?? "");
                  }
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
                  } else if (isAddressLike(t.address ?? "")) {
                    setToken1({
                      id: t.address ?? "",
                      symbol: t.symbol,
                      address: t.address,
                      decimals: t.decimals,
                      name: t.name,
                    });
                    setToken1Addr(t.address ?? "");
                  }
                  setToken1SelectorOpen(false);
                }}
                tokens={selectorTokens}
                selectedToken={token1}
                excludeToken={token0}
              />

              {/* Paste addresses — responsive grid */}
              <div className="grid grid-cols-1 sm:grid-cols-2 gap-3 sm:gap-4">
                <div className="space-y-1.5">
                  <label className="text-xs font-medium text-text-secondary uppercase tracking-wider">
                    Token 0 address
                  </label>
                  <input
                    type="text"
                    className="w-full px-3 py-2.5 bg-surface-2 border border-white/[0.08] rounded-xl text-sm text-text-primary placeholder:text-text-tertiary focus:outline-none focus:border-accent/40 focus:ring-1 focus:ring-accent/20 transition-colors font-mono"
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
                      <span className="text-success flex items-center gap-1 flex-wrap">
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
                  <label className="text-xs font-medium text-text-secondary uppercase tracking-wider">
                    Token 1 address
                  </label>
                  <input
                    type="text"
                    className="w-full px-3 py-2.5 bg-surface-2 border border-white/[0.08] rounded-xl text-sm text-text-primary placeholder:text-text-tertiary focus:outline-none focus:border-accent/40 focus:ring-1 focus:ring-accent/20 transition-colors font-mono"
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
                      <span className="text-success flex items-center gap-1 flex-wrap">
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
                  className={`w-full flex items-center justify-between p-4 rounded-xl border cursor-pointer transition-all ${
                    fee === 3000
                      ? "bg-accent/10 border-accent/50 shadow-sm"
                      : "bg-surface-2/80 border-white/[0.08] hover:border-accent/30"
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
                <div className="grid grid-cols-1 sm:grid-cols-3 gap-3">
                  {FEE_TIERS.map((tier) => (
                    <button
                      key={tier.fee}
                      type="button"
                      className={`flex flex-col items-start p-3 rounded-xl border cursor-pointer transition-all ${
                        fee === tier.fee
                          ? "bg-accent/10 border-accent/50"
                          : "bg-surface-2/80 border-white/[0.08] hover:border-accent/30"
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

              {/* Hook selector */}
              <div>
                <h3 className="text-base font-semibold text-text-primary mb-1">
                  Hook (optional)
                </h3>
                <p className="text-sm text-text-tertiary mb-3">
                  Attach a hook contract to customize pool behavior — e.g. TWAP
                  oracles, dynamic fees, or limit orders.
                </p>
                <div className="grid grid-cols-1 sm:grid-cols-2 gap-3">
                  {AVAILABLE_HOOKS.map((hook) => (
                    <button
                      key={hook.id}
                      type="button"
                      className={`flex flex-col items-start p-3 rounded-xl border cursor-pointer transition-all ${
                        selectedHook === hook.id
                          ? "bg-accent/10 border-accent/50"
                          : "bg-surface-2/80 border-white/[0.08] hover:border-accent/30"
                      }`}
                      onClick={() => setSelectedHook(hook.id)}
                    >
                      <span className="text-sm font-semibold text-text-primary">
                        {hook.name}
                      </span>
                      <span className="text-xs text-text-tertiary mt-0.5">
                        {hook.description}
                      </span>
                      {selectedHook === hook.id && (
                        <Badge variant="accent" className="mt-1">
                          Selected
                        </Badge>
                      )}
                    </button>
                  ))}
                </div>
              </div>

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
            <div className="space-y-4 sm:space-y-5">
              {/* ---- Pool status: loading / already created / set initial price ---- */}
              {poolExistsOnChain === null && (
                <div className="rounded-2xl border border-white/[0.06] bg-surface-2/50 p-4 sm:p-5 md:p-6 shadow-inner">
                  <p className="text-sm text-text-tertiary">Checking pool…</p>
                </div>
              )}
              {poolExistsOnChain === true && (
                <div className="rounded-2xl border border-white/[0.06] bg-surface-2/50 p-4 sm:p-5 md:p-6 space-y-2 shadow-inner">
                  <h3 className="text-base font-semibold text-text-primary">
                    Pool already created
                  </h3>
                  <p className="text-sm text-text-tertiary">
                    This pool exists. Set your price range and deposit amounts
                    below to create a position.
                  </p>
                  {effectivePriceForStep2 > 0 && (
                    <p className="text-sm font-medium text-text-secondary">
                      Current price: 1 {token0.symbol} ={" "}
                      {effectivePriceForStep2 >= 1e6
                        ? effectivePriceForStep2.toExponential(2)
                        : effectivePriceForStep2 < 0.0001
                          ? effectivePriceForStep2.toExponential(2)
                          : effectivePriceForStep2.toFixed(6).replace(/\.?0+$/, "")}{" "}
                      {token1.symbol} (rate from pool)
                    </p>
                  )}
                </div>
              )}
              {poolExistsOnChain === false && (
                <div className="rounded-2xl border border-white/[0.06] bg-surface-2/50 p-4 sm:p-5 md:p-6 space-y-4 shadow-inner">
                  <div>
                    <h3 className="text-base font-semibold text-text-primary mb-1">
                      Set initial price
                    </h3>
                    <p className="text-sm text-text-tertiary">
                      When creating a new pool, you must set the starting
                      exchange rate for both tokens. This rate will reflect the
                      initial market price.
                    </p>
                  </div>
                  <div className="space-y-2">
                    <label className="text-xs font-medium text-text-secondary uppercase tracking-wider">
                      Initial price
                    </label>
                    <div className="flex flex-wrap items-stretch gap-2 sm:gap-3">
                      <input
                        type="text"
                        className="flex-1 min-w-[100px] px-4 py-3 bg-surface-2 border border-white/[0.08] rounded-xl text-xl sm:text-2xl font-bold text-text-primary placeholder:text-text-tertiary focus:outline-none focus:border-accent/40 focus:ring-1 focus:ring-accent/20 transition-colors"
                        placeholder="0"
                        value={
                          priceQuotePerToken0
                            ? initialPriceStr
                            : initialPrice > 0
                              ? (1 / initialPrice)
                                  .toFixed(6)
                                  .replace(/\.?0+$/, "")
                              : ""
                        }
                        onChange={(e) => {
                          const v = e.target.value;
                          if (priceQuotePerToken0) {
                            setInitialPriceStr(v);
                          } else {
                            const n = parseFloat(v);
                            if (Number.isFinite(n) && n > 0)
                              setInitialPriceStr((1 / n).toFixed(10));
                          }
                        }}
                        aria-label="Initial price"
                      />
                      <div className="flex rounded-full p-1 bg-surface-2 border border-white/[0.08] shrink-0">
                        <button
                          type="button"
                          onClick={() => setPriceQuotePerToken0(true)}
                          className={`flex items-center gap-1.5 px-3 py-2 rounded-full text-sm font-medium transition-all cursor-pointer ${
                            priceQuotePerToken0
                              ? "bg-surface-1 text-text-primary shadow-sm border border-white/[0.06]"
                              : "text-text-tertiary hover:text-text-secondary"
                          }`}
                        >
                          <TokenIcon symbol={sym0} size={18} />
                          {sym0}
                        </button>
                        <button
                          type="button"
                          onClick={() => setPriceQuotePerToken0(false)}
                          className={`flex items-center gap-1.5 px-3 py-2 rounded-full text-sm font-medium transition-all cursor-pointer ${
                            !priceQuotePerToken0
                              ? "bg-surface-1 text-text-primary shadow-sm border border-white/[0.06]"
                              : "text-text-tertiary hover:text-text-secondary"
                          }`}
                        >
                          <TokenIcon symbol={sym1} size={18} />
                          {sym1}
                        </button>
                      </div>
                    </div>
                    <p className="text-sm text-text-tertiary">
                      {priceQuotePerToken0
                        ? `${sym1} = 1 ${sym0}`
                        : `${sym0} = 1 ${sym1}`}
                    </p>
                  </div>
                  <div className="flex items-start gap-2 p-3 rounded-xl bg-warning-muted/50 border border-warning/15">
                    <svg
                      width="18"
                      height="18"
                      viewBox="0 0 24 24"
                      fill="none"
                      stroke="currentColor"
                      strokeWidth="2"
                      className="text-warning shrink-0 mt-0.5"
                    >
                      <path d="M10.29 3.86L1.82 18a2 2 0 001.71 3h16.94a2 2 0 001.71-3L13.71 3.86a2 2 0 00-3.42 0z" />
                      <line x1="12" y1="9" x2="12" y2="13" />
                      <line x1="12" y1="17" x2="12.01" y2="17" />
                    </svg>
                    <p className="text-xs text-warning">
                      Market price not found. Please do your own research to
                      avoid loss of funds.
                    </p>
                  </div>
                </div>
              )}

              {/* ---- Set Price Range ---- */}
              <div className="rounded-2xl border border-white/[0.06] bg-surface-2/50 p-4 sm:p-5 md:p-6 space-y-4 sm:space-y-5 shadow-inner">
                <h3 className="text-base font-semibold text-text-primary">
                  Set price range
                </h3>

                {/* Full/Custom toggle */}
                <div className="flex p-1 bg-surface-2 rounded-full w-fit">
                  <button
                    type="button"
                    className={`px-4 py-2 text-sm font-medium rounded-full transition-all cursor-pointer ${
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
                    className={`px-4 py-2 text-sm font-medium rounded-full transition-all cursor-pointer ${
                      rangeMode === "custom"
                        ? "bg-surface-1 text-text-primary shadow-sm"
                        : "text-text-tertiary hover:text-text-secondary"
                    }`}
                    onClick={setCustomRange}
                  >
                    Custom range
                  </button>
                </div>

                <p className="text-sm text-text-tertiary leading-relaxed">
                  {rangeMode === "full"
                    ? "Setting full range liquidity when creating a pool ensures continuous market participation across all possible prices, offering simplicity but with potential for higher impermanent loss."
                    : "Custom range concentrates liquidity within specific bounds, enhancing capital efficiency but needing more active management."}
                </p>

                {/* Min / Max price boxes — responsive */}
                <div className="grid grid-cols-1 sm:grid-cols-2 gap-3 sm:gap-4">
                  <div className="bg-surface-2/80 border border-white/[0.06] rounded-xl p-4 space-y-2">
                    <label className="text-xs font-medium text-text-secondary uppercase tracking-wider">
                      Min price
                    </label>
                    <div className="flex items-center gap-2">
                      {rangeMode === "full" ? (
                        <span className="text-xl sm:text-2xl font-bold text-text-primary">
                          0
                        </span>
                      ) : (
                        <>
                          <button
                            type="button"
                            className="w-8 h-8 flex items-center justify-center rounded-lg bg-surface-3 text-text-secondary hover:text-text-primary hover:bg-surface-1 transition-colors cursor-pointer text-sm font-bold shrink-0"
                            onClick={() => adjustMinPrice(-0.005)}
                          >
                            −
                          </button>
                          <input
                            type="text"
                            className="flex-1 min-w-0 px-2 py-1.5 bg-transparent text-center text-lg font-bold text-text-primary focus:outline-none rounded"
                            value={minPriceStr}
                            onChange={(e) => {
                              setMinPriceStr(e.target.value);
                              setTimeout(syncPriceToTicks, 0);
                            }}
                            onBlur={syncPriceToTicks}
                          />
                          <button
                            type="button"
                            className="w-8 h-8 flex items-center justify-center rounded-lg bg-surface-3 text-text-secondary hover:text-text-primary hover:bg-surface-1 transition-colors cursor-pointer text-sm font-bold shrink-0"
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

                  <div className="bg-surface-2/80 border border-white/[0.06] rounded-xl p-4 space-y-2">
                    <label className="text-xs font-medium text-text-secondary uppercase tracking-wider">
                      Max price
                    </label>
                    <div className="flex items-center gap-2">
                      {rangeMode === "full" ? (
                        <span className="text-xl sm:text-2xl font-bold text-text-primary">
                          ∞
                        </span>
                      ) : (
                        <>
                          <button
                            type="button"
                            className="w-8 h-8 flex items-center justify-center rounded-lg bg-surface-3 text-text-secondary hover:text-text-primary hover:bg-surface-1 transition-colors cursor-pointer text-sm font-bold shrink-0"
                            onClick={() => adjustMaxPrice(-0.005)}
                          >
                            −
                          </button>
                          <input
                            type="text"
                            className="flex-1 min-w-0 px-2 py-1.5 bg-transparent text-center text-lg font-bold text-text-primary focus:outline-none rounded"
                            value={maxPriceStr}
                            onChange={(e) => {
                              setMaxPriceStr(e.target.value);
                              setTimeout(syncPriceToTicks, 0);
                            }}
                            onBlur={syncPriceToTicks}
                          />
                          <button
                            type="button"
                            className="w-8 h-8 flex items-center justify-center rounded-lg bg-surface-3 text-text-secondary hover:text-text-primary hover:bg-surface-1 transition-colors cursor-pointer text-sm font-bold shrink-0"
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

              {/* ---- Deposit tokens ---- */}
              <div className="rounded-2xl border border-white/[0.06] bg-surface-2/50 p-4 sm:p-5 md:p-6 space-y-4 sm:space-y-5 shadow-inner">
                <div>
                  <h3 className="text-base font-semibold text-text-primary mb-1">
                    Deposit tokens
                  </h3>
                  <p className="text-sm text-text-tertiary">
                    Enter the amount for one token — the other will be
                    auto-calculated based on your price range.
                  </p>
                </div>

                {/* Token 0 deposit */}
                <div
                  className={`rounded-xl p-4 transition-all ${
                    depositMode === "token1Only"
                      ? "bg-surface-2/40 border border-white/[0.04] opacity-50"
                      : "bg-surface-2/80 border border-white/[0.06]"
                  }`}
                >
                  {depositMode === "token1Only" && (
                    <p className="text-xs text-warning mb-2">
                      Current price is above your max price — only {sym1} is
                      needed
                    </p>
                  )}
                  <div className="flex flex-wrap items-center gap-2 sm:gap-3">
                    <input
                      type="text"
                      className={`flex-1 min-w-[80px] bg-transparent text-xl sm:text-2xl font-bold placeholder:text-text-tertiary focus:outline-none ${
                        depositMode === "token1Only"
                          ? "text-text-tertiary cursor-not-allowed"
                          : "text-text-primary"
                      }`}
                      placeholder="0"
                      value={amount0}
                      disabled={depositMode === "token1Only"}
                      onChange={(e) => {
                        const v = e.target.value;
                        setAmount0(v);
                        setLastEditedToken(0);
                        setError(null);
                        recalcPairedAmount(0, v);
                      }}
                    />
                    <div className="flex items-center gap-2 px-3 py-2 bg-surface-3/80 rounded-full shrink-0 border border-white/[0.06]">
                      <TokenIcon symbol={sym0} size={22} />
                      <span className="text-sm font-semibold text-text-primary">
                        {sym0}
                      </span>
                    </div>
                  </div>
                  <div className="flex flex-wrap items-center justify-between gap-1 mt-2 text-xs text-text-tertiary">
                    <span>
                      {depositMode !== "token1Only" &&
                      amount0 &&
                      parseFloat(amount0) > 0
                        ? `≈ ${amount1AtPrice(amount0)} ${sym1}`
                        : ""}
                    </span>
                    <div className="flex items-center gap-2">
                      <span>
                        Balance: {balance0Loading ? "…" : balance0Formatted}{" "}
                        {sym0}
                      </span>
                      {isConnected &&
                        balance0Formatted &&
                        balance0Formatted !== "0" &&
                        depositMode !== "token1Only" && (
                          <button
                            type="button"
                            className="px-1.5 py-0.5 text-[10px] font-bold text-accent bg-accent/10 hover:bg-accent/20 rounded transition-colors cursor-pointer"
                            onClick={() => {
                              setAmount0(balance0Formatted);
                              setLastEditedToken(0);
                              recalcPairedAmount(0, balance0Formatted);
                            }}
                          >
                            MAX
                          </button>
                        )}
                    </div>
                  </div>
                </div>

                {/* Token 1 deposit */}
                <div
                  className={`rounded-xl p-4 transition-all ${
                    depositMode === "token0Only"
                      ? "bg-surface-2/40 border border-white/[0.04] opacity-50"
                      : "bg-surface-2/80 border border-white/[0.06]"
                  }`}
                >
                  {depositMode === "token0Only" && (
                    <p className="text-xs text-warning mb-2">
                      Current price is below your min price — only {sym0} is
                      needed
                    </p>
                  )}
                  <div className="flex flex-wrap items-center gap-2 sm:gap-3">
                    <input
                      type="text"
                      className={`flex-1 min-w-[80px] bg-transparent text-xl sm:text-2xl font-bold placeholder:text-text-tertiary focus:outline-none ${
                        depositMode === "token0Only"
                          ? "text-text-tertiary cursor-not-allowed"
                          : "text-text-primary"
                      }`}
                      placeholder="0"
                      value={amount1}
                      disabled={depositMode === "token0Only"}
                      onChange={(e) => {
                        const v = e.target.value;
                        setAmount1(v);
                        setLastEditedToken(1);
                        setError(null);
                        recalcPairedAmount(1, v);
                      }}
                    />
                    <div className="flex items-center gap-2 px-3 py-2 bg-surface-3/80 rounded-full shrink-0 border border-white/[0.06]">
                      <TokenIcon symbol={sym1} size={22} />
                      <span className="text-sm font-semibold text-text-primary">
                        {sym1}
                      </span>
                    </div>
                  </div>
                  <div className="flex flex-wrap items-center justify-between gap-1 mt-2 text-xs text-text-tertiary">
                    <span>
                      {depositMode !== "token0Only" &&
                      amount1 &&
                      parseFloat(amount1) > 0
                        ? `≈ ${amount0AtPrice(amount1)} ${sym0}`
                        : ""}
                    </span>
                    <div className="flex items-center gap-2">
                      <span>
                        Balance: {balance1Loading ? "…" : balance1Formatted}{" "}
                        {sym1}
                      </span>
                      {isConnected &&
                        balance1Formatted &&
                        balance1Formatted !== "0" &&
                        depositMode !== "token0Only" && (
                          <button
                            type="button"
                            className="px-1.5 py-0.5 text-[10px] font-bold text-accent bg-accent/10 hover:bg-accent/20 rounded transition-colors cursor-pointer"
                            onClick={() => {
                              setAmount1(balance1Formatted);
                              setLastEditedToken(1);
                              recalcPairedAmount(1, balance1Formatted);
                            }}
                          >
                            MAX
                          </button>
                        )}
                    </div>
                  </div>
                </div>

                {/* Errors / success */}
                {error && (
                  <ErrorMessage
                    message={error}
                    onDismiss={() => setError(null)}
                  />
                )}
                {txHash && (
                  <div className="flex items-center gap-2 px-4 py-3 rounded-xl bg-success-muted text-success text-sm">
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

                {/* Actions — responsive */}
                <div className="flex flex-col-reverse sm:flex-row gap-3 pt-1">
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
                      (parseFloat(amount0 || "0") <= 0 &&
                        parseFloat(amount1 || "0") <= 0) ||
                      !positionManagerAddress
                    }
                    onClick={addLiquidity}
                    loading={pending}
                  >
                    Create pool & add liquidity
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
