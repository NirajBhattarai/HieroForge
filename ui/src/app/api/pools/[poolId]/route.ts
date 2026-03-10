import { NextResponse } from 'next/server'
import { getPoolById } from '@/lib/dynamo-pools'

export async function GET(
  _request: Request,
  { params }: { params: Promise<{ poolId: string }> }
) {
  try {
    const { poolId } = await params
    if (!poolId) {
      return NextResponse.json({ error: 'Missing poolId' }, { status: 400 })
    }
    const pool = await getPoolById(poolId)
    if (!pool) {
      return NextResponse.json({ error: 'Pool not found' }, { status: 404 })
    }
    return NextResponse.json(pool)
  } catch (err) {
    console.error('Get pool error:', err)
    return NextResponse.json(
      { error: 'Failed to get pool' },
      { status: 500 }
    )
  }
}
