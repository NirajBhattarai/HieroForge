import { NextResponse } from 'next/server'
import { createPublicClient, http, getAddress } from 'viem'
import { ERC20Abi } from '@/abis/ERC20'
import { saveToken } from '@/lib/dynamo-tokens'

const HEDERA_RPC = 'https://testnet.hashio.io/api'
const HEDERA_CHAIN = {
  id: 296,
  name: 'Hedera Testnet',
  nativeCurrency: { name: 'HBAR', symbol: 'HBAR', decimals: 8 },
  rpcUrls: { default: { http: [HEDERA_RPC] } },
} as const

/**
 * GET /api/tokens/lookup?address=0x...
 * Reads token name, symbol, decimals from chain (ERC20 standard calls).
 * Also auto-saves discovered token to DynamoDB.
 */
/** Convert Hedera native ID (0.0.XXXXX) to EVM address. */
function hederaIdToEvmAddress(id: string): string | null {
  const match = id.match(/^(\d+)\.(\d+)\.(\d+)$/)
  if (!match) return null
  const entityNum = BigInt(match[3]!)
  return '0x' + entityNum.toString(16).padStart(40, '0')
}

export async function GET(request: Request) {
  const { searchParams } = new URL(request.url)
  let rawAddress = (searchParams.get('address') ?? '').trim()

  // Auto-convert Hedera native IDs (0.0.XXXXX) to EVM hex
  const evmFromHedera = hederaIdToEvmAddress(rawAddress)
  if (evmFromHedera) rawAddress = evmFromHedera

  // Validate address format
  let address: string
  try {
    address = getAddress(rawAddress)
  } catch {
    return NextResponse.json(
      { error: 'Invalid address — use 0x hex or Hedera format (0.0.XXXXX)' },
      { status: 400 }
    )
  }

  const client = createPublicClient({
    chain: HEDERA_CHAIN,
    transport: http(HEDERA_RPC),
  })

  try {
    // Read name, symbol, decimals in parallel
    const [name, symbol, decimals] = await Promise.all([
      client.readContract({
        address: address as `0x${string}`,
        abi: ERC20Abi,
        functionName: 'name',
      }).catch(() => null),
      client.readContract({
        address: address as `0x${string}`,
        abi: ERC20Abi,
        functionName: 'symbol',
      }).catch(() => null),
      client.readContract({
        address: address as `0x${string}`,
        abi: ERC20Abi,
        functionName: 'decimals',
      }).catch(() => null),
    ])

    if (!symbol) {
      return NextResponse.json(
        { error: 'No ERC-20 token found at this address on Hedera testnet' },
        { status: 404 }
      )
    }

    const tokenData = {
      address: address.toLowerCase(),
      symbol: String(symbol),
      name: String(name ?? symbol),
      decimals: Number(decimals ?? 18),
      isHts: address.toLowerCase().startsWith('0x000000000000000000000000'),
    }

    // Auto-save to DynamoDB (fire-and-forget, don't block response)
    saveToken({
      ...tokenData,
      createdAt: new Date().toISOString(),
    }).catch(() => {})

    return NextResponse.json(tokenData)
  } catch (err) {
    console.error('Token lookup error:', err)
    return NextResponse.json(
      { error: 'Could not read token data — make sure this is a Hedera testnet address' },
      { status: 500 }
    )
  }
}
