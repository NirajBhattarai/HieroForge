'use client'

import { useState, useEffect, useCallback } from 'react'
import { TokenIcon } from './TokenIcon'
import { useTokens } from '@/hooks/useTokens'

export interface PoolInfo {
  poolId: string
  pair: string
  tickSpacing: number
  fee: number
  feeLabel: string
  symbol0: string
  symbol1: string
  currency0: string
  currency1: string
}

interface PoolPositionsProps {
  onCreatePosition: () => void
  onSelectPool: (pool: PoolInfo) => void
}

function shortenAddr(addr: string): string {
  if (!addr || addr.length < 10) return addr
  return `${addr.slice(0, 6)}...${addr.slice(-4)}`
}

export function PoolPositions({ onCreatePosition, onSelectPool }: PoolPositionsProps) {
  const [pools, setPools] = useState<PoolInfo[]>([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)
  const [loadPoolId, setLoadPoolId] = useState('')
  const [loadError, setLoadError] = useState<string | null>(null)
  const [showLoadById, setShowLoadById] = useState(false)
  const [infoBoxDismissed, setInfoBoxDismissed] = useState(false)

  const { tokens: dynamicTokens } = useTokens()
  const tokenByAddr = new Map(dynamicTokens.map((t) => [t.address.toLowerCase(), t]))

  useEffect(() => {
    let cancelled = false
    setLoading(true)
    setError(null)
    fetch('/api/pools')
      .then((res) => {
        if (!res.ok) throw new Error('Failed to load pools')
        return res.json()
      })
      .then((data: Array<{ poolId: string; currency0: string; currency1: string; fee: number; tickSpacing: number; symbol0?: string; symbol1?: string }>) => {
        if (cancelled) return
        setPools(data.map((p) => ({
          poolId: p.poolId,
          pair: [p.symbol0 ?? shortenAddr(p.currency0), p.symbol1 ?? shortenAddr(p.currency1)].join(' / '),
          tickSpacing: p.tickSpacing,
          fee: p.fee,
          feeLabel: (p.fee / 10000).toFixed(2) + '%',
          symbol0: p.symbol0 ?? '',
          symbol1: p.symbol1 ?? '',
          currency0: p.currency0,
          currency1: p.currency1,
        })))
      })
      .catch((err) => {
        if (!cancelled) setError(err instanceof Error ? err.message : 'Failed to load pools')
      })
      .finally(() => {
        if (!cancelled) setLoading(false)
      })
    return () => { cancelled = true }
  }, [])

  const handleLoadById = useCallback(async () => {
    const id = loadPoolId.trim()
    if (!id) { setLoadError('Enter a pool ID'); return }
    setLoadError(null)
    try {
      const res = await fetch(`/api/pools/${encodeURIComponent(id)}`)
      if (!res.ok) {
        if (res.status === 404) throw new Error('Pool not found in DynamoDB')
        throw new Error('Failed to load pool')
      }
      const p = await res.json() as { poolId: string; currency0: string; currency1: string; fee: number; tickSpacing: number; symbol0?: string; symbol1?: string }
      const pool: PoolInfo = {
        poolId: p.poolId,
        pair: [p.symbol0 ?? shortenAddr(p.currency0), p.symbol1 ?? shortenAddr(p.currency1)].join(' / '),
        tickSpacing: p.tickSpacing,
        fee: p.fee,
        feeLabel: (p.fee / 10000).toFixed(2) + '%',
        symbol0: p.symbol0 ?? '',
        symbol1: p.symbol1 ?? '',
        currency0: p.currency0,
        currency1: p.currency1,
      }
      onSelectPool(pool)
    } catch (err) {
      setLoadError(err instanceof Error ? err.message : 'Failed to load pool')
    }
  }, [loadPoolId, onSelectPool])

  const hasPositions = pools.length > 0
  const topPools = pools.slice(0, 8)

  return (
    <div className="pool-tab-layout">
      {/* Left column: Rewards + Your positions */}
      <div className="pool-left">
        {/* Rewards card */}
        <div className="pool-rewards-card">
          <div className="pool-rewards-top">
            <div className="pool-rewards-balance">
              <span className="pool-rewards-amount">0</span>
              <span className="pool-rewards-token">
                <TokenIcon symbol="FORGE" size={24} />
                FORGE
              </span>
            </div>
            <button type="button" className="pool-rewards-collect-btn" disabled>
              Collect rewards
            </button>
          </div>
          <div className="pool-rewards-label">
            Rewards earned
            <span className="pool-rewards-info-icon" title="Rewards info">i</span>
          </div>
          <a href="#" className="pool-rewards-link" onClick={(e) => e.preventDefault()}>
            Find pools with FORGE rewards
            <span className="pool-rewards-arrow">→</span>
          </a>
          <p className="pool-rewards-desc">
            Eligible pools have token rewards so you can earn more.
          </p>
        </div>

        {/* Your positions */}
        <h2 className="pool-section-title">Your positions</h2>
        <div className="pool-filters-row">
          <div className="pool-new-dropdown">
            <button type="button" className="pool-btn-new" onClick={onCreatePosition}>
              + New
            </button>
            <button type="button" className="pool-dropdown-arrow" aria-label="New options">▾</button>
          </div>
          <button type="button" className="pool-filter-btn">Status ▾</button>
          <button type="button" className="pool-filter-btn">Protocol ▾</button>
          <button type="button" className="pool-filter-btn pool-filter-btn--icon" aria-label="View">⊞</button>
        </div>

        {/* Load by pool ID (collapsible) */}
        {showLoadById && (
          <div className="pool-load-by-id">
            <div className="pool-load-row">
              <input
                type="text"
                className="pool-load-input"
                placeholder="Pool ID (0x...)"
                value={loadPoolId}
                onChange={(e) => { setLoadPoolId(e.target.value); setLoadError(null) }}
                onKeyDown={(e) => e.key === 'Enter' && handleLoadById()}
              />
              <button type="button" className="pool-load-submit" onClick={handleLoadById}>Load</button>
            </div>
            {loadError && <p className="pool-load-error">{loadError}</p>}
          </div>
        )}

        {/* Content: empty state or list */}
        {error && <p className="pool-positions-error">{error}</p>}
        {loading ? (
          <div className="pool-empty-state">
            <div className="pool-empty-spinner" />
            <p>Loading positions...</p>
          </div>
        ) : !hasPositions ? (
          <div className="pool-empty-state">
            <div className="pool-empty-icon">
              <svg width="48" height="48" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round">
                <line x1="8" y1="6" x2="21" y2="6" />
                <line x1="8" y1="12" x2="21" y2="12" />
                <line x1="8" y1="18" x2="21" y2="18" />
                <line x1="3" y1="6" x2="3.01" y2="6" />
                <line x1="3" y1="12" x2="3.01" y2="12" />
                <line x1="3" y1="18" x2="3.01" y2="18" />
              </svg>
            </div>
            <h3 className="pool-empty-title">No positions</h3>
            <p className="pool-empty-desc">
              You don&apos;t have any liquidity positions. Create a new position to start earning fees and rewards on eligible pools.
            </p>
            <div className="pool-empty-actions">
              <button type="button" className="pool-btn-explore" onClick={() => setShowLoadById(!showLoadById)}>
                Explore pools
              </button>
              <button type="button" className="pool-btn-new-position" onClick={onCreatePosition}>
                New position
              </button>
            </div>
          </div>
        ) : (
          <div className="pool-positions-list">
            {pools.map((pool) => {
              const t0info = tokenByAddr.get(pool.currency0.toLowerCase())
              const t1info = tokenByAddr.get(pool.currency1.toLowerCase())
              return (
                <div
                  key={pool.poolId}
                  className="pool-position-card"
                  onClick={() => onSelectPool(pool)}
                >
                  <div className="pool-position-left">
                    <div className="pool-position-icons">
                      <TokenIcon symbol={pool.symbol0 || '?'} size={28} />
                      <TokenIcon symbol={pool.symbol1 || '?'} size={28} />
                    </div>
                    <div className="pool-position-info">
                      <span className="pool-position-pair">{pool.pair}</span>
                      <span className="pool-position-meta">v4 · {pool.feeLabel}</span>
                      {(t0info || t1info) && (
                        <span className="pool-position-details">
                          {t0info ? t0info.name : shortenAddr(pool.currency0)}
                          {' / '}
                          {t1info ? t1info.name : shortenAddr(pool.currency1)}
                        </span>
                      )}
                    </div>
                  </div>
                  <div className="pool-position-right">
                    <span className="pool-position-apr">— APR</span>
                    <span className="pool-position-id" title={pool.poolId}>{pool.poolId.slice(0, 10)}...</span>
                  </div>
                </div>
              )
            })}
          </div>
        )}

        {/* Info box */}
        {!infoBoxDismissed && (
          <div className="pool-info-box">
            <span className="pool-info-icon">i</span>
            <div className="pool-info-content">
              <p className="pool-info-title">Looking for your closed positions?</p>
              <p className="pool-info-desc">You can see them by using the filter at the top of the page.</p>
            </div>
            <button type="button" className="pool-info-close" onClick={() => setInfoBoxDismissed(true)} aria-label="Dismiss">×</button>
          </div>
        )}

        {/* Footer link */}
        <p className="pool-footer-link">
          Some v2 positions aren&apos;t displayed automatically.{' '}
          <button type="button" className="pool-import-link" onClick={() => setShowLoadById(true)}>Load pool by ID</button>
        </p>
      </div>

      {/* Right column: Top pools + Learn */}
      <aside className="pool-right">
        <h2 className="pool-sidebar-title">Top pools by TVL</h2>
        <div className="pool-top-pools">
          {loading ? (
            <div className="pool-top-placeholder">Loading...</div>
          ) : topPools.length === 0 ? (
            <div className="pool-top-placeholder">No pools yet</div>
          ) : (
            topPools.map((pool) => (
              <div
                key={pool.poolId}
                className="pool-top-card"
                onClick={() => onSelectPool(pool)}
              >
                <div className="pool-top-icons">
                  <TokenIcon symbol={pool.symbol0 || '?'} size={24} />
                  <TokenIcon symbol={pool.symbol1 || '?'} size={24} />
                </div>
                <div className="pool-top-info">
                  <span className="pool-top-pair">{pool.pair}</span>
                  <span className="pool-top-meta">v4 · {pool.feeLabel}</span>
                </div>
                <span className="pool-top-apr">— APR</span>
              </div>
            ))
          )}
        </div>
        <a href="#" className="pool-explore-more" onClick={(e) => e.preventDefault()}>
          Explore more pools
          <span className="pool-explore-arrow">→</span>
        </a>

        <div className="pool-learn-card">
          <h3 className="pool-learn-title">Learn about liquidity provision</h3>
          <div className="pool-learn-inner">
            <div className="pool-learn-icon-wrap">
              <svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
                <path d="M7 17L17 7" />
                <path d="M17 7H7V17" />
              </svg>
            </div>
            <p className="pool-learn-text">Providing liquidity on different protocols</p>
          </div>
        </div>
      </aside>
    </div>
  )
}
