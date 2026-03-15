import type { NextConfig } from 'next'
import path from 'path'
import { createRequire } from 'module'

const require = createRequire(import.meta.url)

const nextConfig: NextConfig = {
  reactStrictMode: true,
  transpilePackages: ['hashconnect'],
  webpack(config, { isServer }) {
    config.resolve = config.resolve ?? {}

    // Pin every import of these packages to a single resolved path so webpack
    // never bundles two copies (which causes "Identifier 'n' already declared"
    // after minification).  On the client we point to the pre-built browser
    // bundle; on the server we pin to the package root so Node-native code works.
    const sdkRoot = path.dirname(require.resolve('@hashgraph/sdk/package.json'))
    const hcRoot  = path.dirname(require.resolve('hashconnect/package.json'))
    if (!isServer) {
      config.resolve.alias = {
        ...config.resolve.alias,
        '@hashgraph/sdk': path.join(sdkRoot, 'lib', 'browser.js'),
        'hashconnect': hcRoot,
      }
    } else {
      config.resolve.alias = {
        ...config.resolve.alias,
        '@hashgraph/sdk': sdkRoot,
        'hashconnect': hcRoot,
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
