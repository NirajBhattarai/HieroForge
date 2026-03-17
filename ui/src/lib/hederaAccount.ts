/**
 * Resolve the EVM address that Hedera uses as msg.sender for a given account.
 * ECDSA accounts have an evm_address (alias); id-only accounts use long-zero.
 * Using this as the position owner when minting ensures remove/decrease works
 * (same address will be msg.sender when the user sends the remove tx).
 */

const MIRROR_NODE_BY_NETWORK: Record<string, string> = {
  testnet: "https://testnet.mirrornode.hedera.com",
  mainnet: "https://mainnet.mirrornode.hedera.com",
  previewnet: "https://previewnet.mirrornode.hedera.com",
};

/** Hedera accountId (0.0.X) → long-zero EVM address. */
export function accountIdToLongZero(accountId: string | null): string | null {
  if (!accountId) return null;
  const m = String(accountId).trim().match(/^(\d+)\.(\d+)\.(\d+)$/);
  if (!m) return null;
  return ("0x" + BigInt(m[3]!).toString(16).padStart(40, "0")).toLowerCase();
}

/**
 * Fetch the account's evm_address from the mirror node (ECDSA alias).
 * When present, Hedera uses this as msg.sender in contract calls, not the long-zero.
 * Returns null on failure or if the account has no evm_address.
 */
export async function getAccountEvmAddress(
  accountId: string,
  network: string = "testnet"
): Promise<string | null> {
  const base = MIRROR_NODE_BY_NETWORK[network] ?? MIRROR_NODE_BY_NETWORK.testnet;
  const url = `${base}/api/v1/accounts/${encodeURIComponent(accountId.trim())}?transactions=false`;
  try {
    const res = await fetch(url);
    if (!res.ok) return null;
    const data = await res.json();
    const evm = data?.evm_address;
    if (typeof evm === "string" && /^0x[0-9a-fA-F]{40}$/.test(evm)) {
      return evm.toLowerCase();
    }
    return null;
  } catch {
    return null;
  }
}

/**
 * Best EVM address to use as position owner so that the same wallet can remove later.
 * Prefers the account's evm_address (ECDSA alias) so msg.sender matches on remove;
 * falls back to long-zero if the mirror node doesn't return evm_address.
 */
export async function getPositionOwnerAddress(
  accountId: string,
  network: string = "testnet"
): Promise<string | null> {
  const evm = await getAccountEvmAddress(accountId, network);
  if (evm) return evm;
  return accountIdToLongZero(accountId);
}
