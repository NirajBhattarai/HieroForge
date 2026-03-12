import {
  ContractId,
  ContractExecuteTransaction,
  AccountId,
  Hbar,
} from '@hashgraph/sdk'
import { encodeFunctionData, type Abi } from 'viem'
import type { HashConnect } from 'hashconnect'

/**
 * Execute a smart contract function on Hedera using the HashConnect signer (HashPack wallet).
 *
 * Uses the Hedera SDK's ContractExecuteTransaction with the signer-based flow:
 *   freezeWithSigner → executeWithSigner
 * This ensures the transaction is properly serialized for WalletConnect
 * and the HashPack modal closes after approval.
 */
export async function hederaContractExecute(params: {
  hashConnect: HashConnect
  accountId: string
  contractId: string
  abi: Abi | readonly unknown[]
  functionName: string
  args: readonly unknown[]
  gas: number
  payableAmount?: number
}): Promise<string> {
  const { hashConnect, accountId, contractId, abi, functionName, args, gas, payableAmount } = params

  // 1. ABI-encode the function call using viem (reliable, well-tested)
  const calldata = encodeFunctionData({
    abi: abi as Abi,
    functionName,
    args: [...args],
  })

  // Strip '0x' prefix — Hedera SDK expects raw bytes
  const calldataBytes = Buffer.from(calldata.slice(2), 'hex')

  // 2. Build the ContractExecuteTransaction
  const senderAccountId = AccountId.fromString(accountId)

  // Convert EVM address (0x...) to Hedera ContractId
  const cId = contractId.startsWith('0x')
    ? ContractId.fromEvmAddress(0, 0, contractId)
    : ContractId.fromString(contractId)

  const tx = new ContractExecuteTransaction()
    .setContractId(cId)
    .setGas(gas)
    .setFunctionParameters(calldataBytes)
    .setMaxTransactionFee(new Hbar(30))

  if (payableAmount && payableAmount > 0) {
    tx.setPayableAmount(new Hbar(payableAmount))
  }

  // 3. Get signer from HashConnect — the signer handles freezing, signing, and submitting
  // Cast through unknown to bridge type mismatch between top-level @hashgraph/sdk and hashconnect's bundled copy
  const signer = hashConnect.getSigner(
    senderAccountId as unknown as Parameters<typeof hashConnect.getSigner>[0],
  )

  // 4. Freeze the transaction with the signer (sets nodeAccountIds + transactionId)
  const frozenTx = await tx.freezeWithSigner(signer as any)

  // 5. Execute via signer — opens HashPack for approval, waits for completion, modal closes
  const txResponse = await frozenTx.executeWithSigner(signer as any)

  // 6. Get the transaction ID for logging/UI
  const txId = txResponse?.transactionId?.toString() ?? `hedera-tx-${Date.now()}`
  console.log('[hederaContractExecute] tx completed:', txId)

  return txId
}

/**
 * Execute an ERC20 transfer via Hedera SDK with the signer-based flow.
 * For HTS tokens, this uses ContractExecuteTransaction with the transfer(address,uint256) selector.
 */
export async function hederaTokenTransfer(params: {
  hashConnect: HashConnect
  accountId: string
  tokenAddress: string
  to: string
  amount: bigint
  gas?: number
}): Promise<void> {
  const { hashConnect, accountId, tokenAddress, to, amount, gas = 1_200_000 } = params

  // ERC20 transfer(address,uint256) function selector + params
  const { encodeFunctionData: encode } = await import('viem')
  const calldata = encode({
    abi: [
      {
        type: 'function',
        name: 'transfer',
        inputs: [
          { name: 'to', type: 'address' },
          { name: 'amount', type: 'uint256' },
        ],
        outputs: [{ name: '', type: 'bool' }],
        stateMutability: 'nonpayable',
      },
    ] as const,
    functionName: 'transfer',
    args: [to as `0x${string}`, amount],
  })

  const calldataBytes = Buffer.from(calldata.slice(2), 'hex')
  const senderAccountId = AccountId.fromString(accountId)
  const cId = tokenAddress.startsWith('0x')
    ? ContractId.fromEvmAddress(0, 0, tokenAddress)
    : ContractId.fromString(tokenAddress)

  const tx = new ContractExecuteTransaction()
    .setContractId(cId)
    .setGas(gas)
    .setFunctionParameters(calldataBytes)
    .setMaxTransactionFee(new Hbar(10))

  // Get signer from HashConnect
  const signer = hashConnect.getSigner(
    senderAccountId as unknown as Parameters<typeof hashConnect.getSigner>[0],
  )

  // Freeze → execute via signer (proper WalletConnect lifecycle)
  const frozenTx = await tx.freezeWithSigner(signer as any)
  const txResponse = await frozenTx.executeWithSigner(signer as any)
  console.log('[hederaTokenTransfer] tx completed:', txResponse?.transactionId?.toString())
}

/**
 * Execute a multicall on a contract via Hedera SDK.
 * Encodes multicall(bytes[] data) where each entry is a pre-encoded function calldata.
 * This is used by PositionManager to atomically initializePool + modifyLiquidities in one tx.
 */
export async function hederaContractMulticall(params: {
  hashConnect: HashConnect
  accountId: string
  contractId: string
  calls: `0x${string}`[]
  gas: number
  payableAmount?: number
}): Promise<string> {
  const { hashConnect, accountId, contractId, calls, gas, payableAmount } = params

  // Encode multicall(bytes[] data) — selector 0xac9650d8
  const calldata = encodeFunctionData({
    abi: [
      {
        type: 'function',
        name: 'multicall',
        inputs: [{ name: 'data', type: 'bytes[]', internalType: 'bytes[]' }],
        outputs: [{ name: 'results', type: 'bytes[]', internalType: 'bytes[]' }],
        stateMutability: 'payable',
      },
    ] as Abi,
    functionName: 'multicall',
    args: [calls],
  })

  const calldataBytes = Buffer.from(calldata.slice(2), 'hex')
  const senderAccountId = AccountId.fromString(accountId)
  const cId = contractId.startsWith('0x')
    ? ContractId.fromEvmAddress(0, 0, contractId)
    : ContractId.fromString(contractId)

  const tx = new ContractExecuteTransaction()
    .setContractId(cId)
    .setGas(gas)
    .setFunctionParameters(calldataBytes)
    .setMaxTransactionFee(new Hbar(30))

  if (payableAmount && payableAmount > 0) {
    tx.setPayableAmount(new Hbar(payableAmount))
  }

  const signer = hashConnect.getSigner(
    senderAccountId as unknown as Parameters<typeof hashConnect.getSigner>[0],
  )

  const frozenTx = await tx.freezeWithSigner(signer as any)
  const txResponse = await frozenTx.executeWithSigner(signer as any)

  const txId = txResponse?.transactionId?.toString() ?? `hedera-tx-${Date.now()}`
  console.log('[hederaContractMulticall] tx completed:', txId)
  return txId
}
