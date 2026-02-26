import { useState } from 'react'
import './App.css'
import { useHashPack } from './context/HashPackContext.jsx'

const TAB = { SWAP: 'swap', POOL: 'pool', LIQUIDITY: 'liquidity' }

const DEFAULT_TOKENS = [
  { id: 'token0', symbol: 'HBAR' },
  { id: 'token1', symbol: 'USDC' },
  { id: 'token2', symbol: 'TokenA' },
]

function App() {
  const [tab, setTab] = useState(TAB.SWAP)
  const {
    accountId,
    formattedAccountId,
    isConnected,
    isInitialized,
    isConnecting,
    error,
    connect,
    disconnect,
  } = useHashPack()

  // Swap state
  const [amountIn, setAmountIn] = useState('')
  const [amountOut, setAmountOut] = useState('')
  const [tokenIn, setTokenIn] = useState(DEFAULT_TOKENS[0])
  const [tokenOut, setTokenOut] = useState(DEFAULT_TOKENS[1])

  // Add liquidity state
  const [tickLower, setTickLower] = useState('-60')
  const [tickUpper, setTickUpper] = useState('60')
  const [liquidityAmount, setLiquidityAmount] = useState('')
  const [liquidityToken0, setLiquidityToken0] = useState(DEFAULT_TOKENS[0])
  const [liquidityToken1, setLiquidityToken1] = useState(DEFAULT_TOKENS[1])

  const flipTokens = () => {
    setTokenIn(tokenOut)
    setTokenOut(tokenIn)
    setAmountIn(amountOut)
    setAmountOut(amountIn)
  }

  // Mock pools for display
  const pools = [
    { id: '1', pair: 'HBAR / USDC', tickSpacing: 60, fee: '0.3%' },
    { id: '2', pair: 'TokenA / USDC', tickSpacing: 60, fee: '0.3%' },
  ]

  return (
    <div className="app">
      <header className="header">
        <span className="logo">HieroForge</span>
        <nav className="nav">
          <button
            className={`nav-btn ${tab === TAB.SWAP ? 'active' : ''}`}
            onClick={() => setTab(TAB.SWAP)}
          >
            Swap
          </button>
          <button
            className={`nav-btn ${tab === TAB.POOL ? 'active' : ''}`}
            onClick={() => setTab(TAB.POOL)}
          >
            Pool
          </button>
          <button
            className={`nav-btn ${tab === TAB.LIQUIDITY ? 'active' : ''}`}
            onClick={() => setTab(TAB.LIQUIDITY)}
          >
            Add Liquidity
          </button>
        </nav>
        {error && <span className="header-error">{error}</span>}
        <button
          className={`connect-btn ${isConnected ? 'connected' : ''}`}
          onClick={() => (isConnected ? disconnect() : connect())}
          disabled={isConnecting || !isInitialized}
        >
          {isConnecting
            ? 'Connecting...'
            : isConnected
              ? formattedAccountId || accountId
              : 'Connect HashPack'}
        </button>
      </header>

      <main className="main">
        {tab === TAB.SWAP && (
          <div className="card">
            <h2 className="card-title">Swap</h2>
            <div className="token-row">
              <div className="token-row-label">You pay</div>
              <div className="token-row-inner">
                <input
                  type="text"
                  className="token-input"
                  placeholder="0.0"
                  value={amountIn}
                  onChange={(e) => setAmountIn(e.target.value)}
                />
                <select
                  className="token-select"
                  value={tokenIn.id}
                  onChange={(e) =>
                    setTokenIn(DEFAULT_TOKENS.find((t) => t.id === e.target.value))
                  }
                >
                  {DEFAULT_TOKENS.map((t) => (
                    <option key={t.id} value={t.id}>
                      {t.symbol}
                    </option>
                  ))}
                </select>
              </div>
            </div>
            <div className="flip-row">
              <button type="button" className="flip-btn" onClick={flipTokens} aria-label="Flip">
                ↓↑
              </button>
            </div>
            <div className="token-row">
              <div className="token-row-label">You receive</div>
              <div className="token-row-inner">
                <input
                  type="text"
                  className="token-input"
                  placeholder="0.0"
                  value={amountOut}
                  onChange={(e) => setAmountOut(e.target.value)}
                />
                <select
                  className="token-select"
                  value={tokenOut.id}
                  onChange={(e) =>
                    setTokenOut(DEFAULT_TOKENS.find((t) => t.id === e.target.value))
                  }
                >
                  {DEFAULT_TOKENS.map((t) => (
                    <option key={t.id} value={t.id}>
                      {t.symbol}
                    </option>
                  ))}
                </select>
              </div>
            </div>
            <p className="helper">Concentrated liquidity · Price limit optional</p>
            <button
              type="button"
              className="primary-btn"
              disabled={!amountIn || !amountOut || !isConnected}
            >
              Swap
            </button>
          </div>
        )}

        {tab === TAB.POOL && (
          <div className="card">
            <h2 className="card-title">Pools</h2>
            <ul className="pool-list">
              {pools.map((pool) => (
                <li key={pool.id} className="pool-item">
                  <div>
                    <span className="pool-pair">{pool.pair}</span>
                    <div className="pool-meta">
                      Tick spacing {pool.tickSpacing} · Fee {pool.fee}
                    </div>
                  </div>
                </li>
              ))}
            </ul>
            <p className="helper">Initialize new pools from smart contract (PoolManager).</p>
          </div>
        )}

        {tab === TAB.LIQUIDITY && (
          <div className="card">
            <h2 className="card-title">Add Liquidity</h2>
            <div className="form-group">
              <label>Token pair</label>
              <div style={{ display: 'flex', gap: 8, marginTop: 4 }}>
                <select
                  className="token-select"
                  style={{ flex: 1 }}
                  value={liquidityToken0.id}
                  onChange={(e) =>
                    setLiquidityToken0(DEFAULT_TOKENS.find((t) => t.id === e.target.value))
                  }
                >
                  {DEFAULT_TOKENS.map((t) => (
                    <option key={t.id} value={t.id}>
                      {t.symbol}
                    </option>
                  ))}
                </select>
                <select
                  className="token-select"
                  style={{ flex: 1 }}
                  value={liquidityToken1.id}
                  onChange={(e) =>
                    setLiquidityToken1(DEFAULT_TOKENS.find((t) => t.id === e.target.value))
                  }
                >
                  {DEFAULT_TOKENS.map((t) => (
                    <option key={t.id} value={t.id}>
                      {t.symbol}
                    </option>
                  ))}
                </select>
              </div>
            </div>
            <div className="form-group">
              <label>Tick lower (e.g. -60 for tickSpacing 60)</label>
              <input
                type="text"
                value={tickLower}
                onChange={(e) => setTickLower(e.target.value)}
                placeholder="-60"
              />
            </div>
            <div className="form-group">
              <label>Tick upper (e.g. 60 for tickSpacing 60)</label>
              <input
                type="text"
                value={tickUpper}
                onChange={(e) => setTickUpper(e.target.value)}
                placeholder="60"
              />
            </div>
            <div className="form-group">
              <label>Liquidity amount</label>
              <input
                type="text"
                value={liquidityAmount}
                onChange={(e) => setLiquidityAmount(e.target.value)}
                placeholder="0"
              />
            </div>
            <p className="helper">
              Liquidity is provided in the selected tick range. Must be multiple of tick spacing.
            </p>
            <button
              type="button"
              className="primary-btn"
              disabled={!liquidityAmount || !isConnected}
            >
              Add Liquidity
            </button>
          </div>
        )}
      </main>
    </div>
  )
}

export default App
