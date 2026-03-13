import { encodeAbiParameters, getAddress, type Address } from "viem";
import { Actions, Commands } from "../abis/UniversalRouter";

const HOOKS_ZERO = "0x0000000000000000000000000000000000000000" as Address;

export interface SwapPoolKey {
  currency0: Address;
  currency1: Address;
  fee: number;
  tickSpacing: number;
  hooks: Address;
}

/**
 * Build a canonical PoolKey (currency0 < currency1).
 */
export function buildSwapPoolKey(
  tokenA: string,
  tokenB: string,
  fee: number,
  tickSpacing: number,
): SwapPoolKey {
  const a = getAddress(tokenA);
  const b = getAddress(tokenB);
  const currency0 = a.toLowerCase() < b.toLowerCase() ? a : b;
  const currency1 = a.toLowerCase() < b.toLowerCase() ? b : a;
  return { currency0, currency1, fee, tickSpacing, hooks: HOOKS_ZERO };
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

const EXACT_INPUT_SINGLE_PARAMS = [
  POOL_KEY_TUPLE,
  { type: "bool" as const, name: "zeroForOne" },
  { type: "uint128" as const, name: "amountIn" },
  { type: "uint128" as const, name: "amountOutMinimum" },
  { type: "bytes" as const, name: "hookData" },
];

/**
 * Encode the full calldata for UniversalRouter.execute() to perform an exact-input single-hop swap.
 *
 * Encoding layers (matches V4RouterSwapTest.sol):
 * 1. commands = abi.encodePacked(uint8(V4_SWAP))  →  0x10
 * 2. inputs[0] = abi.encode(actions, params)
 *    - actions = abi.encodePacked(SWAP_EXACT_IN_SINGLE, SETTLE_ALL, TAKE_ALL)  →  0x060c0f
 *    - params[0] = abi.encode(ExactInputSingleParams)
 *    - params[1] = abi.encode(currencyIn, amountIn)
 *    - params[2] = abi.encode(currencyOut, amountOutMinimum)
 */
export function encodeSwapExactInSingle(params: {
  poolKey: SwapPoolKey;
  zeroForOne: boolean;
  amountIn: bigint;
  amountOutMinimum: bigint;
}): { commands: `0x${string}`; inputs: `0x${string}`[] } {
  const { poolKey, zeroForOne, amountIn, amountOutMinimum } = params;

  // Currency being sold (settled) and bought (taken)
  const currencyIn = zeroForOne ? poolKey.currency0 : poolKey.currency1;
  const currencyOut = zeroForOne ? poolKey.currency1 : poolKey.currency0;

  // actions = packed bytes [0x06, 0x0c, 0x0f]
  const actions = ("0x" +
    Actions.SWAP_EXACT_IN_SINGLE.toString(16).padStart(2, "0") +
    Actions.SETTLE_ALL.toString(16).padStart(2, "0") +
    Actions.TAKE_ALL.toString(16).padStart(2, "0")) as `0x${string}`;

  // params[0] = abi.encode(ExactInputSingleParams)
  const swapParam = encodeAbiParameters(EXACT_INPUT_SINGLE_PARAMS, [
    poolKey,
    zeroForOne,
    amountIn,
    amountOutMinimum,
    "0x", // hookData
  ]);

  // params[1] = abi.encode(currency, maxAmount) for SETTLE_ALL
  const settleParam = encodeAbiParameters(
    [
      { type: "address", name: "currency" },
      { type: "uint256", name: "maxAmount" },
    ],
    [currencyIn, amountIn],
  );

  // params[2] = abi.encode(currency, minAmount) for TAKE_ALL
  const takeParam = encodeAbiParameters(
    [
      { type: "address", name: "currency" },
      { type: "uint256", name: "minAmount" },
    ],
    [currencyOut, amountOutMinimum],
  );

  // inputs[0] = abi.encode(bytes actions, bytes[] params)
  const input0 = encodeAbiParameters(
    [
      { type: "bytes", name: "actions" },
      { type: "bytes[]", name: "params" },
    ],
    [actions, [swapParam, settleParam, takeParam]],
  );

  // commands = single byte V4_SWAP
  const commands = ("0x" +
    Commands.V4_SWAP.toString(16).padStart(2, "0")) as `0x${string}`;

  return { commands, inputs: [input0] };
}
