/**
 * Dynamic token registry — populated at runtime from the /api/tokens endpoint.
 * getTokenAddress() and getTokenDecimals() read from this registry so every
 * component automatically uses the remote token list instead of hardcoded maps.
 */

export interface RegisteredToken {
  address: string;
  symbol: string;
  decimals: number;
  name?: string;
}

/** symbol (upper) -> token info */
const bySymbol = new Map<string, RegisteredToken>();
/** address (lower) -> token info */
const byAddress = new Map<string, RegisteredToken>();

/** Replace the entire registry with a fresh list (called by useTokens). */
export function registerTokens(tokens: RegisteredToken[]) {
  bySymbol.clear();
  byAddress.clear();
  for (const t of tokens) {
    bySymbol.set(t.symbol.toUpperCase(), t);
    byAddress.set(t.address.toLowerCase(), t);
  }
}

/** Look up a token by symbol. */
export function getRegisteredToken(symbol: string): RegisteredToken | undefined {
  return bySymbol.get(symbol.toUpperCase());
}

/** Look up a token by address. */
export function getRegisteredTokenByAddress(address: string): RegisteredToken | undefined {
  return byAddress.get(address.toLowerCase());
}

/** Get token address by symbol from the registry. Returns "" if not found. */
export function getTokenAddress(symbol: string): string {
  return getRegisteredToken(symbol)?.address ?? "";
}

/** Get token decimals by symbol from the registry. Falls back to 18. */
export function getTokenDecimals(symbol: string): number {
  return getRegisteredToken(symbol)?.decimals ?? 18;
}

/** Get decimals by address from the registry. Falls back to 18. */
export function getTokenDecimalsByAddress(address: string): number {
  return getRegisteredTokenByAddress(address)?.decimals ?? 18;
}
