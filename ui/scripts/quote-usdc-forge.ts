/**
 * Test script: quote how much FORGE you get for N USDC.
 * Run: npx tsx scripts/quote-usdc-forge.ts
 * Optional env:
 *   QUOTE_AMOUNT_USDC=1          — quote for 1 USDC (default 100)
 *   QUOTE_TOKEN_USDC=0x...       — USDC token address (default from constants)
 *   QUOTE_TOKEN_FORGE=0x...      — FORGE token address
 * Revert 0x7a5ed734 = NotEnoughLiquidity(poolId): pool has no or insufficient liquidity for that amount.
 */
import { createPublicClient, http, formatUnits } from 'viem'
import { quoteExactInputSingle } from '../src/lib/quote'
import {
  HEDERA_TESTNET,
  getTokenAddress,
  getTokenDecimals,
  getQuoterAddress,
  DEFAULT_FEE,
  DEFAULT_TICK_SPACING,
} from '../src/constants'

const QUOTER_ADDRESS = '0xb1d21e7edb55428394e2a6a0c2ba314c5b859a74' as const
const AMOUNT_USDC_HUMAN = Number(process.env.QUOTE_AMOUNT_USDC ?? '100')

function getEnvAddr(key: string): string {
  const v = process.env[key]?.trim().toLowerCase()
  return v && v.startsWith('0x') ? v : ''
}

async function main() {
  // Use env override so you can pass your pool's token addresses (e.g. from hieroforge-core .env)
  const usdcAddr = getEnvAddr('QUOTE_TOKEN_USDC') || getTokenAddress('USDC')
  const forgeAddr = getEnvAddr('QUOTE_TOKEN_FORGE') || getTokenAddress('FORGE')
  if (!usdcAddr || !forgeAddr) {
    console.error('Set token addresses: QUOTE_TOKEN_USDC and QUOTE_TOKEN_FORGE (or TOKEN_ADDRESSES in constants)')
    process.exit(1)
  }

  const currency0 = usdcAddr < forgeAddr ? usdcAddr : forgeAddr
  const currency1 = usdcAddr < forgeAddr ? forgeAddr : usdcAddr
  // Paying USDC, receiving FORGE: if USDC < FORGE then we sell token0 for token1 → zeroForOne = true
  const zeroForOne = usdcAddr < forgeAddr

  const poolKey = { currency0, currency1, fee: DEFAULT_FEE, tickSpacing: DEFAULT_TICK_SPACING }
  const decimalsIn = getTokenDecimals('USDC')
  const decimalsOut = getTokenDecimals('FORGE')
  const amountInRaw = BigInt(AMOUNT_USDC_HUMAN) * BigInt(10 ** decimalsIn)

  const publicClient = createPublicClient({
    chain: HEDERA_TESTNET,
    transport: http(HEDERA_TESTNET.rpcUrls.default.http[0]),
  })

  const quoterAddr = getQuoterAddress() || QUOTER_ADDRESS
  console.log('Quoter:', quoterAddr)
  console.log('Pool: currency0=%s currency1=%s', currency0, currency1)
  console.log('Quote: %s USDC in → ? FORGE out (zeroForOne=%s)', AMOUNT_USDC_HUMAN, zeroForOne)

  try {
    const amountOutRaw = await quoteExactInputSingle(
      publicClient,
      quoterAddr as `0x${string}`,
      poolKey,
      zeroForOne,
      amountInRaw
    )
    const amountOutHuman = formatUnits(amountOutRaw, decimalsOut)
    console.log('Result: %s USDC → %s FORGE', AMOUNT_USDC_HUMAN, amountOutHuman)
  } catch (e: unknown) {
    const err = e as { cause?: { cause?: { data?: string }; data?: string }; data?: string }
    const revertData = err?.cause?.cause?.data ?? err?.cause?.data ?? err?.data
    const hex = typeof revertData === 'string' ? revertData : ''
    // NotEnoughLiquidity(bytes32) selector = 0x7a5ed734 (from BaseQuoter.sol)
    if (hex.startsWith('0x7a5ed734')) {
      console.error('Quote failed: NotEnoughLiquidity(poolId)')
      console.error('The pool does not have enough liquidity to swap 100 USDC in one go.')
      console.error('Try a smaller amount (e.g. 1 USDC) or add more liquidity to the pool.')
    } else {
      console.error('Quote failed. Revert data:', hex || '(none)')
      console.error('Pool must exist with fee=3000, tickSpacing=60 and have liquidity.')
    }
    throw e
  }
}

main().catch((e) => {
  console.error(e)
  process.exit(1)
})
