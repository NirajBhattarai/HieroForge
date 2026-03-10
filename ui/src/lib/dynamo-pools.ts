import {
  DynamoDBClient,
  ScanCommand,
  GetItemCommand,
  PutItemCommand,
} from '@aws-sdk/client-dynamodb'
import { marshall, unmarshall } from '@aws-sdk/util-dynamodb'

export interface PoolRecord {
  poolId: string
  currency0: string
  currency1: string
  fee: number
  tickSpacing: number
  symbol0?: string
  symbol1?: string
  createdAt?: string
}

const TABLE_NAME = process.env.DYNAMODB_TABLE_POOLS ?? 'hieroforge-pools'

function getClient(): DynamoDBClient {
  const region = process.env.AWS_REGION ?? 'us-east-1'
  return new DynamoDBClient({ region })
}

export async function listPools(): Promise<PoolRecord[]> {
  const client = getClient()
  const result = await client.send(
    new ScanCommand({
      TableName: TABLE_NAME,
    })
  )
  const items = (result.Items ?? []).map((item) => unmarshall(item) as PoolRecord)
  return items.sort(
    (a, b) =>
      new Date(b.createdAt ?? 0).getTime() - new Date(a.createdAt ?? 0).getTime()
  )
}

export async function getPoolById(poolId: string): Promise<PoolRecord | null> {
  const client = getClient()
  const result = await client.send(
    new GetItemCommand({
      TableName: TABLE_NAME,
      Key: marshall({ poolId: poolId.toLowerCase().trim() }),
    })
  )
  if (!result.Item) return null
  return unmarshall(result.Item) as PoolRecord
}

export async function savePool(pool: PoolRecord): Promise<void> {
  const client = getClient()
  const record: PoolRecord = {
    ...pool,
    poolId: pool.poolId.toLowerCase().trim(),
    createdAt: pool.createdAt ?? new Date().toISOString(),
  }
  await client.send(
    new PutItemCommand({
      TableName: TABLE_NAME,
      Item: marshall(record, { removeUndefinedValues: true }),
    })
  )
}
