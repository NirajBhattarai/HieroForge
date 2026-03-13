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
] as Abi;

// MINT_POSITION action byte
export const MINT_POSITION_ACTION = 0x02;

// sqrtPriceX96 for 1:1 (Q64.96)
export const SQRT_PRICE_1_1 = 79228162514264337593543950336n;
