import { NextResponse } from "next/server";
import { getPoolById, savePool, type PoolRecord } from "@/lib/dynamo-pools";
import {
  validatePoolOnChain,
  discoverPoolFromChain,
} from "@/lib/poolValidation";

/**
 * POST /api/pools/ensure
 * Ensures a pool is in DynamoDB. If not present, validates on-chain, discovers
 * from chain (Initialize event), and saves. Used after create-position so the
 * pool appears in Explore and Pools list.
 * Body: { poolId: string, deployedBy?: string }
 */
export async function POST(request: Request) {
  try {
    const body = (await request.json()) as {
      poolId?: string;
      deployedBy?: string;
    };
    const poolId = body.poolId?.trim();
    const deployedBy = body.deployedBy?.trim();

    if (!poolId) {
      return NextResponse.json(
        { error: "Missing required field: poolId" },
        { status: 400 },
      );
    }

    const normalizedPoolId = poolId.toLowerCase();

    // If already in DynamoDB, return existing
    const existing = await getPoolById(normalizedPoolId);
    if (existing) {
      return NextResponse.json(existing);
    }

    // Validate pool exists on-chain
    const validation = await validatePoolOnChain(normalizedPoolId);
    if (!validation.validated) {
      return NextResponse.json(
        {
          error: `Unable to validate pool on-chain. ${validation.reason ?? ""}`.trim(),
        },
        { status: 503 },
      );
    }
    if (!validation.exists) {
      return NextResponse.json(
        { error: "Pool not initialized on-chain." },
        { status: 404 },
      );
    }

    // Discover from chain and save
    const discovered = await discoverPoolFromChain(normalizedPoolId);
    if (!discovered) {
      return NextResponse.json(
        { error: "Pool exists on-chain but could not discover metadata." },
        { status: 503 },
      );
    }

    const toSave: PoolRecord = {
      ...discovered,
      deployedBy: deployedBy ?? discovered.deployedBy,
    };
    await savePool(toSave);

    return NextResponse.json(toSave);
  } catch (err) {
    console.error("Ensure pool error:", err);
    return NextResponse.json(
      { error: "Failed to ensure pool" },
      { status: 500 },
    );
  }
}
