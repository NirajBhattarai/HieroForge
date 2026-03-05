# HieroForge

**HieroForge** is a concentrated liquidity AMM on Hedera: smart contracts (Foundry/Solidity) and a React frontend with HashPack wallet integration.

## Project structure

```
HieroForge/
├── hieroforge-core/    # Foundry project (Solidity)
│   ├── src/
│   ├── test/
│   ├── script/
│   └── lib/forge-std/
├── ui/                # Vite + React frontend
│   ├── src/
│   │   ├── context/   # HashPackContext (wallet connect)
│   │   └── App.jsx
│   └── package.json
├── .env.example       # Root env (e.g. deploy keys)
└── README.md
```

## Prerequisites

- **Smart contract:** [Foundry](https://getfoundry.sh/) (Forge, Cast, Anvil)
- **UI:** Node.js 18+, npm

## Quick start

### Smart contract

```bash
cd hieroforge-core
git submodule update --init --recursive   # if using submodules
forge build
forge test
```

### UI (frontend + HashPack)

```bash
cd ui
cp .env.example .env
# Edit .env: set VITE_WALLETCONNECT_PROJECT_ID (get one at cloud.walletconnect.com)
npm install
npm run dev
```

Then install the [HashPack](https://www.hashpack.app/) browser extension and click **Connect HashPack** in the app. See [ui/README.md](ui/README.md) for HashPack and env details.

## Configuration

- **Root:** Copy `.env.example` to `.env` for deploy keys (e.g. `PRIVATE_KEY`) if you run deploy scripts from the repo root.
- **UI:** Copy `ui/.env.example` to `ui/.env` and set:
  - `VITE_WALLETCONNECT_PROJECT_ID` (required for HashPack)
  - `VITE_HEDERA_NETWORK` (optional: `testnet` | `mainnet` | `previewnet`, default `testnet`)

## Commands

| What        | Command |
|------------|--------|
| Build contracts | `cd hieroforge-core && forge build` |
| Test contracts (HTS token creation) | `cd hieroforge-core && forge test` |
| HTS tests on forked testnet | `cd hieroforge-core && forge test --match-contract CreateHtsTokenTest --fork-url https://testnet.hashio.io/api` |
| **Create HTS token** (testnet or local) | `cd hieroforge-core && source ../.env 2>/dev/null; forge script script/CreateHtsToken.s.sol:CreateHtsTokenScript --rpc-url ${HEDERA_RPC_URL:-https://testnet.hashio.io/api} --broadcast --private-key $PRIVATE_KEY` |
| Run UI dev server | `cd ui && npm run dev` |
| Build UI for production | `cd ui && npm run build` |

### HTS token (Foundry)

The project uses [Hedera Token Service](https://docs.hedera.com/hedera/sdks-and-apis/sdks/smart-contracts/hedera-service-solidity-libraries) via the HTS precompile. To create a fungible token on **Hedera testnet** or a **local Hedera node**:

1. Set `PRIVATE_KEY` in `.env` (account must have HBAR for fees).
2. Optional: set `TREASURY` (EVM address) or it defaults to the signer.
3. Optional: set `HEDERA_RPC_URL` (default: testnet hashio).
4. From repo root: `cd hieroforge-core && forge script script/CreateHtsToken.s.sol:CreateHtsTokenScript --rpc-url $HEDERA_RPC_URL --broadcast --private-key $PRIVATE_KEY`

For a **local Hedera node**, run the same command with `HEDERA_RPC_URL` pointing at your node’s EVM RPC (e.g. `http://127.0.0.1:7546`). The created token’s address is emitted in the `CreatedToken` event.

## Documentation

- [Foundry Book](https://book.getfoundry.sh/)
- [Hedera](https://docs.hedera.com/)
- [HashPack](https://www.hashpack.app/)
- [WalletConnect Cloud](https://cloud.walletconnect.com/) (project ID for dApps)

### For later: HTS fork testing

- **[hedera-forking](https://github.com/hashgraph/hedera-forking)** — Foundry library (and Hardhat plugin) that emulates the Hedera Token Service at `0x167` so you can run **fork tests** against Hedera (e.g. `forge test --fork-url https://testnet.hashio.io/api`). Use `Hsc.htsSetup()` in test `setUp()` and optional `--skip-simulation` for scripts. Lets you test HTS token creation/transfers locally without a live node. See repo README for setup (`ffi = true`, RPC endpoints, and supported HTS methods).

## License

Apache-2.0 (see SPDX headers in source files).
