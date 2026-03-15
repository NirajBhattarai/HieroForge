import { encodeAbiParameters, getAddress, type Address } from "viem";
import { Actions, Commands } from "../abis/UniversalRouter";

import { HOOKS_ZERO } from "@/constants";

export interface SwapPoolKey {
  currency0: Address;
  currency1: Address;
  fee: number;
  tickSpacing: number;
  hooks: Address;
}

/** A single leg of a multi-hop path (matches PathKey.sol). */
export interface PathKey {
  intermediateCurrency: Address;
  fee: number;
  tickSpacing: number;
  hooks: Address;
  hookData: `0x${string}`;
}

/**
 * Build a canonical PoolKey (currency0 < currency1).
 */
export function buildSwapPoolKey(
  tokenA: string,
  tokenB: string,
  fee: number,
  tickSpacing: number,
  hooks: string = HOOKS_ZERO,
): SwapPoolKey {
  const a = getAddress(tokenA);
  const b = getAddress(tokenB);
  const currency0 = a.toLowerCase() < b.toLowerCase() ? a : b;
  const currency1 = a.toLowerCase() < b.toLowerCase() ? b : a;
  return {
    currency0,
    currency1,
    fee,
    tickSpacing,
    hooks: getAddress(hooks) as Address,
  };
}

/**
 * Build a PathKey[] for a multi-hop route through intermediate tokens.
 * route = [tokenIn, tokenMid1, tokenMid2, ..., tokenOut]
 * fees/tickSpacings = one per hop (length = route.length - 1)
 */
export function buildPath(
  route: string[],
  fees: number[],
  tickSpacings: number[],
  hooks: string[] = [],
): PathKey[] {
  const path: PathKey[] = [];
  for (let i = 1; i < route.length; i++) {
    path.push({
      intermediateCurrency: getAddress(route[i]!) as Address,
      fee: fees[i - 1]!,
      tickSpacing: tickSpacings[i - 1]!,
      hooks: (hooks[i - 1] ? getAddress(hooks[i - 1]) : HOOKS_ZERO) as Address,
      hookData: "0x",
    });
  }
  return path;
}

// ABI types for encoding
const POOL_KEY_TUPLE = {
  type: "tuple" as const,
  components: [
    { type: "address" as const, name: "currency0" },
    { type: "address" as const, name: "currency1" },
    { type: "uint24" as const, name: "fee" },
    { type: "int24" as const, name: "tickSpacing" },
    { type: "address" as const, name: "hooks" },
  ],
  name: "poolKey",
};

const PATH_KEY_TUPLE = {
  type: "tuple[]" as const,
  components: [
    { type: "address" as const, name: "intermediateCurrency" },
    { type: "uint24" as const, name: "fee" },
    { type: "int24" as const, name: "tickSpacing" },
    { type: "address" as const, name: "hooks" },
    { type: "bytes" as const, name: "hookData" },
  ],
  name: "path",
};

const EXACT_INPUT_SINGLE_PARAMS = [
  {
    type: "tuple" as const,
    components: [
      POOL_KEY_TUPLE,
      { type: "bool" as const, name: "zeroForOne" },
      { type: "uint128" as const, name: "amountIn" },
      { type: "uint128" as const, name: "amountOutMinimum" },
      { type: "bytes" as const, name: "hookData" },
    ],
  },
];

const EXACT_OUTPUT_SINGLE_PARAMS = [
  {
    type: "tuple" as const,
    components: [
      POOL_KEY_TUPLE,
      { type: "bool" as const, name: "zeroForOne" },
      { type: "uint128" as const, name: "amountOut" },
      { type: "uint128" as const, name: "amountInMaximum" },
      { type: "bytes" as const, name: "hookData" },
    ],
  },
];

const EXACT_INPUT_PARAMS = [
  {
    type: "tuple" as const,
    components: [
      { type: "address" as const, name: "currencyIn" },
      PATH_KEY_TUPLE,
      { type: "uint128" as const, name: "amountIn" },
      { type: "uint128" as const, name: "amountOutMinimum" },
    ],
  },
];

const EXACT_OUTPUT_PARAMS = [
  {
    type: "tuple" as const,
    components: [
      { type: "address" as const, name: "currencyOut" },
      PATH_KEY_TUPLE,
      { type: "uint128" as const, name: "amountOut" },
      { type: "uint128" as const, name: "amountInMaximum" },
    ],
  },
];

// --- Helper to pack action bytes ---
function packActions(...actionIds: number[]): `0x${string}` {
  return ("0x" +
    actionIds
      .map((a) => a.toString(16).padStart(2, "0"))
      .join("")) as `0x${string}`;
}

function wrapV4Swap(
  actions: `0x${string}`,
  params: `0x${string}`[],
): { commands: `0x${string}`; inputs: `0x${string}`[] } {
  const input0 = encodeAbiParameters(
    [
      { type: "bytes", name: "actions" },
      { type: "bytes[]", name: "params" },
    ],
    [actions, params],
  );
  const commands = ("0x" +
    Commands.V4_SWAP.toString(16).padStart(2, "0")) as `0x${string}`;
  return { commands, inputs: [input0] };
}

// --- Settlement param encoders ---
function encodeSettleAll(currency: Address, maxAmount: bigint): `0x${string}` {
  return encodeAbiParameters(
    [
      { type: "address", name: "currency" },
      { type: "uint256", name: "maxAmount" },
    ],
    [currency, maxAmount],
  );
}

function encodeTakeAll(currency: Address, minAmount: bigint): `0x${string}` {
  return encodeAbiParameters(
    [
      { type: "address", name: "currency" },
      { type: "uint256", name: "minAmount" },
    ],
    [currency, minAmount],
  );
}

function encodeSettlePair(
  currency0: Address,
  currency1: Address,
): `0x${string}` {
  return encodeAbiParameters(
    [
      { type: "address", name: "currency0" },
      { type: "address", name: "currency1" },
    ],
    [currency0, currency1],
  );
}

function encodeTakePair(currency0: Address, currency1: Address): `0x${string}` {
  return encodeAbiParameters(
    [
      { type: "address", name: "currency0" },
      { type: "address", name: "currency1" },
    ],
    [currency0, currency1],
  );
}

/**
 * Encode exact-input single-hop swap for UniversalRouter.execute().
 * Uses SETTLE_ALL + TAKE_ALL settlement.
 */
export function encodeSwapExactInSingle(params: {
  poolKey: SwapPoolKey;
  zeroForOne: boolean;
  amountIn: bigint;
  amountOutMinimum: bigint;
}): { commands: `0x${string}`; inputs: `0x${string}`[] } {
  const { poolKey, zeroForOne, amountIn, amountOutMinimum } = params;

  const currencyIn = zeroForOne ? poolKey.currency0 : poolKey.currency1;
  const currencyOut = zeroForOne ? poolKey.currency1 : poolKey.currency0;

  const actions = packActions(
    Actions.SWAP_EXACT_IN_SINGLE,
    Actions.SETTLE_ALL,
    Actions.TAKE_ALL,
  );

  const swapParam = encodeAbiParameters(EXACT_INPUT_SINGLE_PARAMS, [
    {
      poolKey,
      zeroForOne,
      amountIn,
      amountOutMinimum,
      hookData: "0x",
    },
  ]);
  const settleParam = encodeSettleAll(currencyIn, amountIn);
  const takeParam = encodeTakeAll(currencyOut, amountOutMinimum);

  return wrapV4Swap(actions, [swapParam, settleParam, takeParam]);
}

/**
 * Encode exact-output single-hop swap for UniversalRouter.execute().
 * Uses SETTLE_ALL + TAKE_ALL settlement.
 */
export function encodeSwapExactOutSingle(params: {
  poolKey: SwapPoolKey;
  zeroForOne: boolean;
  amountOut: bigint;
  amountInMaximum: bigint;
}): { commands: `0x${string}`; inputs: `0x${string}`[] } {
  const { poolKey, zeroForOne, amountOut, amountInMaximum } = params;

  const currencyIn = zeroForOne ? poolKey.currency0 : poolKey.currency1;
  const currencyOut = zeroForOne ? poolKey.currency1 : poolKey.currency0;

  const actions = packActions(
    Actions.SWAP_EXACT_OUT_SINGLE,
    Actions.SETTLE_ALL,
    Actions.TAKE_ALL,
  );

  const swapParam = encodeAbiParameters(EXACT_OUTPUT_SINGLE_PARAMS, [
    {
      poolKey,
      zeroForOne,
      amountOut,
      amountInMaximum,
      hookData: "0x",
    },
  ]);
  const settleParam = encodeSettleAll(currencyIn, amountInMaximum);
  const takeParam = encodeTakeAll(currencyOut, amountOut);

  return wrapV4Swap(actions, [swapParam, settleParam, takeParam]);
}

/**
 * Encode exact-input multi-hop swap for UniversalRouter.execute().
 * Uses SETTLE_ALL + TAKE_ALL settlement.
 *
 * @param currencyIn - the starting token address
 * @param path - PathKey[] describing intermediate hops
 * @param amountIn - exact amount to spend
 * @param amountOutMinimum - minimum output after all hops
 */
export function encodeSwapExactIn(params: {
  currencyIn: Address;
  path: PathKey[];
  amountIn: bigint;
  amountOutMinimum: bigint;
}): { commands: `0x${string}`; inputs: `0x${string}`[] } {
  const { currencyIn, path, amountIn, amountOutMinimum } = params;

  // The output currency is the last pathKey's intermediateCurrency
  const currencyOut = path[path.length - 1]!.intermediateCurrency;

  const actions = packActions(
    Actions.SWAP_EXACT_IN,
    Actions.SETTLE_ALL,
    Actions.TAKE_ALL,
  );

  const swapParam = encodeAbiParameters(EXACT_INPUT_PARAMS, [
    {
      currencyIn,
      path: path.map((p) => ({
        intermediateCurrency: p.intermediateCurrency,
        fee: p.fee,
        tickSpacing: p.tickSpacing,
        hooks: p.hooks,
        hookData: p.hookData,
      })),
      amountIn,
      amountOutMinimum,
    },
  ]);
  const settleParam = encodeSettleAll(currencyIn, amountIn);
  const takeParam = encodeTakeAll(currencyOut, amountOutMinimum);

  return wrapV4Swap(actions, [swapParam, settleParam, takeParam]);
}

/**
 * Encode exact-output multi-hop swap for UniversalRouter.execute().
 * Uses SETTLE_ALL + TAKE_ALL settlement.
 *
 * @param currencyOut - the desired output token address
 * @param path - PathKey[] describing intermediate hops (reversed from exact-in)
 * @param amountOut - exact amount desired
 * @param amountInMaximum - maximum amount willing to spend
 */
export function encodeSwapExactOut(params: {
  currencyOut: Address;
  path: PathKey[];
  amountOut: bigint;
  amountInMaximum: bigint;
}): { commands: `0x${string}`; inputs: `0x${string}`[] } {
  const { currencyOut, path, amountOut, amountInMaximum } = params;

  // The input currency is the last pathKey's intermediateCurrency (reversed path)
  const currencyIn = path[path.length - 1]!.intermediateCurrency;

  const actions = packActions(
    Actions.SWAP_EXACT_OUT,
    Actions.SETTLE_ALL,
    Actions.TAKE_ALL,
  );

  const swapParam = encodeAbiParameters(EXACT_OUTPUT_PARAMS, [
    {
      currencyOut,
      path: path.map((p) => ({
        intermediateCurrency: p.intermediateCurrency,
        fee: p.fee,
        tickSpacing: p.tickSpacing,
        hooks: p.hooks,
        hookData: p.hookData,
      })),
      amountOut,
      amountInMaximum,
    },
  ]);
  const settleParam = encodeSettleAll(currencyIn, amountInMaximum);
  const takeParam = encodeTakeAll(currencyOut, amountOut);

  return wrapV4Swap(actions, [swapParam, settleParam, takeParam]);
}

/** Re-export for components. */
export { encodeSettlePair, encodeTakePair };
