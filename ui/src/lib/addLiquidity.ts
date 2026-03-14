import { encodeAbiParameters, keccak256, getAddress, type Address } from "viem";
import {
  MINT_POSITION_ACTION,
  INCREASE_LIQUIDITY_ACTION,
  DECREASE_LIQUIDITY_ACTION,
  BURN_POSITION_ACTION,
  MINT_POSITION_FROM_DELTAS_ACTION,
  INCREASE_LIQUIDITY_FROM_DELTAS_ACTION,
  PM_SETTLE_PAIR,
  PM_CLOSE_CURRENCY,
  SQRT_PRICE_1_1,
} from "../abis/PositionManager";

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

/**
 * Encode unlockData for DECREASE_LIQUIDITY action.
 * Used to remove liquidity from an existing position by tokenId.
 * actions = [DECREASE_LIQUIDITY], params = [abi.encode(tokenId, liquidity, amount0Min, amount1Min, hookData)]
 */
export function encodeUnlockDataDecrease(
  tokenId: bigint,
  liquidity: bigint,
  amount0Min: bigint,
  amount1Min: bigint,
): `0x${string}` {
  const decreaseParam = encodeAbiParameters(
    [
      { type: "uint256", name: "tokenId" },
      { type: "uint256", name: "liquidity" },
      { type: "uint128", name: "amount0Min" },
      { type: "uint128", name: "amount1Min" },
      { type: "bytes", name: "hookData" },
    ],
    [tokenId, liquidity, amount0Min, amount1Min, "0x"],
  );

  const actions =
    `0x${DECREASE_LIQUIDITY_ACTION.toString(16).padStart(2, "0")}` as `0x${string}`;
  return encodeAbiParameters(
    [
      { type: "bytes", name: "actions" },
      { type: "bytes[]", name: "params" },
    ],
    [actions, [decreaseParam]],
  ) as `0x${string}`;
}

/**
 * Encode unlockData for BURN_POSITION action (full remove + burn NFT).
 * actions = [BURN_POSITION], params = [abi.encode(tokenId, amount0Min, amount1Min, hookData)]
 */
export function encodeUnlockDataBurn(
  tokenId: bigint,
  amount0Min: bigint,
  amount1Min: bigint,
): `0x${string}` {
  const burnParam = encodeAbiParameters(
    [
      { type: "uint256", name: "tokenId" },
      { type: "uint128", name: "amount0Min" },
      { type: "uint128", name: "amount1Min" },
      { type: "bytes", name: "hookData" },
    ],
    [tokenId, amount0Min, amount1Min, "0x"],
  );

  const actions =
    `0x${BURN_POSITION_ACTION.toString(16).padStart(2, "0")}` as `0x${string}`;
  return encodeAbiParameters(
    [
      { type: "bytes", name: "actions" },
      { type: "bytes[]", name: "params" },
    ],
    [actions, [burnParam]],
  ) as `0x${string}`;
}

// ---------------------------------------------------------------------------
// FROM_DELTAS variants — auto-settle using PM's internal delta balances
// ---------------------------------------------------------------------------

function packActions(...ids: number[]): `0x${string}` {
  return ("0x" +
    ids.map((a) => a.toString(16).padStart(2, "0")).join("")) as `0x${string}`;
}

/**
 * Encode unlockData for MINT_POSITION_FROM_DELTAS + SETTLE_PAIR.
 * The PositionManager resolves the exact token amounts from its internal deltas
 * rather than requiring explicit amount0Max/amount1Max.
 */
export function encodeUnlockDataMintFromDeltas(
  poolKey: PoolKey,
  tickLower: number,
  tickUpper: number,
  liquidity: bigint,
  amount0Max: bigint,
  amount1Max: bigint,
  owner: Address,
): `0x${string}` {
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

  // SETTLE_PAIR param = abi.encode(currency0, currency1)
  const settlePairParam = encodeAbiParameters(
    [
      { type: "address", name: "currency0" },
      { type: "address", name: "currency1" },
    ],
    [poolKey.currency0, poolKey.currency1],
  );

  const actions = packActions(MINT_POSITION_FROM_DELTAS_ACTION, PM_SETTLE_PAIR);

  return encodeAbiParameters(
    [
      { type: "bytes", name: "actions" },
      { type: "bytes[]", name: "params" },
    ],
    [actions, [mintParam, settlePairParam]],
  ) as `0x${string}`;
}

/**
 * Encode unlockData for INCREASE_LIQUIDITY_FROM_DELTAS + SETTLE_PAIR.
 * Adds liquidity to an existing position using PM delta resolution.
 */
export function encodeUnlockDataIncreaseFromDeltas(
  tokenId: bigint,
  liquidity: bigint,
  amount0Max: bigint,
  amount1Max: bigint,
  currency0: Address,
  currency1: Address,
): `0x${string}` {
  const increaseParam = encodeAbiParameters(
    [
      { type: "uint256", name: "tokenId" },
      { type: "uint256", name: "liquidity" },
      { type: "uint128", name: "amount0Max" },
      { type: "uint128", name: "amount1Max" },
      { type: "bytes", name: "hookData" },
    ],
    [tokenId, liquidity, amount0Max, amount1Max, "0x"],
  );

  const settlePairParam = encodeAbiParameters(
    [
      { type: "address", name: "currency0" },
      { type: "address", name: "currency1" },
    ],
    [currency0, currency1],
  );

  const actions = packActions(
    INCREASE_LIQUIDITY_FROM_DELTAS_ACTION,
    PM_SETTLE_PAIR,
  );

  return encodeAbiParameters(
    [
      { type: "bytes", name: "actions" },
      { type: "bytes[]", name: "params" },
    ],
    [actions, [increaseParam, settlePairParam]],
  ) as `0x${string}`;
}

/**
 * Encode unlockData for MINT_POSITION_FROM_DELTAS + CLOSE_CURRENCY (for each currency).
 * CLOSE_CURRENCY settles any remaining debt and takes any remaining credits.
 */
export function encodeUnlockDataMintFromDeltasWithClose(
  poolKey: PoolKey,
  tickLower: number,
  tickUpper: number,
  liquidity: bigint,
  amount0Max: bigint,
  amount1Max: bigint,
  owner: Address,
): `0x${string}` {
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

  // CLOSE_CURRENCY takes a single currency address
  const close0Param = encodeAbiParameters(
    [{ type: "address", name: "currency" }],
    [poolKey.currency0],
  );
  const close1Param = encodeAbiParameters(
    [{ type: "address", name: "currency" }],
    [poolKey.currency1],
  );

  const actions = packActions(
    MINT_POSITION_FROM_DELTAS_ACTION,
    PM_CLOSE_CURRENCY,
    PM_CLOSE_CURRENCY,
  );

  return encodeAbiParameters(
    [
      { type: "bytes", name: "actions" },
      { type: "bytes[]", name: "params" },
    ],
    [actions, [mintParam, close0Param, close1Param]],
  ) as `0x${string}`;
}
