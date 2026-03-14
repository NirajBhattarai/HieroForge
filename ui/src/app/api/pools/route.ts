import { NextResponse } from "next/server";
import {
  listPools,
  listPoolsByDeployer,
  savePool,
  type PoolRecord,
} from "@/lib/dynamo-pools";

export async function GET(request: Request) {
  try {
    const { searchParams } = new URL(request.url);
    const deployedBy = searchParams.get("deployedBy")?.trim();

    const pools = deployedBy
      ? await listPoolsByDeployer(deployedBy)
      : await listPools();
    return NextResponse.json(pools);
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
    });
    return NextResponse.json({ ok: true });
  } catch (err) {
    console.error("Save pool error:", err);
    return NextResponse.json({ error: "Failed to save pool" }, { status: 500 });
  }
}
