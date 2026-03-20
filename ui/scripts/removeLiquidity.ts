/**
 * Remove liquidity via PositionManager.multicall(modifyLiquidities(...)).
 *
 * Usage:
 *   npx tsx scripts/removeLiquidity.ts
 *
 * Env: POSITION_MANAGER_ADDRESS (or NEXT_PUBLIC_*), TOKEN_ID, optional LIQUIDITY, PERCENT, RPC_URL, PRIVATE_KEY.
 *
 * With periphery credentials (discover positions and remove until success):
 *   PERIPHERY_ENV=../hieroforge-periphery/.env REMOVE_UNTIL_SUCCESS=1 npx tsx scripts/removeLiquidity.ts
 * Or from repo root: cd ui && PERIPHERY_ENV=../hieroforge-periphery/.env REMOVE_UNTIL_SUCCESS=1 npm run remove-liquidity
 */
import { config } from "dotenv";
import { resolve } from "path";

const peripheryEnv = process.env.PERIPHERY_ENV?.trim();
if (peripheryEnv) {
  config({ path: resolve(process.cwd(), peripheryEnv) });
}
config({ path: ".env.local" });
config({ path: ".env" });

import { createPublicClient, createWalletClient, http, encodeFunctionData, type Address } from "viem";
import { privateKeyToAccount } from "viem/accounts";
import { encodeUnlockDataDecrease, encodeUnlockDataBurn } from "../src/lib/addLiquidity";
import { getPositionManagerAddress, getRpcUrl, HEDERA_TESTNET } from "../src/constants";
import { fetchPositionOnChain } from "../src/lib/positionOnChain";
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

const MODIFY_LIQUIDITIES_ABI = [
  {
    type: "function",
    name: "modifyLiquidities",
    inputs: [
      { name: "unlockData", type: "bytes", internalType: "bytes" },
      { name: "deadline", type: "uint256", internalType: "uint256" },
    ],
    outputs: [],
    stateMutability: "payable",
  },
] as const;

function getEnv(name: string): string {
  const v = process.env[name] ?? process.env[name.replace("POSITION_MANAGER", "NEXT_PUBLIC_POSITION_MANAGER")];
  return (v ?? "").trim();
}

async function tryRemoveOne(params: {
  positionManagerAddr: string;
  tokenId: bigint;
  unlockData: `0x${string}`;
  deadline: bigint;
  transport: ReturnType<typeof http>;
  publicClient: ReturnType<typeof createPublicClient>;
  accountAddress?: Address;
  privateKey?: string;
}): Promise<{ success: boolean; hash?: string; error?: string }> {
  const { positionManagerAddr, unlockData, deadline, transport, publicClient, accountAddress, privateKey } = params;
  const modifyCalldata = encodeFunctionData({
    abi: MODIFY_LIQUIDITIES_ABI,
    functionName: "modifyLiquidities",
    args: [unlockData, deadline],
  });
  const multicallCalldata = encodeFunctionData({
    abi: MULTICALL_ABI,
    functionName: "multicall",
    args: [[modifyCalldata as `0x${string}`]],
  });

  const callAccount = accountAddress;
  try {
    await publicClient.call({
      to: positionManagerAddr as Address,
      data: multicallCalldata,
      account: callAccount,
    });
  } catch (err: unknown) {
    const e = err as {
      shortMessage?: string;
      message?: string;
      data?: string | { data?: string };
      cause?: { data?: string; message?: string };
      details?: string;
    };
    let errMsg = e?.shortMessage ?? e?.message ?? String(err);
    const revertData =
      (typeof e?.data === "string" ? e.data : e?.data?.data) ??
      e?.cause?.data;
    if (revertData && typeof revertData === "string") {
      errMsg += ` | revertData: ${revertData.slice(0, 300)}`;
      if (revertData.length >= 10) {
        const selector = revertData.slice(0, 10);
        const known: Record<string, string> = {
          "0x3b99b53d": "SliceOutOfBounds (calldata decode)",
          "0x2d0a3f8e": "NotApproved",
          "0x1e4fbdf7": "PositionNotCleared",
        };
        if (known[selector]) errMsg += ` [${known[selector]}]`;
      }
    }
    console.error("[tryRemoveOne] Full error:", JSON.stringify(err, Object.getOwnPropertyNames(err), 2).slice(0, 800));
    return { success: false, error: errMsg };
  }

  if (!privateKey) return { success: true };

  const pk = (privateKey.startsWith("0x") ? privateKey : "0x" + privateKey) as `0x${string}`;
  const account = privateKeyToAccount(pk);
  const walletClient = createWalletClient({ chain: HEDERA_TESTNET, transport, account });
  try {
    const hash = await walletClient.sendTransaction({
      to: positionManagerAddr as Address,
      data: multicallCalldata,
      gas: 5_000_000n,
      account,
    });
    return { success: true, hash };
  } catch (err: unknown) {
    const e = err as { shortMessage?: string; message?: string };
    return { success: false, error: e?.shortMessage ?? e?.message ?? String(err) };
  }
}

async function runUntilSuccess() {
  const positionManagerAddr = getEnv("POSITION_MANAGER_ADDRESS") || getPositionManagerAddress();
  const rpcUrl = process.env.RPC_URL?.trim() || getRpcUrl();
  const privateKey = process.env.PRIVATE_KEY?.trim();

  if (!positionManagerAddr) {
    console.error("Set POSITION_MANAGER_ADDRESS (or load periphery .env with PERIPHERY_ENV).");
    process.exit(1);
  }
  if (!privateKey) {
    console.error("Set PRIVATE_KEY to send transactions (e.g. from periphery .env).");
    process.exit(1);
  }

  const transport = http(rpcUrl);
  const publicClient = createPublicClient({ chain: HEDERA_TESTNET, transport });
  const accountAddress = privateKeyToAccount(
    (privateKey.startsWith("0x") ? privateKey : "0x" + privateKey) as `0x${string}`,
  ).address as Address;

  const nextId = (await publicClient.readContract({
    address: positionManagerAddr as Address,
    abi: PositionManagerAbi,
    functionName: "nextTokenId",
    args: [],
  })) as bigint;
  const maxTokenId = nextId > 0n ? nextId - 1n : 0n;
  console.log("nextTokenId:", nextId.toString(), "-> try tokenIds 1.." + maxTokenId.toString());

  for (let tid = 1n; tid <= maxTokenId; tid++) {
    const pos = await fetchPositionOnChain(tid.toString(), positionManagerAddr, rpcUrl);
    if (!pos) {
      console.log("Token", tid.toString(), ": no position info, skip");
      continue;
    }
    const liquidity = BigInt(pos.liquidity);
    console.log("Token", tid.toString(), "liquidity:", pos.liquidity);

    const deadline = BigInt(Math.floor(Date.now() / 1000) + 3600);

    if (liquidity === 0n) {
      const unlockData = encodeUnlockDataBurn(tid, 0n, 0n);
      console.log("  Try BURN (0 liquidity)...");
      const r = await tryRemoveOne({
        positionManagerAddr,
        tokenId: tid,
        unlockData,
        deadline,
        transport,
        publicClient,
        accountAddress,
        privateKey,
      });
      if (r.success) {
        console.log("SUCCESS. Tx hash:", r.hash ?? "(simulation only)");
        if (r.hash) process.exit(0);
        continue;
      }
      console.log("  Revert:", r.error);
      continue;
    }

    const percentOptions = [25, 50, 75, 100] as const;
    for (const pct of percentOptions) {
      const toRemove = (liquidity * BigInt(pct)) / 100n;
      if (toRemove <= 0n) continue;
      console.log("  Try DECREASE", pct + "% liquidity:", toRemove.toString());
      const unlockDataDec = encodeUnlockDataDecrease(tid, toRemove, 0n, 0n);
      const rDec = await tryRemoveOne({
        positionManagerAddr,
        tokenId: tid,
        unlockData: unlockDataDec,
        deadline: BigInt(Math.floor(Date.now() / 1000) + 3600),
        transport,
        publicClient,
        accountAddress,
        privateKey,
      });
      if (rDec.success) {
        console.log("SUCCESS (decrease " + pct + "%). Tx hash:", rDec.hash ?? "(simulation only)");
        if (rDec.hash) process.exit(0);
        break;
      }
      console.log("    Revert:", rDec.error);
    }

    console.log("  Try BURN (full position)...");
    const unlockDataBurn = encodeUnlockDataBurn(tid, 0n, 0n);
    const rBurn = await tryRemoveOne({
      positionManagerAddr,
      tokenId: tid,
      unlockData: unlockDataBurn,
      deadline: BigInt(Math.floor(Date.now() / 1000) + 3600),
      transport,
      publicClient,
      accountAddress,
      privateKey,
    });
    if (rBurn.success) {
      console.log("SUCCESS (burn). Tx hash:", rBurn.hash ?? "(simulation only)");
      if (rBurn.hash) process.exit(0);
    } else {
      console.log("  Burn revert:", rBurn.error);
    }
  }

  console.error("No position could be removed. Tried tokenIds 1.." + maxTokenId.toString());
  process.exit(1);
}

async function run() {
  const positionManagerAddr = getEnv("POSITION_MANAGER_ADDRESS") || getPositionManagerAddress();
  const tokenIdRaw = getEnv("TOKEN_ID");
  const liquidityRaw = getEnv("LIQUIDITY");
  const percent = Math.min(100, Math.max(0, Number(process.env.PERCENT ?? "100")));
  const rpcUrl = process.env.RPC_URL?.trim() || getRpcUrl();
  const privateKey = process.env.PRIVATE_KEY?.trim();

  if (!positionManagerAddr || !tokenIdRaw) {
    console.error("Set POSITION_MANAGER_ADDRESS and TOKEN_ID");
    process.exit(1);
  }

  const tokenId = BigInt(tokenIdRaw);
  const deadline = BigInt(Math.floor(Date.now() / 1000) + 3600);
  const transport = http(rpcUrl);
  const publicClient = createPublicClient({ chain: HEDERA_TESTNET, transport });

  let liquidityToRemove: bigint;
  let unlockData: `0x${string}`;
  if (percent === 100) {
    unlockData = encodeUnlockDataBurn(tokenId, 0n, 0n);
    liquidityToRemove = 0n;
    console.log("Mode: BURN_POSITION (100%)");
  } else {
    if (liquidityRaw) {
      liquidityToRemove = BigInt(liquidityRaw);
    } else {
      const pos = await fetchPositionOnChain(tokenIdRaw, positionManagerAddr, rpcUrl);
      if (!pos?.liquidity) {
        console.error("Position not found or no liquidity. Set LIQUIDITY manually (raw units).");
        process.exit(1);
      }
      const total = BigInt(pos.liquidity);
      liquidityToRemove = (total * BigInt(percent)) / 100n;
      console.log("Fetched position liquidity:", pos.liquidity, "-> remove", liquidityToRemove.toString(), "(" + percent + "%)");
    }
    if (liquidityToRemove <= 0n) {
      console.error("LIQUIDITY to remove must be > 0.");
      process.exit(1);
    }
    unlockData = encodeUnlockDataDecrease(tokenId, liquidityToRemove, 0n, 0n);
    console.log("Mode: DECREASE_LIQUIDITY", { liquidity: liquidityToRemove.toString() });
  }

  console.log("UnlockData hex:", unlockData);

  const fromEnv = process.env.FROM_ADDRESS?.trim();
  const accountAddress = fromEnv
    ? ("0x" + (fromEnv.replace(/^0x/, "").padStart(40, "0").slice(-40))) as Address
    : privateKey
      ? (privateKeyToAccount((privateKey.startsWith("0x") ? privateKey : "0x" + privateKey) as `0x${string}`).address as Address)
      : undefined;
  if (fromEnv) console.log("Simulating as FROM_ADDRESS (owner):", accountAddress);

  const result = await tryRemoveOne({
    positionManagerAddr,
    tokenId,
    unlockData,
    deadline,
    transport,
    publicClient,
    accountAddress,
    privateKey,
  });

  if (!result.success) {
    console.error("Simulation: REVERT", result.error);
    if (privateKey && process.env.SEND_ANYWAY === "1") {
      console.log("Sending tx to capture on-chain revert reason...");
      const pk = (privateKey.startsWith("0x") ? privateKey : "0x" + privateKey) as `0x${string}`;
      const account = privateKeyToAccount(pk);
      const walletClient = createWalletClient({ chain: HEDERA_TESTNET, transport, account });
      const modifyCalldata = encodeFunctionData({
        abi: MODIFY_LIQUIDITIES_ABI,
        functionName: "modifyLiquidities",
        args: [unlockData, deadline],
      });
      const multicallCalldata = encodeFunctionData({
        abi: MULTICALL_ABI,
        functionName: "multicall",
        args: [[modifyCalldata as `0x${string}`]],
      });
      try {
        const hash = await walletClient.sendTransaction({
          to: positionManagerAddr as Address,
          data: multicallCalldata,
          gas: 5_000_000n,
          account,
        });
        console.log("Tx hash:", hash);
        console.log("Waiting 8s then fetching revert reason...");
        await new Promise((r) => setTimeout(r, 8000));
        const crRes = await fetch(
          `https://testnet.mirrornode.hedera.com/api/v1/contracts/results/${hash}`,
        );
        if (crRes.ok) {
          const cr = await crRes.json();
          if (cr.error_message) {
            console.log("");
            console.log("--- On-chain revert reason ---");
            console.log(cr.error_message);
          }
        }
      } catch (sendErr) {
        console.error("Send failed:", sendErr);
      }
    }
    process.exit(1);
  }
  console.log("Simulation: SUCCESS");
  if (result.hash) console.log("Tx hash:", result.hash);
  else if (!privateKey) console.log("Set PRIVATE_KEY to send the transaction.");
}

const removeUntilSuccess = process.env.REMOVE_UNTIL_SUCCESS === "1" || process.env.REMOVE_UNTIL_SUCCESS === "true";
if (removeUntilSuccess) {
  runUntilSuccess().catch((e) => {
    console.error(e);
    process.exit(1);
  });
} else {
  run().catch((e) => {
    console.error(e);
    process.exit(1);
  });
}
