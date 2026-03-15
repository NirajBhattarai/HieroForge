import type { NextConfig } from 'next'
import path from 'path'
import { createRequire } from 'module'

const require = createRequire(import.meta.url)

const nextConfig: NextConfig = {
  reactStrictMode: true,
  webpack(config, { isServer }) {
    config.resolve = config.resolve ?? {}

    // Use the pre-built browser bundle of @hashgraph/sdk on the client
    // so we don't pull Node/gRPC deps (fs, net, tls) into the browser.
    // The npm "overrides" in package.json ensures there is only ONE copy
    // of the SDK in node_modules (no nested duplicate under hashconnect).
    const sdkRoot = path.dirname(require.resolve('@hashgraph/sdk/package.json'))

    // hashconnect imports '@hashgraph/proto' (the old package name).
    // In SDK >=2.80 this was renamed to '@hiero-ledger/proto' and lives
    // inside the SDK's own node_modules.
    const protoPath = path.join(sdkRoot, 'node_modules', '@hiero-ledger', 'proto')
    config.resolve.alias = {
      ...config.resolve.alias,
      '@hashgraph/proto': protoPath,
    }

    if (!isServer) {
      config.resolve.alias['@hashgraph/sdk'] = path.join(sdkRoot, 'lib', 'browser.js')
      config.resolve.fallback = {
        ...config.resolve.fallback,
        fs: false,
        net: false,
        tls: false,
      }
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
