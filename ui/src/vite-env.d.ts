/// <reference types="vite/client" />

interface ImportMetaEnv {
  readonly VITE_WALLETCONNECT_PROJECT_ID?: string
  readonly VITE_HEDERA_NETWORK?: string
  readonly VITE_POOL_MANAGER_ADDRESS?: string
  readonly VITE_QUOTER_ADDRESS?: string
  readonly VITE_CHAIN_ID?: string
}

interface ImportMeta {
  readonly env: ImportMetaEnv
}
