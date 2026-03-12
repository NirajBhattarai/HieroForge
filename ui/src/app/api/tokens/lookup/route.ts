import { NextResponse } from 'next/server'
import { createPublicClient, http, getAddress } from 'viem'
import { ERC20Abi } from '@/abis/ERC20'
import { saveToken } from '@/lib/dynamo-tokens'

const HEDERA_RPC = 'https://testnet.hashio.io/api'
const HEDERA_MIRROR = 'https://testnet.mirrornode.hedera.com'
const HEDERA_CHAIN = {
  id: 296,
  name: 'Hedera Testnet',
  nativeCurrency: { name: 'HBAR', symbol: 'HBAR', decimals: 8 },
  rpcUrls: { default: { http: [HEDERA_RPC] } },
} as const

/** Convert Hedera native ID (0.0.XXXXX) to EVM address. */
function hederaIdToEvmAddress(id: string): string | null {
  const match = id.match(/^(\d+)\.(\d+)\.(\d+)$/)
  if (!match) return null
  const entityNum = BigInt(match[3]!)
  return '0x' + entityNum.toString(16).padStart(40, '0')
}

/** Convert EVM address to Hedera account format for mirror node queries. */
function evmAddressToHederaId(addr: string): string | null {
  const hex = addr.replace(/^0x/, '').replace(/^0+/, '')
  if (!hex) return null
  const num = parseInt(hex, 16)
  if (!Number.isFinite(num) || num <= 0) return null
  return `0.0.${num}`
}

/** Try the Hedera Mirror Node REST API for HTS token metadata. */
async function lookupViaMirrorNode(address: string): Promise<{
  symbol: string; name: string; decimals: number; tokenId: string
} | null> {
  const hederaId = evmAddressToHederaId(address)
  if (!hederaId) return null
  try {
    const res = await fetch(`${HEDERA_MIRROR}/api/v1/tokens/${hederaId}`)
    if (!res.ok) return null
    const data = await res.json()
    if (!data.symbol) return null
    return {
      symbol: String(data.symbol),
      name: String(data.name ?? data.symbol),
      decimals: Number(data.decimals ?? 0),
      tokenId: String(data.token_id),
    }
  } catch {
    return null
  }
}

/**
 * GET /api/tokens/lookup?address=0x...
 * Reads HTS token metadata from chain (balanceOf/symbol/decimals) + Hedera Mirror Node fallback.
 * Auto-saves discovered token to DynamoDB.
 */
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

  const isHts = address.toLowerCase().startsWith('0x000000000000000000000000')

  // For HTS tokens, prefer Mirror Node (it has the real token metadata)
  if (isHts) {
    const mirror = await lookupViaMirrorNode(address)
    if (mirror) {
      const tokenData = {
        address: address.toLowerCase(),
        symbol: mirror.symbol,
        name: mirror.name,
        decimals: mirror.decimals,
        isHts: true,
        hederaId: mirror.tokenId,
      }
      saveToken({ ...tokenData, createdAt: new Date().toISOString() }).catch(() => {})
      return NextResponse.json(tokenData)
    }
  }

  // Fallback: ERC-20 read calls via RPC
  const client = createPublicClient({
    chain: HEDERA_CHAIN,
    transport: http(HEDERA_RPC),
  })

  try {
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
      isHts,
    }

    saveToken({ ...tokenData, createdAt: new Date().toISOString() }).catch(() => {})
    return NextResponse.json(tokenData)
  } catch {
    return NextResponse.json(
      { error: 'Could not read token data — make sure this is a Hedera testnet address' },
      { status: 500 }
    )
  }
}
