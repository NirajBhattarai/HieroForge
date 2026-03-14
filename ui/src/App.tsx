"use client";

import { useState, useCallback } from "react";
import { useHashPack } from "@/context/HashPackContext";
import { getFriendlyErrorMessage } from "@/lib/errors";
import { Header } from "@/components/Header";
import { SwapCard } from "@/components/SwapCard";
import { PoolPositions, type PoolInfo } from "@/components/PoolPositions";
import { PositionDetail } from "@/components/PositionDetail";
import { AddLiquidityModal } from "@/components/AddLiquidityModal";
import { RemoveLiquidityModal } from "@/components/RemoveLiquidityModal";
import { NewPosition } from "@/components/NewPosition";
import { Explore } from "@/components/Explore";
import { Modal } from "@/components/ui/Modal";
import { TAB, type TokenOption } from "@/constants";
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
  const tokenOptions: TokenOption[] = dynamicTokens.map((t) => ({
    id: t.address,
    symbol: t.symbol,
    address: t.address,
    decimals: t.decimals,
    name: t.name,
  }));

  const [showNewPositionModal, setShowNewPositionModal] = useState(false);
  const [selectedPoolForPosition, setSelectedPoolForPosition] =
    useState<PoolInfo | null>(null);
  /** When set, Pool tab shows this pool's detail view instead of the list */
  const [selectedPoolDetail, setSelectedPoolDetail] = useState<PoolInfo | null>(
    null,
  );
  /** When set, show Add liquidity modal (from position detail) */
  const [addLiquidityPool, setAddLiquidityPool] = useState<PoolInfo | null>(null);
  /** When set, show Remove liquidity modal (from position detail) */
  const [removeLiquidityPool, setRemoveLiquidityPool] =
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
    setSelectedPoolDetail(pool);
    setTab(TAB.POOL);
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
            {selectedPoolDetail ? (
              <PositionDetail
                pool={selectedPoolDetail}
                onBack={() => setSelectedPoolDetail(null)}
                onAddLiquidity={() => {
                  setAddLiquidityPool(selectedPoolDetail);
                }}
                onRemoveLiquidity={() => {
                  setRemoveLiquidityPool(selectedPoolDetail);
                }}
              />
            ) : (
              <PoolPositions
                onCreatePosition={() => {
                  setSelectedPoolForPosition(null);
                  setShowNewPositionModal(true);
                }}
                onSelectPool={handleSelectPool}
              />
            )}
          </div>
        )}

        {/* Add liquidity modal (from position detail) */}
        <Modal
          open={!!addLiquidityPool}
          onClose={() => setAddLiquidityPool(null)}
          title="Add liquidity"
          headerRight={
            <button
              type="button"
              className="flex items-center justify-center w-9 h-9 rounded-xl text-text-tertiary hover:text-text-primary hover:bg-surface-3/80 transition-colors cursor-pointer"
              aria-label="Settings"
            >
              <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
                <circle cx="12" cy="12" r="3" />
                <path d="M19.4 15a1.65 1.65 0 00.33 1.82l.06.06a2 2 0 010 2.83 2 2 0 01-2.83 0l-.06-.06a1.65 1.65 0 00-1.82-.33 1.65 1.65 0 00-1 1.51V21a2 2 0 01-2 2 2 2 0 01-2-2v-.09A1.65 1.65 0 009 19.4a1.65 1.65 0 00-1.82.33l-.06.06a2 2 0 01-2.83 0 2 2 0 010-2.83l.06-.06A1.65 1.65 0 004.68 15a1.65 1.65 0 00-1.51-1H3a2 2 0 01-2-2 2 2 0 012-2h.09A1.65 1.65 0 004.6 9a1.65 1.65 0 00-.33-1.82l-.06-.06a2 2 0 010-2.83 2 2 0 012.83 0l.06.06A1.65 1.65 0 009 4.68a1.65 1.65 0 001-1.51V3a2 2 0 012-2 2 2 0 012 2v.09a1.65 1.65 0 001 1.51 1.65 1.65 0 001.82-.33l.06-.06a2 2 0 012.83 0 2 2 0 010 2.83l-.06.06A1.65 1.65 0 0019.32 9a1.65 1.65 0 001.51 1H21a2 2 0 012 2 2 2 0 01-2 2h-.09a1.65 1.65 0 00-1.51 1z" />
              </svg>
            </button>
          }
          maxWidth="max-w-[480px]"
        >
          {addLiquidityPool && (
            <AddLiquidityModal
              pool={addLiquidityPool}
              onClose={() => setAddLiquidityPool(null)}
              onOpenFullFlow={() => {
                setAddLiquidityPool(null);
                setSelectedPoolForPosition(addLiquidityPool);
                setShowNewPositionModal(true);
              }}
            />
          )}
        </Modal>

        {/* Remove liquidity modal (from position detail) */}
        <Modal
          open={!!removeLiquidityPool}
          onClose={() => setRemoveLiquidityPool(null)}
          title="Remove liquidity"
          headerRight={
            <button
              type="button"
              className="flex items-center justify-center w-9 h-9 rounded-xl text-text-tertiary hover:text-text-primary hover:bg-surface-3/80 transition-colors cursor-pointer"
              aria-label="Settings"
            >
              <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
                <circle cx="12" cy="12" r="3" />
                <path d="M19.4 15a1.65 1.65 0 00.33 1.82l.06.06a2 2 0 010 2.83 2 2 0 01-2.83 0l-.06-.06a1.65 1.65 0 00-1.82-.33 1.65 1.65 0 00-1 1.51V21a2 2 0 01-2 2 2 2 0 01-2-2v-.09A1.65 1.65 0 009 19.4a1.65 1.65 0 00-1.82.33l-.06.06a2 2 0 01-2.83 0 2 2 0 010-2.83l.06-.06A1.65 1.65 0 004.68 15a1.65 1.65 0 00-1.51-1H3a2 2 0 01-2-2 2 2 0 012-2h.09A1.65 1.65 0 004.6 9a1.65 1.65 0 00-.33-1.82l-.06-.06a2 2 0 010-2.83 2 2 0 012.83 0l.06.06A1.65 1.65 0 009 4.68a1.65 1.65 0 001-1.51V3a2 2 0 012-2 2 2 0 012 2v.09a1.65 1.65 0 001 1.51 1.65 1.65 0 001.82-.33l.06-.06a2 2 0 012.83 0 2 2 0 010 2.83l-.06.06A1.65 1.65 0 0019.32 9a1.65 1.65 0 001.51 1H21a2 2 0 012 2 2 2 0 01-2 2h-.09a1.65 1.65 0 00-1.51 1z" />
              </svg>
            </button>
          }
          maxWidth="max-w-[480px]"
        >
          {removeLiquidityPool && (
            <RemoveLiquidityModal
              pool={removeLiquidityPool}
              onClose={() => setRemoveLiquidityPool(null)}
            />
          )}
        </Modal>

        {/* New Position Modal (full flow: pair, fee, range, deposit) */}
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
