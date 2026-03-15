"use client";

import { useState, useCallback } from "react";
import { TokenPairIcon } from "./TokenIcon";
import { Badge } from "@/components/ui/Badge";
import { Button } from "@/components/ui/Button";
import { ErrorMessage } from "./ErrorMessage";
import { useHashPack } from "@/context/HashPackContext";
import { getPositionManagerAddress } from "@/constants";
import { encodeUnlockDataBurn } from "@/lib/addLiquidity";
import { hederaContractMulticall } from "@/lib/hederaContract";
import { PositionManagerAbi } from "@/abis/PositionManager";
import { getFriendlyErrorMessage } from "@/lib/errors";
import type { PoolInfo } from "./PoolPositions";

interface BurnPositionModalProps {
  pool: PoolInfo;
  onClose: () => void;
}

function formatFee(fee: number): string {
  return `${(fee / 10000).toFixed(2)}%`;
}

const HEDERA_GAS_MODIFY_LIQ = 5_000_000;

export function BurnPositionModal({ pool, onClose }: BurnPositionModalProps) {
  const { accountId, isConnected, hashConnectRef } = useHashPack();
  const [tokenId, setTokenId] = useState(
    pool.tokenId != null ? String(pool.tokenId) : "",
  );
  const [confirmed, setConfirmed] = useState(false);
  const [pending, setPending] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [txHash, setTxHash] = useState<string | null>(null);

  const positionManagerAddress = getPositionManagerAddress();

  const burnPosition = useCallback(async () => {
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

    setError(null);
    setPending(true);
    setTxHash(null);

    try {
      const posTokenId = BigInt(tokenId.trim());
      const deadline = BigInt(Math.floor(Date.now() / 1000) + 3600);

      // BURN_POSITION removes all remaining liquidity, collects fees, and burns the NFT
      const unlockData = encodeUnlockDataBurn(posTokenId, 0n, 0n);

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

      // Delete position record from DynamoDB if we have the positionId
      if (pool.tokenId != null) {
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
  }, [positionManagerAddress, tokenId, isConnected, accountId, hashConnectRef]);

  const buttonText = !isConnected
    ? "Connect wallet"
    : !tokenId.trim()
      ? "Enter position token ID"
      : !confirmed
        ? "Confirm to burn"
        : pending
          ? "Burning position…"
          : "Burn position & withdraw all";

  const canSubmit =
    isConnected &&
    !!tokenId.trim() &&
    confirmed &&
    !pending &&
    !txHash &&
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
      </div>

      {/* Warning */}
      <div className="rounded-xl border border-error/20 bg-error-muted/50 p-4">
        <div className="flex items-start gap-3">
          <svg
            width="20"
            height="20"
            viewBox="0 0 24 24"
            fill="none"
            stroke="currentColor"
            strokeWidth="2"
            strokeLinecap="round"
            strokeLinejoin="round"
            className="text-error shrink-0 mt-0.5"
          >
            <path d="M10.29 3.86L1.82 18a2 2 0 001.71 3h16.94a2 2 0 001.71-3L13.71 3.86a2 2 0 00-3.42 0z" />
            <line x1="12" y1="9" x2="12" y2="13" />
            <line x1="12" y1="17" x2="12.01" y2="17" />
          </svg>
          <div>
            <p className="text-sm font-medium text-error">
              This action is irreversible
            </p>
            <p className="text-xs text-text-secondary mt-1">
              Burning will remove <strong>all remaining liquidity</strong>,
              collect any accrued fees, and permanently destroy the position
              NFT. You will receive your tokens back.
            </p>
          </div>
        </div>
      </div>

      {/* What happens */}
      <div className="rounded-xl border border-white/[0.06] bg-surface-2/30 p-4">
        <p className="text-xs font-medium text-text-tertiary uppercase tracking-wider mb-3">
          What will happen
        </p>
        <div className="space-y-2.5">
          <div className="flex items-start gap-2.5">
            <span className="flex items-center justify-center w-5 h-5 rounded-full bg-accent/15 text-accent text-xs font-bold shrink-0 mt-0.5">
              1
            </span>
            <p className="text-sm text-text-secondary">
              All remaining liquidity is withdrawn from the pool
            </p>
          </div>
          <div className="flex items-start gap-2.5">
            <span className="flex items-center justify-center w-5 h-5 rounded-full bg-accent/15 text-accent text-xs font-bold shrink-0 mt-0.5">
              2
            </span>
            <p className="text-sm text-text-secondary">
              Any uncollected fees are sent to your wallet
            </p>
          </div>
          <div className="flex items-start gap-2.5">
            <span className="flex items-center justify-center w-5 h-5 rounded-full bg-accent/15 text-accent text-xs font-bold shrink-0 mt-0.5">
              3
            </span>
            <p className="text-sm text-text-secondary">
              The position NFT is permanently burned
            </p>
          </div>
        </div>
      </div>

      {/* Token ID input */}
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
            setTxHash(null);
          }}
        />
        <p className="text-xs text-text-tertiary">
          The NFT token ID of your position from the mint transaction
        </p>
      </div>

      {/* Confirmation checkbox */}
      {tokenId.trim() && (
        <label className="flex items-start gap-3 p-3 rounded-xl border border-white/[0.06] bg-surface-2/30 cursor-pointer select-none">
          <input
            type="checkbox"
            checked={confirmed}
            onChange={(e) => setConfirmed(e.target.checked)}
            className="mt-0.5 w-4 h-4 rounded border-white/20 bg-surface-3 text-accent focus:ring-accent/30 cursor-pointer"
          />
          <span className="text-sm text-text-secondary">
            I understand that burning this position is permanent and cannot be
            undone. All liquidity and fees will be withdrawn to my wallet.
          </span>
        </label>
      )}

      {/* Error / Success */}
      {error && (
        <ErrorMessage message={error} onDismiss={() => setError(null)} />
      )}
      {txHash && (
        <div className="flex items-center gap-2 px-4 py-3 rounded-xl bg-success-muted text-success text-sm">
          Position burned!{" "}
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
        variant="danger"
        fullWidth
        disabled={!canSubmit}
        onClick={burnPosition}
        loading={pending}
      >
        {buttonText}
      </Button>
    </div>
  );
}
