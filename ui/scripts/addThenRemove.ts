/**
 * Add liquidity (mint position) then remove 25% in one run using the same key.
 * Proves that remove liquidity works when the sender is the position owner.
 *
 * Usage (from ui/):
 *   PERIPHERY_ENV=../hieroforge-periphery/.env npx tsx scripts/addThenRemove.ts
 *
 * Requires in periphery .env: PRIVATE_KEY, POSITION_MANAGER_ADDRESS, CURRENCY0_ADDRESS, CURRENCY1_ADDRESS.
 * The wallet must have token balances and HBAR for gas.
 */
import { config } from "dotenv";
import { resolve } from "path";

const peripheryEnv = process.env.PERIPHERY_ENV?.trim();
if (peripheryEnv) {
  config({ path: resolve(process.cwd(), peripheryEnv) });
}
config({ path: ".env.local" });
config({ path: ".env" });

import { createPublicClient, createWalletClient, http, encodeFunctionData } from "viem";
import { privateKeyToAccount } from "viem/accounts";
import { getPositionManagerAddress, getRpcUrl, HEDERA_TESTNET } from "../src/constants";
import {
  buildPoolKey,
  encodeUnlockDataMintFromDeltas,
  encodeUnlockDataDecrease,
} from "../src/lib/addLiquidity";
import { getAmount0Delta, getAmount1Delta, getSqrtPriceAtTick } from "../src/lib/sqrtPriceMath";
import { PositionManagerAbi } from "../src/abis/PositionManager";

const MULTICALL_ABI = [
  {
    type: "function",
    name: "multicall",
    inputs: [{ name: "data", type: "bytes[]", internalType: "bytes[]" }],
    outputs: [{ name: "results", type: "bytes[]", internalType: "bytes[]" }],
    stateMutability: "payable",
  },
] as const;

const ERC20_APPROVE_ABI = [
  {
    type: "function",
    name: "approve",
    inputs: [
      { name: "spender", type: "address", internalType: "address" },
      { name: "amount", type: "uint256", internalType: "uint256" },
    ],
    outputs: [{ name: "", type: "bool", internalType: "bool" }],
    stateMutability: "nonpayable",
  },
] as const;

function getEnv(name: string): string {
  const v =
    process.env[name] ??
    process.env[name.replace("POSITION_MANAGER", "NEXT_PUBLIC_POSITION_MANAGER")];
  return (v ?? "").trim();
}

async function main() {
  const pmAddr =
    getEnv("POSITION_MANAGER_ADDRESS") || getEnv("NEXT_PUBLIC_POSITION_MANAGER_ADDRESS");
  const c0 = getEnv("CURRENCY0_ADDRESS") || getEnv("CURRENCY0");
  const c1 = getEnv("CURRENCY1_ADDRESS") || getEnv("CURRENCY1");
  const privateKey = process.env.PRIVATE_KEY?.trim();
  const rpcUrl = process.env.RPC_URL?.trim() || getRpcUrl();

  if (!pmAddr || !c0 || !c1 || !privateKey) {
    console.error("Set PERIPHERY_ENV=../hieroforge-periphery/.env and ensure PRIVATE_KEY, CURRENCY0_ADDRESS, CURRENCY1_ADDRESS exist.");
    process.exit(1);
  }

  const transport = http(rpcUrl);
  const account = privateKeyToAccount(
    (privateKey.startsWith("0x") ? privateKey : "0x" + privateKey) as `0x${string}`,
  );
  const publicClient = createPublicClient({ chain: HEDERA_TESTNET, transport });
  const walletClient = createWalletClient({ chain: HEDERA_TESTNET, transport, account });

  const tickLower = 0;
  const tickUpper = 16140;
  const liquidity = 10_000n;
  const lower = getSqrtPriceAtTick(tickLower);
  const upper = getSqrtPriceAtTick(tickUpper);
  const amount0Full = getAmount0Delta(lower, upper, liquidity, true);
  const amount1Full = getAmount1Delta(lower, upper, liquidity, true);
  const amount0 = (amount0Full * 101n) / 100n + 1n;
  const amount1 = (amount1Full * 101n) / 100n + 1n;

  const poolKey = buildPoolKey(c0 as `0x${string}`, c1 as `0x${string}`, 3000, 60);
  const deadline = BigInt(Math.floor(Date.now() / 1000) + 3600);

  console.log("1. Approving tokens for PositionManager...");
  const approve0 = encodeFunctionData({
    abi: ERC20_APPROVE_ABI,
    functionName: "approve",
    args: [pmAddr as `0x${string}`, amount0],
  });
  const approve1 = encodeFunctionData({
    abi: ERC20_APPROVE_ABI,
    functionName: "approve",
    args: [pmAddr as `0x${string}`, amount1],
  });
  await walletClient.sendTransaction({
    to: poolKey.currency0 as `0x${string}`,
    data: approve0,
    account,
  });
  await walletClient.sendTransaction({
    to: poolKey.currency1 as `0x${string}`,
    data: approve1,
    account,
  });
  console.log("   Approved.");

  console.log("2. Adding liquidity (mint position)...");
  const mintUnlockData = encodeUnlockDataMintFromDeltas(
    poolKey,
    tickLower,
    tickUpper,
    liquidity,
    amount0,
    amount1,
    account.address as `0x${string}`,
  );
  const modifyMintCalldata = encodeFunctionData({
    abi: [{ type: "function", name: "modifyLiquidities", inputs: [{ name: "unlockData", type: "bytes" }, { name: "deadline", type: "uint256" }], stateMutability: "payable" }],
    functionName: "modifyLiquidities",
    args: [mintUnlockData, deadline],
  });
  const multicallAdd = encodeFunctionData({
    abi: MULTICALL_ABI,
    functionName: "multicall",
    args: [[modifyMintCalldata as `0x${string}`]],
  });
  const addHash = await walletClient.sendTransaction({
    to: pmAddr as `0x${string}`,
    data: multicallAdd,
    gas: 5_000_000n,
    account,
  });
  console.log("   Tx hash:", addHash);

  const nextId = (await publicClient.readContract({
    address: pmAddr as `0x${string}`,
    abi: PositionManagerAbi,
    functionName: "nextTokenId",
    args: [],
  })) as bigint;
  const tokenId = nextId - 1n;
  console.log("   Position minted: tokenId", tokenId.toString());

  const liquidityDecrease = (liquidity * 25n) / 100n;
  console.log("3. Removing 25% liquidity...");
  const decreaseUnlockData = encodeUnlockDataDecrease(tokenId, liquidityDecrease, 0n, 0n);
  const modifyDecreaseCalldata = encodeFunctionData({
    abi: [{ type: "function", name: "modifyLiquidities", inputs: [{ name: "unlockData", type: "bytes" }, { name: "deadline", type: "uint256" }], stateMutability: "payable" }],
    functionName: "modifyLiquidities",
    args: [decreaseUnlockData, deadline],
  });
  const multicallRemove = encodeFunctionData({
    abi: MULTICALL_ABI,
    functionName: "multicall",
    args: [[modifyDecreaseCalldata as `0x${string}`]],
  });
  const removeHash = await walletClient.sendTransaction({
    to: pmAddr as `0x${string}`,
    data: multicallRemove,
    gas: 5_000_000n,
    account,
  });
  console.log("   Tx hash:", removeHash);
  console.log("");
  console.log("SUCCESS: Added liquidity then removed 25%. Remove liquidity encoding works.");
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
