/**
 * Decode PositionManager positionInfo (packed uint256) and fetch position + poolKey from chain.
 * Layout (from PositionInfo.sol): 200 bits poolId | 24 bits tickUpper | 24 bits tickLower | 8 bits hasSubscriber
 */
import { createPublicClient, http } from "viem";
import { PositionManagerAbi } from "@/abis/PositionManager";
import { getRpcUrl, getPositionManagerAddress } from "@/constants";

const TICK_LOWER_OFFSET = 8;
const TICK_UPPER_OFFSET = 32;
const MASK_24_BITS = 0xffffff;

function signExtend24(v: number): number {
  return v & 0x800000 ? v - 0x1000000 : v;
}

/**
 * Decode packed PositionInfo uint256 to tickLower, tickUpper, and poolId (for poolKeys lookup).
 * poolId is the upper 200 bits of the packed info; encoded as 25 bytes (50 hex chars) for bytes25.
 */
export function decodePositionInfo(info: bigint): {
  tickLower: number;
  tickUpper: number;
  poolIdBytes25: `0x${string}`;
} {
  const tickLower = signExtend24(
    Number((info >> BigInt(TICK_LOWER_OFFSET)) & BigInt(MASK_24_BITS)),
  );
  const tickUpper = signExtend24(
    Number((info >> BigInt(TICK_UPPER_OFFSET)) & BigInt(MASK_24_BITS)),
  );
  const poolId200 = info >> 56n;
  const poolIdHex = poolId200.toString(16).padStart(50, "0");
  const poolIdBytes25 = ("0x" + poolIdHex) as `0x${string}`;
  return { tickLower, tickUpper, poolIdBytes25 };
}

export interface PositionOnChain {
  tokenId: number;
  liquidity: string;
  tickLower: number;
  tickUpper: number;
  currency0: string;
  currency1: string;
  fee: number;
  tickSpacing: number;
  hooks: string;
  owner?: string;
}

/**
 * Fetch position data from PositionManager contract (liquidity, ticks, poolKey).
 * Returns null if token does not exist or tickSpacing is 0.
 */
export async function fetchPositionOnChain(
  tokenId: number | string,
  positionManagerAddress?: string,
  rpcUrl?: string,
): Promise<PositionOnChain | null> {
  const tid = BigInt(tokenId);
  const pmAddr = (positionManagerAddress || getPositionManagerAddress()) as `0x${string}`;
  const client = createPublicClient({
    transport: http(rpcUrl || getRpcUrl()),
  });

  const [liquidity, infoRaw, owner] = await Promise.all([
    client.readContract({
      address: pmAddr,
      abi: PositionManagerAbi,
      functionName: "positionLiquidity",
      args: [tid],
    }),
    client.readContract({
      address: pmAddr,
      abi: PositionManagerAbi,
      functionName: "positionInfo",
      args: [tid],
    }),
    client
      .readContract({
        address: pmAddr,
        abi: PositionManagerAbi,
        functionName: "ownerOf",
        args: [tid],
      })
      .catch(() => null),
  ]);

  const infoBigInt = BigInt(infoRaw as bigint);
  if (infoBigInt === 0n) return null;
  const { tickLower, tickUpper, poolIdBytes25 } = decodePositionInfo(infoBigInt);

  let poolKey: { currency0: string; currency1: string; fee: number; tickSpacing: number; hooks?: string };
  try {
    poolKey = (await client.readContract({
      address: pmAddr,
      abi: PositionManagerAbi,
      functionName: "poolKeys",
      args: [poolIdBytes25],
    })) as { currency0: string; currency1: string; fee: number; tickSpacing: number; hooks?: string };
  } catch {
    return null;
  }

  if (poolKey.tickSpacing === 0) return null;

  const hooksAddr =
    typeof poolKey.hooks === "string" ? poolKey.hooks : "0x0000000000000000000000000000000000000000";
  return {
    tokenId: Number(tid),
    liquidity: String(liquidity),
    tickLower,
    tickUpper,
    currency0: poolKey.currency0,
    currency1: poolKey.currency1,
    fee: Number(poolKey.fee),
    tickSpacing: Number(poolKey.tickSpacing),
    hooks: hooksAddr,
    owner: typeof owner === "string" ? owner : undefined,
  };
}
