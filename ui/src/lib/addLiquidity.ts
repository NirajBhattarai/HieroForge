import { encodeAbiParameters, keccak256, getAddress, type Address } from "viem";
import { MINT_POSITION_ACTION, SQRT_PRICE_1_1 } from "../abis/PositionManager";

const HOOKS_ZERO = "0x0000000000000000000000000000000000000000" as const;

/** Convert Hedera native ID (0.0.XXXXX) to EVM address if needed. */
function normalizeAddress(addr: string): string {
  const match = addr.match(/^(\d+)\.(\d+)\.(\d+)$/);
  if (match) return "0x" + BigInt(match[3]!).toString(16).padStart(40, "0");
  return addr;
}

export interface PoolKey {
  currency0: Address;
  currency1: Address;
  fee: number;
  tickSpacing: number;
  hooks: Address;
}

/** Build PoolKey with currency0 < currency1 (canonical order). */
export function buildPoolKey(
  token0: Address,
  token1: Address,
  fee: number,
  tickSpacing: number,
): PoolKey {
  // Checksummed addresses required by viem's encodeAbiParameters
  const a = getAddress(normalizeAddress(token0));
  const b = getAddress(normalizeAddress(token1));
  const currency0 = a.toLowerCase() < b.toLowerCase() ? a : b;
  const currency1 = a.toLowerCase() < b.toLowerCase() ? b : a;
  return {
    currency0: currency0 as Address,
    currency1: currency1 as Address,
    fee,
    tickSpacing,
    hooks: HOOKS_ZERO,
  };
}

/** Compute PoolId = keccak256(abi.encode(poolKey)) (matches core PoolIdLibrary.toId). */
export function getPoolId(poolKey: PoolKey): `0x${string}` {
  const encoded = encodeAbiParameters(
    [
      { type: "address", name: "currency0" },
      { type: "address", name: "currency1" },
      { type: "uint24", name: "fee" },
      { type: "int24", name: "tickSpacing" },
      { type: "address", name: "hooks" },
    ],
    [
      poolKey.currency0,
      poolKey.currency1,
      poolKey.fee,
      poolKey.tickSpacing,
      poolKey.hooks,
    ],
  );
  return keccak256(encoded);
}

/** Encode unlockData for modifyLiquidities: abi.encode(actions, params) where actions = [MINT_POSITION], params = [mintParams]. */
export function encodeUnlockDataMint(
  poolKey: PoolKey,
  tickLower: number,
  tickUpper: number,
  liquidity: bigint,
  amount0Max: bigint,
  amount1Max: bigint,
  owner: Address,
): `0x${string}` {
  // amount0Max/amount1Max = the amounts transferred to PM. Matches Foundry script: uint128(amount0), uint128(amount1).
  const mintParam = encodeAbiParameters(
    [
      {
        type: "tuple",
        name: "poolKey",
        components: [
          { type: "address", name: "currency0" },
          { type: "address", name: "currency1" },
          { type: "uint24", name: "fee" },
          { type: "int24", name: "tickSpacing" },
          { type: "address", name: "hooks" },
        ],
      },
      { type: "int24", name: "tickLower" },
      { type: "int24", name: "tickUpper" },
      { type: "uint256", name: "liquidity" },
      { type: "uint128", name: "amount0Max" },
      { type: "uint128", name: "amount1Max" },
      { type: "address", name: "owner" },
      { type: "bytes", name: "hookData" },
    ],
    [
      poolKey,
      tickLower,
      tickUpper,
      liquidity,
      amount0Max,
      amount1Max,
      owner,
      "0x",
    ],
  );
  // actions = single byte MINT_POSITION (0x02), same as abi.encodePacked(uint8(0x02))
  const actions =
    `0x${MINT_POSITION_ACTION.toString(16).padStart(2, "0")}` as `0x${string}`;
  // unlockData = abi.encode(bytes actions, bytes[] params)
  return encodeAbiParameters(
    [
      { type: "bytes", name: "actions" },
      { type: "bytes[]", name: "params" },
    ],
    [actions, [mintParam]],
  ) as `0x${string}`;
}

/** Default sqrtPriceX96 for new pools (1:1). */
export { SQRT_PRICE_1_1 };
