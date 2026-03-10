'use client'

import { useState, useCallback, useEffect, useRef } from 'react'
import { createWalletClient, createPublicClient, custom, http, parseUnits, formatUnits, encodeFunctionData } from 'viem'
import './App.css'
import { useHashPack } from '@/context/HashPackContext'
import { PoolManagerAbi, SQRT_PRICE_PRESETS } from '@/abis/PoolManager'
import { PositionManagerAbi, SQRT_PRICE_1_1 } from '@/abis/PositionManager'
import { ERC20Abi } from '@/abis/ERC20'
import { quoteExactInputSingle, NotEnoughLiquidityError } from '@/lib/quote'
import { getFriendlyErrorMessage } from '@/lib/errors'
import { ErrorMessage } from '@/components/ErrorMessage'
import { TokenIcon } from '@/components/TokenIcon'
import {
  buildPoolKey,
  getPoolId,
  encodeUnlockDataMint,
} from '@/lib/addLiquidity'
import { tickToPrice, priceToTick, roundToTickSpacing, PRICE_STRATEGIES } from '@/lib/priceUtils'
import {
  TAB,
  HEDERA_TESTNET,
  DEFAULT_TOKENS,
  getTokenAddress,
  getTokenDecimals,
  getPoolManagerAddress,
  getQuoterAddress,
  getPositionManagerAddress,
  DEFAULT_FEE,
  DEFAULT_TICK_SPACING,
  type TokenOption,
} from '@/constants'

interface PoolInfo {
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

interface CreatePoolTx {
  hash: string
}

function App() {
  const [tab, setTab] = useState<string>(TAB.SWAP)
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
  const [quoteError, setQuoteError] = useState<string | null>(null)
  const [quoteLoading, setQuoteLoading] = useState(false)
  const [tokenIn, setTokenIn] = useState<TokenOption>(DEFAULT_TOKENS[0]!)
  const [tokenOut, setTokenOut] = useState<TokenOption>(DEFAULT_TOKENS[1]!)

  // Add liquidity state (Uniswap v4 style: create pool if needed, else add)
  const [liquidityToken0, setLiquidityToken0] = useState<TokenOption>(DEFAULT_TOKENS[0]!)
  const [liquidityToken1, setLiquidityToken1] = useState<TokenOption>(DEFAULT_TOKENS[1]!)
  const [liquidityFeeTier, setLiquidityFeeTier] = useState('3000') // 0.3%
  const [liquidityTickSpacing, setLiquidityTickSpacing] = useState(60)
  const [tickLower, setTickLower] = useState(-60)
  const [tickUpper, setTickUpper] = useState(60)
  const [amount0, setAmount0] = useState('')
  const [amount1, setAmount1] = useState('')
  const [liquidityAmount, setLiquidityAmount] = useState('100000000') // L for the range
  const [poolInitialized, setPoolInitialized] = useState<boolean | null>(null)
  const [liquidityError, setLiquidityError] = useState<string | null>(null)
  const [addLiquidityTx, setAddLiquidityTx] = useState<{ hash: string } | null>(null)
  const [addLiquidityPending, setAddLiquidityPending] = useState(false)

  // Pool view: 'list' = pool list, 'create' = create pool / add liquidity page
  const [poolView, setPoolView] = useState<'list' | 'create'>('list')

  // Pools from DynamoDB (no hardcoding)
  const [availablePools, setAvailablePools] = useState<PoolInfo[]>([])
  const [poolsLoading, setPoolsLoading] = useState(true)
  const [poolsError, setPoolsError] = useState<string | null>(null)
  const [loadPoolIdInput, setLoadPoolIdInput] = useState('')
  const [loadPoolError, setLoadPoolError] = useState<string | null>(null)
  const [savePoolPending, setSavePoolPending] = useState(false)
  const [savePoolSuccess, setSavePoolSuccess] = useState(false)
  // Selected pool for swap/liquidity (fee + tickSpacing + pair); set when loading by ID or clicking a pool
  const [selectedPool, setSelectedPool] = useState<{
    poolId: string
    currency0: string
    currency1: string
    fee: number
    tickSpacing: number
    symbol0: string
    symbol1: string
  } | null>(null)

  // Create pool state (addresses; fee/tick from liquidityFeeTier/liquidityTickSpacing)
  const [token0Address, setToken0Address] = useState('')
  const [token1Address, setToken1Address] = useState('')
  const [createPoolTx, setCreatePoolTx] = useState<CreatePoolTx | null>(null)
  const [createPoolError, setCreatePoolError] = useState<string | null>(null)
  const [createPoolPending, setCreatePoolPending] = useState(false)

  // Min/Max price for range (token1 per token0); used on Create page
  const [minPriceStr, setMinPriceStr] = useState('0.9')
  const [maxPriceStr, setMaxPriceStr] = useState('1.1')
  const currentPriceRef = 1 // 1:1 for new pool; could be from getPoolState later

  const poolManagerAddress = getPoolManagerAddress()
  const quoterAddress = getQuoterAddress()
  const positionManagerAddress = getPositionManagerAddress()

  // Fetch pools from DynamoDB on mount
  useEffect(() => {
    let cancelled = false
    setPoolsLoading(true)
    setPoolsError(null)
    fetch('/api/pools')
      .then((res) => {
        if (!res.ok) throw new Error('Failed to load pools')
        return res.json()
      })
      .then((data: Array<{ poolId: string; currency0: string; currency1: string; fee: number; tickSpacing: number; symbol0?: string; symbol1?: string }>) => {
        if (cancelled) return
        const list: PoolInfo[] = data.map((p) => ({
          poolId: p.poolId,
          pair: [p.symbol0 ?? shortenAddr(p.currency0), p.symbol1 ?? shortenAddr(p.currency1)].join(' / '),
          tickSpacing: p.tickSpacing,
          fee: p.fee,
          feeLabel: (p.fee / 10000).toFixed(2) + '%',
          symbol0: p.symbol0 ?? '',
          symbol1: p.symbol1 ?? '',
          currency0: p.currency0,
          currency1: p.currency1,
        }))
        setAvailablePools(list)
      })
      .catch((err) => {
        if (!cancelled) setPoolsError(err instanceof Error ? err.message : 'Failed to load pools')
      })
      .finally(() => {
        if (!cancelled) setPoolsLoading(false)
      })
    return () => { cancelled = true }
  }, [])

  function shortenAddr(addr: string): string {
    if (!addr || addr.length < 10) return addr
    return `${addr.slice(0, 6)}...${addr.slice(-4)}`
  }

  const loadPoolById = useCallback(async () => {
    const id = loadPoolIdInput.trim()
    if (!id) {
      setLoadPoolError('Enter a pool ID')
      return
    }
    setLoadPoolError(null)
    try {
      const res = await fetch(`/api/pools/${encodeURIComponent(id)}`)
      if (!res.ok) {
        if (res.status === 404) throw new Error('Pool not found')
        throw new Error('Failed to load pool')
      }
      const p = await res.json() as { poolId: string; currency0: string; currency1: string; fee: number; tickSpacing: number; symbol0?: string; symbol1?: string }
      const sym0 = p.symbol0 ?? ''
      const sym1 = p.symbol1 ?? ''
      const t0 = DEFAULT_TOKENS.find((t) => t.symbol === sym0) ?? DEFAULT_TOKENS[0]!
      const t1 = DEFAULT_TOKENS.find((t) => t.symbol === sym1) ?? DEFAULT_TOKENS[1]!
      setSelectedPool({
        poolId: p.poolId,
        currency0: p.currency0,
        currency1: p.currency1,
        fee: p.fee,
        tickSpacing: p.tickSpacing,
        symbol0: sym0,
        symbol1: sym1,
      })
      setLiquidityToken0(t0)
      setLiquidityToken1(t1)
      setLiquidityFeeTier(String(p.fee))
      setLiquidityTickSpacing(p.tickSpacing)
      setTokenIn(t0)
      setTokenOut(t1)
      setToken0Address(p.currency0)
      setToken1Address(p.currency1)
      setPoolView('create')
    } catch (err) {
      setLoadPoolError(err instanceof Error ? err.message : 'Failed to load pool')
    }
  }, [loadPoolIdInput])

  // Public client for read-only quote (eth_call)
  const publicClientRef = useRef<ReturnType<typeof createPublicClient> | null>(null)
  if (!publicClientRef.current && typeof window !== 'undefined') {
    publicClientRef.current = createPublicClient({
      chain: HEDERA_TESTNET,
      transport: http(HEDERA_TESTNET.rpcUrls.default.http[0]),
    })
  }

  // Quote exact input: when amountIn or token pair changes, fetch amountOut from Quoter (live update)
  useEffect(() => {
    if (!quoterAddress || !amountIn || amountIn === '.' || amountIn === '0' || amountIn === '0.') {
      if (amountIn === '' || amountIn === '0' || amountIn === '0.') setAmountOut('')
      setQuoteError(null)
      setQuoteLoading(false)
      return
    }
    const addrIn = getTokenAddress(tokenIn.symbol)
    const addrOut = getTokenAddress(tokenOut.symbol)
    if (!addrIn || !addrOut || addrIn === addrOut) {
      setAmountOut('')
      setQuoteError(null)
      setQuoteLoading(false)
      return
    }

    const currency0 = addrIn < addrOut ? addrIn : addrOut
    const currency1 = addrIn < addrOut ? addrOut : addrIn
    const zeroForOne = addrIn < addrOut
    const useSelected =
      selectedPool &&
      selectedPool.currency0.toLowerCase() === currency0.toLowerCase() &&
      selectedPool.currency1.toLowerCase() === currency1.toLowerCase()
    const fee = useSelected ? selectedPool.fee : DEFAULT_FEE
    const tickSpacing = useSelected ? selectedPool.tickSpacing : DEFAULT_TICK_SPACING
    const poolKey = { currency0, currency1, fee, tickSpacing }
    const decimalsIn = getTokenDecimals(tokenIn.symbol)
    const decimalsOut = getTokenDecimals(tokenOut.symbol)

    let cancelled = false
    setQuoteError(null)
    setQuoteLoading(true)
    const id = setTimeout(async () => {
      try {
        let amountInWei: bigint
        try {
          amountInWei = parseUnits(amountIn, decimalsIn)
        } catch {
          if (!cancelled) setAmountOut('')
          if (!cancelled) setQuoteLoading(false)
          return
        }
        const client = publicClientRef.current
        if (!client) {
          if (!cancelled) setQuoteLoading(false)
          return
        }
        const amountOutWei = await quoteExactInputSingle(
          client as import('viem').PublicClient,
          quoterAddress as `0x${string}`,
          poolKey,
          zeroForOne,
          amountInWei
        )
        if (!cancelled) {
          setAmountOut(formatUnits(amountOutWei, decimalsOut))
          setQuoteError(null)
        }
      } catch (err) {
        if (!cancelled) {
          setAmountOut('')
          setQuoteError(
            err instanceof NotEnoughLiquidityError ? err.message : getFriendlyErrorMessage(err, 'quote')
          )
        }
      }
      if (!cancelled) setQuoteLoading(false)
    }, 300)
    return () => {
      cancelled = true
      clearTimeout(id)
    }
  }, [amountIn, tokenIn.symbol, tokenOut.symbol, quoterAddress, selectedPool])

  // Fetch pool initialized state for Add Liquidity (Uniswap v4: show "Create pool & add" vs "Add liquidity")
  useEffect(() => {
    if (!poolManagerAddress || !publicClientRef.current) {
      setPoolInitialized(null)
      return
    }
    const addr0 = getTokenAddress(liquidityToken0.symbol)
    const addr1 = getTokenAddress(liquidityToken1.symbol)
    if (!addr0 || !addr1 || addr0 === addr1) {
      setPoolInitialized(null)
      return
    }
    const feeNum = parseInt(liquidityFeeTier, 10) || 3000
    const poolKey = buildPoolKey(
      addr0 as `0x${string}`,
      addr1 as `0x${string}`,
      feeNum,
      liquidityTickSpacing
    )
    const poolId = getPoolId(poolKey)
    let cancelled = false
    publicClientRef.current
      .readContract({
        address: poolManagerAddress as `0x${string}`,
        abi: PoolManagerAbi,
        functionName: 'getPoolState',
        args: [poolId],
      })
      .then((value: unknown) => {
        if (!cancelled) setPoolInitialized((value as readonly [boolean, bigint, number])[0])
      })
      .catch(() => {
        if (!cancelled) setPoolInitialized(false)
      })
    return () => {
      cancelled = true
    }
  }, [poolManagerAddress, liquidityToken0.symbol, liquidityToken1.symbol, liquidityFeeTier, liquidityTickSpacing])

  const createPool = useCallback(async () => {
    if (!poolManagerAddress || !token0Address || !token1Address) {
      setCreatePoolError('Set VITE_POOL_MANAGER_ADDRESS and both token addresses.')
      return
    }
    const addr0 = token0Address.trim()
    const addr1 = token1Address.trim()
    if (addr0 === addr1) {
      setCreatePoolError('Token addresses must be different.')
      return
    }
    const currency0 = addr0.toLowerCase() < addr1.toLowerCase() ? addr0 : addr1
    const currency1 = addr0.toLowerCase() < addr1.toLowerCase() ? addr1 : addr0
    const feeNum = parseInt(liquidityFeeTier, 10) || 3000
    const tickSpacingNum = liquidityTickSpacing
    if (isNaN(feeNum) || feeNum < 0 || feeNum > 1_000_000) {
      setCreatePoolError('Fee must be 0–1000000 (e.g. 3000 = 0.3%).')
      return
    }
    if (isNaN(tickSpacingNum) || tickSpacingNum < 1 || tickSpacingNum > 32767) {
      setCreatePoolError('Tick spacing must be 1–32767.')
      return
    }
    const sqrtPriceX96 = BigInt(SQRT_PRICE_PRESETS['1'] ?? '79228162514264337593543950336')
    const poolKey = { currency0, currency1, fee: feeNum, tickSpacing: tickSpacingNum, hooks: '0x0000000000000000000000000000000000000000' as const }

    const provider = typeof window !== 'undefined' && (window as unknown as { ethereum?: unknown }).ethereum
    if (!provider) {
      setCreatePoolError('No EVM wallet found. Install MetaMask or use an EVM-compatible wallet on Hedera Testnet.')
      return
    }

    setCreatePoolError(null)
    setCreatePoolPending(true)
    setCreatePoolTx(null)
    try {
      const walletClient = createWalletClient({ chain: HEDERA_TESTNET, transport: custom(provider as Parameters<typeof custom>[0]) })
      const [address] = await walletClient.requestAddresses()
      if (!address) {
        setCreatePoolError('Connect your EVM wallet first.')
        setCreatePoolPending(false)
        return
      }
      const hash = await walletClient.writeContract({
        address: poolManagerAddress as `0x${string}`,
        abi: PoolManagerAbi,
        functionName: 'initialize',
        args: [poolKey, sqrtPriceX96],
        account: address,
      })
      setCreatePoolTx({ hash })
    } catch (err: unknown) {
      setCreatePoolError(getFriendlyErrorMessage(err, 'transaction'))
    } finally {
      setCreatePoolPending(false)
    }
  }, [poolManagerAddress, token0Address, token1Address, liquidityFeeTier, liquidityTickSpacing])

  const addLiquidity = useCallback(async () => {
    const provider = typeof window !== 'undefined' && (window as unknown as { ethereum?: unknown }).ethereum
    if (!provider) {
      setLiquidityError('No EVM wallet found. Use an EVM-compatible wallet on Hedera Testnet.')
      return
    }
    if (!positionManagerAddress) {
      setLiquidityError('Set VITE_POSITION_MANAGER_ADDRESS in .env.')
      return
    }
    const addr0 = getTokenAddress(liquidityToken0.symbol)
    const addr1 = getTokenAddress(liquidityToken1.symbol)
    if (!addr0 || !addr1 || addr0 === addr1) {
      setLiquidityError('Select two different tokens.')
      return
    }
    const feeNum = parseInt(liquidityFeeTier, 10) || 3000
    const poolKey = buildPoolKey(addr0 as `0x${string}`, addr1 as `0x${string}`, feeNum, liquidityTickSpacing)
    const dec0 = getTokenDecimals(liquidityToken0.symbol)
    const dec1 = getTokenDecimals(liquidityToken1.symbol)
    let amount0Wei: bigint
    let amount1Wei: bigint
    let liquidityWei: bigint
    try {
      amount0Wei = parseUnits(amount0 || '0', dec0)
      amount1Wei = parseUnits(amount1 || '0', dec1)
      liquidityWei = BigInt(liquidityAmount || '0')
    } catch {
      setLiquidityError('Invalid amount or liquidity.')
      return
    }
    if (amount0Wei === 0n && amount1Wei === 0n) {
      setLiquidityError('Enter amount for at least one token.')
      return
    }
    if (liquidityWei === 0n) {
      setLiquidityError('Enter liquidity amount (e.g. 100000000).')
      return
    }
    setLiquidityError(null)
    setAddLiquidityPending(true)
    setAddLiquidityTx(null)
    try {
      const walletClient = createWalletClient({
        chain: HEDERA_TESTNET,
        transport: custom(provider as Parameters<typeof custom>[0]),
      })
      const [userAddress] = await walletClient.requestAddresses()
      if (!userAddress) {
        setLiquidityError('Connect your EVM wallet first.')
        setAddLiquidityPending(false)
        return
      }
      const pmAddr = positionManagerAddress as `0x${string}`
      const deadline = BigInt(Math.floor(Date.now() / 1000) + 3600)
      const unlockData = encodeUnlockDataMint(
        poolKey,
        tickLower,
        tickUpper,
        liquidityWei,
        amount0Wei,
        amount1Wei,
        userAddress
      )
      // 1) Approve PositionManager for both tokens if needed
      if (amount0Wei > 0n) {
        const allowance0 = (await publicClientRef.current!.readContract({
          address: poolKey.currency0 as `0x${string}`,
          abi: ERC20Abi,
          functionName: 'allowance',
          args: [userAddress, pmAddr],
        })) as bigint
        if (allowance0 < amount0Wei) {
          const hash0 = await walletClient.writeContract({
            address: poolKey.currency0 as `0x${string}`,
            abi: ERC20Abi,
            functionName: 'approve',
            args: [pmAddr, amount0Wei],
            account: userAddress,
          })
          await publicClientRef.current!.waitForTransactionReceipt({ hash: hash0 })
        }
      }
      if (amount1Wei > 0n) {
        const allowance1 = (await publicClientRef.current!.readContract({
          address: poolKey.currency1 as `0x${string}`,
          abi: ERC20Abi,
          functionName: 'allowance',
          args: [userAddress, pmAddr],
        })) as bigint
        if (allowance1 < amount1Wei) {
          const hash1 = await walletClient.writeContract({
            address: poolKey.currency1 as `0x${string}`,
            abi: ERC20Abi,
            functionName: 'approve',
            args: [pmAddr, amount1Wei],
            account: userAddress,
          })
          await publicClientRef.current!.waitForTransactionReceipt({ hash: hash1 })
        }
      }
      // 2) Transfer tokens to PositionManager
      if (amount0Wei > 0n) {
        await walletClient.writeContract({
          address: poolKey.currency0 as `0x${string}`,
          abi: ERC20Abi,
          functionName: 'transfer',
          args: [pmAddr, amount0Wei],
          account: userAddress,
        })
      }
      if (amount1Wei > 0n) {
        await walletClient.writeContract({
          address: poolKey.currency1 as `0x${string}`,
          abi: ERC20Abi,
          functionName: 'transfer',
          args: [pmAddr, amount1Wei],
          account: userAddress,
        })
      }
      // 3) Multicall: initializePool + modifyLiquidities (initializePool is no-op if pool exists)
      const initCalldata = encodeFunctionData({
        abi: PositionManagerAbi,
        functionName: 'initializePool',
        args: [poolKey, SQRT_PRICE_1_1],
      })
      const modifyCalldata = encodeFunctionData({
        abi: PositionManagerAbi,
        functionName: 'modifyLiquidities',
        args: [unlockData, deadline],
      })
      const hash = await walletClient.writeContract({
        address: pmAddr,
        abi: PositionManagerAbi,
        functionName: 'multicall',
        args: [[initCalldata, modifyCalldata]],
        account: userAddress,
      })
      setAddLiquidityTx({ hash })
    } catch (err: unknown) {
      setLiquidityError(getFriendlyErrorMessage(err, 'transaction'))
    } finally {
      setAddLiquidityPending(false)
    }
  }, [
    positionManagerAddress,
    liquidityToken0.symbol,
    liquidityToken1.symbol,
    liquidityFeeTier,
    liquidityTickSpacing,
    tickLower,
    tickUpper,
    amount0,
    amount1,
    liquidityAmount,
  ])

  const flipTokens = () => {
    setTokenIn(tokenOut)
    setTokenOut(tokenIn)
    setAmountIn(amountOut)
    setAmountOut('') // re-quote will fill from Quoter
  }

  const selectPoolForLiquidity = (pool: PoolInfo) => {
    const t0 = pool.symbol0
      ? DEFAULT_TOKENS.find((t) => t.symbol === pool.symbol0) ?? DEFAULT_TOKENS[0]!
      : DEFAULT_TOKENS[0]!
    const t1 = pool.symbol1
      ? DEFAULT_TOKENS.find((t) => t.symbol === pool.symbol1) ?? DEFAULT_TOKENS[1]!
      : DEFAULT_TOKENS[1]!
    setLiquidityToken0(t0)
    setLiquidityToken1(t1)
    setLiquidityFeeTier(String(pool.fee))
    setLiquidityTickSpacing(pool.tickSpacing)
    setSelectedPool({
      poolId: pool.poolId,
      currency0: pool.currency0,
      currency1: pool.currency1,
      fee: pool.fee,
      tickSpacing: pool.tickSpacing,
      symbol0: pool.symbol0,
      symbol1: pool.symbol1,
    })
    setToken0Address(pool.currency0)
    setToken1Address(pool.currency1)
    setPoolView('create')
  }

  const savePoolToList = useCallback(async () => {
    const addr0 = getTokenAddress(liquidityToken0.symbol)
    const addr1 = getTokenAddress(liquidityToken1.symbol)
    if (!addr0 || !addr1 || addr0 === addr1) {
      return
    }
    const feeNum = parseInt(liquidityFeeTier, 10) || 3000
    const poolKey = buildPoolKey(addr0 as `0x${string}`, addr1 as `0x${string}`, feeNum, liquidityTickSpacing)
    const poolId = getPoolId(poolKey)
    setSavePoolPending(true)
    setSavePoolSuccess(false)
    try {
      const res = await fetch('/api/pools', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          poolId,
          currency0: poolKey.currency0,
          currency1: poolKey.currency1,
          fee: feeNum,
          tickSpacing: liquidityTickSpacing,
          symbol0: liquidityToken0.symbol,
          symbol1: liquidityToken1.symbol,
        }),
      })
      if (!res.ok) throw new Error('Failed to save pool')
      setSavePoolSuccess(true)
      setAvailablePools((prev: PoolInfo[]) => [
        {
          poolId,
          pair: `${liquidityToken0.symbol} / ${liquidityToken1.symbol}`,
          tickSpacing: liquidityTickSpacing,
          fee: feeNum,
          feeLabel: (feeNum / 10000).toFixed(2) + '%',
          symbol0: liquidityToken0.symbol,
          symbol1: liquidityToken1.symbol,
          currency0: poolKey.currency0,
          currency1: poolKey.currency1,
        },
        ...prev,
      ])
    } catch {
      // ignore
    } finally {
      setSavePoolPending(false)
    }
  }, [liquidityToken0.symbol, liquidityToken1.symbol, liquidityFeeTier, liquidityTickSpacing])

  const applyPriceStrategy = (strategy: (typeof PRICE_STRATEGIES)[number]) => {
    const ref = currentPriceRef
    if ('tickDelta' in strategy && strategy.tickDelta !== undefined) {
      const spacing = liquidityTickSpacing
      const centerTick = priceToTick(ref)
      const roundedCenter = roundToTickSpacing(centerTick, spacing)
      const delta = strategy.tickDelta * spacing
      setTickLower(roundedCenter - delta)
      setTickUpper(roundedCenter + delta)
      setMinPriceStr(tickToPrice(roundedCenter - delta).toFixed(4))
      setMaxPriceStr(tickToPrice(roundedCenter + delta).toFixed(4))
      return
    }
    const minPct = 'minPct' in strategy ? strategy.minPct ?? 0 : 0
    const maxPct = 'maxPct' in strategy ? strategy.maxPct ?? 0 : 0
    const minP = ref * (1 + minPct)
    const maxP = ref * (1 + maxPct)
    setMinPriceStr(minP.toFixed(4))
    setMaxPriceStr(maxP.toFixed(4))
    const spacing = liquidityTickSpacing
    setTickLower(roundToTickSpacing(priceToTick(minP), spacing))
    setTickUpper(roundToTickSpacing(priceToTick(maxP), spacing))
  }

  const syncPriceToTicks = () => {
    const minP = parseFloat(minPriceStr)
    const maxP = parseFloat(maxPriceStr)
    if (!Number.isFinite(minP) || !Number.isFinite(maxP)) return
    const spacing = liquidityTickSpacing
    setTickLower(roundToTickSpacing(priceToTick(minP), spacing))
    setTickUpper(roundToTickSpacing(priceToTick(maxP), spacing))
  }

  const adjustMinPrice = (delta: number) => {
    const p = parseFloat(minPriceStr) || currentPriceRef
    setMinPriceStr((p * (1 + delta)).toFixed(4))
    setTimeout(syncPriceToTicks, 0)
  }
  const adjustMaxPrice = (delta: number) => {
    const p = parseFloat(maxPriceStr) || currentPriceRef
    setMaxPriceStr((p * (1 + delta)).toFixed(4))
    setTimeout(syncPriceToTicks, 0)
  }

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
        </nav>
        {error && (
          <ErrorMessage
            message={getFriendlyErrorMessage(error, 'wallet')}
            className="header-error-inline"
          />
        )}
        <button
          className={`connect-btn ${isConnected ? 'connected' : ''}`}
          onClick={() => (isConnected ? disconnect() : connect())}
          disabled={isConnecting || !isInitialized}
        >
          {isConnecting
            ? 'Connecting...'
            : isConnected
              ? (formattedAccountId || accountId || '')
              : 'Connect HashPack'}
        </button>
      </header>

      <main className="main">
        {tab === TAB.SWAP && (
          <div className={`card card--swap ${quoteError ? 'card--error' : ''}`}>
            <h2 className="card-title">Swap</h2>
            <div className={`token-row ${quoteError ? 'token-row--error' : ''}`}>
              <div className="token-row-label">You pay</div>
              <div className="token-row-inner">
                <input
                  type="text"
                  className="token-input"
                  placeholder="0.0"
                  value={amountIn}
                  onChange={(e) => setAmountIn(e.target.value)}
                />
                <div className="token-select-wrap">
                  <TokenIcon symbol={tokenIn.symbol} size={28} />
                  <select
                    className="token-select"
                    value={tokenIn.id}
                    onChange={(e) =>
                      setTokenIn(DEFAULT_TOKENS.find((t) => t.id === e.target.value) ?? DEFAULT_TOKENS[0]!)
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
            </div>
            <div className="flip-row">
              <button type="button" className="flip-btn" onClick={flipTokens} aria-label="Flip">
                ↓↑
              </button>
            </div>
            <div className={`token-row ${quoteError ? 'token-row--error' : ''}`}>
              <div className="token-row-label">You receive</div>
              <div className="token-row-inner">
                <input
                  type="text"
                  className="token-input"
                  placeholder={quoteLoading ? 'Updating…' : '0.0'}
                  aria-invalid={!!quoteError}
                  aria-describedby={quoteError ? 'quote-error-msg' : undefined}
                  value={amountOut}
                  onChange={(e) => setAmountOut(e.target.value)}
                  readOnly={!!quoterAddress}
                  aria-readonly={!!quoterAddress}
                />
                <div className="token-select-wrap">
                  <TokenIcon symbol={tokenOut.symbol} size={28} />
                  <select
                    className="token-select"
                    value={tokenOut.id}
                    onChange={(e) =>
                      setTokenOut(DEFAULT_TOKENS.find((t) => t.id === e.target.value) ?? DEFAULT_TOKENS[1]!)
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
            </div>
            {quoteError && (
              <ErrorMessage id="quote-error-msg" message={quoteError} className="quote-error" />
            )}
            <p className="helper">Concentrated liquidity · Price limit optional</p>
            {quoterAddress ? (
              <p className="helper">Live quote from Quoter (exact input). Edit TOKEN_ADDRESSES in src/constants.ts for your token addresses.</p>
            ) : (
              <p className="helper">Set VITE_QUOTER_ADDRESS in .env and TOKEN_ADDRESSES in src/constants.ts to see quoted output.</p>
            )}
            <button
              type="button"
              className="primary-btn"
              disabled={!amountIn || !amountOut || !isConnected}
            >
              Swap
            </button>
          </div>
        )}

        {tab === TAB.POOL && poolView === 'list' && (
          <div className="card card--pool-list">
            <h2 className="card-title">Pools</h2>
            <p className="helper pool-list-subtitle">Select a pool to add liquidity, or load by pool ID. Pools are stored in DynamoDB—no hardcoded list.</p>
            <div className="pool-load-section">
              <label htmlFor="load-pool-id">Load pool by ID</label>
              <div className="pool-load-row">
                <input
                  id="load-pool-id"
                  type="text"
                  placeholder="0x... (pool ID from create)"
                  value={loadPoolIdInput}
                  onChange={(e) => { setLoadPoolIdInput(e.target.value); setLoadPoolError(null) }}
                  onKeyDown={(e) => e.key === 'Enter' && loadPoolById()}
                />
                <button type="button" className="primary-btn" style={{ marginTop: 0, width: 'auto' }} onClick={loadPoolById}>
                  Load
                </button>
              </div>
              {loadPoolError && (
                <p className="pools-error" role="alert">
                  {loadPoolError}
                  <button type="button" onClick={() => setLoadPoolError(null)} aria-label="Dismiss" style={{ marginLeft: 8, background: 'none', border: 'none', color: 'inherit', cursor: 'pointer' }}>×</button>
                </p>
              )}
            </div>
            {poolsError && <p className="pools-error">{poolsError}</p>}
            {poolsLoading ? (
              <p className="pools-loading">Loading pools…</p>
            ) : (
              <>
                <ul className="pool-list pool-list--grid">
                  {availablePools.map((pool) => (
                    <li
                      key={pool.poolId}
                      className="pool-card"
                      onClick={() => selectPoolForLiquidity(pool)}
                    >
                      <div className="pool-card-icons">
                        <TokenIcon symbol={pool.symbol0 || '?'} size={36} />
                        <TokenIcon symbol={pool.symbol1 || '?'} size={36} />
                      </div>
                      <span className="pool-card-pair">{pool.pair}</span>
                      <span className="pool-card-fee">{pool.feeLabel}</span>
                    </li>
                  ))}
                </ul>
                {availablePools.length === 0 && (
                  <p className="helper">No pools yet. Create a pool and save it to the list, or add DYNAMODB_TABLE_POOLS and seed data.</p>
                )}
              </>
            )}
            <button
              type="button"
              className="primary-btn primary-btn--create-pool"
              onClick={() => setPoolView('create')}
            >
              Create pool
            </button>
          </div>
        )}

        {tab === TAB.POOL && poolView === 'create' && (
          <div className="card card--pool-create">
            <button type="button" className="back-btn" onClick={() => setPoolView('list')}>
              ← Back to pools
            </button>
            <h2 className="card-title">Create pool & add liquidity</h2>
            <p className="helper">Paste token addresses and set price range. New pools are created at 1:1; you can add liquidity in a custom range.</p>

            <section className="create-section">
              <h3 className="create-section-title">Token addresses</h3>
              <div className="form-group">
                <label>Token 0 (currency0)</label>
                <input
                  type="text"
                  value={token0Address}
                  onChange={(e) => setToken0Address(e.target.value)}
                  placeholder="Paste token address (0x...)"
                  className="input-paste"
                />
              </div>
              <div className="form-group">
                <label>Token 1 (currency1)</label>
                <input
                  type="text"
                  value={token1Address}
                  onChange={(e) => setToken1Address(e.target.value)}
                  placeholder="Paste token address (0x...)"
                  className="input-paste"
                />
              </div>
              <p className="helper">Or select from known tokens below to add liquidity to an existing pair.</p>
              <div className="liquidity-token-row">
                <TokenIcon symbol={liquidityToken0.symbol} size={24} />
                <select
                  className="token-select liquidity-select"
                  value={liquidityToken0.id}
                  onChange={(e) => {
                    setLiquidityToken0(DEFAULT_TOKENS.find((t) => t.id === e.target.value) ?? DEFAULT_TOKENS[0]!)
                    setToken0Address(getTokenAddress((DEFAULT_TOKENS.find((t) => t.id === e.target.value) ?? DEFAULT_TOKENS[0]!).symbol))
                  }}
                >
                  {DEFAULT_TOKENS.map((t) => (
                    <option key={t.id} value={t.id}>{t.symbol}</option>
                  ))}
                </select>
                <span className="liquidity-pair-sep">/</span>
                <TokenIcon symbol={liquidityToken1.symbol} size={24} />
                <select
                  className="token-select liquidity-select"
                  value={liquidityToken1.id}
                  onChange={(e) => {
                    setLiquidityToken1(DEFAULT_TOKENS.find((t) => t.id === e.target.value) ?? DEFAULT_TOKENS[1]!)
                    setToken1Address(getTokenAddress((DEFAULT_TOKENS.find((t) => t.id === e.target.value) ?? DEFAULT_TOKENS[1]!).symbol))
                  }}
                >
                  {DEFAULT_TOKENS.map((t) => (
                    <option key={t.id} value={t.id}>{t.symbol}</option>
                  ))}
                </select>
              </div>
              <div className="form-group">
                <label>Fee tier</label>
                <select
                  className="token-select"
                  value={liquidityFeeTier}
                  onChange={(e) => {
                    setLiquidityFeeTier(e.target.value)
                    if (e.target.value === '3000') setLiquidityTickSpacing(60)
                    else if (e.target.value === '10000') setLiquidityTickSpacing(200)
                  }}
                >
                  <option value="3000">0.3%</option>
                  <option value="10000">1%</option>
                </select>
              </div>
            </section>

            <section className="create-section">
              <h3 className="create-section-title">Price strategies</h3>
              <div className="strategy-grid">
                {PRICE_STRATEGIES.map((s) => (
                  <button
                    key={s.id}
                    type="button"
                    className="strategy-card"
                    onClick={() => applyPriceStrategy(s)}
                  >
                    <span className="strategy-label">{s.label}</span>
                    <span className="strategy-value">{s.value}</span>
                    <span className="strategy-desc">{s.desc}</span>
                  </button>
                ))}
              </div>
            </section>

            <section className="create-section">
              <h3 className="create-section-title">Price range</h3>
              <p className="helper">Min and max price (token1 per token0). Current reference: {currentPriceRef}.</p>
              <div className="price-range-row">
                <div className="price-input-group">
                  <label>Min price</label>
                  <div className="price-input-wrap">
                    <button type="button" className="price-adj-btn" onClick={() => adjustMinPrice(-0.01)} aria-label="Decrease">−</button>
                    <input
                      type="text"
                      className="price-input"
                      value={minPriceStr}
                      onChange={(e) => { setMinPriceStr(e.target.value); setTimeout(syncPriceToTicks, 0) }}
                      onBlur={syncPriceToTicks}
                    />
                    <button type="button" className="price-adj-btn" onClick={() => adjustMinPrice(0.01)} aria-label="Increase">+</button>
                  </div>
                  {currentPriceRef > 0 && (
                    <span className="price-pct">
                      {((parseFloat(minPriceStr) || 0) / currentPriceRef - 1) * 100 >= 0 ? '+' : ''}
                      {(((parseFloat(minPriceStr) || 0) / currentPriceRef - 1) * 100).toFixed(2)}%
                    </span>
                  )}
                </div>
                <div className="price-input-group">
                  <label>Max price</label>
                  <div className="price-input-wrap">
                    <button type="button" className="price-adj-btn" onClick={() => adjustMaxPrice(-0.01)} aria-label="Decrease">−</button>
                    <input
                      type="text"
                      className="price-input"
                      value={maxPriceStr}
                      onChange={(e) => { setMaxPriceStr(e.target.value); setTimeout(syncPriceToTicks, 0) }}
                      onBlur={syncPriceToTicks}
                    />
                    <button type="button" className="price-adj-btn" onClick={() => adjustMaxPrice(0.01)} aria-label="Increase">+</button>
                  </div>
                  {currentPriceRef > 0 && (
                    <span className="price-pct">
                      {((parseFloat(maxPriceStr) || 0) / currentPriceRef - 1) * 100 >= 0 ? '+' : ''}
                      {(((parseFloat(maxPriceStr) || 0) / currentPriceRef - 1) * 100).toFixed(2)}%
                    </span>
                  )}
                </div>
              </div>
            </section>

            <section className="create-section">
              <h3 className="create-section-title">Deposit tokens</h3>
              <p className="helper">Specify the token amounts for your liquidity contribution.</p>
              <div className="form-group">
                <label>{liquidityToken0.symbol}</label>
                <div className="token-row token-row--with-icon">
                  <input
                    type="text"
                    className="token-input"
                    placeholder="0.0"
                    value={amount0}
                    onChange={(e) => { setAmount0(e.target.value); setLiquidityError(null) }}
                  />
                  <span className="token-symbol-wrap">
                    <TokenIcon symbol={liquidityToken0.symbol} size={22} />
                    <span>{liquidityToken0.symbol}</span>
                  </span>
                </div>
              </div>
              <div className="form-group">
                <label>{liquidityToken1.symbol}</label>
                <div className="token-row token-row--with-icon">
                  <input
                    type="text"
                    className="token-input"
                    placeholder="0.0"
                    value={amount1}
                    onChange={(e) => { setAmount1(e.target.value); setLiquidityError(null) }}
                  />
                  <span className="token-symbol-wrap">
                    <TokenIcon symbol={liquidityToken1.symbol} size={22} />
                    <span>{liquidityToken1.symbol}</span>
                  </span>
                </div>
              </div>
              <div className="form-group">
                <label>Liquidity (L)</label>
                <input
                  type="text"
                  value={liquidityAmount}
                  onChange={(e) => { setLiquidityAmount(e.target.value); setLiquidityError(null) }}
                  placeholder="100000000"
                />
              </div>
            </section>

            {!positionManagerAddress && (
              <p className="helper create-pool-warn">Set VITE_POSITION_MANAGER_ADDRESS in .env to add liquidity.</p>
            )}
            {createPoolError && (
              <ErrorMessage message={createPoolError} className="create-pool-err" onDismiss={() => setCreatePoolError(null)} />
            )}
            {liquidityError && (
              <ErrorMessage message={liquidityError} className="liquidity-error" onDismiss={() => setLiquidityError(null)} />
            )}
            {(createPoolTx || addLiquidityTx) && (
              <p className="helper create-pool-success">
                <a href={`https://hashscan.io/testnet/transaction/${(createPoolTx || addLiquidityTx)?.hash}`} target="_blank" rel="noreferrer">View transaction</a>
              </p>
            )}
            <div className="create-section">
              <h3 className="create-section-title">Save to pool list</h3>
              <p className="helper">Save this pool to DynamoDB so you can load it by ID later and swap without hardcoding.</p>
              <button
                type="button"
                className="pool-save-btn"
                disabled={savePoolPending || !getTokenAddress(liquidityToken0.symbol) || !getTokenAddress(liquidityToken1.symbol)}
                onClick={savePoolToList}
              >
                {savePoolPending ? 'Saving…' : savePoolSuccess ? 'Saved' : 'Save pool to list'}
              </button>
            </div>
            <div className="create-actions">
              {poolManagerAddress && (
                <button
                  type="button"
                  className="primary-btn primary-btn--secondary"
                  disabled={createPoolPending || !token0Address || !token1Address}
                  onClick={createPool}
                >
                  {createPoolPending ? 'Creating…' : 'Create pool only'}
                </button>
              )}
              <button
                type="button"
                className="primary-btn"
                disabled={!positionManagerAddress || addLiquidityPending || (!amount0 && !amount1)}
                onClick={addLiquidity}
              >
                {addLiquidityPending ? 'Adding…' : poolInitialized === false ? 'Create pool & add liquidity' : 'Add liquidity'}
              </button>
            </div>
          </div>
        )}
      </main>
    </div>
  )
}

export default App
