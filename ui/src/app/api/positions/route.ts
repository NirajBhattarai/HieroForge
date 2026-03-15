import { NextResponse } from "next/server";
import {
  listPositionsByOwner,
  listAllPositions,
  savePosition,
  deletePosition,
  type PositionRecord,
} from "@/lib/dynamo-positions";

export async function GET(request: Request) {
  try {
    const { searchParams } = new URL(request.url);
    const owner = searchParams.get("owner")?.trim();

    const positions = owner
      ? await listPositionsByOwner(owner)
      : await listAllPositions();

    return NextResponse.json(positions);
  } catch (err) {
    console.error("List positions error:", err);
    return NextResponse.json(
      { error: "Failed to list positions" },
      { status: 500 },
    );
  }
}

export async function POST(request: Request) {
  try {
    const body = (await request.json()) as PositionRecord;
    const {
      tokenId,
      poolId,
      owner,
      tickLower,
      tickUpper,
      liquidity,
      currency0,
      currency1,
      fee,
      tickSpacing,
    } = body;

    if (
      tokenId == null ||
      !poolId ||
      !owner ||
      tickLower == null ||
      tickUpper == null ||
      !liquidity ||
      !currency0 ||
      !currency1 ||
      fee == null ||
      tickSpacing == null
    ) {
      return NextResponse.json(
        {
          error:
            "Missing required fields: tokenId, poolId, owner, tickLower, tickUpper, liquidity, currency0, currency1, fee, tickSpacing",
        },
        { status: 400 },
      );
    }

    await savePosition({
      positionId: String(tokenId),
      tokenId: Number(tokenId),
      poolId,
      owner: owner.toLowerCase().trim(),
      tickLower: Number(tickLower),
      tickUpper: Number(tickUpper),
      liquidity: String(liquidity),
      currency0: currency0.toLowerCase().trim(),
      currency1: currency1.toLowerCase().trim(),
      fee: Number(fee),
      tickSpacing: Number(tickSpacing),
      symbol0: body.symbol0 ?? undefined,
      symbol1: body.symbol1 ?? undefined,
      decimals0: body.decimals0 != null ? Number(body.decimals0) : undefined,
      decimals1: body.decimals1 != null ? Number(body.decimals1) : undefined,
      hooks: body.hooks ?? undefined,
      hookName: body.hookName ?? undefined,
    });
    return NextResponse.json({ ok: true });
  } catch (err) {
    console.error("Save position error:", err);
    return NextResponse.json(
      { error: "Failed to save position" },
      { status: 500 },
    );
  }
}

export async function DELETE(request: Request) {
  try {
    const { searchParams } = new URL(request.url);
    const positionId = searchParams.get("positionId")?.trim();

    if (!positionId) {
      return NextResponse.json(
        { error: "Missing positionId query parameter" },
        { status: 400 },
      );
    }

    await deletePosition(positionId);
    return NextResponse.json({ ok: true });
  } catch (err) {
    console.error("Delete position error:", err);
    return NextResponse.json(
      { error: "Failed to delete position" },
      { status: 500 },
    );
  }
}
