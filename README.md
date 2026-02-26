# HieroForge

**HieroForge** is a concentrated liquidity AMM on Hedera: smart contracts (Foundry/Solidity) and a React frontend with HashPack wallet integration.

## Project structure

```
HieroForge/
├── smart-contract/    # Foundry project (Solidity)
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
cd smart-contract
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
| Build contracts | `cd smart-contract && forge build` |
| Test contracts  | `cd smart-contract && forge test` |
| Run UI dev server | `cd ui && npm run dev` |
| Build UI for production | `cd ui && npm run build` |

## Documentation

- [Foundry Book](https://book.getfoundry.sh/)
- [Hedera](https://docs.hedera.com/)
- [HashPack](https://www.hashpack.app/)
- [WalletConnect Cloud](https://cloud.walletconnect.com/) (project ID for dApps)

## License

Apache-2.0 (see SPDX headers in source files).
