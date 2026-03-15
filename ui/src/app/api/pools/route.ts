import { NextResponse } from "next/server";
import {
  listPools,
  listPoolsByDeployer,
  savePool,
  getPoolById,
  deletePoolById,
  type PoolRecord,
} from "@/lib/dynamo-pools";
import { validatePoolOnChain } from "@/lib/poolValidation";

export async function GET(request: Request) {
  try {
    const { searchParams } = new URL(request.url);
    const deployedBy = searchParams.get("deployedBy")?.trim();

    const pools = deployedBy
      ? await listPoolsByDeployer(deployedBy)
      : await listPools();

    const checks = await Promise.all(
      pools.map(async (pool) => {
        const validation = await validatePoolOnChain(pool.poolId);
        return { pool, validation };
      }),
    );

    const validPools: PoolRecord[] = [];
    const stalePoolIds: string[] = [];

    for (const { pool, validation } of checks) {
      if (validation.validated && !validation.exists) {
        stalePoolIds.push(pool.poolId);
        continue;
      }
      validPools.push(pool);
    }

    if (stalePoolIds.length > 0) {
      await Promise.all(
        stalePoolIds.map(async (poolId) => {
          try {
            await deletePoolById(poolId);
          } catch (err) {
            console.warn(
              "Failed to delete stale pool from DynamoDB:",
              poolId,
              err,
            );
          }
        }),
      );
    }

    return NextResponse.json(validPools);
  } catch (err) {
    console.error("List pools error:", err);
    return NextResponse.json(
      { error: "Failed to list pools" },
      { status: 500 },
    );
  }
}

export async function POST(request: Request) {
  try {
    const body = (await request.json()) as PoolRecord;
    const {
      poolId,
      currency0,
      currency1,
      fee,
      tickSpacing,
      symbol0,
      symbol1,
      deployedBy,
      initialPrice,
      sqrtPriceX96,
      decimals0,
      decimals1,
      hooks,
      hookName,
    } = body;
    if (
      !poolId ||
      !currency0 ||
      !currency1 ||
      fee == null ||
      tickSpacing == null
    ) {
      return NextResponse.json(
        {
          error:
            "Missing required fields: poolId, currency0, currency1, fee, tickSpacing",
        },
        { status: 400 },
      );
    }

    const validation = await validatePoolOnChain(poolId);
    if (!validation.validated) {
      return NextResponse.json(
        {
          error:
            `Unable to validate pool on-chain. Not saving to database. ${validation.reason ?? ""}`.trim(),
        },
        { status: 503 },
      );
    }
    if (!validation.exists) {
      return NextResponse.json(
        { error: "Pool not initialized on-chain. Not saving to database." },
        { status: 400 },
      );
    }

    // Check if pool already exists in DynamoDB
    const existing = await getPoolById(poolId);
    if (existing) {
      return NextResponse.json(existing);
    }

    await savePool({
      poolId,
      currency0: currency0.toLowerCase().trim(),
      currency1: currency1.toLowerCase().trim(),
      fee: Number(fee),
      tickSpacing: Number(tickSpacing),
      symbol0: symbol0 ?? undefined,
      symbol1: symbol1 ?? undefined,
      deployedBy: deployedBy ?? undefined,
      initialPrice: initialPrice ?? undefined,
      sqrtPriceX96: sqrtPriceX96 ?? undefined,
      decimals0: decimals0 != null ? Number(decimals0) : undefined,
      decimals1: decimals1 != null ? Number(decimals1) : undefined,
      hooks: hooks ?? undefined,
      hookName: hookName ?? undefined,
    });
    return NextResponse.json({ ok: true });
  } catch (err) {
    console.error("Save pool error:", err);
    return NextResponse.json({ error: "Failed to save pool" }, { status: 500 });
  }
}
