/**
 * Print the on-chain owner of a position NFT (ERC721 ownerOf) from the Position Manager.
 * Use this to verify who can remove liquidity: the transaction sender must be this owner.
 *
 * Usage:
 *   npx tsx scripts/positionOwner.ts [tokenId]
 *   TOKEN_ID=1 npx tsx scripts/positionOwner.ts
 *
 * Loads .env and PERIPHERY_ENV like removeLiquidity.ts.
 */
import { config } from "dotenv";
import { resolve } from "path";

const peripheryEnv = process.env.PERIPHERY_ENV?.trim();
if (peripheryEnv) {
  config({ path: resolve(process.cwd(), peripheryEnv) });
}
config({ path: ".env.local" });
config({ path: ".env" });

import { createPublicClient, http } from "viem";
import { getPositionManagerAddress, getRpcUrl } from "../src/constants";
import { PositionManagerAbi } from "../src/abis/PositionManager";

function getEnv(name: string): string {
  const v =
    process.env[name] ??
    process.env[name.replace("POSITION_MANAGER", "NEXT_PUBLIC_POSITION_MANAGER")];
  return (v ?? "").trim();
}

async function main() {
  const tokenIdRaw = process.argv[2] ?? process.env.TOKEN_ID ?? "1";
  const tokenId = BigInt(tokenIdRaw);
  const pmAddr = getEnv("POSITION_MANAGER_ADDRESS") || getEnv("NEXT_PUBLIC_POSITION_MANAGER_ADDRESS");
  if (!pmAddr) {
    console.error("Set POSITION_MANAGER_ADDRESS or NEXT_PUBLIC_POSITION_MANAGER_ADDRESS");
    process.exit(1);
  }

  const client = createPublicClient({
    transport: http(getRpcUrl()),
  });

  const owner = await client.readContract({
    address: pmAddr as `0x${string}`,
    abi: PositionManagerAbi,
    functionName: "ownerOf",
    args: [tokenId],
  });

  const ownerLower = (owner as string).toLowerCase();
  // Long-zero form: 0x0000...0NNN → Hedera account 0.0.NNN
  const longZeroMatch = ownerLower.match(/^0x0+([0-9a-f]+)$/);
  const hederaAccount = longZeroMatch
    ? `0.0.${parseInt(longZeroMatch[1], 16)}`
    : null;

  console.log("Position Manager:", pmAddr);
  console.log("Token ID:", tokenId.toString());
  console.log("");
  console.log("On-chain owner (who can remove liquidity):");
  console.log("  EVM address:", owner as string);
  if (hederaAccount) {
    console.log("  Hedera account (if long-zero):", hederaAccount);
  }
  console.log("");
  console.log("When you remove liquidity from the UI, the wallet that signs the tx must have this EVM address as the transaction sender. If you see Unauthorized, your connected wallet's sender address does not match the above.");
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
