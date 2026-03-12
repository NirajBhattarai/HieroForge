'use client'

import { useState, useEffect } from 'react'
import { TokenIcon } from './TokenIcon'
import type { PoolInfo } from './PoolPositions'

function shortenAddr(addr: string): string {
  if (!addr || addr.length < 10) return addr
  return `${addr.slice(0, 6)}...${addr.slice(-4)}`
}

interface ExploreProps {
  onSelectPool: (pool: PoolInfo) => void
}

export function Explore({ onSelectPool }: ExploreProps) {
  const [pools, setPools] = useState<PoolInfo[]>([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)
  const [search, setSearch] = useState('')

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

  const q = search.trim().toLowerCase()
  const filtered = q
    ? pools.filter(
        (p) =>
          p.pair.toLowerCase().includes(q) ||
          p.symbol0.toLowerCase().includes(q) ||
          p.symbol1.toLowerCase().includes(q) ||
          p.poolId.toLowerCase().includes(q)
      )
    : pools

  return (
    <div className="explore-page">
      <div className="explore-header">
        <h1 className="explore-title">Explore</h1>
        <p className="explore-subtitle">
          Browse all liquidity pools. Select a pool to add liquidity.
        </p>
      </div>

      <div className="explore-search-wrap">
        <span className="explore-search-icon" aria-hidden>⌕</span>
        <input
          type="search"
          className="explore-search"
          placeholder="Search tokens and pools"
          value={search}
          onChange={(e) => setSearch(e.target.value)}
          aria-label="Search pools"
        />
      </div>

      {error && <p className="explore-error">{error}</p>}
      {loading ? (
        <div className="explore-loading">
          <div className="explore-spinner" />
          <p>Loading pools...</p>
        </div>
      ) : filtered.length === 0 ? (
        <div className="explore-empty">
          <p>{q ? 'No pools match your search.' : 'No pools yet.'}</p>
          <p className="explore-empty-hint">Create a pool from the Pool tab.</p>
        </div>
      ) : (
        <div className="explore-list">
          {filtered.map((pool) => (
            <button
              key={pool.poolId}
              type="button"
              className="explore-pool-card"
              onClick={() => onSelectPool(pool)}
            >
              <div className="explore-pool-icons">
                <TokenIcon symbol={pool.symbol0 || '?'} size={32} />
                <TokenIcon symbol={pool.symbol1 || '?'} size={32} />
              </div>
              <div className="explore-pool-info">
                <span className="explore-pool-pair">{pool.pair}</span>
                <span className="explore-pool-meta">v4 · {pool.feeLabel}</span>
              </div>
              <span className="explore-pool-apr">— APR</span>
              <span className="explore-pool-arrow">→</span>
            </button>
          ))}
        </div>
      )}
    </div>
  )
}
