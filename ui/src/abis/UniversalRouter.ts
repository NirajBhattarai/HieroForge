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
} as const;

/** Action constants from Actions.sol */
export const Actions = {
  SWAP_EXACT_IN_SINGLE: 0x06,
  SWAP_EXACT_OUT_SINGLE: 0x08,
  SETTLE_ALL: 0x0c,
  TAKE_ALL: 0x0f,
} as const;
