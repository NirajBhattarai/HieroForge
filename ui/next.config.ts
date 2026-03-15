import type { NextConfig } from 'next'
import path from 'path'
import { createRequire } from 'module'

const require = createRequire(import.meta.url)

const nextConfig: NextConfig = {
  reactStrictMode: true,
  transpilePackages: ['hashconnect', '@hashgraph/sdk'],
  webpack(config) {
    // Dedupe @hashgraph/sdk so hashconnect and app use one copy (avoids "Identifier 'n' has already been declared" in minified chunk)
    config.resolve = config.resolve ?? {}
    config.resolve.alias = {
      ...config.resolve.alias,
      '@hashgraph/sdk': path.dirname(require.resolve('@hashgraph/sdk/package.json')),
    }
    // Suppress "Critical dependency" warnings from hashconnect / hedera-wallet-connect
    config.ignoreWarnings = [
      ...(config.ignoreWarnings ?? []),
      { module: /node_modules[\\/]@hashgraph[\\/]hedera-wallet-connect/ },
      { module: /node_modules[\\/]hashconnect/ },
    ]
    return config
  },
}

export default nextConfig
