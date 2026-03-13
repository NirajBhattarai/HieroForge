"use client";

import { type TabValue, TAB } from "@/constants";
import { Badge } from "@/components/ui/Badge";

interface HeaderProps {
  tab: string;
  setTab: (tab: TabValue) => void;
  isConnected: boolean;
  isConnecting: boolean;
  isInitialized: boolean;
  formattedAccountId: string | null;
  accountId: string | null;
  error: string | Error | null;
  onConnect: () => void;
  onDisconnect: () => void;
}

const NAV_ITEMS: { key: TabValue; label: string }[] = [
  { key: TAB.TRADE, label: "Trade" },
  { key: TAB.EXPLORE, label: "Explore" },
  { key: TAB.POOL, label: "Pool" },
];

export function Header({
  tab,
  setTab,
  isConnected,
  isConnecting,
  isInitialized,
  formattedAccountId,
  accountId,
  onConnect,
  onDisconnect,
}: HeaderProps) {
  return (
    <header className="sticky top-0 z-40 w-full border-b border-border bg-surface-0/80 backdrop-blur-xl">
      <div className="mx-auto max-w-6xl flex items-center justify-between h-16 px-4 lg:px-6">
        {/* Logo */}
        <div className="flex items-center gap-6">
          <span className="text-xl font-bold tracking-tight text-text-primary flex items-center gap-2">
            <svg width="28" height="28" viewBox="0 0 32 32" fill="none">
              <rect width="32" height="32" rx="8" fill="url(#logo-grad)" />
              <path
                d="M10 22V10l6 4 6-4v12l-6-4-6 4z"
                fill="white"
                fillOpacity="0.9"
              />
              <defs>
                <linearGradient
                  id="logo-grad"
                  x1="0"
                  y1="0"
                  x2="32"
                  y2="32"
                  gradientUnits="userSpaceOnUse"
                >
                  <stop stopColor="#38bdf8" />
                  <stop offset="1" stopColor="#818cf8" />
                </linearGradient>
              </defs>
            </svg>
            HieroForge
          </span>

          {/* Navigation pills */}
          <nav className="hidden sm:flex items-center bg-surface-1 rounded-[--radius-full] p-1">
            {NAV_ITEMS.map((item) => (
              <button
                key={item.key}
                onClick={() => setTab(item.key)}
                className={`
                  px-4 py-1.5 text-sm font-medium rounded-[--radius-full]
                  transition-all duration-200 cursor-pointer
                  ${
                    tab === item.key
                      ? "bg-surface-3 text-text-primary shadow-sm"
                      : "text-text-tertiary hover:text-text-secondary"
                  }
                `}
              >
                {item.label}
              </button>
            ))}
          </nav>
        </div>

        {/* Right side */}
        <div className="flex items-center gap-3">
          <Badge variant="accent" className="hidden sm:inline-flex">
            Testnet
          </Badge>

          <button
            onClick={() => (isConnected ? onDisconnect() : onConnect())}
            disabled={isConnecting || !isInitialized}
            className={`
              px-4 py-2 text-sm font-semibold rounded-[--radius-md]
              transition-all duration-200 cursor-pointer
              disabled:opacity-50 disabled:cursor-not-allowed
              ${
                isConnected
                  ? "bg-surface-2 text-text-primary border border-border hover:border-border-hover hover:bg-surface-3"
                  : "bg-accent text-surface-0 hover:bg-accent-hover shadow-sm"
              }
            `}
          >
            {isConnecting ? (
              <span className="flex items-center gap-2">
                <svg
                  className="animate-spin h-4 w-4"
                  viewBox="0 0 24 24"
                  fill="none"
                >
                  <circle
                    className="opacity-25"
                    cx="12"
                    cy="12"
                    r="10"
                    stroke="currentColor"
                    strokeWidth="4"
                  />
                  <path
                    className="opacity-75"
                    fill="currentColor"
                    d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4z"
                  />
                </svg>
                Connecting...
              </span>
            ) : isConnected ? (
              <span className="flex items-center gap-2">
                <span className="w-2 h-2 rounded-full bg-success" />
                {formattedAccountId || accountId || ""}
              </span>
            ) : (
              "Connect Wallet"
            )}
          </button>
        </div>
      </div>

      {/* Mobile nav */}
      <nav className="flex sm:hidden items-center justify-center gap-1 px-4 pb-2">
        {NAV_ITEMS.map((item) => (
          <button
            key={item.key}
            onClick={() => setTab(item.key)}
            className={`
              px-4 py-1.5 text-sm font-medium rounded-[--radius-full]
              transition-all duration-200 cursor-pointer flex-1 text-center
              ${
                tab === item.key
                  ? "bg-surface-3 text-text-primary"
                  : "text-text-tertiary hover:text-text-secondary"
              }
            `}
          >
            {item.label}
          </button>
        ))}
      </nav>
    </header>
  );
}
