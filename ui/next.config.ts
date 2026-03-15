import type { NextConfig } from 'next'
import path from 'path'
import { createRequire } from 'module'

const require = createRequire(import.meta.url)

const nextConfig: NextConfig = {
  reactStrictMode: true,
  transpilePackages: ['hashconnect'],
  webpack(config, { isServer }) {
    config.resolve = config.resolve ?? {}

    // Force a single copy of these packages so webpack never bundles them twice.
    // Duplicate copies cause the minified "Identifier 'n' already declared" SyntaxError.
    config.resolve.dedupe = [
      ...((config.resolve.dedupe as string[] | undefined) ?? []),
      '@hashgraph/sdk',
      'hashconnect',
    ]

    // Use the pre-built browser bundle only on the client side.
    // Applying the alias on the server side would break server routes that legitimately
    // use the Node build (e.g. API routes calling mirror-node).
    if (!isServer) {
      const sdkRoot = path.dirname(require.resolve('@hashgraph/sdk/package.json'))
      config.resolve.alias = {
        ...config.resolve.alias,
        '@hashgraph/sdk': path.join(sdkRoot, 'lib', 'browser.js'),
      }
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
