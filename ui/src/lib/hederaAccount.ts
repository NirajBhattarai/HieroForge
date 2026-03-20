import { AccountId } from "@hashgraph/sdk";

const MIRROR_NODE_BY_NETWORK: Record<string, string> = {
  testnet: "https://testnet.mirrornode.hedera.com",
  mainnet: "https://mainnet.mirrornode.hedera.com",
  previewnet: "https://previewnet.mirrornode.hedera.com",
};

/** `0.0.n` (optional Hedera checksum suffix); excludes alias-style third segments. */
const NUMERIC_HEDERA_ACCOUNT_ID = /^\d+\.\d+\.\d+(?:-[a-z]{5})?$/i;

/**
 * Hedera account id (e.g. from HashPack: `0.0.n`, optional checksum) → long-zero EVM address.
 * Uses @hashgraph/sdk encoding so shard/realm/num map to Solidity address the same way as the network.
 */
export function accountIdToLongZero(accountId: string | null): string | null {
  if (!accountId) return null;
  const t = accountId.trim();
  if (!NUMERIC_HEDERA_ACCOUNT_ID.test(t)) return null;
  try {
    const raw = AccountId.fromString(t).toSolidityAddress();
    const hex = raw.startsWith("0x") ? raw.slice(2) : raw;
    if (!/^[0-9a-fA-F]{40}$/.test(hex)) return null;
    return ("0x" + hex.toLowerCase()) as `0x${string}`;
  } catch {
    return null;
  }
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
