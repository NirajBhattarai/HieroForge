"use client";

import { useState, useEffect, useCallback, useRef } from "react";
import {
  createPublicClient,
  http,
  type PublicClient,
  type Address,
} from "viem";
import {
  HEDERA_TESTNET,
  HOOKS_ZERO,
  getHookPermissionsFromAddress,
} from "@/constants";
import { Badge } from "@/components/ui/Badge";

const TWAP_ORACLE_ABI = [
  {
    type: "function",
    name: "observe",
    inputs: [
      { name: "id", type: "bytes32" },
      { name: "secondsAgo", type: "uint32" },
    ],
    outputs: [{ name: "arithmeticMeanTick", type: "int24" }],
    stateMutability: "view",
  },
  {
    type: "function",
    name: "getObservationCount",
    inputs: [{ name: "id", type: "bytes32" }],
    outputs: [{ name: "", type: "uint256" }],
    stateMutability: "view",
  },
] as const;

/** Convert tick to human-readable price (1.0001^tick). */
function tickToPrice(tick: number): string {
  const price = Math.pow(1.0001, tick);
  if (price >= 1000) return price.toFixed(0);
  if (price >= 1) return price.toFixed(4);
  return price.toPrecision(4);
}

interface TWAPOracleCardProps {
  hookAddress: string;
  poolId: string;
  symbol0: string;
  symbol1: string;
}

interface TWAPData {
  currentTick: number | null;
  twap5m: number | null;
  twap1h: number | null;
  observations: number | null;
  loading: boolean;
  error: string | null;
}

export function TWAPOracleCard({
  hookAddress,
  poolId,
  symbol0,
  symbol1,
}: TWAPOracleCardProps) {
  const [data, setData] = useState<TWAPData>({
    currentTick: null,
    twap5m: null,
    twap1h: null,
    observations: null,
    loading: true,
    error: null,
  });
  const [autoRefresh, setAutoRefresh] = useState(true);
  const clientRef = useRef<PublicClient | null>(null);

  if (!clientRef.current && typeof window !== "undefined") {
    clientRef.current = createPublicClient({
      chain: HEDERA_TESTNET,
      transport: http(),
    }) as PublicClient;
  }

  const fetchTWAP = useCallback(async () => {
    const client = clientRef.current;
    if (!client || !hookAddress || hookAddress === HOOKS_ZERO || !poolId)
      return;

    setData((prev) => ({ ...prev, loading: true, error: null }));
    try {
      const hookAddr = hookAddress as Address;
      const id = poolId as `0x${string}`;

      // Parallel reads: current tick (0s), 5-min TWAP, 1-hour TWAP
      const results = await Promise.allSettled([
        client.readContract({
          address: hookAddr,
          abi: TWAP_ORACLE_ABI,
          functionName: "observe",
          args: [id, 0],
        }),
        client.readContract({
          address: hookAddr,
          abi: TWAP_ORACLE_ABI,
          functionName: "observe",
          args: [id, 300],
        }),
        client.readContract({
          address: hookAddr,
          abi: TWAP_ORACLE_ABI,
          functionName: "observe",
          args: [id, 3600],
        }),
      ]);

      setData({
        currentTick:
          results[0].status === "fulfilled" ? Number(results[0].value) : null,
        twap5m:
          results[1].status === "fulfilled" ? Number(results[1].value) : null,
        twap1h:
          results[2].status === "fulfilled" ? Number(results[2].value) : null,
        observations: null,
        loading: false,
        error: null,
      });
    } catch (err) {
      setData((prev) => ({
        ...prev,
        loading: false,
        error: err instanceof Error ? err.message : "Failed to fetch TWAP data",
      }));
    }
  }, [hookAddress, poolId]);

  useEffect(() => {
    fetchTWAP();
  }, [fetchTWAP]);

  // Auto-refresh every 30 seconds
  useEffect(() => {
    if (!autoRefresh) return;
    const interval = setInterval(fetchTWAP, 30000);
    return () => clearInterval(interval);
  }, [autoRefresh, fetchTWAP]);

  const permissions = getHookPermissionsFromAddress(hookAddress);

  return (
    <div className="rounded-2xl border border-blue-500/20 bg-blue-500/[0.04] p-4 sm:p-5 space-y-4">
      {/* Header */}
      <div className="flex items-center justify-between">
        <div className="flex items-center gap-2.5">
          <div className="w-8 h-8 rounded-full bg-blue-500/20 flex items-center justify-center">
            <svg
              width="16"
              height="16"
              viewBox="0 0 24 24"
              fill="none"
              stroke="currentColor"
              strokeWidth="2"
              className="text-blue-400"
            >
              <polyline points="22 12 18 12 15 21 9 3 6 12 2 12" />
            </svg>
          </div>
          <div>
            <h4 className="text-sm font-semibold text-text-primary">
              TWAP Oracle
            </h4>
            <p className="text-xs text-text-tertiary">
              Time-Weighted Average Price
            </p>
          </div>
        </div>
        <div className="flex items-center gap-2">
          <button
            type="button"
            className="p-1.5 rounded-lg hover:bg-surface-3/80 transition-colors cursor-pointer"
            onClick={fetchTWAP}
            title="Refresh"
          >
            <svg
              width="14"
              height="14"
              viewBox="0 0 24 24"
              fill="none"
              stroke="currentColor"
              strokeWidth="2"
              className={`text-text-tertiary ${data.loading ? "animate-spin" : ""}`}
            >
              <polyline points="23 4 23 10 17 10" />
              <polyline points="1 20 1 14 7 14" />
              <path d="M3.51 9a9 9 0 0 1 14.85-3.36L23 10M1 14l4.64 4.36A9 9 0 0 0 20.49 15" />
            </svg>
          </button>
          <label className="flex items-center gap-1.5 text-xs text-text-tertiary cursor-pointer">
            <input
              type="checkbox"
              checked={autoRefresh}
              onChange={(e) => setAutoRefresh(e.target.checked)}
              className="rounded border-border accent-blue-500"
            />
            Auto
          </label>
        </div>
      </div>

      {/* Hook permissions */}
      {permissions.length > 0 && (
        <div className="flex flex-wrap gap-1.5">
          {permissions.map((p) => (
            <span
              key={p}
              className="px-2 py-0.5 text-[10px] font-medium rounded-full bg-blue-500/10 text-blue-400 border border-blue-500/20"
            >
              {p}
            </span>
          ))}
        </div>
      )}

      {/* Data display */}
      {data.error ? (
        <div className="text-xs text-text-tertiary bg-surface-2/50 rounded-xl px-3 py-2">
          No oracle data yet — swap on this pool to start recording ticks.
        </div>
      ) : data.loading ? (
        <div className="grid grid-cols-3 gap-3">
          {[1, 2, 3].map((i) => (
            <div key={i} className="h-16 skeleton rounded-xl" />
          ))}
        </div>
      ) : (
        <div className="grid grid-cols-3 gap-3">
          {/* Current price */}
          <div className="bg-surface-2/60 rounded-xl p-3 space-y-1">
            <p className="text-[10px] font-medium text-text-tertiary uppercase tracking-wider">
              Current
            </p>
            <p className="text-lg font-bold text-text-primary">
              {data.currentTick != null ? tickToPrice(data.currentTick) : "—"}
            </p>
            <p className="text-[10px] text-text-tertiary">
              {symbol1} per {symbol0}
            </p>
            {data.currentTick != null && (
              <p className="text-[10px] text-text-tertiary font-mono">
                tick {data.currentTick}
              </p>
            )}
          </div>

          {/* 5-min TWAP */}
          <div className="bg-surface-2/60 rounded-xl p-3 space-y-1">
            <p className="text-[10px] font-medium text-text-tertiary uppercase tracking-wider">
              5m TWAP
            </p>
            <p className="text-lg font-bold text-blue-400">
              {data.twap5m != null ? tickToPrice(data.twap5m) : "—"}
            </p>
            <p className="text-[10px] text-text-tertiary">
              {symbol1} per {symbol0}
            </p>
            {data.twap5m != null && data.currentTick != null && (
              <p
                className={`text-[10px] font-medium ${data.twap5m > data.currentTick ? "text-green-400" : data.twap5m < data.currentTick ? "text-red-400" : "text-text-tertiary"}`}
              >
                {data.twap5m > data.currentTick ? "+" : ""}
                {data.twap5m - data.currentTick} ticks
              </p>
            )}
          </div>

          {/* 1-hour TWAP */}
          <div className="bg-surface-2/60 rounded-xl p-3 space-y-1">
            <p className="text-[10px] font-medium text-text-tertiary uppercase tracking-wider">
              1h TWAP
            </p>
            <p className="text-lg font-bold text-blue-400">
              {data.twap1h != null ? tickToPrice(data.twap1h) : "—"}
            </p>
            <p className="text-[10px] text-text-tertiary">
              {symbol1} per {symbol0}
            </p>
            {data.twap1h != null && data.currentTick != null && (
              <p
                className={`text-[10px] font-medium ${data.twap1h > data.currentTick ? "text-green-400" : data.twap1h < data.currentTick ? "text-red-400" : "text-text-tertiary"}`}
              >
                {data.twap1h > data.currentTick ? "+" : ""}
                {data.twap1h - data.currentTick} ticks
              </p>
            )}
          </div>
        </div>
      )}

      {/* Footer */}
      <div className="flex items-center justify-between text-[10px] text-text-tertiary pt-1 border-t border-blue-500/10">
        <span className="font-mono truncate max-w-[180px]" title={hookAddress}>
          Hook: {hookAddress.slice(0, 8)}...{hookAddress.slice(-6)}
        </span>
        <span>Ring buffer oracle · 720 max observations</span>
      </div>
    </div>
  );
}

/** Compact hook badge for pool lists. */
export function HookBadge({
  hookAddress,
  hookName,
}: {
  hookAddress?: string;
  hookName?: string;
}) {
  if (!hookAddress || hookAddress === HOOKS_ZERO) return null;

  const label = hookName || "Hook";
  return (
    <Badge className="bg-blue-500/10 text-blue-400 border-blue-500/20">
      <svg
        width="10"
        height="10"
        viewBox="0 0 24 24"
        fill="none"
        stroke="currentColor"
        strokeWidth="2.5"
        className="inline mr-1 -mt-px"
      >
        <path d="M10 13a5 5 0 0 0 7.54.54l3-3a5 5 0 0 0-7.07-7.07l-1.72 1.71" />
        <path d="M14 11a5 5 0 0 0-7.54-.54l-3 3a5 5 0 0 0 7.07 7.07l1.71-1.71" />
      </svg>
      {label}
    </Badge>
  );
}
