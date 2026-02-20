# HieroForge

Smart contract project for Hedera, built with [Foundry](https://getfoundry.sh/) and Solidity 0.8.28. Uses [hedera-forking](https://github.com/hashgraph/hedera-forking) for local HTS emulation and mainnet/testnet forking.

## Prerequisites

- [Foundry](https://book.getfoundry.sh/getting-started/installation) (Forge, Cast, Anvil)
- For HTS/fork tests: `ffi` is enabled (see `foundry.toml`)

## Quick Start

```bash
# Install dependencies (forge-std, hedera-forking are git submodules)
git submodule update --init --recursive

# Build
forge build

# Run all tests
forge test

# Run tests with Hedera mainnet fork (HTS mirror node)
forge test --fork-url https://mainnet.hashio.io/api
```

## Project Structure

```
HieroForge/
├── src/
│   ├── Core.sol              # Core contract (implements ICore)
│   ├── interfaces/
│   │   ├── ICore.sol
│   │   └── IHooks.sol
│   └── types/
│       ├── Currency.sol      # address wrapper for token/currency id
│       └── PoolKey.sol       # pool key (token0, token1, fee, tickSpacing, hooks)
├── test/
│   ├── CreateTokenTest.t.sol # HTS fungible token creation
│   └── USDCExampleTest.t.sol # USDC on Hedera mainnet fork
├── script/                   # Deploy scripts
├── lib/
│   ├── forge-std/
│   └── hedera-forking/       # HTS emulation & mirror node forking
├── foundry.toml
└── remappings.txt
```

## Configuration

- **Solidity:** 0.8.28 (`foundry.toml` → `solc = "0.8.28"`)
- **Remappings** (`remappings.txt`):
  - `forge-std/=lib/forge-std/src/`
  - `hedera-forking/=lib/hedera-forking/contracts/`
- **RPC endpoints** (in `foundry.toml`): `mainnet`, `testnet`, `previewnet`, `localnode` (Hashio / Hedera)

## Commands

| Command | Description |
|--------|-------------|
| `forge build` | Compile contracts |
| `forge test` | Run tests |
| `forge test --fork-url <url>` | Run tests against a forked network (e.g. Hedera mainnet) |
| `forge fmt` | Format Solidity |
| `forge snapshot` | Gas snapshots |
| `anvil` | Start local node |
| `cast <subcommand>` | Interact with contracts and chains |

### Test examples

```bash
# All tests
forge test

# With mainnet fork (for HTS / USDC tests)
forge test --fork-url https://mainnet.hashio.io/api

# Single test contract
forge test --match-contract CreateTokenTest -vv
forge test --match-contract USDCExampleTest -vv
```

## Documentation

- [Foundry Book](https://book.getfoundry.sh/)
- [Hedera Forking](https://github.com/hashgraph/hedera-forking) (HTS emulation, mirror node)
- [Hashio](https://hashio.io/) (Hedera RPC)

## License

Apache-2.0 (see SPDX headers in source files).
