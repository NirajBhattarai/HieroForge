"use client";

import { useState, useEffect, useRef } from "react";
import { Modal } from "@/components/ui/Modal";
import { TokenIcon } from "@/components/TokenIcon";
import type { TokenOption } from "@/constants";

interface TokenSelectorProps {
  open: boolean;
  onClose: () => void;
  onSelect: (token: TokenOption) => void;
  tokens: TokenOption[];
  selectedToken?: TokenOption;
  excludeToken?: TokenOption;
}

const POPULAR_SYMBOLS = ["HBAR", "USDC", "TKA", "TKB", "FORGE"];

export function TokenSelector({
  open,
  onClose,
  onSelect,
  tokens,
  selectedToken,
  excludeToken,
}: TokenSelectorProps) {
  const [search, setSearch] = useState("");
  const [lookupLoading, setLookupLoading] = useState(false);
  const [lookupError, setLookupError] = useState<string | null>(null);
  const inputRef = useRef<HTMLInputElement>(null);
  const lastLookupQueryRef = useRef<string>("");

  useEffect(() => {
    if (open) {
      setSearch("");
      setLookupError(null);
      setLookupLoading(false);
      lastLookupQueryRef.current = "";
      setTimeout(() => inputRef.current?.focus(), 100);
    }
  }, [open]);

  const q = search.trim().toLowerCase();
  const filtered = tokens.filter((t) => {
    if (excludeToken && t.id === excludeToken.id) return false;
    if (!q) return true;
    return (
      t.symbol.toLowerCase().includes(q) ||
      t.name?.toLowerCase().includes(q) ||
      t.address?.toLowerCase().includes(q) ||
      t.id.toLowerCase().includes(q)
    );
  });

  const popularTokens = tokens.filter(
    (t) =>
      POPULAR_SYMBOLS.includes(t.symbol) &&
      (!excludeToken || t.id !== excludeToken.id),
  );

  const handleSelect = (token: TokenOption) => {
    onSelect(token);
    onClose();
  };

  const isAddressSearch = /^0x[0-9a-f]{40}$/i.test(q) || /^0\.0\.\d+$/i.test(q);

  const handleLookupPastedAddress = async () => {
    const raw = search.trim();
    if (!raw) return;

    try {
      setLookupLoading(true);
      setLookupError(null);
      const res = await fetch(
        `/api/tokens/lookup?address=${encodeURIComponent(raw)}`,
      );
      const body = (await res.json().catch(() => null)) as
        | {
            address: string;
            symbol: string;
            name: string;
            decimals: number;
          }
        | { error?: string }
        | null;

      if (!res.ok || !body || !("address" in body)) {
        throw new Error(
          (body && "error" in body && body.error) || "Token lookup failed",
        );
      }

      handleSelect({
        id: body.address,
        symbol: body.symbol,
        name: body.name,
        address: body.address,
        decimals: body.decimals,
      });
    } catch (err) {
      setLookupError(
        err instanceof Error ? err.message : "Token lookup failed",
      );
    } finally {
      setLookupLoading(false);
    }
  };

  useEffect(() => {
    if (!open) return;
    if (!isAddressSearch) return;
    if (lookupLoading) return;

    const normalizedQuery = q;
    if (!normalizedQuery || normalizedQuery === lastLookupQueryRef.current) {
      return;
    }

    lastLookupQueryRef.current = normalizedQuery;
    void handleLookupPastedAddress();
    // Intentionally depends on `q`/`isAddressSearch` to run immediately when user pastes.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [open, q, isAddressSearch]);

  return (
    <Modal open={open} onClose={onClose} title="Select a token">
      <div className="p-4">
        {/* Search */}
        <div className="relative mb-3">
          <svg
            className="absolute left-3 top-1/2 -translate-y-1/2 text-text-tertiary"
            width="18"
            height="18"
            viewBox="0 0 24 24"
            fill="none"
            stroke="currentColor"
            strokeWidth="2"
            strokeLinecap="round"
            strokeLinejoin="round"
          >
            <circle cx="11" cy="11" r="8" />
            <line x1="21" y1="21" x2="16.65" y2="16.65" />
          </svg>
          <input
            ref={inputRef}
            type="text"
            className="w-full pl-10 pr-4 py-3 bg-surface-2 border border-border rounded-[--radius-md] text-text-primary placeholder:text-text-tertiary text-sm focus:outline-none focus:border-border-focus transition-colors"
            placeholder="Search by name or paste address"
            value={search}
            onChange={(e) => setSearch(e.target.value)}
          />
        </div>

        {/* Popular tokens */}
        {!q && popularTokens.length > 0 && (
          <div className="flex flex-wrap gap-2 mb-4">
            {popularTokens.map((t) => (
              <button
                key={t.id}
                type="button"
                onClick={() => handleSelect(t)}
                className={`
                  inline-flex items-center gap-1.5 px-3 py-1.5
                  rounded-[--radius-full] border text-sm font-medium
                  transition-all duration-150 cursor-pointer
                  ${
                    selectedToken?.id === t.id
                      ? "bg-accent-muted border-accent/30 text-accent"
                      : "bg-surface-2 border-border text-text-primary hover:border-border-hover hover:bg-surface-3"
                  }
                `}
              >
                <TokenIcon symbol={t.symbol} size={20} />
                {t.symbol}
              </button>
            ))}
          </div>
        )}

        {q && isAddressSearch && (
          <div className="mb-3">
            <div className="w-full px-3 py-2.5 rounded-[--radius-md] border border-accent/30 bg-accent/10 text-accent text-sm font-medium">
              {lookupLoading
                ? "Looking up token..."
                : "Detected address. Resolving token automatically..."}
            </div>
            {lookupError && (
              <p className="mt-1.5 text-xs text-error">{lookupError}</p>
            )}
          </div>
        )}

        <div className="h-px bg-border mb-2" />

        {/* Token list */}
        <div className="max-h-[360px] overflow-y-auto -mx-4 px-4">
          {filtered.length === 0 ? (
            <div className="py-12 text-center text-text-tertiary text-sm">
              {q ? "No tokens found" : "No tokens available"}
            </div>
          ) : (
            <div className="space-y-0.5">
              {filtered.map((t) => {
                const isSelected = selectedToken?.id === t.id;
                return (
                  <button
                    key={t.id}
                    type="button"
                    onClick={() => handleSelect(t)}
                    className={`
                      w-full flex items-center gap-3 px-3 py-2.5
                      rounded-[--radius-md] transition-colors duration-150 cursor-pointer
                      ${isSelected ? "bg-accent-muted" : "hover:bg-surface-2"}
                    `}
                  >
                    <TokenIcon symbol={t.symbol} size={36} />
                    <div className="flex flex-col items-start min-w-0">
                      <span className="text-sm font-semibold text-text-primary">
                        {t.symbol}
                      </span>
                      <span className="text-xs text-text-tertiary truncate max-w-[200px]">
                        {t.name || t.symbol}
                      </span>
                    </div>
                    {isSelected && (
                      <svg
                        className="ml-auto text-accent shrink-0"
                        width="18"
                        height="18"
                        viewBox="0 0 24 24"
                        fill="none"
                        stroke="currentColor"
                        strokeWidth="2.5"
                      >
                        <polyline points="20 6 9 17 4 12" />
                      </svg>
                    )}
                  </button>
                );
              })}
            </div>
          )}
        </div>
      </div>
    </Modal>
  );
}
