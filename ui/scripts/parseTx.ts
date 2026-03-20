/**
 * Parse a Hedera transaction (add liquidity or any contract call) from the mirror node.
 * Prints: transaction_id, caller (from), contract (to), and for add-liquidity: minted tokenId.
 *
 * Usage:
 *   npx tsx scripts/parseTx.ts 1773717413.691946978
 *   npx tsx scripts/parseTx.ts 0.0.6651398-1773717405-295779692
 *
 * Arg: consensus timestamp (e.g. 1773717413.691946978) or full transaction_id (0.0.X-s-n).
 */
const MIRROR = "https://testnet.mirrornode.hedera.com";

async function main() {
  const arg = process.argv[2];
  if (!arg) {
    console.error("Usage: npx tsx scripts/parseTx.ts <timestamp-or-transaction-id>");
    process.exit(1);
  }

  let mirrorTxId: string;
  if (arg.includes("-") && /^0\.0\.\d+-\d+-\d+$/.test(arg)) {
    mirrorTxId = arg;
  } else {
    const res = await fetch(
      `${MIRROR}/api/v1/transactions?timestamp=${arg}&limit=1`,
    );
    if (!res.ok) {
      console.error("Mirror node error:", res.status);
      process.exit(1);
    }
    const data = await res.json();
    const tx = data?.transactions?.[0];
    if (!tx) {
      console.error("No transaction found for timestamp:", arg);
      process.exit(1);
    }
    mirrorTxId = tx.transaction_id;
    console.log("Transaction ID:", mirrorTxId);
    console.log("Result:", tx.result);
    console.log("Name:", tx.name);
  }

  const res = await fetch(
    `${MIRROR}/api/v1/contracts/results/${mirrorTxId}`,
  );
  if (!res.ok) {
    console.error("Contract result not found:", res.status);
    process.exit(1);
  }
  const cr = await res.json();

  const from = cr.from;
  const to = cr.to;
  const address = cr.address;
  const result = cr.result ?? cr.status;
  const errorMessage = cr.error_message;

  console.log("");
  console.log("--- Contract result ---");
  console.log("From (caller EVM):", from);
  console.log("To (contract EVM):", to ?? address);
  console.log("Contract address:", address);
  console.log("Result:", result);
  if (errorMessage) console.log("Error message:", errorMessage);

  if (cr.logs?.length) {
    for (const log of cr.logs) {
      const sig = log.topics?.[0];
      const transferSig = "0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef";
      if (sig === transferSig && log.topics?.length >= 4) {
        const tokenIdHex = log.topics[3];
        const tokenId = BigInt(tokenIdHex).toString();
        if (log.address?.toLowerCase() === address?.toLowerCase()) {
          console.log("");
          console.log("--- Position NFT minted (Transfer from PositionManager) ---");
          console.log("Token ID:", tokenId);
          console.log("(Use this token ID in Remove Liquidity.)");
        }
      }
    }
  }

  console.log("");
  if (result === "SUCCESS" && from) {
    const shortFrom = from.slice(0, 10) + "..." + from.slice(-6);
    console.log("--- For Remove Liquidity ---");
    console.log("Owner (from):", from, "→ Use this wallet in HashPack to remove.");
    console.log("PositionManager:", address);
  }
  console.log("");
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});

export {};
