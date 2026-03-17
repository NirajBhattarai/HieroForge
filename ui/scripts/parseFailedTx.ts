/**
 * Fetch a (possibly failed) transaction's contract result from Hedera mirror node
 * and print the error_message (revert reason).
 *
 * Usage:
 *   npx tsx scripts/parseFailedTx.ts <transaction_id_or_hash>
 *   npx tsx scripts/parseFailedTx.ts 0.0.6651398-1773718548-174954366
 *
 * If the tx failed with CONTRACT_REVERT_EXECUTED, error_message will show the reason.
 */
const MIRROR = "https://testnet.mirrornode.hedera.com";

async function main() {
  const txId = process.argv[2]?.trim();
  if (!txId) {
    console.error("Usage: npx tsx scripts/parseFailedTx.ts <transaction_id_or_hash>");
    process.exit(1);
  }

  const res = await fetch(
    `${MIRROR}/api/v1/contracts/results/${txId}`,
  );
  if (!res.ok) {
    console.error("Contract result not found:", res.status, await res.text());
    process.exit(1);
  }
  const cr = await res.json();

  console.log("Transaction:", txId);
  console.log("Result:", cr.result ?? cr.status);
  console.log("From:", cr.from);
  console.log("To:", cr.to ?? cr.address);
  if (cr.error_message) {
    console.log("");
    console.log("--- Revert reason (error_message) ---");
    console.log(cr.error_message);
  } else {
    console.log("");
    console.log("No error_message (tx may have succeeded or reverted without message).");
  }
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
