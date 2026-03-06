import type { Abi } from 'viem'

// Minimal ABI for PoolManager: initialize pool and read state
export const PoolManagerAbi = [
  {
    type: 'function',
    name: 'initialize',
    inputs: [
      {
        name: 'key',
        type: 'tuple',
        internalType: 'struct PoolKey',
        components: [
          { name: 'currency0', type: 'address', internalType: 'Currency' },
          { name: 'currency1', type: 'address', internalType: 'Currency' },
          { name: 'fee', type: 'uint24', internalType: 'uint24' },
          { name: 'tickSpacing', type: 'int24', internalType: 'int24' },
          { name: 'hooks', type: 'address', internalType: 'address' },
        ],
      },
      { name: 'sqrtPriceX96', type: 'uint256', internalType: 'uint160' },
    ],
    outputs: [{ name: 'tick', type: 'int24', internalType: 'int24' }],
    stateMutability: 'nonpayable',
  },
  {
    type: 'function',
    name: 'getPoolState',
    inputs: [{ name: 'id', type: 'bytes32', internalType: 'PoolId' }],
    outputs: [
      { name: 'initialized', type: 'bool', internalType: 'bool' },
      { name: 'sqrtPriceX96', type: 'uint256', internalType: 'uint160' },
      { name: 'tick', type: 'int24', internalType: 'int24' },
    ],
    stateMutability: 'view',
  },
] as Abi

// sqrtPriceX96 presets (Q64.96): token1 per token0
// From Constants.sol: 1:1, 1:2, 1:4, 2:1, 4:1
export const SQRT_PRICE_PRESETS: Record<string, string> = {
  '0.25': '39614081257132168796771975168',   // 1:4
  '0.5': '56022770974786139918731938227',    // 1:2
  '1': '79228162514264337593543950336',      // 1:1
  '2': '112045541949572279837463876454',     // 2:1
  '4': '158456325028528675187087900672',     // 4:1
}
