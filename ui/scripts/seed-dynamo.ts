/**
 * Seed script: Creates DynamoDB tables (if missing) and populates them with
 * the deployed tokens and pool from the Hedera testnet deployment.
 *
 * Usage:  npx tsx scripts/seed-dynamo.ts
 *
 * Reads AWS credentials from ../.env.local automatically via dotenv.
 */

import { config } from 'dotenv'
import { resolve, dirname } from 'path'
import { fileURLToPath } from 'url'
import {
  DynamoDBClient,
  CreateTableCommand,
  DescribeTableCommand,
  PutItemCommand,
} from '@aws-sdk/client-dynamodb'
import { marshall } from '@aws-sdk/util-dynamodb'

const __filename = fileURLToPath(import.meta.url)
const __dirname = dirname(__filename)

// Load .env.local from the ui/ directory
config({ path: resolve(__dirname, '../.env.local') })

const REGION = process.env.AWS_REGION ?? 'eu-north-1'
const TOKENS_TABLE = process.env.DYNAMODB_TABLE_TOKENS ?? 'hieroforge-tokens'
const POOLS_TABLE = process.env.DYNAMODB_TABLE_POOLS ?? 'hieroforge-pools'

const client = new DynamoDBClient({ region: REGION })

import { keccak256, encodeAbiParameters, parseAbiParameters } from 'viem'

// ───── Data from our Hedera testnet deployment ─────

const DEPLOYED_TOKENS = [
  {
    address: '0x00000000000000000000000000000000007c4657',
    symbol: 'TKA',
    name: 'HieroForge Token A',
    decimals: 8,
    isHts: true,
    hederaId: '0.0.8144471',
    deployedBy: '0x00000000000000000000000000000000007c4657', // update with real deployer
  },
  {
    address: '0x00000000000000000000000000000000007c4669',
    symbol: 'TKB',
    name: 'HieroForge Token B',
    decimals: 8,
    isHts: true,
    hederaId: '0.0.8144489',
    deployedBy: '0x00000000000000000000000000000000007c4657', // update with real deployer
  },
]

// Pool created with these two tokens, fee 3000, tickSpacing 60
const DEPLOYED_POOL = {
  currency0: '0x00000000000000000000000000000000007c4657',
  currency1: '0x00000000000000000000000000000000007c4669',
  fee: 3000,
  tickSpacing: 60,
  symbol0: 'TKA',
  symbol1: 'TKB',
  deployedBy: '0x00000000000000000000000000000000007c4657', // update with real deployer
  initialPrice: '1',
  sqrtPriceX96: '79228162514264337593543950336',
  decimals0: 8,
  decimals1: 8,
}

// ───── Helpers ─────

async function tableExists(tableName: string): Promise<boolean> {
  try {
    await client.send(new DescribeTableCommand({ TableName: tableName }))
    return true
  } catch (err: unknown) {
    if (err && typeof err === 'object' && 'name' in err && (err as { name: string }).name === 'ResourceNotFoundException') return false
    throw err
  }
}

async function createTable(tableName: string, partitionKey: string) {
  console.log(`  Creating table "${tableName}" with key "${partitionKey}"...`)
  await client.send(
    new CreateTableCommand({
      TableName: tableName,
      KeySchema: [{ AttributeName: partitionKey, KeyType: 'HASH' }],
      AttributeDefinitions: [{ AttributeName: partitionKey, AttributeType: 'S' }],
      BillingMode: 'PAY_PER_REQUEST',
    })
  )
  // Wait for table to become ACTIVE
  let active = false
  for (let i = 0; i < 30; i++) {
    const desc = await client.send(new DescribeTableCommand({ TableName: tableName }))
    if (desc.Table?.TableStatus === 'ACTIVE') { active = true; break }
    await new Promise((r) => setTimeout(r, 2000))
  }
  if (!active) throw new Error(`Table "${tableName}" did not become ACTIVE in time`)
  console.log(`  ✓ Table "${tableName}" is ACTIVE`)
}

async function putItem(tableName: string, item: Record<string, unknown>) {
  await client.send(
    new PutItemCommand({
      TableName: tableName,
      Item: marshall(item, { removeUndefinedValues: true }),
    })
  )
}

// ───── Compute poolId using keccak256 (same logic as Solidity) ─────

function computePoolId(c0: string, c1: string, fee: number, tickSpacing: number): string {
  const sorted0 = c0.toLowerCase() < c1.toLowerCase() ? c0 : c1
  const sorted1 = c0.toLowerCase() < c1.toLowerCase() ? c1 : c0
  const encoded = encodeAbiParameters(
    parseAbiParameters('address, address, uint24, int24, address'),
    [
      sorted0 as `0x${string}`,
      sorted1 as `0x${string}`,
      fee,
      tickSpacing,
      '0x0000000000000000000000000000000000000000' as `0x${string}`,
    ]
  )
  return keccak256(encoded)
}

// ───── Main ─────

async function main() {
  console.log('HieroForge DynamoDB Seed Script')
  console.log(`Region: ${REGION}`)
  console.log()

  // 1. Ensure tokens table
  console.log(`[1/4] Checking tokens table "${TOKENS_TABLE}"...`)
  if (await tableExists(TOKENS_TABLE)) {
    console.log(`  ✓ Table exists`)
  } else {
    await createTable(TOKENS_TABLE, 'address')
  }

  // 2. Ensure pools table
  console.log(`[2/4] Checking pools table "${POOLS_TABLE}"...`)
  if (await tableExists(POOLS_TABLE)) {
    console.log(`  ✓ Table exists`)
  } else {
    await createTable(POOLS_TABLE, 'poolId')
  }

  // 3. Seed tokens
  console.log(`[3/4] Seeding tokens...`)
  for (const token of DEPLOYED_TOKENS) {
    console.log(`  → ${token.symbol} (${token.address})`)
    await putItem(TOKENS_TABLE, {
      ...token,
      createdAt: new Date().toISOString(),
    })
  }
  console.log(`  ✓ ${DEPLOYED_TOKENS.length} tokens seeded`)

  // 4. Seed pool
  console.log(`[4/4] Seeding pool...`)
  const poolId = computePoolId(
    DEPLOYED_POOL.currency0,
    DEPLOYED_POOL.currency1,
    DEPLOYED_POOL.fee,
    DEPLOYED_POOL.tickSpacing
  )
  console.log(`  → Pool ID: ${poolId}`)
  console.log(`  → ${DEPLOYED_POOL.symbol0}/${DEPLOYED_POOL.symbol1} fee=${DEPLOYED_POOL.fee}`)
  await putItem(POOLS_TABLE, {
    poolId: poolId.toLowerCase(),
    ...DEPLOYED_POOL,
    createdAt: new Date().toISOString(),
  })
  console.log(`  ✓ Pool seeded`)

  console.log()
  console.log('Done! Your DynamoDB tables are populated.')
  console.log('Restart the dev server to see the data in the UI.')
}

main().catch((err) => {
  console.error('Seed failed:', err)
  process.exit(1)
})
