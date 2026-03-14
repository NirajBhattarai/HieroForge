import {
  encodeFunctionData,
  decodeFunctionResult,
  decodeErrorResult,
  type PublicClient,
} from "viem";
import { QuoterAbi, type PoolKeyForQuote } from "../abis/Quoter";
import { getRpcUrl } from "../constants";

const ZERO_ADDRESS = "0x0000000000000000000000000000000000000000" as const;

/** Revert selector for NotEnoughLiquidity(bytes32) from BaseV4Quoter.sol */
const NOT_ENOUGH_LIQUIDITY_SELECTOR = "0x7a5ed734";

export class NotEnoughLiquidityError extends Error {
  readonly code = "NOT_ENOUGH_LIQUIDITY" as const;
  constructor() {
    super(
      "Not enough liquidity in the pool for this amount. Try a smaller amount or add liquidity.",
    );
    this.name = "NotEnoughLiquidityError";
  }
}

export interface QuoteParams {
  poolKey: PoolKeyForQuote & { hooks: string };
  zeroForOne: boolean;
  exactAmount: bigint;
  hookData: `0x${string}`;
}

export interface QuoteResult {
  amount: bigint;
  gasEstimate: bigint;
}

/**
 * Build params for V4Quoter.quoteExactInputSingle / quoteExactOutputSingle.
 */
export function quoteParams(
  poolKey: PoolKeyForQuote,
  zeroForOne: boolean,
  exactAmount: bigint,
): QuoteParams {
  return {
    poolKey: {
      currency0: poolKey.currency0,
      currency1: poolKey.currency1,
      fee: poolKey.fee,
      tickSpacing: poolKey.tickSpacing,
      hooks: ZERO_ADDRESS,
    },
    zeroForOne,
    exactAmount,
    hookData: "0x",
  };
}

/**
 * Extract revert data hex from a viem/contract error (may be nested).
 * Hedera relay returns `{ error: { data: "0x..." } }` which viem wraps in nested cause chain.
 */
function getRevertDataHex(err: unknown): string | null {
  let e: unknown = err;
  for (let i = 0; i < 8 && e; i++) {
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    const obj = e as any;
    for (const accessor of [
      obj?.data,
      obj?.details,
      obj?.data?.data,
      obj?.error?.data,
    ]) {
      if (accessor != null) {
        const hex =
          typeof accessor === "string" ? accessor : accessor?.toString?.();
        if (typeof hex === "string" && hex.startsWith("0x") && hex.length >= 10)
          return hex;
      }
    }
    e = obj?.cause ?? obj?.error;
  }
  try {
    const str = String(err);
    const m = str.match(/0x[0-9a-fA-F]{8,}/);
    if (m) return m[0];
  } catch {
    /* ignore */
  }
  return null;
}

/**
 * Parse QuoteSwap(uint256) from revert data. Returns the amount or null if not QuoteSwap.
 * Kept for backward compatibility — old Quoter contracts still revert with QuoteSwap.
 */
export function parseQuoteSwapRevert(data: string | null): bigint | null {
  if (
    !data ||
    typeof data !== "string" ||
    !data.startsWith("0x") ||
    data.length < 2 + 8 + 64
  )
    return null;
  try {
    const decoded = decodeErrorResult({
      abi: QuoterAbi,
      data: data as `0x${string}`,
    });
    if (decoded?.errorName === "QuoteSwap" && decoded?.args?.length)
      return decoded.args[0] as bigint;
  } catch {
    return null;
  }
  return null;
}

/**
 * Try to decode V4Quoter return data: (uint256 amount, uint256 gasEstimate).
 * Returns amount or null if data doesn't decode properly.
 */
function tryDecodeQuoteReturn(
  functionName: string,
  data: string | null,
): QuoteResult | null {
  if (
    !data ||
    typeof data !== "string" ||
    !data.startsWith("0x") ||
    data.length < 2 + 128
  )
    return null;
  try {
    const decoded = decodeFunctionResult({
      abi: QuoterAbi,
      functionName,
      data: data as `0x${string}`,
    });
    const arr = decoded as readonly bigint[];
    if (arr && arr.length >= 2 && typeof arr[0] === "bigint") {
      return { amount: arr[0], gasEstimate: arr[1] };
    }
  } catch {
    /* not a valid return */
  }
  return null;
}

/**
 * Raw RPC eth_call — bypasses viem to get Hedera revert/return data directly.
 */
async function rawEthCall(to: string, data: string): Promise<string | null> {
  try {
    const resp = await fetch(getRpcUrl(), {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        jsonrpc: "2.0",
        id: 1,
        method: "eth_call",
        params: [{ to, data }, "latest"],
      }),
    });
    const json = (await resp.json()) as {
      result?: string;
      error?: { data?: string };
    };
    const hex = json?.error?.data ?? json?.result;
    return typeof hex === "string" && hex.startsWith("0x") && hex.length >= 10
      ? hex
      : null;
  } catch {
    return null;
  }
}

/**
 * Core quote logic: tries V4Quoter return values first, then falls back to QuoteSwap revert parsing.
 * This handles both: (1) V4Quoter returning clean (amount, gasEstimate) and
 * (2) Hedera relay returning the try/catch revert data as error instead of return.
 */
async function executeQuote(
  publicClient: PublicClient,
  quoterAddress: `0x${string}`,
  functionName: string,
  params: QuoteParams,
): Promise<QuoteResult> {
  const calldata = encodeFunctionData({
    abi: QuoterAbi,
    functionName,
    args: [params],
  });

  try {
    const result = await publicClient.call({
      to: quoterAddress,
      data: calldata,
    });
    const raw = result as unknown;
    const resultHex =
      typeof raw === "string" && raw.startsWith("0x")
        ? raw
        : typeof (raw as { data?: string })?.data === "string"
          ? (raw as { data: string }).data
          : null;

    // V4Quoter returns (uint256, uint256) — try decoding as return value first
    const decoded = tryDecodeQuoteReturn(functionName, resultHex);
    if (decoded !== null) return decoded;

    // Fallback: old-style QuoteSwap revert in result data
    const amount = parseQuoteSwapRevert(resultHex);
    if (amount !== null) return { amount, gasEstimate: 0n };

    if (resultHex?.startsWith(NOT_ENOUGH_LIQUIDITY_SELECTOR))
      throw new NotEnoughLiquidityError();
  } catch (err: unknown) {
    if (err instanceof NotEnoughLiquidityError) throw err;

    const hex = getRevertDataHex(err);

    // Try as V4Quoter return data (Hedera may put it in error.data)
    const decoded = tryDecodeQuoteReturn(functionName, hex);
    if (decoded !== null) return decoded;

    // Try as QuoteSwap revert
    const amount = parseQuoteSwapRevert(hex);
    if (amount !== null) return { amount, gasEstimate: 0n };

    if (hex?.startsWith(NOT_ENOUGH_LIQUIDITY_SELECTOR))
      throw new NotEnoughLiquidityError();

    // Raw fetch fallback for Hedera relay edge cases
    const rawHex = await rawEthCall(quoterAddress, calldata);
    const rawDecoded = tryDecodeQuoteReturn(functionName, rawHex);
    if (rawDecoded !== null) return rawDecoded;
    const rawAmount = parseQuoteSwapRevert(rawHex);
    if (rawAmount !== null) return { amount: rawAmount, gasEstimate: 0n };
    if (rawHex?.startsWith(NOT_ENOUGH_LIQUIDITY_SELECTOR))
      throw new NotEnoughLiquidityError();

    throw err;
  }
  throw new Error("V4Quoter: unexpected empty response");
}

/**
 * Quote exact input: get amountOut for a given amountIn.
 * V4Quoter returns (amountOut, gasEstimate) via try/catch internally.
 */
export async function quoteExactInputSingle(
  publicClient: PublicClient,
  quoterAddress: `0x${string}`,
  poolKey: PoolKeyForQuote,
  zeroForOne: boolean,
  amountIn: bigint,
): Promise<bigint> {
  const params = quoteParams(poolKey, zeroForOne, amountIn);
  const result = await executeQuote(
    publicClient,
    quoterAddress,
    "quoteExactInputSingle",
    params,
  );
  return result.amount;
}

/**
 * Quote exact output: get amountIn for a given amountOut.
 */
export async function quoteExactOutputSingle(
  publicClient: PublicClient,
  quoterAddress: `0x${string}`,
  poolKey: PoolKeyForQuote,
  zeroForOne: boolean,
  amountOut: bigint,
): Promise<bigint> {
  const params = quoteParams(poolKey, zeroForOne, amountOut);
  const result = await executeQuote(
    publicClient,
    quoterAddress,
    "quoteExactOutputSingle",
    params,
  );
  return result.amount;
}

/**
 * Quote exact input with gas estimate.
 */
export async function quoteExactInputSingleWithGas(
  publicClient: PublicClient,
  quoterAddress: `0x${string}`,
  poolKey: PoolKeyForQuote,
  zeroForOne: boolean,
  amountIn: bigint,
): Promise<QuoteResult> {
  const params = quoteParams(poolKey, zeroForOne, amountIn);
  return executeQuote(
    publicClient,
    quoterAddress,
    "quoteExactInputSingle",
    params,
  );
}

/**
 * Quote exact output with gas estimate.
 */
export async function quoteExactOutputSingleWithGas(
  publicClient: PublicClient,
  quoterAddress: `0x${string}`,
  poolKey: PoolKeyForQuote,
  zeroForOne: boolean,
  amountOut: bigint,
): Promise<QuoteResult> {
  const params = quoteParams(poolKey, zeroForOne, amountOut);
  return executeQuote(
    publicClient,
    quoterAddress,
    "quoteExactOutputSingle",
    params,
  );
}
