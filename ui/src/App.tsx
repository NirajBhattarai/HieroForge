"use client";

import { useState, useCallback } from "react";
import { useHashPack } from "@/context/HashPackContext";
import { getFriendlyErrorMessage } from "@/lib/errors";
import { Header } from "@/components/Header";
import { SwapCard } from "@/components/SwapCard";
import { PoolPositions, type PoolInfo } from "@/components/PoolPositions";
import { NewPosition } from "@/components/NewPosition";
import { Explore } from "@/components/Explore";
import { Modal } from "@/components/ui/Modal";
import { TAB, DEFAULT_TOKENS, type TokenOption } from "@/constants";
import { useTokens } from "@/hooks/useTokens";

function App() {
  const [tab, setTab] = useState<string>(TAB.TRADE);
  const {
    accountId,
    formattedAccountId,
    isConnected,
    isInitialized,
    isConnecting,
    error,
    connect,
    disconnect,
  } = useHashPack();

  const { tokens: dynamicTokens } = useTokens();
  const tokenOptions: TokenOption[] =
    dynamicTokens.length > 0
      ? dynamicTokens.map((t) => ({
          id: t.address,
          symbol: t.symbol,
          address: t.address,
          decimals: t.decimals,
          name: t.name,
        }))
      : DEFAULT_TOKENS;

  const [showNewPositionModal, setShowNewPositionModal] = useState(false);
  const [selectedPoolForPosition, setSelectedPoolForPosition] =
    useState<PoolInfo | null>(null);
  const [selectedPool, setSelectedPool] = useState<{
    poolId: string;
    currency0: string;
    currency1: string;
    fee: number;
    tickSpacing: number;
    symbol0: string;
    symbol1: string;
  } | null>(null);

  const handleSelectPool = useCallback((pool: PoolInfo) => {
    setSelectedPool({
      poolId: pool.poolId,
      currency0: pool.currency0,
      currency1: pool.currency1,
      fee: pool.fee,
      tickSpacing: pool.tickSpacing,
      symbol0: pool.symbol0,
      symbol1: pool.symbol1,
    });
    setSelectedPoolForPosition(pool);
    setTab(TAB.POOL);
    setShowNewPositionModal(true);
  }, []);

  return (
    <div className="min-h-screen flex flex-col">
      <Header
        tab={tab}
        setTab={setTab}
        isConnected={isConnected}
        isConnecting={isConnecting}
        isInitialized={isInitialized}
        formattedAccountId={formattedAccountId}
        accountId={accountId}
        error={error}
        onConnect={connect}
        onDisconnect={disconnect}
      />

      <main className="flex-1 flex flex-col">
        {/* Trade Tab */}
        {tab === TAB.TRADE && (
          <div className="flex-1 flex items-start justify-center pt-12 px-4 pb-8">
            <SwapCard selectedPool={selectedPool} />
          </div>
        )}

        {/* Explore Tab */}
        {tab === TAB.EXPLORE && (
          <div className="flex-1">
            <Explore onSelectPool={handleSelectPool} />
          </div>
        )}

        {/* Pool Tab */}
        {tab === TAB.POOL && (
          <div className="flex-1">
            <PoolPositions
              onCreatePosition={() => {
                setSelectedPoolForPosition(null);
                setShowNewPositionModal(true);
              }}
              onSelectPool={handleSelectPool}
            />
          </div>
        )}

        {/* New Position Modal */}
        <Modal
          open={showNewPositionModal}
          onClose={() => setShowNewPositionModal(false)}
          maxWidth="max-w-[900px]"
        >
          <NewPosition
            onBack={() => setShowNewPositionModal(false)}
            preselectedPool={selectedPoolForPosition}
          />
        </Modal>
      </main>
    </div>
  );
}

export default App;
