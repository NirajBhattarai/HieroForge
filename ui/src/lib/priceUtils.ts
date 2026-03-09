/** Uniswap v3/v4: price (token1 per token0) = 1.0001^tick */
const Q = 1.0001

export function tickToPrice(tick: number): number {
  return Math.pow(Q, tick)
}

export function priceToTick(price: number): number {
  if (price <= 0) return -887272
  return Math.log(price) / Math.log(Q)
}

/** Round tick to nearest multiple of tickSpacing */
export function roundToTickSpacing(tick: number, tickSpacing: number): number {
  return Math.round(tick / tickSpacing) * tickSpacing
}

/** Price strategy presets (minPct, maxPct) relative to current price. e.g. (-0.5, 1) = -50% to +100% */
export const PRICE_STRATEGIES = [
  { id: 'stable', label: 'Stable', value: '± 3 ticks', desc: 'Good for stablecoins or low volatility pairs', tickDelta: 3 },
  { id: 'wide', label: 'Wide', value: '-50% – +100%', desc: 'Good for volatile pairs', minPct: -0.5, maxPct: 1 },
  { id: 'one-sided-lower', label: 'One-sided lower', value: '-50%', desc: 'Supply liquidity if price goes down', minPct: -0.5, maxPct: 0 },
  { id: 'one-sided-upper', label: 'One-sided upper', value: '+100%', desc: 'Supply liquidity if price goes up', minPct: 0, maxPct: 1 },
] as const
