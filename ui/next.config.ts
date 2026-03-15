import type { NextConfig } from 'next'
import path from 'path'
import { createRequire } from 'module'

const require = createRequire(import.meta.url)

const nextConfig: NextConfig = {
  reactStrictMode: true,
  transpilePackages: ['hashconnect', '@hashgraph/sdk'],
  webpack(config, { isServer }) {
    // Dedupe @hashgraph/sdk and use browser build so we don't pull Node/grpc (fs, net, tls) into client bundle
    const sdkRoot = path.dirname(require.resolve('@hashgraph/sdk/package.json'))
    config.resolve = config.resolve ?? {}
    config.resolve.alias = {
      ...config.resolve.alias,
      '@hashgraph/sdk': path.join(sdkRoot, 'lib', 'browser.js'),
    }
    // Stub Node built-ins for client bundle when SDK or deps reference them
    if (!isServer) {
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
