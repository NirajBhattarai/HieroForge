import { NextResponse } from "next/server";
import { deletePoolById, getPoolById, savePool } from "@/lib/dynamo-pools";
import {
  validatePoolOnChain,
  discoverPoolFromChain,
} from "@/lib/poolValidation";

export async function GET(
  _request: Request,
  { params }: { params: Promise<{ poolId: string }> },
) {
  try {
    const { poolId } = await params;
    if (!poolId) {
      return NextResponse.json({ error: "Missing poolId" }, { status: 400 });
    }

    // 1. Check DynamoDB first
    let pool = await getPoolById(poolId);

    // 2. If not in DynamoDB, try discovering from on-chain Initialize event
    if (!pool) {
      const discovered = await discoverPoolFromChain(poolId);
      if (!discovered) {
        return NextResponse.json(
          { error: "Pool not found on-chain" },
          { status: 404 },
        );
      }
      // Save discovered pool to DynamoDB for future lookups
      await savePool(discovered);
      return NextResponse.json(discovered);
    }

    // 3. Validate the DynamoDB record is still live on-chain
    const validation = await validatePoolOnChain(pool.poolId);
    if (validation.validated && !validation.exists) {
      try {
        await deletePoolById(pool.poolId);
      } catch (err) {
        console.warn(
          "Failed to delete stale pool from DynamoDB:",
          pool.poolId,
          err,
        );
      }
      return NextResponse.json({ error: "Pool not found" }, { status: 404 });
    }

    return NextResponse.json(pool);
  } catch (err) {
    console.error("Get pool error:", err);
    return NextResponse.json({ error: "Failed to get pool" }, { status: 500 });
  }
}
