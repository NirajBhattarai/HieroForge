import {
  DynamoDBClient,
  ScanCommand,
  GetItemCommand,
  PutItemCommand,
} from "@aws-sdk/client-dynamodb";
import { marshall, unmarshall } from "@aws-sdk/util-dynamodb";

export interface TokenRecord {
  /** Contract address (partition key), lowercased 0x... */
  address: string;
  symbol: string;
  name: string;
  decimals: number;
  logoUrl?: string;
  /** Whether this is an HTS (Hedera Token Service) token */
  isHts?: boolean;
  createdAt?: string;
}

const TABLE_NAME = process.env.DYNAMODB_TABLE_TOKENS ?? "hieroforge-tokens";

function isDynamoConfigured(): boolean {
  return !!(process.env.AWS_ACCESS_KEY_ID && process.env.AWS_SECRET_ACCESS_KEY);
}

function getClient(): DynamoDBClient {
  const region = process.env.AWS_REGION ?? "us-east-1";
  return new DynamoDBClient({ region });
}

/** List all tokens from DynamoDB. Returns [] if not configured. */
export async function listTokens(): Promise<TokenRecord[]> {
  if (!isDynamoConfigured()) return [];
  const client = getClient();
  const result = await client.send(new ScanCommand({ TableName: TABLE_NAME }));
  const items = (result.Items ?? []).map(
    (item) => unmarshall(item) as TokenRecord,
  );
  return items.sort((a, b) => a.symbol.localeCompare(b.symbol));
}

/** Get a single token by address. */
export async function getTokenByAddress(
  address: string,
): Promise<TokenRecord | null> {
  if (!isDynamoConfigured()) return null;
  const client = getClient();
  const result = await client.send(
    new GetItemCommand({
      TableName: TABLE_NAME,
      Key: marshall({ address: address.toLowerCase().trim() }),
    }),
  );
  if (!result.Item) return null;
  return unmarshall(result.Item) as TokenRecord;
}

/** Save (upsert) a token record. */
export async function saveToken(token: TokenRecord): Promise<void> {
  if (!isDynamoConfigured()) {
    console.warn("DynamoDB not configured – token not persisted.");
    return;
  }
  const client = getClient();
  const record: TokenRecord = {
    ...token,
    address: token.address.toLowerCase().trim(),
    createdAt: token.createdAt ?? new Date().toISOString(),
  };
  await client.send(
    new PutItemCommand({
      TableName: TABLE_NAME,
      Item: marshall(record, { removeUndefinedValues: true }),
    }),
  );
}
