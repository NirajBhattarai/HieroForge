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
import { hederaContractExecute } from "@/lib/hederaContract";
import { PositionManagerAbi } from "@/abis/PositionManager";
import { PoolManagerAbi } from "@/abis/PoolManager";
import { amountsForLiquidity, getSqrtPriceAtTick } from "@/lib/sqrtPriceMath";
import { getFriendlyErrorMessage } from "@/lib/errors";
import { accountIdToLongZero, getAccountEvmAddress } from "@/lib/hederaAccount";
import type { PoolInfo } from "./PoolPositions";

interface RemoveLiquidityModalProps {
  pool: PoolInfo;
  onClose: () => void;
  onReview?: (percent: number) => void;
}

function formatFee(fee: number): string {
  return `${(fee / 10000).toFixed(2)}%`;
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
  const [accountEvmAlias, setAccountEvmAlias] = useState<string | null>(null);

  const network = (typeof process !== "undefined" && process.env?.NEXT_PUBLIC_HEDERA_NETWORK) || "testnet";
  useEffect(() => {
    if (!accountId) {
      setAccountEvmAlias(null);
      return;
    }
    let cancelled = false;
    getAccountEvmAddress(accountId, network).then((evm) => {
      if (!cancelled) setAccountEvmAlias(evm ?? null);
    });
    return () => { cancelled = true; };
  }, [accountId, network]);

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

  const { estimated0, estimated1, estimatesReady } = useMemo(() => {
    if (
      !sqrtPriceX96 ||
      !hasTicks ||
      liquidityWei <= 0n
    ) {
      return { estimated0: "—", estimated1: "—", estimatesReady: false };
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
        estimatesReady: true,
      };
    } catch {
      return { estimated0: "—", estimated1: "—", estimatesReady: false };
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
      // If the token no longer exists (e.g. already burned), the on-chain loader returns null.
      setError(percent === 100 ? "Position not found on chain (already burned)." : "Load position from chain first.");
      return;
    }
    // Burn-only (100%) is allowed even when tracked liquidity is 0.
    // PositionManager._burn supports burning when liquidity is already cleared.
    if (liquidityWei <= 0n && percent !== 100) {
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

      // For BURN_POSITION we need ERC721 approval:
      // PositionManager._burn() uses onlyIfApproved(msgSender(), tokenId).
      // So the account that sends modifyLiquidities must be approved (or be the owner).
      const ensureBurnApproval = async () => {
        if (percent !== 100) return;
        const spender =
          (accountEvmAlias?.toLowerCase() ?? accountIdToLongZero(accountId)?.toLowerCase()) ??
          null;
        if (!spender) {
          setError("Unable to resolve sender EVM address for burn approval.");
          return;
        }

        const owner =
          (onChain?.owner ? String(onChain.owner) : undefined)?.toLowerCase() ??
          null;

        // If we can't read on-chain owner, fall back to ownerOf().
        let ownerResolved = owner;
        if (!ownerResolved) {
          const ownerFromChain = (await publicClient.readContract({
            address: positionManagerAddress as `0x${string}`,
            abi: PositionManagerAbi,
            functionName: "ownerOf",
            args: [posTokenId],
          })) as string;
          ownerResolved = ownerFromChain.toLowerCase();
        }

        if (!ownerResolved) {
          setError("Unable to resolve position owner for burn approval.");
          return;
        }

        // If the connected wallet is not the ERC721 owner, we can't auto-approve;
        // the owner must approve the sender.
        if (ownerResolved !== spender) {
          setError(
            "Connected wallet is not the position NFT owner. Switch to the owner wallet or have the owner approve this NFT."
          );
          return;
        }

        const approved = (await publicClient.readContract({
          address: positionManagerAddress as `0x${string}`,
          abi: PositionManagerAbi,
          functionName: "getApproved",
          args: [posTokenId],
        })) as string;

        const approvedForAll = (await publicClient.readContract({
          address: positionManagerAddress as `0x${string}`,
          abi: PositionManagerAbi,
          functionName: "isApprovedForAll",
          args: [ownerResolved as `0x${string}`, spender as `0x${string}`],
        })) as boolean;

        const alreadyApproved =
          (approved && approved.toLowerCase() === spender.toLowerCase()) || approvedForAll;

        if (alreadyApproved) return;

        // Approve spender to burn this specific token.
        const approveArgs: readonly unknown[] = [spender as `0x${string}`, posTokenId];
        await hederaContractExecute({
          hashConnect: hc,
          accountId,
          contractId: positionManagerAddress,
          abi: PositionManagerAbi,
          functionName: "approve",
          args: approveArgs,
          gas: 2_000_000,
        });
      };

      if (percent === 100) {
        await ensureBurnApproval();
      }

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
      if (percent === 100) {
        try {
          // DynamoDB positions table stores positionId as String(tokenId).
          const positionId =
            (resolvedTokenId ?? (onChain?.tokenId != null ? String(onChain.tokenId) : "")) ||
            "";
          if (!positionId) return;
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
    onChain?.tokenId,
    onChain?.owner,
    liquidityWei,
    accountEvmAlias,
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
            : liquidityWei <= 0n && percent !== 100
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
    (percent === 100 ? true : liquidityWei > 0n) &&
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
            You: {accountId} → long-zero: {accountIdToLongZero(accountId) ?? "—"}
          </p>
          {accountEvmAlias && (
            <p className="text-xs text-text-secondary font-mono break-all mt-0.5">
              Your ECDSA address (tx sender): {accountEvmAlias}
            </p>
          )}
          {(() => {
            const owner = onChain.owner.toLowerCase();
            const longZero = (accountIdToLongZero(accountId) ?? "").toLowerCase();
            const evmAlias = (accountEvmAlias ?? "").toLowerCase();
            const ownerIsLongZero = owner === longZero;
            const ownerIsEvmAlias = evmAlias && owner === evmAlias;
            if (ownerIsEvmAlias) {
              return (
                <p className="text-xs text-success mt-2">
                  You can remove — owner matches your tx sender (ECDSA).
                </p>
              );
            }
            if (ownerIsLongZero && evmAlias) {
              return (
                <p className="text-xs text-amber-500 mt-2">
                  Remove will fail: Hedera sends txs from your ECDSA address, but this position is owned by your long-zero. New positions created from this app now use your ECDSA address so remove works. This position was created with the old flow; use the same sender that created it, or add new liquidity and remove that instead.
                </p>
              );
            }
            if (owner !== longZero && !ownerIsEvmAlias) {
              return (
                <p className="text-xs text-amber-500 mt-2">
                  Only the on-chain owner can remove. If you see Unauthorized, use the wallet that created this position.
                </p>
              );
            }
            return (
              <p className="text-xs text-text-tertiary mt-2">
                If you get Unauthorized, Hedera may be using your ECDSA address as sender. New positions use that address so remove works.
              </p>
            );
          })()}
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
          {!estimatesReady && (
            <p className="text-xs text-text-tertiary">
              — means the app couldn’t estimate yet (needs on-chain pool price + position range).
            </p>
          )}
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
