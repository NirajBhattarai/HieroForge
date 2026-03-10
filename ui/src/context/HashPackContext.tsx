'use client'

import { createContext, useContext, useState, useEffect, useCallback, useRef, type ReactNode } from 'react'
import { HashConnect } from 'hashconnect'
import { LedgerId } from '@hashgraph/sdk'
import { ModalCtrl } from '@walletconnect/modal-core'

export interface HashPackContextValue {
  accountId: string | null
  formattedAccountId: string
  isConnected: boolean
  isInitialized: boolean
  isConnecting: boolean
  error: string | null
  connect: () => Promise<void>
  disconnect: () => Promise<void>
  hashConnectRef: React.MutableRefObject<HashConnect | null>
}

const HashPackContext = createContext<HashPackContextValue | null>(null)

const APP_METADATA = {
  name: 'HieroForge',
  description: 'Concentrated liquidity AMM on Hedera',
  icons: ['https://vitejs.dev/logo.svg'],
  url: typeof window !== 'undefined' ? window.location.origin : '',
}

function formatAccountId(accountId: string | null): string {
  if (!accountId) return ''
  const s = String(accountId)
  if (s.length <= 12) return s
  return `${s.slice(0, 8)}...${s.slice(-4)}`
}

interface PairingData {
  accountIds?: string[]
}

const SESSION_KEY = 'hieroforge_connected_account'

function saveSession(accountId: string | null) {
  try {
    if (accountId) {
      sessionStorage.setItem(SESSION_KEY, accountId)
    } else {
      sessionStorage.removeItem(SESSION_KEY)
    }
  } catch { /* SSR or private mode */ }
}

function loadSession(): string | null {
  try {
    return sessionStorage.getItem(SESSION_KEY)
  } catch {
    return null
  }
}

export function HashPackProvider({ children }: { children: ReactNode }) {
  const [accountId, setAccountId] = useState<string | null>(null)
  const [isInitialized, setIsInitialized] = useState(false)
  const [isConnecting, setIsConnecting] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const hashConnectRef = useRef<HashConnect | null>(null)
  const initCalledRef = useRef(false)

  const projectId = process.env.NEXT_PUBLIC_WALLETCONNECT_PROJECT_ID
  const network = process.env.NEXT_PUBLIC_HEDERA_NETWORK || 'testnet'

  // Keep sessionStorage in sync whenever accountId changes
  useEffect(() => {
    saveSession(accountId)
  }, [accountId])

  useEffect(() => {
    if (!projectId || projectId === 'your_project_id_here') {
      setError('Missing NEXT_PUBLIC_WALLETCONNECT_PROJECT_ID. Add it to .env (see .env.example).')
      return
    }

    // Guard against React Strict Mode double-mount
    if (initCalledRef.current) return
    initCalledRef.current = true

    const ledgerId =
      network === 'mainnet'
        ? LedgerId.MAINNET
        : network === 'previewnet'
          ? LedgerId.PREVIEWNET
          : LedgerId.TESTNET

    const hashconnect = new HashConnect(ledgerId, projectId, APP_METADATA, false)

    hashconnect.pairingEvent.on((pairingData: PairingData) => {
      const id = pairingData?.accountIds?.[0] ?? null
      setAccountId(id)
      setIsConnecting(false)
      setError(null)
      try {
        ModalCtrl.close()
      } catch {
        // ignore if modal state not available
      }
    })

    hashconnect.disconnectionEvent.on(() => {
      setAccountId(null)
    })

    hashconnect
      .init()
      .then(() => {
        hashConnectRef.current = hashconnect
        setIsInitialized(true)
        setError(null)
        try { ModalCtrl.close() } catch { /* noop */ }

        // Restore from HashConnect's own session first, fall back to sessionStorage
        if ((hashconnect?.connectedAccountIds?.length ?? 0) > 0) {
          setAccountId(hashconnect.connectedAccountIds?.[0]?.toString() ?? null)
        } else {
          const saved = loadSession()
          if (saved) setAccountId(saved)
        }
      })
      .catch((err: unknown) => {
        setError(err instanceof Error ? err.message : 'Failed to initialize HashPack')
        setIsInitialized(false)
      })

    return () => {
      // Cleanup: close any WalletConnect modal overlay
      // NOTE: we do NOT disconnect here — we want the session to survive HMR / remounts
      try { ModalCtrl.close() } catch { /* noop */ }
      hashConnectRef.current = null
    }
  }, [projectId, network])

  const connect = useCallback(async () => {
    if (!isInitialized) {
      setError('Wallet not ready. Wait for init or check .env')
      return
    }
    const hc = hashConnectRef.current
    if (!hc) {
      setError('HashPack not loaded')
      return
    }
    setError(null)
    setIsConnecting(true)
    try {
      await hc.openPairingModal()
    } catch (err: unknown) {
      setError(err instanceof Error ? err.message : 'Failed to open HashPack')
      setIsConnecting(false)
    }
  }, [isInitialized])

  const disconnect = useCallback(async () => {
    const hc = hashConnectRef.current
    if (hc) {
      try {
        await hc.disconnect()
      } catch {
        // ignore
      }
    }
    setAccountId(null)
    saveSession(null)
    setIsConnecting(false)
  }, [])

  const value: HashPackContextValue = {
    accountId,
    formattedAccountId: formatAccountId(accountId),
    isConnected: !!accountId,
    isInitialized,
    isConnecting,
    error,
    connect,
    disconnect,
    hashConnectRef,
  }

  return (
    <HashPackContext.Provider value={value}>
      {children}
    </HashPackContext.Provider>
  )
}

export function useHashPack(): HashPackContextValue {
  const ctx = useContext(HashPackContext)
  if (!ctx) {
    // Return safe defaults while provider is loading (dynamic import)
    return {
      accountId: null,
      formattedAccountId: '',
      isConnected: false,
      isInitialized: false,
      isConnecting: false,
      error: null,
      connect: async () => {},
      disconnect: async () => {},
      hashConnectRef: { current: null },
    }
  }
  return ctx
}
