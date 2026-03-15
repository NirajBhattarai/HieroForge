import { createPublicClient, http, isAddress, getAddress } from "viem";
import { PoolManagerAbi } from "@/abis/PoolManager";
import { HEDERA_TESTNET, getPoolManagerAddress, getRpcUrl } from "@/constants";
import type { PoolRecord } from "@/lib/dynamo-pools";

const HEDERA_MIRROR = "https://testnet.mirrornode.hedera.com";

/** Initialize event topic0 hash. */
const INITIALIZE_EVENT_TOPIC =
  "0xdd466e674ea557f56295e2d0218a125ea4b4f0f6f3307b95f85e6110838d6438";

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

/** Convert EVM address to Hedera entity format (0.0.XXXXX). */
function evmAddressToHederaId(addr: string): string | null {
  const hex = addr.replace(/^0x/, "").replace(/^0+/, "");
  if (!hex) return null;
  const num = parseInt(hex, 16);
  if (!Number.isFinite(num) || num <= 0) return null;
  return `0.0.${num}`;
}

/** Lookup HTS token metadata from mirror node. */
async function lookupTokenMeta(
  address: string,
): Promise<{ symbol: string; decimals: number } | null> {
  const hederaId = evmAddressToHederaId(address);
  if (!hederaId) return null;
  try {
    const res = await fetch(`${HEDERA_MIRROR}/api/v1/tokens/${hederaId}`);
    if (!res.ok) return null;
    const data = await res.json();
    return {
      symbol: String(data.symbol ?? ""),
      decimals: Number(data.decimals ?? 0),
    };
  } catch {
    return null;
  }
}

/**
 * Discover a pool's full details from on-chain data by querying
 * the Hedera mirror node for the Initialize event log.
 *
 * Returns a PoolRecord if the pool exists on-chain, or null otherwise.
 */
export async function discoverPoolFromChain(
  poolId: string,
): Promise<PoolRecord | null> {
  const normalizedPoolId = poolId.toLowerCase().trim();
  if (!isValidPoolId(normalizedPoolId)) return null;

  const poolManagerAddress = getPoolManagerAddress();
  if (!poolManagerAddress || !isAddress(poolManagerAddress)) return null;

  // 1. Confirm pool exists on-chain
  const validation = await validatePoolOnChain(normalizedPoolId);
  if (!validation.exists) return null;

  // 2. Query mirror node for Initialize event log
  // The PoolManager EVM address may need converting to entity ID for the logs endpoint
  const contractId = evmAddressToHederaId(poolManagerAddress);
  if (!contractId) return null;

  const logsUrl =
    `${HEDERA_MIRROR}/api/v1/contracts/${contractId}/results/logs` +
    `?topic0=${INITIALIZE_EVENT_TOPIC}` +
    `&topic1=${normalizedPoolId}` +
    `&limit=1`;

  let logEntry: {
    topics: string[];
    data: string;
  } | null = null;

  try {
    const res = await fetch(logsUrl);
    if (!res.ok) return null;
    const json = await res.json();
    const logs = json.logs as Array<{ topics: string[]; data: string }>;
    if (!logs || logs.length === 0) return null;
    logEntry = logs[0];
  } catch {
    return null;
  }

  if (!logEntry || logEntry.topics.length < 4) return null;

  // 3. Parse event topics and data
  // topics: [eventSig, poolId, currency0, currency1]
  const currency0 = getAddress(
    "0x" + logEntry.topics[2].slice(-40),
  ).toLowerCase();
  const currency1 = getAddress(
    "0x" + logEntry.topics[3].slice(-40),
  ).toLowerCase();

  // data: fee(uint24) | tickSpacing(int24) | hooks(address) | sqrtPriceX96(uint160) | tick(int24)
  // Each is ABI-encoded as 32 bytes
  const rawData = logEntry.data.replace(/^0x/, "");
  if (rawData.length < 320) return null;

  const fee = parseInt(rawData.slice(0, 64), 16);
  // tickSpacing is int24 — check sign bit
  const tickSpacingRaw = BigInt("0x" + rawData.slice(64, 128));
  const tickSpacing =
    tickSpacingRaw > BigInt("0x7fffff")
      ? Number(tickSpacingRaw - BigInt("0x1" + "0".repeat(64)))
      : Number(tickSpacingRaw);
  const hooks = getAddress(
    "0x" + rawData.slice(128, 192).slice(-40),
  ).toLowerCase();
  const sqrtPriceX96 = BigInt("0x" + rawData.slice(192, 256)).toString();

  // 4. Fetch token metadata
  const [meta0, meta1] = await Promise.all([
    lookupTokenMeta(currency0),
    lookupTokenMeta(currency1),
  ]);

  const record: PoolRecord = {
    poolId: normalizedPoolId,
    currency0,
    currency1,
    fee,
    tickSpacing,
    symbol0: meta0?.symbol,
    symbol1: meta1?.symbol,
    decimals0: meta0?.decimals,
    decimals1: meta1?.decimals,
    hooks,
    sqrtPriceX96,
    createdAt: new Date().toISOString(),
  };

  return record;
}
