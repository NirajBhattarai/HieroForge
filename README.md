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
│   ├── PoolManager.sol        # Pool manager contract (implements IPoolManager)
│   ├── interfaces/
│   │   ├── IPoolManager.sol
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

## Deploy to Hedera Testnet

1. **Get testnet HBAR**  
   Create an account and use the [Hedera Portal Faucet](https://portal.hedera.com/faucet) (or another testnet faucet).

2. **Configure environment**  
   Copy `.env.example` to `.env` and set your deployer private key:
   ```bash
   cp .env.example .env
   # Edit .env and set PRIVATE_KEY=0x<your_hex_private_key>
   ```

3. **Run the deploy script**  
   Dry run (simulation only):
   ```bash
   forge script script/Deploy.s.sol --rpc-url testnet
   ```
   Broadcast to Hedera testnet (chain ID 296):
   ```bash
   forge script script/Deploy.s.sol --rpc-url testnet --broadcast --private-key $PRIVATE_KEY
   ```
   Or load the key from `.env` (ensure `foundry.toml` has no `no_storage_caching` that would block `vm.envOr`):
   ```bash
   source .env && forge script script/Deploy.s.sol --rpc-url testnet --broadcast --private-key $PRIVATE_KEY
   ```

4. **Optional**  
   If the RPC does not return chain ID, pass it explicitly:
   ```bash
   forge script script/Deploy.s.sol --rpc-url testnet --broadcast --chain-id 296 --private-key $PRIVATE_KEY
   ```

## Verify on HashScan (Hedera testnet)

After deploying, verify the contract source on [HashScan](https://hashscan.io/) so the bytecode is publicly verified.

1. **Using the script (recommended)**  
   From the project root, pass the deployed contract address (chain ID 296 = testnet by default):
   ```bash
   chmod +x script/verify.sh
   ./script/verify.sh <DEPLOYED_CONTRACT_ADDRESS>
   ```
   For mainnet (295) or previewnet (297):
   ```bash
   ./script/verify.sh <DEPLOYED_CONTRACT_ADDRESS> 295
   ```

2. **Using Forge directly**  
   PoolManager has no constructor arguments. Run:
   ```bash
   forge verify-contract <CONTRACT_ADDRESS> src/PoolManager.sol:PoolManager \
     --chain-id 296 \
     --verifier sourcify \
     --verifier-url "https://server-verify.hashscan.io/" \
     --rpc-url testnet
   ```
   Replace `<CONTRACT_ADDRESS>` with the address from the deploy step. Use `--chain-id 295` for mainnet or `297` for previewnet.

3. **Check result**  
   Open [HashScan](https://hashscan.io/), switch to the correct network (Testnet/Mainnet/Previewnet), search for your contract address. The "Contract" tab should show verified source after a short delay.

## Commands

| Command | Description |
|--------|-------------|
| `forge build` | Compile contracts |
| `forge test` | Run tests |
| `forge test --fork-url <url>` | Run tests against a forked network (e.g. Hedera mainnet) |
| `forge script script/Deploy.s.sol --rpc-url testnet --broadcast` | Deploy PoolManager to Hedera testnet |
| `./script/verify.sh <CONTRACT_ADDRESS>` | Verify PoolManager on HashScan (testnet) |
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
