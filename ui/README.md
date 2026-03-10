# HieroForge UI

Frontend for **HieroForge** (concentrated liquidity AMM on Hedera). Built with **Next.js 15** and React 19.

### Prerequisites (Node.js & npm)

You need Node.js 18+ and npm. If you get `command not found: npm`:

- **Using nvm:** Run `source ~/.nvm/nvm.sh` then `nvm install` (or `nvm use` if you already have Node). Then run `npm install` in `ui/`.
- **Using Homebrew:** `brew install node`, then `npm install` in `ui/`.
- **Otherwise:** Install from [nodejs.org](https://nodejs.org/) and open a new terminal.

Then from the `ui` folder:

```bash
npm install
npm run dev
```

- **Contracts / ABIs:** `src/abis/` (Quoter, PositionManager, PoolManager, ERC20).
- **Run dev:** `npm run dev` (Next.js dev server)
- **Build:** `npm run build` then `npm run start`

### Environment

1. Copy `ui/.env.example` to `ui/.env.local`.
2. Set `NEXT_PUBLIC_WALLETCONNECT_PROJECT_ID` (get from [cloud.walletconnect.com](https://cloud.walletconnect.com/)).
3. Set contract addresses: `NEXT_PUBLIC_POOL_MANAGER_ADDRESS`, `NEXT_PUBLIC_QUOTER_ADDRESS`, `NEXT_PUBLIC_POSITION_MANAGER_ADDRESS`.
4. Optionally set `NEXT_PUBLIC_HEDERA_NETWORK` (`testnet` | `mainnet` | `previewnet`).

### Pools from DynamoDB (no hardcoded list)

Pools are stored in **DynamoDB** so you can load any pool by ID and swap without hardcoding.

1. **Create a DynamoDB table** (e.g. in AWS Console or CLI):
   - Table name: `hieroforge-pools` (or set `DYNAMODB_TABLE_POOLS` in env).
   - Partition key: `poolId` (String).
   - No sort key.

2. **Configure AWS** in `ui/.env.local`:
   - `AWS_REGION` (e.g. `us-east-1`)
   - `AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY` (or use IAM role if deployed to Lambda/ECS).
   - `DYNAMODB_TABLE_POOLS=hieroforge-pools`

3. **In the UI:**
   - **Pool** tab: list is loaded from DynamoDB; use **Load pool by ID** to paste a pool ID (e.g. after creating a pool) and prefill swap/liquidity.
   - When creating a pool or adding liquidity, click **Save pool to list** to store it in DynamoDB for easy loading later.

### HashPack wallet

Install [HashPack](https://www.hashpack.app/) and click **Connect HashPack** in the app.
