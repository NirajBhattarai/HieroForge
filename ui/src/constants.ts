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

/** PositionManager contract for positions and liquidity (add/remove/burn). */
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

// ─── Hooks ─────────────────────────────────────────────────────────────────
export const HOOKS_ZERO = "0x0000000000000000000000000000000000000000" as const;

/** Hook permission bit flags (lower 6 bits of hook address). */
export const HOOK_FLAGS = {
  BEFORE_INITIALIZE: 1 << 0,
  AFTER_INITIALIZE: 1 << 1,
  BEFORE_MODIFY_LIQUIDITY: 1 << 2,
  AFTER_MODIFY_LIQUIDITY: 1 << 3,
  BEFORE_SWAP: 1 << 4,
  AFTER_SWAP: 1 << 5,
} as const;

export interface HookOption {
  id: string;
  name: string;
  description: string;
  address: string;
  /** Which callbacks this hook implements (for display). */
  permissions: string[];
  /** CSS badge color class */
  color: string;
}

/** Available hooks on the current deployment. */
export const AVAILABLE_HOOKS: HookOption[] = [
  {
    id: "none",
    name: "No Hook",
    description: "Standard pool with no custom logic",
    address: HOOKS_ZERO,
    permissions: [],
    color: "text-text-tertiary",
  },
  {
    id: "twap",
    name: "TWAP Oracle",
    description:
      "Time-weighted average price oracle — records tick history after each swap",
    address:
      (process.env.NEXT_PUBLIC_TWAP_HOOK_ADDRESS ?? "").trim() || HOOKS_ZERO,
    permissions: ["afterInitialize", "afterSwap"],
    color: "text-blue-400",
  },
];

/** Resolve hook address given a hook option ID. */
export function getHookAddress(hookId: string): string {
  return AVAILABLE_HOOKS.find((h) => h.id === hookId)?.address ?? HOOKS_ZERO;
}

/** Identify hook from address. */
export function getHookById(address: string): HookOption | undefined {
  const lc = address.toLowerCase();
  return AVAILABLE_HOOKS.find((h) => h.address.toLowerCase() === lc);
}

/** Detect hook permissions from last byte of address. */
export function getHookPermissionsFromAddress(address: string): string[] {
  const addr = address.toLowerCase();
  if (addr === HOOKS_ZERO) return [];
  const lastByte = parseInt(addr.slice(-2), 16);
  const perms: string[] = [];
  if (lastByte & HOOK_FLAGS.BEFORE_INITIALIZE) perms.push("beforeInitialize");
  if (lastByte & HOOK_FLAGS.AFTER_INITIALIZE) perms.push("afterInitialize");
  if (lastByte & HOOK_FLAGS.BEFORE_MODIFY_LIQUIDITY)
    perms.push("beforeModifyLiquidity");
  if (lastByte & HOOK_FLAGS.AFTER_MODIFY_LIQUIDITY)
    perms.push("afterModifyLiquidity");
  if (lastByte & HOOK_FLAGS.BEFORE_SWAP) perms.push("beforeSwap");
  if (lastByte & HOOK_FLAGS.AFTER_SWAP) perms.push("afterSwap");
  return perms;
}
