import { NextResponse } from "next/server";
import { listTokens, saveToken, type TokenRecord } from "@/lib/dynamo-tokens";

export async function GET() {
  try {
    const tokens = await listTokens();
    return NextResponse.json(tokens);
  } catch (err) {
    console.error("List tokens error:", err);
    return NextResponse.json(
      { error: "Failed to list tokens" },
      { status: 500 },
    );
  }
}

export async function POST(request: Request) {
  try {
    const body = (await request.json()) as TokenRecord;
    const { address, symbol, name, decimals } = body;
    if (!address || !symbol || !name || decimals == null) {
      return NextResponse.json(
        { error: "Missing required fields: address, symbol, name, decimals" },
        { status: 400 },
      );
    }
    await saveToken({
      address: address.toLowerCase().trim(),
      symbol: symbol.trim(),
      name: name.trim(),
      decimals: Number(decimals),
      logoUrl: body.logoUrl ?? undefined,
      isHts: body.isHts ?? true,
    });
    return NextResponse.json({ ok: true });
  } catch (err) {
    console.error("Save token error:", err);
    return NextResponse.json(
      { error: "Failed to save token" },
      { status: 500 },
    );
  }
}
