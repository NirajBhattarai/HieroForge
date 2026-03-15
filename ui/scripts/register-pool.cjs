#!/usr/bin/env node
/**
 * register-pool.js — Register a deployed liquidity pool in DynamoDB.
 *
 * Called automatically by create-pool-and-add-liquidity.sh, or manually:
 *   node ../ui/scripts/register-pool.js \
 *     --currency0 0x...4657 --currency1 0x...4669 \
 *     --fee 3000 --tickSpacing 60 --symbol0 TKA --symbol1 TKB
 *
 * Computes poolId = keccak256(abi.encode(currency0, currency1, fee, tickSpacing, hooks=0x0))
 * Reads AWS credentials from ../ui/.env.local
 */

const {
  DynamoDBClient,
  PutItemCommand,
  CreateTableCommand,
  DescribeTableCommand,
} = require("@aws-sdk/client-dynamodb");
const { marshall } = require("@aws-sdk/util-dynamodb");
const { keccak256, encodeAbiParameters, parseAbiParameters } = require("viem");
const fs = require("fs");
const path = require("path");

// ── Load .env.local ──
function loadEnv(filePath) {
  if (!fs.existsSync(filePath)) return;
  const lines = fs.readFileSync(filePath, "utf8").split("\n");
  for (const line of lines) {
    const trimmed = line.trim();
    if (!trimmed || trimmed.startsWith("#")) continue;
    const eqIdx = trimmed.indexOf("=");
    if (eqIdx < 0) continue;
    const key = trimmed.slice(0, eqIdx).trim();
    const val = trimmed.slice(eqIdx + 1).trim();
    if (!process.env[key]) process.env[key] = val;
  }
}

const envPath = path.resolve(__dirname, "..", ".env.local");
loadEnv(envPath);

// ── Parse CLI args ──
function parseArgs(argv) {
  const args = {};
  for (let i = 2; i < argv.length; i++) {
    if (argv[i].startsWith("--")) {
      args[argv[i].slice(2)] = argv[++i];
    }
  }
  return args;
}

const args = parseArgs(process.argv);
const currency0Input = (args.currency0 || "").toLowerCase().trim();
const currency1Input = (args.currency1 || "").toLowerCase().trim();
const fee = parseInt(args.fee || "3000", 10);
const tickSpacing = parseInt(args.tickSpacing || "60", 10);
const symbol0 = (args.symbol0 || "").trim();
const symbol1 = (args.symbol1 || "").trim();

if (!currency0Input || !currency1Input) {
  console.error(
    "Usage: register-pool.js --currency0 0x... --currency1 0x... --fee 3000 --tickSpacing 60 --symbol0 TKA --symbol1 TKB",
  );
  process.exit(1);
}

// Sort currencies so currency0 < currency1
const sorted0 =
  currency0Input < currency1Input ? currency0Input : currency1Input;
const sorted1 =
  currency0Input < currency1Input ? currency1Input : currency0Input;

// Compute pool ID (matches Solidity PoolId.toId)
const encoded = encodeAbiParameters(
  parseAbiParameters("address, address, uint24, int24, address"),
  [
    sorted0,
    sorted1,
    fee,
    tickSpacing,
    "0x0000000000000000000000000000000000000000",
  ],
);
const poolId = keccak256(encoded);

const REGION = process.env.HF_AWS_REGION || "eu-north-1";
const TABLE = process.env.DYNAMODB_TABLE_POOLS || "hieroforge-pools";

async function ensureTable(client) {
  try {
    await client.send(new DescribeTableCommand({ TableName: TABLE }));
  } catch (err) {
    if (err.name === "ResourceNotFoundException") {
      console.log(`  Creating table "${TABLE}"...`);
      await client.send(
        new CreateTableCommand({
          TableName: TABLE,
          KeySchema: [{ AttributeName: "poolId", KeyType: "HASH" }],
          AttributeDefinitions: [
            { AttributeName: "poolId", AttributeType: "S" },
          ],
          BillingMode: "PAY_PER_REQUEST",
        }),
      );
      for (let i = 0; i < 30; i++) {
        const desc = await client.send(
          new DescribeTableCommand({ TableName: TABLE }),
        );
        if (desc.Table?.TableStatus === "ACTIVE") break;
        await new Promise((r) => setTimeout(r, 2000));
      }
    } else {
      throw err;
    }
  }
}

async function main() {
  const client = new DynamoDBClient({
    region: REGION,
    credentials: {
      accessKeyId: process.env.HF_AWS_ACCESS_KEY_ID,
      secretAccessKey: process.env.HF_AWS_SECRET_ACCESS_KEY,
    },
  });
  await ensureTable(client);

  const record = {
    poolId: poolId.toLowerCase(),
    currency0: sorted0,
    currency1: sorted1,
    fee,
    tickSpacing,
    ...(symbol0 ? { symbol0 } : {}),
    ...(symbol1 ? { symbol1 } : {}),
    createdAt: new Date().toISOString(),
  };

  await client.send(
    new PutItemCommand({
      TableName: TABLE,
      Item: marshall(record, { removeUndefinedValues: true }),
    }),
  );

  console.log(
    `[DynamoDB] Pool registered: ${symbol0 || sorted0}/${symbol1 || sorted1} (fee=${fee})`,
  );
  console.log(`[DynamoDB] Pool ID: ${poolId}`);
}

main().catch((err) => {
  console.error("[DynamoDB] Failed to register pool:", err.message);
  process.exit(1);
});
