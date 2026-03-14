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
    <header className="sticky top-0 z-40 w-full border-b border-white/[0.06] bg-surface-0/90 backdrop-blur-xl shadow-[0_1px_0_0_rgba(255,255,255,0.03)]">
      <div className="mx-auto max-w-6xl flex items-center justify-between h-14 sm:h-16 px-3 sm:px-4 lg:px-6">
        {/* Logo */}
        <div className="flex items-center gap-4 sm:gap-6">
          <span className="text-lg sm:text-xl font-bold tracking-tight text-text-primary flex items-center gap-2">
            <svg width="26" height="26" className="sm:w-7 sm:h-7" viewBox="0 0 32 32" fill="none">
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

          {/* Desktop nav pills */}
          <nav className="hidden sm:flex items-center rounded-full p-1 bg-surface-2/80 border border-white/[0.06] shadow-inner">
            {NAV_ITEMS.map((item) => (
              <button
                key={item.key}
                onClick={() => setTab(item.key)}
                className={`
                  px-4 py-2 text-sm font-medium rounded-full
                  transition-all duration-200 cursor-pointer
                  ${
                    tab === item.key
                      ? "bg-surface-1 text-text-primary shadow-sm border border-white/[0.08]"
                      : "text-text-tertiary hover:text-text-secondary hover:bg-white/[0.04] active:bg-white/[0.06]"
                  }
                `}
              >
                {item.label}
              </button>
            ))}
          </nav>
        </div>

        {/* Right side */}
        <div className="flex items-center gap-2 sm:gap-3">
          <Badge variant="accent" className="hidden sm:inline-flex cursor-default">
            Testnet
          </Badge>

          <button
            onClick={() => (isConnected ? onDisconnect() : onConnect())}
            disabled={isConnecting || !isInitialized}
            className={`
              px-3 sm:px-4 py-2 text-sm font-semibold rounded-xl
              transition-all duration-200 cursor-pointer
              disabled:opacity-50 disabled:cursor-not-allowed
              ${
                isConnected
                  ? "bg-surface-2/80 text-text-primary border border-white/[0.08] hover:border-accent/30 hover:bg-surface-3/80"
                  : "bg-accent text-surface-0 hover:bg-accent-hover shadow-md hover:shadow-lg hover:shadow-accent/20"
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
                <span className="w-2 h-2 rounded-full bg-success ring-2 ring-success/30" />
                {formattedAccountId || accountId || ""}
              </span>
            ) : (
              "Connect Wallet"
            )}
          </button>
        </div>
      </div>

      {/* Mobile nav — pill container */}
      <nav className="flex sm:hidden items-center gap-1 px-3 pb-3 pt-0.5">
        <div className="flex flex-1 items-center rounded-full p-1 bg-surface-2/80 border border-white/[0.06] shadow-inner">
          {NAV_ITEMS.map((item) => (
            <button
              key={item.key}
              onClick={() => setTab(item.key)}
              className={`
                flex-1 px-3 py-2.5 text-sm font-medium rounded-full text-center
                transition-all duration-200 cursor-pointer
                ${
                  tab === item.key
                    ? "bg-surface-1 text-text-primary shadow-sm border border-white/[0.08]"
                    : "text-text-tertiary hover:text-text-secondary active:bg-white/[0.04]"
                }
              `}
            >
              {item.label}
            </button>
          ))}
        </div>
      </nav>
    </header>
  );
}
