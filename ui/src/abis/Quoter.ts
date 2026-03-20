import type { Abi } from "viem";

// V4Quoter ABI for quoteExactInputSingle / quoteExactOutputSingle (returns values, matches Uniswap v4)
// Also includes quoteExactInput / quoteExactOutput for multi-hop, and QuoteSwap error for fallback decoding
// Matches hieroforge-periphery V4Quoter.sol and QuoterRevert.sol

const poolKeyComponents = [
  { name: "currency0", type: "address", internalType: "address" },
  { name: "currency1", type: "address", internalType: "address" },
  { name: "fee", type: "uint24", internalType: "uint24" },
  { name: "tickSpacing", type: "int24", internalType: "int24" },
  { name: "hooks", type: "address", internalType: "address" },
];

const quoteExactSingleParamsComponents = [
  {
    name: "poolKey",
    type: "tuple" as const,
    internalType: "struct IV4Quoter.QuoteExactSingleParams",
    components: poolKeyComponents,
  },
  { name: "zeroForOne", type: "bool" as const, internalType: "bool" },
  { name: "exactAmount", type: "uint128" as const, internalType: "uint128" },
  { name: "hookData", type: "bytes" as const, internalType: "bytes" },
];

const pathKeyComponents = [
  { name: "intermediateCurrency", type: "address", internalType: "Currency" },
  { name: "fee", type: "uint24", internalType: "uint24" },
  { name: "tickSpacing", type: "int24", internalType: "int24" },
  { name: "hooks", type: "address", internalType: "address" },
  { name: "hookData", type: "bytes", internalType: "bytes" },
];

const quoteExactParamsComponents = [
  { name: "exactCurrency", type: "address" as const, internalType: "Currency" },
  {
    name: "path",
    type: "tuple[]" as const,
    internalType: "struct PathKey[]",
    components: pathKeyComponents,
  },
  { name: "exactAmount", type: "uint128" as const, internalType: "uint128" },
];

export const QuoterAbi: Abi = [
  // Single-hop: returns (amountOut, gasEstimate) or (amountIn, gasEstimate)
  {
    type: "function",
    name: "quoteExactInputSingle",
    inputs: [
      {
        name: "params",
        type: "tuple",
        internalType: "struct IV4Quoter.QuoteExactSingleParams",
        components: quoteExactSingleParamsComponents,
      },
    ],
    outputs: [
      { name: "amountOut", type: "uint256", internalType: "uint256" },
      { name: "gasEstimate", type: "uint256", internalType: "uint256" },
    ],
    stateMutability: "nonpayable",
  },
  {
    type: "function",
    name: "quoteExactOutputSingle",
    inputs: [
      {
        name: "params",
        type: "tuple",
        internalType: "struct IV4Quoter.QuoteExactSingleParams",
        components: quoteExactSingleParamsComponents,
      },
    ],
    outputs: [
      { name: "amountIn", type: "uint256", internalType: "uint256" },
      { name: "gasEstimate", type: "uint256", internalType: "uint256" },
    ],
    stateMutability: "nonpayable",
  },
  // Multi-hop
  {
    type: "function",
    name: "quoteExactInput",
    inputs: [
      {
        name: "params",
        type: "tuple",
        internalType: "struct IV4Quoter.QuoteExactParams",
        components: quoteExactParamsComponents,
      },
    ],
    outputs: [
      { name: "amountOut", type: "uint256", internalType: "uint256" },
      { name: "gasEstimate", type: "uint256", internalType: "uint256" },
    ],
    stateMutability: "nonpayable",
  },
  {
    type: "function",
    name: "quoteExactOutput",
    inputs: [
      {
        name: "params",
        type: "tuple",
        internalType: "struct IV4Quoter.QuoteExactParams",
        components: quoteExactParamsComponents,
      },
    ],
    outputs: [
      { name: "amountIn", type: "uint256", internalType: "uint256" },
      { name: "gasEstimate", type: "uint256", internalType: "uint256" },
    ],
    stateMutability: "nonpayable",
  },
  // Error for fallback parsing (if Hedera relay returns revert data instead of clean return)
  {
    type: "error",
    name: "QuoteSwap",
    inputs: [{ name: "amount", type: "uint256", internalType: "uint256" }],
  },
];

export interface PoolKeyForQuote {
  currency0: string;
  currency1: string;
  fee: number;
  tickSpacing: number;
  /**
   * v4 pool hooks contract address.
   * If omitted, quote code falls back to 0x0 (no hooks).
   */
  hooks?: string;
}
