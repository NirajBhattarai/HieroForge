/** BigInt integer square root via Newton's method */
function bigIntSqrt(n: bigint): bigint {
  if (n < 0n) throw new Error("Square root of negative number");
  if (n === 0n) return 0n;
  let x = n;
  let y = (x + 1n) / 2n;
  while (y < x) {
    x = y;
    y = (x + n / x) / 2n;
  }
  return x;
}

const Q96 = 1n << 96n;

/**
 * Convert a human-readable price to sqrtPriceX96 (Uniswap V3/V4 Q64.96 format).
 *
 * price = how many token1 per 1 token0 (in human units, e.g. "1500 USDC per ETH").
 * sqrtPriceX96 = sqrt(price × 10^(decimals1 − decimals0)) × 2^96
 */
export function encodePriceSqrt(
  price: number,
  decimals0: number,
  decimals1: number,
): bigint {
  if (price <= 0) throw new Error("Price must be positive");

  const PRECISION = 10n ** 18n;
  const priceNum = BigInt(Math.round(price * 1e18));
  const decDiff = decimals1 - decimals0;

  let adjustedNum = priceNum;
  if (decDiff >= 0) {
    adjustedNum = priceNum * 10n ** BigInt(decDiff);
  } else {
    adjustedNum = priceNum / 10n ** BigInt(-decDiff);
  }

  // sqrtPriceX96 = sqrt(adjustedPrice) * Q96 = sqrt(adjustedNum * Q96² / PRECISION)
  const inner = (adjustedNum * Q96 * Q96) / PRECISION;
  return bigIntSqrt(inner);
}

/** Uniswap v3/v4: price (token1 per token0) = 1.0001^tick */
const Q = 1.0001;

export function tickToPrice(tick: number): number {
  return Math.pow(Q, tick);
}

export function priceToTick(price: number): number {
  if (price <= 0) return -887272;
  return Math.log(price) / Math.log(Q);
}

/** Round tick to nearest multiple of tickSpacing */
export function roundToTickSpacing(tick: number, tickSpacing: number): number {
  return Math.round(tick / tickSpacing) * tickSpacing;
}

// ---------------------------------------------------------------------------
// Uniswap V3/V4 concentrated liquidity math (floating-point for UI display)
// ---------------------------------------------------------------------------

/**
 * Compute liquidity (L) and the paired token amount given one deposit amount.
 *
 * currentPrice, minPrice, maxPrice are human-readable (token1 per token0).
 * amount is in human units (e.g. "100.5").
 * inputToken: 0 if user typed amount0, 1 if user typed amount1.
 *
 * Returns { liquidity, amount0, amount1 } in human units.
 */
export function computeLiquidityFromAmount(
  currentPrice: number,
  minPrice: number,
  maxPrice: number,
  amount: number,
  inputToken: 0 | 1,
): { liquidity: number; amount0: number; amount1: number } {
  if (currentPrice <= 0 || minPrice < 0 || maxPrice <= 0 || maxPrice <= minPrice || amount <= 0) {
    return { liquidity: 0, amount0: 0, amount1: 0 };
  }

  const sqrtP = Math.sqrt(currentPrice);
  const sqrtPa = Math.sqrt(Math.max(minPrice, 1e-18));
  const sqrtPb = Math.sqrt(maxPrice);

  let L: number;

  if (currentPrice <= minPrice) {
    // Below range: only token0 required
    if (inputToken === 1) return { liquidity: 0, amount0: 0, amount1: amount };
    L = amount * (sqrtPa * sqrtPb) / (sqrtPb - sqrtPa);
    return { liquidity: L, amount0: amount, amount1: 0 };
  }

  if (currentPrice >= maxPrice) {
    // Above range: only token1 required
    if (inputToken === 0) return { liquidity: 0, amount0: amount, amount1: 0 };
    L = amount / (sqrtPb - sqrtPa);
    return { liquidity: L, amount0: 0, amount1: amount };
  }

  // In range: both tokens needed
  if (inputToken === 0) {
    L = amount * (sqrtP * sqrtPb) / (sqrtPb - sqrtP);
    const amount1Calc = L * (sqrtP - sqrtPa);
    return { liquidity: L, amount0: amount, amount1: amount1Calc };
  } else {
    L = amount / (sqrtP - sqrtPa);
    const amount0Calc = L * (sqrtPb - sqrtP) / (sqrtP * sqrtPb);
    return { liquidity: L, amount0: amount0Calc, amount1: amount };
  }
}

/**
 * Convert a human-unit liquidity value to on-chain wei-unit liquidity.
 * Because the concentrated liquidity formula uses sqrt(price-in-raw-terms),
 * liquidity scales by 10^((dec0+dec1)/2).
 */
export function liquidityToWei(
  liquidityHuman: number,
  decimals0: number,
  decimals1: number,
): bigint {
  if (liquidityHuman <= 0) return 0n;
  const scale = (decimals0 + decimals1) / 2;
  const scaled = liquidityHuman * Math.pow(10, scale);
  // Use string conversion to avoid BigInt precision loss
  return BigInt(Math.floor(scaled).toLocaleString("fullwide", { useGrouping: false }));
}

/** Price strategy presets (minPct, maxPct) relative to current price. e.g. (-0.5, 1) = -50% to +100% */
export const PRICE_STRATEGIES = [
  {
    id: "stable",
    label: "Stable",
    value: "± 3 ticks",
    desc: "Good for stablecoins or low volatility pairs",
    tickDelta: 3,
  },
  {
    id: "wide",
    label: "Wide",
    value: "-50% – +100%",
    desc: "Good for volatile pairs",
    minPct: -0.5,
    maxPct: 1,
  },
  {
    id: "one-sided-lower",
    label: "One-sided lower",
    value: "-50%",
    desc: "Supply liquidity if price goes down",
    minPct: -0.5,
    maxPct: 0,
  },
  {
    id: "one-sided-upper",
    label: "One-sided upper",
    value: "+100%",
    desc: "Supply liquidity if price goes up",
    minPct: 0,
    maxPct: 1,
  },
] as const;
