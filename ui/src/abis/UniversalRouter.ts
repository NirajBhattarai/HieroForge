import type { Abi } from "viem";

/**
 * UniversalRouter ABI — only the execute() function needed for swaps.
 * Solidity: function execute(bytes calldata commands, bytes[] calldata inputs, uint256 deadline) external payable
 */
export const UniversalRouterAbi = [
  {
    type: "function",
    name: "execute",
    inputs: [
      { name: "commands", type: "bytes", internalType: "bytes" },
      { name: "inputs", type: "bytes[]", internalType: "bytes[]" },
      { name: "deadline", type: "uint256", internalType: "uint256" },
    ],
    outputs: [],
    stateMutability: "payable",
  },
] as Abi;

/** Command constants from Commands.sol */
export const Commands = {
  V4_SWAP: 0x10,
  V4_POSITION_CALL: 0x11,
  SWEEP: 0x12,
} as const;

/** Action constants from Actions.sol */
export const Actions = {
  // Liquidity
  INCREASE_LIQUIDITY: 0x00,
  DECREASE_LIQUIDITY: 0x01,
  MINT_POSITION: 0x02,
  BURN_POSITION: 0x03,
  INCREASE_LIQUIDITY_FROM_DELTAS: 0x04,
  MINT_POSITION_FROM_DELTAS: 0x05,
  // Swapping
  SWAP_EXACT_IN_SINGLE: 0x06,
  SWAP_EXACT_IN: 0x07,
  SWAP_EXACT_OUT_SINGLE: 0x08,
  SWAP_EXACT_OUT: 0x09,
  // Settlement
  SETTLE: 0x0b,
  SETTLE_ALL: 0x0c,
  SETTLE_PAIR: 0x0d,
  TAKE: 0x0e,
  TAKE_ALL: 0x0f,
  TAKE_PORTION: 0x10,
  TAKE_PAIR: 0x11,
  CLOSE_CURRENCY: 0x12,
  CLEAR_OR_TAKE: 0x13,
  SWEEP: 0x14,
} as const;
