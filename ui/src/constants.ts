// App tabs (Uniswap-style: Trade = Swap, Explore = all pools, Pool = your positions)
export const TAB = {
  TRADE: "trade",
  EXPLORE: "explore",
  POOL: "pool",
} as const;
export type TabValue = (typeof TAB)[keyof typeof TAB];

const HASHIO_RPC = "https://testnet.hashio.io/api";
/** Thirdweb free RPC for Hedera Testnet (chain 296) */
const THIRDWEB_RPC = "https://296.rpc.thirdweb.com";
const DEFAULT_RPC = THIRDWEB_RPC;

/** RPC URL for Hedera (balance, eth_call, etc.). Use NEXT_PUBLIC_RPC_URL in .env to override. */
export function getRpcUrl(): string {
  return (
    (typeof process !== "undefined" &&
      process.env?.NEXT_PUBLIC_RPC_URL?.trim()) ||
    DEFAULT_RPC
  );
}

// Hedera testnet chain for viem
export const HEDERA_TESTNET = {
  id: 296,
  name: "Hedera Testnet",
  nativeCurrency: { name: "HBAR", symbol: "HBAR", decimals: 8 },
  rpcUrls: { default: { http: [HASHIO_RPC] } },
  blockExplorers: {
    default: { name: "HashScan", url: "https://hashscan.io/testnet" },
  },
} as const;

// Token list for Swap / Liquidity (HTS only)
export interface TokenOption {
  id: string;
  symbol: string;
  address?: string;
  decimals?: number;
  name?: string;
}

/** Optional token logo URLs (symbol -> url). Add your own in constants or .env. */
export const TOKEN_IMAGES: Record<string, string> = {
  HBAR: "https://assets.coingecko.com/coins/images/3688/small/hbar.png",
  USDC: "https://assets.coingecko.com/coins/images/6319/small/usdc.png",
  // Add more: FORGE, SWIRL, etc. or leave blank for letter fallback
};

// Token address/decimals lookups are now backed by the dynamic registry
// populated from DynamoDB via useTokens(). Import directly from tokenRegistry.
export { getTokenAddress, getTokenDecimals } from "@/lib/tokenRegistry";

// Default pool params for Quoter (must match an existing pool)
export const DEFAULT_FEE = 3000;
export const DEFAULT_TICK_SPACING = 60;

/** Supported fee tiers (Uniswap v4-style). */
export const FEE_TIERS = [
  { fee: 500, label: "0.05%", desc: "Best for stable pairs" },
  { fee: 3000, label: "0.3%", desc: "Best for most pairs", tag: "Most used" },
  { fee: 10000, label: "1%", desc: "Best for exotic pairs" },
] as const;

/** Map fee to its associated tickSpacing. */
export function feeTierToTickSpacing(fee: number): number {
  if (fee === 500) return 10;
  if (fee === 10000) return 200;
  return 60;
}

// Contract addresses (from env) – Next.js NEXT_PUBLIC_* available on client and server
export function getPoolManagerAddress(): string {
  return (process.env.NEXT_PUBLIC_POOL_MANAGER_ADDRESS ?? "").trim();
}

/** Quoter contract address (NEXT_PUBLIC_QUOTER_ADDRESS). */
export function getQuoterAddress(): string {
  return (process.env.NEXT_PUBLIC_QUOTER_ADDRESS ?? "").trim();
}

/** PositionManager (NEXT_PUBLIC_POSITION_MANAGER_ADDRESS). Required for Add Liquidity. */
export function getPositionManagerAddress(): string {
  return (process.env.NEXT_PUBLIC_POSITION_MANAGER_ADDRESS ?? "").trim();
}

/** UniversalRouter (NEXT_PUBLIC_ROUTER_ADDRESS). Required for Swap. */
export function getRouterAddress(): string {
  return (process.env.NEXT_PUBLIC_ROUTER_ADDRESS ?? "").trim();
}

export function getChainId(): number {
  return Number(process.env.NEXT_PUBLIC_CHAIN_ID ?? "296");
}
