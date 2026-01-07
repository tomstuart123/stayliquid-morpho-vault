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

   **Note**: Get a free Alchemy/Infura API key at:
   - Alchemy: https://www.alchemy.com/
   - Infura: https://www.infura.io/

#### Deploy on Mainnet Fork (Local Testing)

```bash
# Load environment variables
source .env

# Run deployment script on mainnet fork
forge script script/DeployVault.s.sol:DeployVault \
    --fork-url $MAINNET_RPC_URL \
    -vvvv

# Save the output addresses:
# - Vault Address: 0x...
# - Gate Address: 0x...
# - Factory Address: 0x...
# - Adapter Address: 0x...
# - Adapter Factory Address: 0x...
```

**Expected Output**:
```
=== Morpho Vault V2 Deployment ===
Network: Mainnet Fork
Admin: 0x...
Curator: 0x...
Asset: USDC 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48

1. Deploying VaultV2Factory...
   Factory deployed at: 0x...

2. Deploying AllowlistGate...
   Gate deployed at: 0x...
   Gate admin: 0x...

3. Deploying Vault via Factory...
   Vault deployed at: 0x...

4. Configuring Vault...
   Name: StayLiquid Allowlisted Vault
   Symbol: slUSDC
   Curator set to: 0x...

5. Setting Gates (as curator)...
   sendAssetsGate set
   receiveSharesGate set
   sendSharesGate set
   receiveAssetsGate set

6. Deploying Morpho Market Adapter...
   Adapter Factory deployed at: 0x...
   Adapter deployed at: 0x...
   Adapter added to vault
   Curator set as allocator

7. Configuring Market Caps...
   Absolute cap set to: 1000000 USDC
   Relative cap set to: 90%

=== Deployment Complete ===
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

**Note**: For Sepolia deployment, you'll need to update the contract addresses in the script to use Sepolia addresses for Morpho Blue, USDC, etc.

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

- [ ] Save all deployment addresses (vault, gate, adapter, factories)
- [ ] Verify contracts on Etherscan (automatic with `--verify` flag)
- [ ] Add initial users to allowlist: `gate.setAllowed(user, true)`
- [ ] Allocate funds to Morpho market: `vault.allocate(adapter, marketData, amount)`
- [ ] Test deposit with allowlisted wallet
- [ ] Verify vault is earning yield from Morpho market
- [ ] Update frontend with contract addresses
- [ ] Document market parameters used

### Managing the Allowlist

After deployment, use the `AllowlistGate` contract to manage user access:

```bash
# Add user to allowlist (as admin)
cast send $GATE_ADDRESS "setAllowed(address,bool)" $USER_ADDRESS true \
    --rpc-url $MAINNET_RPC_URL \
    --private-key $ADMIN_PRIVATE_KEY

# Remove user from allowlist
cast send $GATE_ADDRESS "setAllowed(address,bool)" $USER_ADDRESS false \
    --rpc-url $MAINNET_RPC_URL \
    --private-key $ADMIN_PRIVATE_KEY

# Check if user is allowed
cast call $GATE_ADDRESS "allowed(address)" $USER_ADDRESS \
    --rpc-url $MAINNET_RPC_URL
```

### Managing the Allowlist (Batch)

For managing multiple addresses efficiently, use the batch management script:

#### Configuration

1. Create a config file from the example:
   ```bash
   cp allowlist-config.example.json allowlist-config.json
   ```

2. Edit `allowlist-config.json` with your addresses:
   ```json
   {
     "mode": "add",
     "addresses": [
       "0x0742D35CC6634c0532925A3b844bc9E7595f0Beb",
       "0x1234567890123456789012345678901234567890",
       "0xABcdEFABcdEFabcdEfAbCdefabcdeFABcDEFabCD"
     ]
   }
   ```

   **Config Fields**:
   - `mode`: Either `"add"` (allowlist addresses) or `"remove"` (remove from allowlist)
   - `addresses`: Array of Ethereum addresses to process (must be valid checksummed addresses)
   
   **Note**: Replace the example addresses above with your actual user addresses before running in production.

#### Usage

**Environment Variables**:
- `GATE_ADDRESS` (required): Address of the deployed AllowlistGate contract
- `ALLOWLIST_CONFIG_PATH` (optional): Path to config file (defaults to `allowlist-config.json`)

**Dry Run** (simulate without broadcasting):
```bash
# Load environment
source .env

# Set gate address from deployment
export GATE_ADDRESS=0x...  # from deployment output

# Dry run - test adding addresses
forge script script/ManageAllowlist.s.sol:ManageAllowlist \
    --fork-url mainnet \
    -vvvv
```

**Expected Output**:
```
=== Allowlist Batch Management ===
Gate Address: 0x...
Config File: allowlist-config.json

Mode: add
Addresses to process: 3

Addresses:
   1 . 0x0742D35CC6634c0532925A3b844bc9E7595f0Beb
   2 . 0x1234567890123456789012345678901234567890
   3 . 0xABcdEFABcdEFabcdEfAbCdefabcdeFABcDEFabCD

Executing batch operation...

=== Operation Complete ===
Successfully added 3 addresses to allowlist
```

**Broadcast** (actually execute on-chain):
```bash
# Add addresses to allowlist
forge script script/ManageAllowlist.s.sol:ManageAllowlist \
    --fork-url mainnet \
    --broadcast \
    --private-key $ADMIN_PRIVATE_KEY \
    -vvvv

# For removing addresses, change mode in config to "remove" and run again
```

**Custom Config Path**:
```bash
# Use a different config file
export ALLOWLIST_CONFIG_PATH=allowlist-production.json
forge script script/ManageAllowlist.s.sol:ManageAllowlist \
    --fork-url mainnet \
    --broadcast \
    --private-key $ADMIN_PRIVATE_KEY
```

**Verify Changes**:
```bash
# Check if an address is now allowed
cast call $GATE_ADDRESS "allowed(address)" 0x0742D35CC6634c0532925A3b844bc9E7595f0Beb \
    --rpc-url $MAINNET_RPC_URL
```

### Allocating to Morpho Markets

After deployment, the curator can allocate vault funds to Morpho Blue markets:

```bash
# Example: Allocate 100,000 USDC to a market
# First, encode the market parameters (use the same params from deployment)
# Then call allocate:
cast send $VAULT_ADDRESS "allocate(address,bytes,uint256)" \
    $ADAPTER_ADDRESS \
    $MARKET_DATA \
    100000000000 \
    --rpc-url $MAINNET_RPC_URL \
    --private-key $CURATOR_PRIVATE_KEY
```

**Important Notes**:
- The script uses example market parameters that should be verified for production
- Check https://app.morpho.org/ethereum for accurate market details
- Ensure the market accepts USDC as the loan token
- The Adaptive Curve IRM address is: `0x870aC11D48B15DB9a138Cf899d20F13F79Ba00BC`
- Morpho Blue contract: `0xBBBBBbbBBb9cC5e90e3b3Af64bdAF62C37EEFFCb`

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
