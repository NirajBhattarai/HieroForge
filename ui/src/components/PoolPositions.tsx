'use client'

import { useState, useEffect, useCallback } from 'react'
import { TokenIcon } from './TokenIcon'
import { useTokens, type DynamicToken } from '@/hooks/useTokens'

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

  // Dynamic tokens from DynamoDB for enriching pool display
  const { tokens: dynamicTokens } = useTokens()
  const tokenByAddr = new Map(dynamicTokens.map((t) => [t.address.toLowerCase(), t]))

  // Fetch pools from DynamoDB on mount
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

  return (
    <div className="positions-page">
      {/* Header */}
      <div className="positions-header">
        <div>
          <h2 className="positions-title">Positions</h2>
          <p className="positions-subtitle">
            Create and manage your liquidity positions. Pools are stored in DynamoDB.
          </p>
        </div>
        <button type="button" className="btn-new-position" onClick={onCreatePosition}>
          + New position
        </button>
      </div>

      {/* Load by pool ID */}
      <div className="load-by-id">
        <div className="load-by-id-row">
          <input
            type="text"
            className="load-by-id-input"
            placeholder="Load pool by ID (0x...)"
            value={loadPoolId}
            onChange={(e) => { setLoadPoolId(e.target.value); setLoadError(null) }}
            onKeyDown={(e) => e.key === 'Enter' && handleLoadById()}
          />
          <button type="button" className="btn-load" onClick={handleLoadById}>
            Load
          </button>
        </div>
        {loadError && <p className="load-error">{loadError}</p>}
      </div>

      {/* Pool list */}
      {error && <p className="positions-error">{error}</p>}
      {loading ? (
        <div className="positions-empty">
          <div className="positions-spinner" />
          <p>Loading positions...</p>
        </div>
      ) : pools.length === 0 ? (
        <div className="positions-empty">
          <div className="positions-empty-icon">📊</div>
          <h3>No positions yet</h3>
          <p>Create a new position to provide liquidity and earn fees.</p>
          <button type="button" className="btn-new-position" onClick={onCreatePosition}>
            + New position
          </button>
        </div>
      ) : (
        <div className="positions-list">
          {pools.map((pool) => {
            const t0info = tokenByAddr.get(pool.currency0.toLowerCase())
            const t1info = tokenByAddr.get(pool.currency1.toLowerCase())
            return (
              <div
                key={pool.poolId}
                className="position-card"
                onClick={() => onSelectPool(pool)}
              >
                <div className="position-card-left">
                  <div className="position-card-icons">
                    <TokenIcon symbol={pool.symbol0 || '?'} size={32} />
                    <TokenIcon symbol={pool.symbol1 || '?'} size={32} />
                  </div>
                  <div className="position-card-info">
                    <span className="position-card-pair">{pool.pair}</span>
                    <span className="position-card-fee">{pool.feeLabel} fee tier</span>
                    {(t0info || t1info) && (
                      <span className="position-card-details">
                        {t0info ? `${t0info.name} (${t0info.decimals}d)` : shortenAddr(pool.currency0)}
                        {' / '}
                        {t1info ? `${t1info.name} (${t1info.decimals}d)` : shortenAddr(pool.currency1)}
                      </span>
                    )}
                  </div>
                </div>
                <div className="position-card-right">
                  <span className="position-card-id" title={pool.poolId}>
                    {pool.poolId.slice(0, 10)}...
                  </span>
                </div>
              </div>
            )
          })}
        </div>
      )}
    </div>
  )
}
