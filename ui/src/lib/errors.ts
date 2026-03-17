/**
 * Normalize unknown errors into user-friendly messages.
 */

export function getErrorMessage(
  err: unknown,
  fallback = "Something went wrong.",
): string {
  if (err == null) return fallback;
  if (typeof err === "string") return err;
  if (err instanceof Error) {
    const msg = (err as { shortMessage?: string }).shortMessage ?? err.message;
    if (msg) return msg;
  }
  const msg = (err as { message?: string })?.message;
  if (typeof msg === "string" && msg) return msg;
  return fallback;
}

/** User rejected the request (e.g. wallet popup cancelled). */
export function isUserRejected(err: unknown): boolean {
  const msg = err instanceof Error ? err.message : String(err ?? "");
  return (
    /user rejected|user denied|rejected the request|cancelled|canceled/i.test(
      msg,
    ) ||
    /denied transaction|transaction was rejected/i.test(msg) ||
    msg.includes("4001") ||
    msg.includes("ACTION_REJECTED")
  );
}

/** Map common contract/RPC errors to friendly messages. */
export function getFriendlyErrorMessage(
  err: unknown,
  context: "quote" | "transaction" | "wallet" | "swap",
): string {
  if (isUserRejected(err)) return "Transaction was cancelled.";
  const raw = getErrorMessage(err, "");
  if (!raw)
    return context === "quote"
      ? "Unable to get quote."
      : context === "wallet"
        ? "Connection failed."
        : context === "swap"
          ? "Swap failed."
          : "Transaction failed.";

  // Contract / revert patterns
  if (/insufficient liquidity|not enough liquidity/i.test(raw))
    return "Not enough liquidity for this amount. Try a smaller amount or add liquidity.";
  if (/pool does not exist|pool not found|invalid pool/i.test(raw))
    return "Pool not found. Create the pool first or check token addresses.";
  if (/slippage|slippage tolerance|amount out of range/i.test(raw))
    return "Price moved. Try again or increase slippage.";
  if (/deadline|expired/i.test(raw))
    return "Transaction expired. Please try again.";
  if (/insufficient funds|balance too low|exceeds balance/i.test(raw))
    return "Insufficient balance.";
  if (/nonce|replacement fee/i.test(raw))
    return "Transaction conflict. Please try again.";
  if (/incorrect request/i.test(raw))
    return "Hedera RPC rejected the request. This may be a gas estimation issue — please try again.";
  if (/network|fetch|timeout|econnrefused/i.test(raw))
    return "Network error. Check your connection and try again.";
  if (/wrong network|chain mismatch|unsupported chain/i.test(raw))
    return "Wrong network. Please switch to Hedera Testnet.";
  // Unauthorized (0x82b42900) = not owner or approved for the position NFT
  if (raw.includes("0x82b42900") && context === "transaction")
    return "Connect the wallet that owns this position (the one that added liquidity), or use an approved operator.";
  if (
    /transaction failed on-chain|contract_revert_executed|revert/i.test(raw) &&
    context === "transaction"
  )
    return "Transaction reverted. Make sure you're connected with the wallet that owns this position (the one that added liquidity).";

  return raw.length > 120 ? `${raw.slice(0, 117)}...` : raw;
}
