## Foundry

**Foundry is a blazing fast, portable and modular toolkit for Ethereum application development written in Rust.**

Foundry consists of:

- **Forge**: Ethereum testing framework (like Truffle, Hardhat and DappTools).
- **Cast**: Swiss army knife for interacting with EVM smart contracts, sending transactions and getting chain data.
- **Anvil**: Local Ethereum node, akin to Ganache, Hardhat Network.
- **Chisel**: Fast, utilitarian, and verbose solidity REPL.

## Documentation

https://book.getfoundry.sh/

## Usage

### Build

```shell
$ forge build
```

### Test

```shell
$ forge test
```

### Format

```shell
$ forge fmt
```

### Gas Snapshots

```shell
$ forge snapshot
```

### Anvil

```shell
$ anvil
```

### Deploy PoolManager (and optionally Router)

**Deploy PoolManager only:**

```shell
export PRIVATE_KEY=0x...
forge script script/DeployPoolManagerOnly.s.sol:DeployPoolManagerOnlyScript --rpc-url testnet --broadcast --private-key $PRIVATE_KEY
```

**Deploy PoolManager and ModifyLiquidityRouter:**

```shell
forge script script/DeployPoolManager.s.sol:DeployPoolManagerScript --rpc-url testnet --broadcast --private-key $PRIVATE_KEY
```

Or with explicit RPC URL:

```shell
forge script script/DeployPoolManager.s.sol:DeployPoolManagerScript --rpc-url https://testnet.hashio.io/api --broadcast --private-key $PRIVATE_KEY
```

The scripts log the deployed address(es). Set `VITE_POOL_MANAGER_ADDRESS` in the UI `.env` to enable the Create Pool form.

### Deploy / Create HTS token

```shell
$ forge script script/CreateHtsToken.s.sol:CreateHtsTokenScript --rpc-url $HEDERA_RPC_URL --broadcast --private-key $PRIVATE_KEY
```

### Cast

```shell
$ cast <subcommand>
```

### Help

```shell
$ forge --help
$ anvil --help
$ cast --help
```
