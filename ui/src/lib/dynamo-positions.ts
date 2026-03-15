import {
  DynamoDBClient,
  ScanCommand,
  PutItemCommand,
  DeleteItemCommand,
} from "@aws-sdk/client-dynamodb";
import { marshall, unmarshall } from "@aws-sdk/util-dynamodb";

export interface PositionRecord {
  /** Composite key: `${tokenId}` */
  positionId: string;
  /** NFT token ID from PositionManager */
  tokenId: number;
  /** Pool ID (keccak256 of pool key) */
  poolId: string;
  /** Owner EVM address (lowercase) */
  owner: string;
  /** Lower tick of the position range */
  tickLower: number;
  /** Upper tick of the position range */
  tickUpper: number;
  /** Liquidity amount (string for big numbers) */
  liquidity: string;
  /** Pool metadata for display */
  currency0: string;
  currency1: string;
  symbol0?: string;
  symbol1?: string;
  fee: number;
  tickSpacing: number;
  decimals0?: number;
  decimals1?: number;
  hooks?: string;
  hookName?: string;
  createdAt?: string;
}

const TABLE_NAME =
  process.env.DYNAMODB_TABLE_POSITIONS ?? "hieroforge-positions";

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

/** List all positions for a specific owner (EVM address). */
export async function listPositionsByOwner(
  owner: string,
): Promise<PositionRecord[]> {
  if (!isDynamoConfigured()) return [];
  const client = getClient();
  const result = await client.send(
    new ScanCommand({
      TableName: TABLE_NAME,
      FilterExpression: "#o = :owner",
      ExpressionAttributeNames: { "#o": "owner" },
      ExpressionAttributeValues: marshall({
        ":owner": owner.toLowerCase().trim(),
      }),
    }),
  );
  const items = (result.Items ?? []).map(
    (item) => unmarshall(item) as PositionRecord,
  );
  return items.sort(
    (a, b) =>
      new Date(b.createdAt ?? 0).getTime() -
      new Date(a.createdAt ?? 0).getTime(),
  );
}

/** List all positions (for admin/explore). */
export async function listAllPositions(): Promise<PositionRecord[]> {
  if (!isDynamoConfigured()) return [];
  const client = getClient();
  const result = await client.send(new ScanCommand({ TableName: TABLE_NAME }));
  const items = (result.Items ?? []).map(
    (item) => unmarshall(item) as PositionRecord,
  );
  return items.sort(
    (a, b) =>
      new Date(b.createdAt ?? 0).getTime() -
      new Date(a.createdAt ?? 0).getTime(),
  );
}

/** Save a new position record. */
export async function savePosition(pos: PositionRecord): Promise<void> {
  if (!isDynamoConfigured()) {
    console.warn(
      "DynamoDB not configured – position not persisted. Set HF_AWS_ACCESS_KEY_ID and HF_AWS_SECRET_ACCESS_KEY.",
    );
    return;
  }
  const client = getClient();
  const record: PositionRecord = {
    ...pos,
    positionId: String(pos.tokenId),
    owner: pos.owner.toLowerCase().trim(),
    poolId: pos.poolId.toLowerCase().trim(),
    createdAt: pos.createdAt ?? new Date().toISOString(),
  };
  await client.send(
    new PutItemCommand({
      TableName: TABLE_NAME,
      Item: marshall(record, { removeUndefinedValues: true }),
    }),
  );
}

/** Delete a position record (e.g. after burn). */
export async function deletePosition(positionId: string): Promise<void> {
  if (!isDynamoConfigured()) return;
  const client = getClient();
  await client.send(
    new DeleteItemCommand({
      TableName: TABLE_NAME,
      Key: marshall({ positionId }),
    }),
  );
}
