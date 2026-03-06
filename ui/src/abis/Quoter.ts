import type { Abi } from 'viem'

// Quoter ABI for quoteExactInputSingle / quoteExactOutputSingle and QuoteSwap error decoding
// Matches hieroforge-periphery Quoter.sol and QuoterRevert.sol

const poolKeyComponents = [
  { name: 'currency0', type: 'address', internalType: 'address' },
  { name: 'currency1', type: 'address', internalType: 'address' },
  { name: 'fee', type: 'uint24', internalType: 'uint24' },
  { name: 'tickSpacing', type: 'int24', internalType: 'int24' },
  { name: 'hooks', type: 'address', internalType: 'address' },
]

const quoteParamsComponents = [
  { name: 'poolKey', type: 'tuple' as const, internalType: 'struct IQuoter.QuoteExactSingleParams', components: poolKeyComponents },
  { name: 'zeroForOne', type: 'bool' as const, internalType: 'bool' },
  { name: 'exactAmount', type: 'uint128' as const, internalType: 'uint128' },
  { name: 'hookData', type: 'bytes' as const, internalType: 'bytes' },
]

export const QuoterAbi: Abi = [
  {
    type: 'function',
    name: 'quoteExactInputSingle',
    inputs: [{ name: 'params', type: 'tuple', internalType: 'struct IQuoter.QuoteExactSingleParams', components: quoteParamsComponents }],
    outputs: [],
    stateMutability: 'nonpayable',
  },
  {
    type: 'function',
    name: 'quoteExactOutputSingle',
    inputs: [{ name: 'params', type: 'tuple', internalType: 'struct IQuoter.QuoteExactSingleParams', components: quoteParamsComponents }],
    outputs: [],
    stateMutability: 'nonpayable',
  },
  {
    type: 'error',
    name: 'QuoteSwap',
    inputs: [{ name: 'amount', type: 'uint256', internalType: 'uint256' }],
  },
]

export interface PoolKeyForQuote {
  currency0: string
  currency1: string
  fee: number
  tickSpacing: number
}
