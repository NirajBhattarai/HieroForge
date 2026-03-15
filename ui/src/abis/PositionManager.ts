import type { Abi } from "viem";

// PoolKey: (address currency0, address currency1, uint24 fee, int24 tickSpacing, address hooks)
export const PoolKeyAbi = [
  { name: "currency0", type: "address", internalType: "address" },
  { name: "currency1", type: "address", internalType: "address" },
  { name: "fee", type: "uint24", internalType: "uint24" },
  { name: "tickSpacing", type: "int24", internalType: "int24" },
  { name: "hooks", type: "address", internalType: "address" },
] as const;

export const PositionManagerAbi = [
  {
    type: "function",
    name: "multicall",
    inputs: [{ name: "data", type: "bytes[]", internalType: "bytes[]" }],
    outputs: [{ name: "results", type: "bytes[]", internalType: "bytes[]" }],
    stateMutability: "payable",
  },
  {
    type: "function",
    name: "initializePool",
    inputs: [
      {
        name: "key",
        type: "tuple",
        internalType: "struct PoolKey",
        components: [
          { name: "currency0", type: "address", internalType: "address" },
          { name: "currency1", type: "address", internalType: "address" },
          { name: "fee", type: "uint24", internalType: "uint24" },
          { name: "tickSpacing", type: "int24", internalType: "int24" },
          { name: "hooks", type: "address", internalType: "address" },
        ],
      },
      { name: "sqrtPriceX96", type: "uint160", internalType: "uint160" },
    ],
    outputs: [{ name: "", type: "int24", internalType: "int24" }],
    stateMutability: "payable",
  },
  {
    type: "function",
    name: "modifyLiquidities",
    inputs: [
      { name: "unlockData", type: "bytes", internalType: "bytes" },
      { name: "deadline", type: "uint256", internalType: "uint256" },
    ],
    outputs: [],
    stateMutability: "payable",
  },
  {
    type: "function",
    name: "nextTokenId",
    inputs: [],
    outputs: [{ name: "", type: "uint256", internalType: "uint256" }],
    stateMutability: "view",
  },
  {
    type: "function",
    name: "positionLiquidity",
    inputs: [{ name: "tokenId", type: "uint256", internalType: "uint256" }],
    outputs: [{ name: "", type: "uint128", internalType: "uint128" }],
    stateMutability: "view",
  },
] as Abi;

// V4 PositionManager action bytes
export const INCREASE_LIQUIDITY_ACTION = 0x00;
export const DECREASE_LIQUIDITY_ACTION = 0x01;
export const MINT_POSITION_ACTION = 0x02;
export const BURN_POSITION_ACTION = 0x03;
export const INCREASE_LIQUIDITY_FROM_DELTAS_ACTION = 0x04;
export const MINT_POSITION_FROM_DELTAS_ACTION = 0x05;

// Settlement actions (also usable inside PositionManager action chains)
export const PM_SETTLE = 0x0b;
export const PM_SETTLE_PAIR = 0x0d;
export const PM_TAKE_PAIR = 0x11;
export const PM_CLOSE_CURRENCY = 0x12;

// sqrtPriceX96 for 1:1 (Q64.96)
export const SQRT_PRICE_1_1 = 79228162514264337593543950336n;
