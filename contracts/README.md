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

Run all tests:
```shell
$ forge test
```

Run unit tests only:
```shell
$ forge test --match-path "test/AllowlistGate.t.sol"
```

Run integration tests (requires mainnet RPC URL):
```shell
# Copy .env.example to .env and add your mainnet RPC URL
$ cp .env.example .env
# Edit .env and set MAINNET_RPC_URL

# Run integration tests
$ forge test --match-path "test/VaultIntegration.t.sol" --fork-url $MAINNET_RPC_URL -vvv
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

### Deploy

## Deployment

### Deploy Complete System (Vault + Gate + Morpho Adapter)

This deploys:
- Morpho Vault V2 via factory
- AllowlistGate attached to all 4 gate interfaces
- Morpho Blue market adapter for real yield generation
- Market cap configuration for allocation control
- Configured for production use

#### Prerequisites

1. Copy `.env.example` to `.env`:
   ```bash
   cp .env.example .env
   ```

2. Configure `.env`:
   ```bash
   ADMIN_ADDRESS=0x...        # Your admin wallet (controls allowlist)
   CURATOR_ADDRESS=0x...      # Vault curator (optional, defaults to admin)
   MAINNET_RPC_URL=https://... # Alchemy/Infura mainnet RPC
   PRIVATE_KEY=0x...          # Deployer private key (needs ETH for gas)
   ```

#### Deploy on Mainnet Fork (Local Testing)

```bash
# Run deployment script on mainnet fork
forge script script/DeployVault.s.sol:DeployVault \
    --fork-url $MAINNET_RPC_URL \
    -vvvv

# Save the output addresses:
# - Vault Address: 0x...
# - Gate Address: 0x...
# - Factory Address: 0x...
# - Adapter Address: 0x...
```

#### Deploy to Testnet (Sepolia)

```bash
# Dry run first
forge script script/DeployVault.s.sol:DeployVault \
    --rpc-url $SEPOLIA_RPC_URL \
    -vvvv

# Deploy for real
forge script script/DeployVault.s.sol:DeployVault \
    --rpc-url $SEPOLIA_RPC_URL \
    --broadcast \
    --verify \
    -vvvv
```

#### Deploy to Mainnet

```bash
# IMPORTANT: Dry run first (no --broadcast)
forge script script/DeployVault.s.sol:DeployVault \
    --rpc-url $MAINNET_RPC_URL \
    -vvvv

# Review output carefully, then deploy:
forge script script/DeployVault.s.sol:DeployVault \
    --rpc-url $MAINNET_RPC_URL \
    --broadcast \
    --verify \
    -vvvv

# Save deployment addresses immediately!
```

### Post-Deployment Checklist

- [ ] Save vault address
- [ ] Save gate address  
- [ ] Save adapter address
- [ ] Verify contracts on Etherscan
- [ ] Add initial users to allowlist: `gate.setAllowed(user, true)`
- [ ] Allocate funds to Morpho market: `vault.allocate(adapter, marketData, amount)`
- [ ] Test deposit with allowlisted wallet
- [ ] Verify vault is earning yield from Morpho market
- [ ] Update frontend with contract addresses

### Managing the Allowlist

After deployment, use the `AllowlistGate` contract to manage user access:

```bash
# Add user to allowlist (as admin)
cast send $GATE_ADDRESS "setAllowed(address,bool)" $USER_ADDRESS true --private-key $ADMIN_PRIVATE_KEY

# Remove user from allowlist
cast send $GATE_ADDRESS "setAllowed(address,bool)" $USER_ADDRESS false --private-key $ADMIN_PRIVATE_KEY

# Check if user is allowed
cast call $GATE_ADDRESS "allowed(address)" $USER_ADDRESS
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
