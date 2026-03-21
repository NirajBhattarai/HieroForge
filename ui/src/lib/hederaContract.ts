import {
  ContractId,
  ContractExecuteTransaction,
  AccountId,
  Hbar,
} from "@hashgraph/sdk";
import { encodeFunctionData, type Abi } from "viem";
import type { HashConnect } from "hashconnect";

/**
 * Execute a smart contract function on Hedera using the HashConnect signer (HashPack wallet).
 *
 * Uses the Hedera SDK's ContractExecuteTransaction with the signer-based flow:
 *   freezeWithSigner → executeWithSigner
 * This ensures the transaction is properly serialized for WalletConnect
 * and the HashPack modal closes after approval.
 */
export async function hederaContractExecute(params: {
  hashConnect: HashConnect;
  accountId: string;
  contractId: string;
  abi: Abi | readonly unknown[];
  functionName: string;
  args: readonly unknown[];
  gas: number;
  payableAmount?: number;
}): Promise<string> {
  const {
    hashConnect,
    accountId,
    contractId,
    abi,
    functionName,
    args,
    gas,
    payableAmount,
  } = params;

  // 1. ABI-encode the function call using viem (reliable, well-tested)
  const calldata = encodeFunctionData({
    abi: abi as Abi,
    functionName,
    args: [...args],
  });

  // Strip '0x' prefix — Hedera SDK expects raw bytes
  const calldataBytes = Buffer.from(calldata.slice(2), "hex");

  // 2. Build the ContractExecuteTransaction
  const senderAccountId = AccountId.fromString(accountId);

  // Convert EVM address (0x...) to Hedera ContractId
  const cId = contractId.startsWith("0x")
    ? ContractId.fromEvmAddress(0, 0, contractId)
    : ContractId.fromString(contractId);

  const tx = new ContractExecuteTransaction()
    .setContractId(cId)
    .setGas(gas)
    .setFunctionParameters(calldataBytes)
    .setMaxTransactionFee(new Hbar(30));

  if (payableAmount && payableAmount > 0) {
    tx.setPayableAmount(new Hbar(payableAmount));
  }

  // 3. Get signer from HashConnect — the signer handles freezing, signing, and submitting
  // Cast through unknown to bridge type mismatch between top-level @hashgraph/sdk and hashconnect's bundled copy
  const signer = hashConnect.getSigner(
    senderAccountId as unknown as Parameters<typeof hashConnect.getSigner>[0],
  );

  // 4. Freeze the transaction with the signer (sets nodeAccountIds + transactionId)
  const frozenTx = await tx.freezeWithSigner(signer as any);

  // 5. Execute via signer — opens HashPack for approval, waits for completion, modal closes
  const txResponse = await frozenTx.executeWithSigner(signer as any);

  // 6. Get the transaction ID for logging/UI
  const txId =
    txResponse?.transactionId?.toString() ?? `hedera-tx-${Date.now()}`;
  console.log("[hederaContractExecute] tx submitted:", txId);

  // 7. Poll mirror node to confirm the transaction actually succeeded
  await waitForTransactionSuccess(txId);
  console.log("[hederaContractExecute] tx confirmed SUCCESS:", txId);

  return txId;
}

/**
 * Execute an ERC20 transfer via Hedera SDK with the signer-based flow.
 * For HTS tokens, this uses ContractExecuteTransaction with the transfer(address,uint256) selector.
 */
export async function hederaTokenTransfer(params: {
  hashConnect: HashConnect;
  accountId: string;
  tokenAddress: string;
  to: string;
  amount: bigint;
  gas?: number;
}): Promise<void> {
  const {
    hashConnect,
    accountId,
    tokenAddress,
    to,
    amount,
    gas = 1_200_000,
  } = params;

  // ERC20 transfer(address,uint256) function selector + params
  const { encodeFunctionData: encode } = await import("viem");
  const calldata = encode({
    abi: [
      {
        type: "function",
        name: "transfer",
        inputs: [
          { name: "to", type: "address" },
          { name: "amount", type: "uint256" },
        ],
        outputs: [{ name: "", type: "bool" }],
        stateMutability: "nonpayable",
      },
    ] as const,
    functionName: "transfer",
    args: [to as `0x${string}`, amount],
  });

  const calldataBytes = Buffer.from(calldata.slice(2), "hex");
  const senderAccountId = AccountId.fromString(accountId);
  const cId = tokenAddress.startsWith("0x")
    ? ContractId.fromEvmAddress(0, 0, tokenAddress)
    : ContractId.fromString(tokenAddress);

  const tx = new ContractExecuteTransaction()
    .setContractId(cId)
    .setGas(gas)
    .setFunctionParameters(calldataBytes)
    .setMaxTransactionFee(new Hbar(10));

  // Get signer from HashConnect
  const signer = hashConnect.getSigner(
    senderAccountId as unknown as Parameters<typeof hashConnect.getSigner>[0],
  );

  // Freeze → execute via signer (proper WalletConnect lifecycle)
  const frozenTx = await tx.freezeWithSigner(signer as any);
  const txResponse = await frozenTx.executeWithSigner(signer as any);

  const txId =
    txResponse?.transactionId?.toString() ?? `hedera-tx-${Date.now()}`;
  console.log("[hederaTokenTransfer] tx submitted:", txId);

  // Verify the transfer actually succeeded on-chain (detect CONTRACT_REVERT_EXECUTED)
  await waitForTransactionSuccess(txId);
  console.log("[hederaTokenTransfer] tx confirmed SUCCESS:", txId);
}

/**
 * ERC20 approve(spender, amount) for HashPack — required when PositionManager settles
 * via transferFrom (e.g. MINT_FROM_DELTAS + SETTLE_PAIR). Not used for plain MINT + transfer-to-PM.
 */
export async function hederaTokenApprove(params: {
  hashConnect: HashConnect;
  accountId: string;
  tokenAddress: string;
  spender: string;
  amount: bigint;
  gas?: number;
}): Promise<void> {
  const {
    hashConnect,
    accountId,
    tokenAddress,
    spender,
    amount,
    gas = 1_200_000,
  } = params;

  const { encodeFunctionData: encode } = await import("viem");
  const calldata = encode({
    abi: [
      {
        type: "function",
        name: "approve",
        inputs: [
          { name: "spender", type: "address" },
          { name: "amount", type: "uint256" },
        ],
        outputs: [{ name: "", type: "bool" }],
        stateMutability: "nonpayable",
      },
    ] as const,
    functionName: "approve",
    args: [spender as `0x${string}`, amount],
  });

  const calldataBytes = Buffer.from(calldata.slice(2), "hex");
  const senderAccountId = AccountId.fromString(accountId);
  const cId = tokenAddress.startsWith("0x")
    ? ContractId.fromEvmAddress(0, 0, tokenAddress)
    : ContractId.fromString(tokenAddress);

  const tx = new ContractExecuteTransaction()
    .setContractId(cId)
    .setGas(gas)
    .setFunctionParameters(calldataBytes)
    .setMaxTransactionFee(new Hbar(10));

  const signer = hashConnect.getSigner(
    senderAccountId as unknown as Parameters<typeof hashConnect.getSigner>[0],
  );
  const frozenTx = await tx.freezeWithSigner(signer as any);
  const txResponse = await frozenTx.executeWithSigner(signer as any);
  const txId =
    txResponse?.transactionId?.toString() ?? `hedera-tx-${Date.now()}`;
  console.log("[hederaTokenApprove] tx submitted:", txId);
  await waitForTransactionSuccess(txId);
  console.log("[hederaTokenApprove] tx confirmed SUCCESS:", txId);
}

/**
 * Execute a multicall on a contract via Hedera SDK.
 * Encodes multicall(bytes[] data) where each entry is a pre-encoded function calldata.
 * This is used by PositionManager to atomically initializePool + modifyLiquidities in one tx.
 */
export async function hederaContractMulticall(params: {
  hashConnect: HashConnect;
  accountId: string;
  contractId: string;
  calls: `0x${string}`[];
  gas: number;
  payableAmount?: number;
}): Promise<string> {
  const { hashConnect, accountId, contractId, calls, gas, payableAmount } =
    params;

  // Encode multicall(bytes[] data) — selector 0xac9650d8
  const calldata = encodeFunctionData({
    abi: [
      {
        type: "function",
        name: "multicall",
        inputs: [{ name: "data", type: "bytes[]", internalType: "bytes[]" }],
        outputs: [
          { name: "results", type: "bytes[]", internalType: "bytes[]" },
        ],
        stateMutability: "payable",
      },
    ] as Abi,
    functionName: "multicall",
    args: [calls],
  });

  const calldataBytes = Buffer.from(calldata.slice(2), "hex");
  const senderAccountId = AccountId.fromString(accountId);
  const cId = contractId.startsWith("0x")
    ? ContractId.fromEvmAddress(0, 0, contractId)
    : ContractId.fromString(contractId);

  const tx = new ContractExecuteTransaction()
    .setContractId(cId)
    .setGas(gas)
    .setFunctionParameters(calldataBytes)
    .setMaxTransactionFee(new Hbar(30));

  if (payableAmount && payableAmount > 0) {
    tx.setPayableAmount(new Hbar(payableAmount));
  }

  const signer = hashConnect.getSigner(
    senderAccountId as unknown as Parameters<typeof hashConnect.getSigner>[0],
  );

  const frozenTx = await tx.freezeWithSigner(signer as any);
  const txResponse = await frozenTx.executeWithSigner(signer as any);

  const txId =
    txResponse?.transactionId?.toString() ?? `hedera-tx-${Date.now()}`;
  console.log("[hederaContractMulticall] tx submitted:", txId);

  // Verify the multicall actually succeeded on-chain
  await waitForTransactionSuccess(txId);
  console.log("[hederaContractMulticall] tx confirmed SUCCESS:", txId);

  return txId;
}

const MIRROR_NODE = "https://testnet.mirrornode.hedera.com";

/**
 * Poll the Hedera mirror node until the transaction reaches consensus,
 * then check if it succeeded. Throws if the transaction failed or timed out.
 *
 * Hedera transaction IDs look like "0.0.12345@1234567890.123456789"
 * Mirror node expects the format "0.0.12345-1234567890-123456789"
 */
async function waitForTransactionSuccess(
  txId: string,
  maxAttempts = 20,
  intervalMs = 3000,
): Promise<void> {
  // Convert SDK txId format "0.0.X@seconds.nanos" → mirror node format "0.0.X-seconds-nanos"
  const atIdx = txId.indexOf("@");
  if (atIdx === -1) {
    // Can't verify without a valid transaction ID format
    console.warn(
      "[waitForTransactionSuccess] Non-standard txId format, skipping verification:",
      txId,
    );
    return;
  }
  const accountPart = txId.substring(0, atIdx); // "0.0.X"
  const timestampPart = txId.substring(atIdx + 1); // "seconds.nanos"
  const mirrorTxId = `${accountPart}-${timestampPart.replace(".", "-")}`;

  for (let attempt = 0; attempt < maxAttempts; attempt++) {
    try {
      const res = await fetch(
        `${MIRROR_NODE}/api/v1/transactions/${mirrorTxId}`,
      );
      if (res.status === 404) {
        // Transaction not yet indexed — wait and retry
        await new Promise((r) => setTimeout(r, intervalMs));
        continue;
      }
      if (!res.ok) {
        await new Promise((r) => setTimeout(r, intervalMs));
        continue;
      }
      const data = await res.json();
      const transactions = data?.transactions;
      if (!transactions || transactions.length === 0) {
        await new Promise((r) => setTimeout(r, intervalMs));
        continue;
      }
      const result = transactions[0].result;
      if (result === "SUCCESS") {
        return; // Transaction confirmed successful
      }
      // Transaction reached consensus but failed — fetch contract revert reason if any
      let revertDetail = result;
      try {
        const contractRes = await fetch(
          `${MIRROR_NODE}/api/v1/contracts/results/${mirrorTxId}`,
        );
        if (contractRes.ok) {
          const cr = await contractRes.json();
          if (cr?.error_message) {
            revertDetail = `${result}: ${cr.error_message}`;
          }
        }
      } catch {
        // ignore
      }
      throw new Error(`Transaction failed on-chain: ${revertDetail}`);
    } catch (err) {
      // Re-throw our own errors (transaction failures)
      if (
        err instanceof Error &&
        err.message.startsWith("Transaction failed")
      ) {
        throw err;
      }
      // Network errors — wait and retry
      await new Promise((r) => setTimeout(r, intervalMs));
    }
  }
  throw new Error(
    "Transaction confirmation timed out — check HashScan for status",
  );
}
