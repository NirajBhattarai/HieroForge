// App tabs
export const TAB = { SWAP: 'swap', POOL: 'pool', LIQUIDITY: 'liquidity' } as const
export type TabValue = (typeof TAB)[keyof typeof TAB]

// Hedera testnet chain for viem
export const HEDERA_TESTNET = {
  id: 296,
  name: 'Hedera Testnet',
  nativeCurrency: { name: 'HBAR', symbol: 'HBAR', decimals: 8 },
  rpcUrls: { default: { http: ['https://testnet.hashio.io/api'] } },
  blockExplorers: { default: { name: 'HashScan', url: 'https://hashscan.io/testnet' } },
} as const

// Token list for Swap / Liquidity
export interface TokenOption {
  id: string
  symbol: string
}

export const DEFAULT_TOKENS: TokenOption[] = [
  { id: 'token0', symbol: 'HBAR' },
  { id: 'token1', symbol: 'USDC' },
  { id: 'token2', symbol: 'FORGE' },
  { id: 'token3', symbol: 'SWIRL' },
  { id: 'token4', symbol: 'ORBIT' },
  { id: 'token5', symbol: 'PULSE' },
  { id: 'token6', symbol: 'FLUX' },
  { id: 'token7', symbol: 'SPARK' },
  { id: 'token8', symbol: 'NOVA' },
  { id: 'token9', symbol: 'EMBER' },
]

/** Optional token logo URLs (symbol -> url). Add your own in constants or .env. */
export const TOKEN_IMAGES: Record<string, string> = {
  HBAR: 'https://assets.coingecko.com/coins/images/3688/small/hbar.png',
  USDC: 'https://assets.coingecko.com/coins/images/6319/small/usdc.png',
  // Add more: FORGE, SWIRL, etc. or leave blank for letter fallback
}

/**
 * Token symbol -> contract address. All are HTS (Hedera Token Service) long-form: 0x0000...<id>.
 * Pool key and Quoter use these same addresses. Edit with your deployed HTS token ids.
 */
export const TOKEN_ADDRESSES: Record<string, string> = {
  HBAR: '0x0000000000000000000000000000000000000408',
  USDC: '0x00000000000000000000000000000000007b97e4',
  FORGE: '0x00000000000000000000000000000000007b97D4',
  SWIRL: '0x00000000000000000000000000000000007b8a82',
  ORBIT: '0x00000000000000000000000000000000007b8a96',
  PULSE: '0x00000000000000000000000000000000007B8AA3',
  FLUX: '0x00000000000000000000000000000000007B8Ab7',
  SPARK: '0x00000000000000000000000000000000007b8AC3',
  NOVA: '0x00000000000000000000000000000000007B8Ad4',
  EMBER: '0x00000000000000000000000000000000007B8aE3',
}

/** Token decimals (for parseUnits/formatUnits). Default 18 if not set. */
export const TOKEN_DECIMALS: Record<string, number> = {
  HBAR: 8,
  USDC: 6,
  FORGE: 4,
  SWIRL: 4,
  ORBIT: 4,
  PULSE: 4,
  FLUX: 4,
  SPARK: 4,
  NOVA: 4,
  EMBER: 4,
}

/** Get token address by symbol; loads from TOKEN_ADDRESSES. */
export function getTokenAddress(symbol: string): string {
  return (TOKEN_ADDRESSES[symbol] ?? '').trim().toLowerCase()
}

/** Get token decimals by symbol; default 18. */
export function getTokenDecimals(symbol: string): number {
  return TOKEN_DECIMALS[symbol] ?? 18
}

// Default pool params for Quoter (must match an existing pool)
export const DEFAULT_FEE = 3000
export const DEFAULT_TICK_SPACING = 60

// Contract addresses (from env) – Next.js NEXT_PUBLIC_* available on client and server
export function getPoolManagerAddress(): string {
  return (process.env.NEXT_PUBLIC_POOL_MANAGER_ADDRESS ?? '').trim()
}

/** Quoter contract address (NEXT_PUBLIC_QUOTER_ADDRESS). */
export function getQuoterAddress(): string {
  return (process.env.NEXT_PUBLIC_QUOTER_ADDRESS ?? '').trim()
}

/** PositionManager (NEXT_PUBLIC_POSITION_MANAGER_ADDRESS). Required for Add Liquidity. */
export function getPositionManagerAddress(): string {
  return (process.env.NEXT_PUBLIC_POSITION_MANAGER_ADDRESS ?? '').trim()
}

export function getChainId(): number {
  return Number(process.env.NEXT_PUBLIC_CHAIN_ID ?? '296')
}
