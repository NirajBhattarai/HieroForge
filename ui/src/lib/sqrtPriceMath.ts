/**
 * BigInt implementations of Uniswap V4 SqrtPriceMath and TickMath.
 * Mirrors the Solidity logic in hieroforge-core/src/libraries/ so the UI
 * computes the EXACT same liquidity and amounts as the contract.
 */

const Q96 = 1n << 96n;
const Q192 = Q96 * Q96;

export const MAX_TICK = 887272;
export const MIN_TICK = -887272;
export const MIN_SQRT_PRICE = 4295128739n;
export const MAX_SQRT_PRICE =
  1461446703485210103287273052203988822378723970342n;

// ---------------------------------------------------------------------------
// TickMath — getSqrtPriceAtTick (magic-constant implementation from Solidity)
// ---------------------------------------------------------------------------

/**
 * Compute sqrtPriceX96 from a tick, matching TickMath.sol exactly.
 * Uses the same magic-constant bit manipulation as the Solidity code.
 */
export function getSqrtPriceAtTick(tick: number): bigint {
  if (tick < MIN_TICK || tick > MAX_TICK) {
    throw new Error(`InvalidTick: ${tick} outside [${MIN_TICK}, ${MAX_TICK}]`);
  }
  const absTick = Math.abs(tick);

  // Start with ratio = 2^128 and multiply by magic constants for each nonzero bit
  let ratio: bigint;
  ratio =
    (absTick & 0x1) !== 0
      ? 0xfffcb933bd6fad37aa2d162d1a594001n
      : 0x100000000000000000000000000000000n;
  if ((absTick & 0x2) !== 0)
    ratio = (ratio * 0xfff97272373d413259a46990580e213an) >> 128n;
  if ((absTick & 0x4) !== 0)
    ratio = (ratio * 0xfff2e50f5f656932ef12357cf3c7fdccn) >> 128n;
  if ((absTick & 0x8) !== 0)
    ratio = (ratio * 0xffe5caca7e10e4e61c3624eaa0941cd0n) >> 128n;
  if ((absTick & 0x10) !== 0)
    ratio = (ratio * 0xffcb9843d60f6159c9db58835c926644n) >> 128n;
  if ((absTick & 0x20) !== 0)
    ratio = (ratio * 0xff973b41fa98c081472e6896dfb254c0n) >> 128n;
  if ((absTick & 0x40) !== 0)
    ratio = (ratio * 0xff2ea16466c96a3843ec78b326b52861n) >> 128n;
  if ((absTick & 0x80) !== 0)
    ratio = (ratio * 0xfe5dee046a99a2a811c461f1969c3053n) >> 128n;
  if ((absTick & 0x100) !== 0)
    ratio = (ratio * 0xfcbe86c7900a88aedcffc83b479aa3a4n) >> 128n;
  if ((absTick & 0x200) !== 0)
    ratio = (ratio * 0xf987a7253ac413176f2b074cf7815e54n) >> 128n;
  if ((absTick & 0x400) !== 0)
    ratio = (ratio * 0xf3392b0822b70005940c7a398e4b70f3n) >> 128n;
  if ((absTick & 0x800) !== 0)
    ratio = (ratio * 0xe7159475a2c29b7443b29c7fa6e889d9n) >> 128n;
  if ((absTick & 0x1000) !== 0)
    ratio = (ratio * 0xd097f3bdfd2022b8845ad8f792aa5825n) >> 128n;
  if ((absTick & 0x2000) !== 0)
    ratio = (ratio * 0xa9f746462d870fdf8a65dc1f90e061e5n) >> 128n;
  if ((absTick & 0x4000) !== 0)
    ratio = (ratio * 0x70d869a156d2a1b890bb3df62baf32f7n) >> 128n;
  if ((absTick & 0x8000) !== 0)
    ratio = (ratio * 0x31be135f97d08fd981231505542fcfa6n) >> 128n;
  if ((absTick & 0x10000) !== 0)
    ratio = (ratio * 0x9aa508b5b7a84e1c677de54f3e99bc9n) >> 128n;
  if ((absTick & 0x20000) !== 0)
    ratio = (ratio * 0x5d6af8dedb81196699c329225ee604n) >> 128n;
  if ((absTick & 0x40000) !== 0)
    ratio = (ratio * 0x2216e584f5fa1ea926041bedfe98n) >> 128n;
  if ((absTick & 0x80000) !== 0)
    ratio = (ratio * 0x48a170391f7dc42444e8fa2n) >> 128n;

  // Invert if tick > 0
  if (tick > 0)
    ratio =
      0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffn /
      ratio;

  // Round up and shift from Q128 to Q96
  const remainder = ratio % (1n << 32n);
  return (ratio >> 32n) + (remainder === 0n ? 0n : 1n);
}

// ---------------------------------------------------------------------------
// Amount deltas — matches SqrtPriceMath.sol
// ---------------------------------------------------------------------------

function mulDiv(a: bigint, b: bigint, d: bigint): bigint {
  return (a * b) / d;
}

function mulDivRoundUp(a: bigint, b: bigint, d: bigint): bigint {
  const result = (a * b) / d;
  if ((a * b) % d > 0n) return result + 1n;
  return result;
}

/**
 * amount0 = L × Q96 × (sqrtPB − sqrtPA) / (sqrtPB × sqrtPA)
 * roundUp: true for amount owed to pool (add liquidity), false for amount out
 */
export function getAmount0Delta(
  sqrtPA: bigint,
  sqrtPB: bigint,
  liquidity: bigint,
  roundUp = true,
): bigint {
  let lower = sqrtPA;
  let upper = sqrtPB;
  if (lower > upper) [lower, upper] = [upper, lower];

  const numerator = liquidity * Q96 * (upper - lower);
  const denominator = upper * lower;

  return roundUp
    ? (numerator + denominator - 1n) / denominator
    : numerator / denominator;
}

/**
 * amount1 = L × (sqrtPB − sqrtPA) / Q96
 */
export function getAmount1Delta(
  sqrtPA: bigint,
  sqrtPB: bigint,
  liquidity: bigint,
  roundUp = true,
): bigint {
  let lower = sqrtPA;
  let upper = sqrtPB;
  if (lower > upper) [lower, upper] = [upper, lower];

  const numerator = liquidity * (upper - lower);
  return roundUp ? (numerator + Q96 - 1n) / Q96 : numerator / Q96;
}

// ---------------------------------------------------------------------------
// Inverse: compute L from amounts (used for UI amount input)
// ---------------------------------------------------------------------------

/** L = amount0 × sqrtPC × sqrtPB / (Q96 × (sqrtPB − sqrtPC)) */
export function getLiquidityForAmount0(
  sqrtPC: bigint,
  sqrtPB: bigint,
  amount0: bigint,
): bigint {
  let lower = sqrtPC;
  let upper = sqrtPB;
  if (lower > upper) [lower, upper] = [upper, lower];
  const diff = upper - lower;
  if (diff === 0n) return 0n;
  return mulDiv(amount0 * lower, upper, diff * Q96);
}

/** L = amount1 × Q96 / (sqrtPC − sqrtPA) */
export function getLiquidityForAmount1(
  sqrtPA: bigint,
  sqrtPC: bigint,
  amount1: bigint,
): bigint {
  let lower = sqrtPA;
  let upper = sqrtPC;
  if (lower > upper) [lower, upper] = [upper, lower];
  const diff = upper - lower;
  if (diff === 0n) return 0n;
  return mulDiv(amount1, Q96, diff);
}

/**
 * Compute the maximum liquidity that can be provided with given token amounts.
 * This mirrors the contract's LiquidityAmounts.getLiquidityForAmounts().
 */
export function maxLiquidityForAmounts(
  sqrtPriceX96: bigint,
  sqrtPA: bigint,
  sqrtPB: bigint,
  amount0: bigint,
  amount1: bigint,
): bigint {
  let lower = sqrtPA;
  let upper = sqrtPB;
  if (lower > upper) [lower, upper] = [upper, lower];

  if (sqrtPriceX96 <= lower) {
    // Below range: only token0 needed
    return getLiquidityForAmount0(lower, upper, amount0);
  }
  if (sqrtPriceX96 >= upper) {
    // Above range: only token1 needed
    return getLiquidityForAmount1(lower, upper, amount1);
  }
  // In range: use the binding constraint (min of both)
  const l0 = getLiquidityForAmount0(sqrtPriceX96, upper, amount0);
  const l1 = getLiquidityForAmount1(lower, sqrtPriceX96, amount1);
  return l0 < l1 ? l0 : l1;
}

/**
 * Given a liquidity value and the current/range sqrtPrices, compute the exact
 * amounts needed (with round-up, matching contract behavior).
 * Returns { amount0, amount1 } in raw token units (wei).
 */
export function amountsForLiquidity(
  sqrtPriceX96: bigint,
  sqrtPA: bigint,
  sqrtPB: bigint,
  liquidity: bigint,
): { amount0: bigint; amount1: bigint } {
  let lower = sqrtPA;
  let upper = sqrtPB;
  if (lower > upper) [lower, upper] = [upper, lower];

  let amount0 = 0n;
  let amount1 = 0n;

  if (sqrtPriceX96 <= lower) {
    amount0 = getAmount0Delta(lower, upper, liquidity, true);
  } else if (sqrtPriceX96 >= upper) {
    amount1 = getAmount1Delta(lower, upper, liquidity, true);
  } else {
    amount0 = getAmount0Delta(sqrtPriceX96, upper, liquidity, true);
    amount1 = getAmount1Delta(lower, sqrtPriceX96, liquidity, true);
  }

  return { amount0, amount1 };
}

/**
 * Clamp a tick to [MIN_TICK, MAX_TICK] range, rounded to tickSpacing.
 */
export function clampTick(tick: number, tickSpacing: number): number {
  const maxAligned = Math.floor(MAX_TICK / tickSpacing) * tickSpacing;
  const minAligned = Math.ceil(MIN_TICK / tickSpacing) * tickSpacing;
  return Math.max(minAligned, Math.min(maxAligned, tick));
}
