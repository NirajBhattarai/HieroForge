import { createPublicClient, http, isAddress } from "viem";
import { PoolManagerAbi } from "@/abis/PoolManager";
import { HEDERA_TESTNET, getPoolManagerAddress, getRpcUrl } from "@/constants";

export interface PoolValidationResult {
  validated: boolean;
  exists: boolean;
  reason?: string;
}

function isValidPoolId(poolId: string): boolean {
  return /^0x[0-9a-fA-F]{64}$/.test(poolId.trim());
}

/**
 * Confirms whether a pool exists on-chain by reading PoolManager.getPoolState(poolId).
 * A pool is considered valid only when initialized == true.
 */
export async function validatePoolOnChain(
  poolId: string,
): Promise<PoolValidationResult> {
  const normalizedPoolId = poolId.toLowerCase().trim();
  if (!isValidPoolId(normalizedPoolId)) {
    return {
      validated: true,
      exists: false,
      reason: "Invalid poolId format",
    };
  }

  const poolManagerAddress = getPoolManagerAddress();
  if (!poolManagerAddress || !isAddress(poolManagerAddress)) {
    return {
      validated: false,
      exists: false,
      reason: "PoolManager address is missing or invalid",
    };
  }

  try {
    const client = createPublicClient({
      chain: HEDERA_TESTNET,
      transport: http(getRpcUrl()),
    });

    const state = (await client.readContract({
      address: poolManagerAddress as `0x${string}`,
      abi: PoolManagerAbi,
      functionName: "getPoolState",
      args: [normalizedPoolId as `0x${string}`],
    })) as readonly [boolean, bigint, number];

    return {
      validated: true,
      exists: !!state?.[0],
    };
  } catch (err) {
    return {
      validated: false,
      exists: false,
      reason: err instanceof Error ? err.message : "Chain validation failed",
    };
  }
}
