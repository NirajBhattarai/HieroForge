#!/usr/bin/env node
/**
 * register-token.js — Register a deployed token in DynamoDB.
 *
 * Called automatically by deploy-token.sh after deployment, or manually:
 *   node ../ui/scripts/register-token.js \
 *     --address 0x00000000000000000000000000000000007c4657 \
 *     --symbol TKA --name "HieroForge Token A" --decimals 8 --hts
 *
 * Reads AWS credentials from ../ui/.env.local
 */

const {
  DynamoDBClient,
  PutItemCommand,
  CreateTableCommand,
  DescribeTableCommand,
} = require("@aws-sdk/client-dynamodb");
const { marshall } = require("@aws-sdk/util-dynamodb");
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

// Load from ui/.env.local
const envPath = path.resolve(__dirname, "..", ".env.local");
loadEnv(envPath);

// ── Parse CLI args ──
function parseArgs(argv) {
  const args = {};
  for (let i = 2; i < argv.length; i++) {
    const arg = argv[i];
    if (arg.startsWith("--")) {
      const key = arg.slice(2);
      if (key === "hts") {
        args.isHts = true;
      } else {
        args[key] = argv[++i];
      }
    }
  }
  return args;
}

const args = parseArgs(process.argv);
const address = (args.address || "").toLowerCase().trim();
const symbol = (args.symbol || "").trim();
const name = (args.name || "").trim();
const decimals = parseInt(args.decimals || "8", 10);
const isHts = !!args.isHts;
const logoUrl = (args.logoUrl || "").trim() || undefined;

if (!address || !symbol || !name) {
  console.error(
    'Usage: register-token.js --address 0x... --symbol SYM --name "Token Name" --decimals 8 [--hts] [--logoUrl URL]',
  );
  process.exit(1);
}

const REGION = process.env.HF_AWS_REGION || "eu-north-1";
const TABLE = process.env.DYNAMODB_TABLE_TOKENS || "hieroforge-tokens";

async function ensureTable(client) {
  try {
    await client.send(new DescribeTableCommand({ TableName: TABLE }));
  } catch (err) {
    if (err.name === "ResourceNotFoundException") {
      console.log(`  Creating table "${TABLE}"...`);
      await client.send(
        new CreateTableCommand({
          TableName: TABLE,
          KeySchema: [{ AttributeName: "address", KeyType: "HASH" }],
          AttributeDefinitions: [
            { AttributeName: "address", AttributeType: "S" },
          ],
          BillingMode: "PAY_PER_REQUEST",
        }),
      );
      // Wait for active
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
    address,
    symbol,
    name,
    decimals,
    isHts,
    ...(logoUrl ? { logoUrl } : {}),
    createdAt: new Date().toISOString(),
  };

  await client.send(
    new PutItemCommand({
      TableName: TABLE,
      Item: marshall(record, { removeUndefinedValues: true }),
    }),
  );

  console.log(`[DynamoDB] Token registered: ${symbol} (${address})`);
}

main().catch((err) => {
  console.error("[DynamoDB] Failed to register token:", err.message);
  process.exit(1);
});
