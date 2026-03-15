import {
  DynamoDBClient,
  ScanCommand,
  GetItemCommand,
  PutItemCommand,
  DeleteItemCommand,
} from "@aws-sdk/client-dynamodb";
import { marshall, unmarshall } from "@aws-sdk/util-dynamodb";

export interface PoolRecord {
  poolId: string;
  currency0: string;
  currency1: string;
  fee: number;
  tickSpacing: number;
  symbol0?: string;
  symbol1?: string;
  /** Wallet address (EVM hex) or Hedera account ID of the deployer */
  deployedBy?: string;
  /** Human-readable initial price set at pool creation */
  initialPrice?: string;
  /** sqrtPriceX96 used for pool initialization */
  sqrtPriceX96?: string;
  /** Token0 decimals */
  decimals0?: number;
  /** Token1 decimals */
  decimals1?: number;
  /** Hook contract address (0x0 for no hook) */
  hooks?: string;
  /** Hook name label (e.g. "TWAP Oracle") */
  hookName?: string;
  createdAt?: string;
}

const TABLE_NAME = process.env.DYNAMODB_TABLE_POOLS ?? "hieroforge-pools";

function isDynamoConfigured(): boolean {
  return !!(
    process.env.HF_AWS_ACCESS_KEY_ID && process.env.HF_AWS_SECRET_ACCESS_KEY
  );
}

function getClient(): DynamoDBClient {
  const region = process.env.HF_AWS_REGION ?? "us-east-1";
  return new DynamoDBClient({
    region,
    credentials: {
      accessKeyId: process.env.HF_AWS_ACCESS_KEY_ID!,
      secretAccessKey: process.env.HF_AWS_SECRET_ACCESS_KEY!,
    },
  });
}

export async function listPools(): Promise<PoolRecord[]> {
  if (!isDynamoConfigured()) return [];
  const client = getClient();
  const result = await client.send(
    new ScanCommand({
      TableName: TABLE_NAME,
    }),
  );
  const items = (result.Items ?? []).map(
    (item) => unmarshall(item) as PoolRecord,
  );
  return items.sort(
    (a, b) =>
      new Date(b.createdAt ?? 0).getTime() -
      new Date(a.createdAt ?? 0).getTime(),
  );
}

export async function getPoolById(poolId: string): Promise<PoolRecord | null> {
  if (!isDynamoConfigured()) return null;
  const client = getClient();
  const result = await client.send(
    new GetItemCommand({
      TableName: TABLE_NAME,
      Key: marshall({ poolId: poolId.toLowerCase().trim() }),
    }),
  );
  if (!result.Item) return null;
  return unmarshall(result.Item) as PoolRecord;
}

/** List pools deployed by a specific wallet/account. */
export async function listPoolsByDeployer(
  deployedBy: string,
): Promise<PoolRecord[]> {
  if (!isDynamoConfigured()) return [];
  const client = getClient();
  const result = await client.send(
    new ScanCommand({
      TableName: TABLE_NAME,
      FilterExpression: "deployedBy = :d",
      ExpressionAttributeValues: marshall({
        ":d": deployedBy.toLowerCase().trim(),
      }),
    }),
  );
  const items = (result.Items ?? []).map(
    (item) => unmarshall(item) as PoolRecord,
  );
  return items.sort(
    (a, b) =>
      new Date(b.createdAt ?? 0).getTime() -
      new Date(a.createdAt ?? 0).getTime(),
  );
}

export async function savePool(pool: PoolRecord): Promise<void> {
  if (!isDynamoConfigured()) {
    console.warn(
      "DynamoDB not configured – pool not persisted. Set HF_AWS_ACCESS_KEY_ID and HF_AWS_SECRET_ACCESS_KEY.",
    );
    return;
  }
  const client = getClient();
  const record: PoolRecord = {
    ...pool,
    poolId: pool.poolId.toLowerCase().trim(),
    deployedBy: pool.deployedBy?.toLowerCase().trim(),
    createdAt: pool.createdAt ?? new Date().toISOString(),
  };
  await client.send(
    new PutItemCommand({
      TableName: TABLE_NAME,
      Item: marshall(record, { removeUndefinedValues: true }),
    }),
  );
}

export async function deletePoolById(poolId: string): Promise<void> {
  if (!isDynamoConfigured()) return;
  const client = getClient();
  await client.send(
    new DeleteItemCommand({
      TableName: TABLE_NAME,
      Key: marshall({ poolId: poolId.toLowerCase().trim() }),
    }),
  );
}
