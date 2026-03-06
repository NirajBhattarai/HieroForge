import { encodeFunctionData, decodeErrorResult, type PublicClient } from 'viem'
import { QuoterAbi, type PoolKeyForQuote } from '../abis/Quoter'

const ZERO_ADDRESS = '0x0000000000000000000000000000000000000000' as const

/** Revert selector for NotEnoughLiquidity(bytes32) from BaseQuoter.sol */
const NOT_ENOUGH_LIQUIDITY_SELECTOR = '0x7a5ed734'

export class NotEnoughLiquidityError extends Error {
  readonly code = 'NOT_ENOUGH_LIQUIDITY' as const
  constructor() {
    super('Not enough liquidity in the pool for this amount. Try a smaller amount or add liquidity.')
    this.name = 'NotEnoughLiquidityError'
  }
}

export interface QuoteParams {
  poolKey: PoolKeyForQuote & { hooks: string }
  zeroForOne: boolean
  exactAmount: bigint
  hookData: `0x${string}`
}

/**
 * Build params for Quoter.quoteExactInputSingle / quoteExactOutputSingle.
 */
export function quoteParams(poolKey: PoolKeyForQuote, zeroForOne: boolean, exactAmount: bigint): QuoteParams {
  return {
    poolKey: {
      currency0: poolKey.currency0,
      currency1: poolKey.currency1,
      fee: poolKey.fee,
      tickSpacing: poolKey.tickSpacing,
      hooks: ZERO_ADDRESS,
    },
    zeroForOne,
    exactAmount,
    hookData: '0x',
  }
}

/**
 * Extract revert data hex from a viem/contract error (may be nested).
 */
function getRevertDataHex(err: unknown): string | null {
  let e: unknown = err
  for (let i = 0; i < 5 && e; i++) {
    const obj = e as { data?: unknown; details?: unknown; cause?: unknown }
    const data = obj?.data ?? obj?.details
    if (data != null) {
      const hex = typeof data === 'string' ? data : (data as { toString?: () => string })?.toString?.()
      if (hex && typeof hex === 'string' && hex.startsWith('0x')) return hex
    }
    e = obj?.cause
  }
  return null
}

/**
 * Parse QuoteSwap(uint256) from revert data. Returns the amount or null if not QuoteSwap.
 */
export function parseQuoteSwapRevert(data: string | null): bigint | null {
  if (!data || typeof data !== 'string' || !data.startsWith('0x') || data.length < 2 + 8 + 64) return null
  try {
    const decoded = decodeErrorResult({ abi: QuoterAbi, data: data as `0x${string}` })
    if (decoded?.errorName === 'QuoteSwap' && decoded?.args?.length) return decoded.args[0] as bigint
  } catch {
    return null
  }
  return null
}

/**
 * Quote exact input: get amountOut for a given amountIn.
 * Calls quoter via eth_call; the contract reverts with QuoteSwap(amountOut) on success.
 * Handles both: (1) RPC returns error with revert data, (2) RPC returns 200 with revert data in result (e.g. Hedera Hashio).
 */
export async function quoteExactInputSingle(
  publicClient: PublicClient,
  quoterAddress: `0x${string}`,
  poolKey: PoolKeyForQuote,
  zeroForOne: boolean,
  amountIn: bigint
): Promise<bigint> {
  const params = quoteParams(poolKey, zeroForOne, amountIn)
  const calldata = encodeFunctionData({
    abi: QuoterAbi,
    functionName: 'quoteExactInputSingle',
    args: [params],
  })
  try {
    const result = await publicClient.call({
      to: quoterAddress,
      data: calldata,
    })
    // Some relays (e.g. Hedera Hashio) return 200 with revert data in result; parse QuoteSwap from it
    const raw = result as unknown
    const resultHex =
      typeof raw === 'string' && raw.startsWith('0x')
        ? raw
        : typeof (raw as { data?: string })?.data === 'string'
          ? (raw as { data: string }).data
          : null
    const amount = parseQuoteSwapRevert(resultHex)
    if (amount !== null) return amount
    if (resultHex?.startsWith(NOT_ENOUGH_LIQUIDITY_SELECTOR)) throw new NotEnoughLiquidityError()
  } catch (err: unknown) {
    if (err instanceof NotEnoughLiquidityError) throw err
    const hex = getRevertDataHex(err)
    const amount = parseQuoteSwapRevert(hex)
    if (amount !== null) return amount
    if (hex?.startsWith(NOT_ENOUGH_LIQUIDITY_SELECTOR)) throw new NotEnoughLiquidityError()
    throw err
  }
  throw new Error('Quoter did not revert with QuoteSwap')
}

/**
 * Quote exact output: get amountIn for a given amountOut.
 * Same revert handling as quoteExactInputSingle (error or result data).
 */
export async function quoteExactOutputSingle(
  publicClient: PublicClient,
  quoterAddress: `0x${string}`,
  poolKey: PoolKeyForQuote,
  zeroForOne: boolean,
  amountOut: bigint
): Promise<bigint> {
  const params = quoteParams(poolKey, zeroForOne, amountOut)
  const calldata = encodeFunctionData({
    abi: QuoterAbi,
    functionName: 'quoteExactOutputSingle',
    args: [params],
  })
  try {
    const result = await publicClient.call({
      to: quoterAddress,
      data: calldata,
    })
    const raw = result as unknown
    const resultHex =
      typeof raw === 'string' && raw.startsWith('0x')
        ? raw
        : typeof (raw as { data?: string })?.data === 'string'
          ? (raw as { data: string }).data
          : null
    const amount = parseQuoteSwapRevert(resultHex)
    if (amount !== null) return amount
    if (resultHex?.startsWith(NOT_ENOUGH_LIQUIDITY_SELECTOR)) throw new NotEnoughLiquidityError()
  } catch (err: unknown) {
    if (err instanceof NotEnoughLiquidityError) throw err
    const hex = getRevertDataHex(err)
    const amount = parseQuoteSwapRevert(hex)
    if (amount !== null) return amount
    if (hex?.startsWith(NOT_ENOUGH_LIQUIDITY_SELECTOR)) throw new NotEnoughLiquidityError()
    throw err
  }
  throw new Error('Quoter did not revert with QuoteSwap')
}
