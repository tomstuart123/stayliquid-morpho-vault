# Architecture: Allowlist-Gated Morpho Vault V2 (v0.1)

## Overview
**Minimum custom code** approach: Use Morpho Vault V2 completely stock, enforce allowlist via Morpho's native Gate mechanism. Only custom Solidity is a minimal AllowlistGate contract that implements two gate interfaces.

---

## Core Principle
- **No wrapper vaults**
- **No custom ERC-4626 implementation**
- **No strategy contracts** (unless Morpho forces it)
- **Only custom code**: `AllowlistGate.sol` (~100-150 lines)

---

## Architecture Components

### 1. Morpho Vault V2 (Stock)
- **Source**: `lib/morpho-vault-v2/` (cloned from `github.com/morpho-org/vault-v2`)
- **Usage**: Deploy via `VaultV2Factory.createVaultV2(owner, asset, salt)`
- **Asset**: USDC (`0xA0b86991c6218b36c1d19D4a2e9Eb0c3606eB48`)
- **Configuration**: 
  - Set `sendAssetsGate` to our AllowlistGate (deposit gating)
  - Set `receiveSharesGate` to our AllowlistGate (holder gating)
  - Use Morpho's native allocation/ejection controls
  - No custom vault logic

### 2. Allowlist Gate (Only Custom Contract)
- **File**: `src/gates/AllowlistGate.sol`
- **Implements**: `ISendAssetsGate` + `IReceiveSharesGate` (from Morpho)
- **Purpose**: Hard-block deposits from non-approved wallets, prevent shares from being minted/transferred to non-approved wallets
- **Functions**: 
  - `canSendAssets(address account) → bool` (deposit gating)
  - `canReceiveShares(address account) → bool` (holder gating)
- **Size**: ~100-150 lines (tiny and auditable)

### 3. Deployment Flow
1. Deploy `AllowlistGate` (takes admin address)
2. Deploy Morpho Vault V2 via factory (USDC, owner, salt)
3. Set `sendAssetsGate` on vault (as curator, timelock = 0 at creation)
4. Set `receiveSharesGate` on vault (as curator, timelock = 0 at creation)
5. Allowlist fee recipient addresses (if fees are configured)
6. Vault is now gated

**Note**: Foundry scripts typically broadcast multiple transactions. For v0.1 private demo, do not publicize the vault address until gates are set (effectively no ungated window). For true atomicity, see "Deployer Contract" section below.

---

## Gate Interfaces (Exact Signatures from Morpho)

**Source**: `lib/morpho-vault-v2/src/interfaces/IGate.sol`

```solidity
// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity >=0.5.0;

interface ISendAssetsGate {
    function canSendAssets(address account) external view returns (bool);
}

interface IReceiveSharesGate {
    function canReceiveShares(address account) external view returns (bool);
}
```

**Requirements**:
- Both must be `view` (read-only)
- Both must NEVER REVERT under any circumstance (default deny on failure)
- `account` parameter is the address being checked

**Important**: The "never revert" requirement applies ONLY to `canSendAssets()` and `canReceiveShares()` functions. Admin setter functions (e.g., `setAllowed()`, `transferOwnership()`) can and should revert on authorization failures.

---

## Sender vs Receiver Model (Policy Behavior)

**sendAssetsGate**:
- Checks: `msg.sender` (the payer/depositor)
- Purpose: Gate who can deposit assets into the vault
- Example: User calls `vault.deposit(1000, alice)` → Gate checks `msg.sender` (the user), not `alice`

**receiveSharesGate**:
- Checks: `onBehalf` / `to` (the share receiver)
- Purpose: Gate who can hold vault shares
- Example: User calls `vault.deposit(1000, alice)` → Gate checks `alice` (the share receiver), not `msg.sender`
- Example: User calls `vault.transfer(bob, 100)` → Gate checks `bob` (the share receiver)

**This is intended policy behavior**: We gate deposits by sender and share holdings by receiver.

---

## How Gates Are Enforced

### **sendAssetsGate (Deposit Gating)**

**Call Path** (from `VaultV2.sol`):
1. User calls `vault.deposit(assets, onBehalf)` or `vault.mint(shares, onBehalf)`
2. Vault calls `enter(assets, shares, onBehalf)` internally
3. `enter()` checks: `require(canSendAssets(msg.sender), ErrorsLib.CannotSendAssets())` (line 774)
4. `canSendAssets()` (line 931-933) checks:
   - If `sendAssetsGate == address(0)` → allow (no gate set)
   - Otherwise → call `ISendAssetsGate(sendAssetsGate).canSendAssets(msg.sender)`
5. If gate returns `false` → Deposit reverts with `CannotSendAssets`
6. If gate returns `true` → Deposit proceeds

**Policy**: `sendAssetsGate` checks `msg.sender` (the payer/depositor). This is the intended behavior - we gate who can deposit assets into the vault.

**Hard Enforcement**: Gate check happens in `enter()`, which is called by both `deposit()` and `mint()`. No way to bypass for direct contract calls.

### **receiveSharesGate (Holder Gating)**

**Call Paths** (from `VaultV2.sol`):

1. **On Deposit** (line 773):
   - `enter()` checks: `require(canReceiveShares(onBehalf), ErrorsLib.CannotReceiveShares())`
   - Prevents shares from being minted to non-approved wallets
   - **Policy**: Checks `onBehalf` (the share receiver), not `msg.sender`

2. **On Transfer** (line 848):
   - `transfer(to, shares)` checks: `require(canReceiveShares(to), ErrorsLib.CannotReceiveShares())`
   - Prevents shares from being transferred to non-approved wallets
   - **Policy**: Checks `to` (the share receiver)

3. **On TransferFrom** (line 862):
   - `transferFrom(from, to, shares)` checks: `require(canReceiveShares(to), ErrorsLib.CannotReceiveShares())`
   - Prevents shares from being transferred to non-approved wallets
   - **Policy**: Checks `to` (the share receiver)

4. **On Fee Accrual** (lines 672, 677):
   - `accrueInterest()` checks `canReceiveShares(performanceFeeRecipient)` and `canReceiveShares(managementFeeRecipient)`
   - Fees are only minted if recipients are approved
   - **Operational Requirement**: Fee recipient addresses MUST be allowlisted from day 0 OR explicitly configured to an allowlisted address during deployment

**Policy**: `receiveSharesGate` checks the share receiver (`onBehalf`, `to`), not the sender. This is the intended behavior - we gate who can hold vault shares.

**Note**: `createShares()` itself does NOT check the gate - the check happens BEFORE `createShares()` is called.

**Hard Enforcement**: Gate check happens before any share minting or transfer. No way to bypass.

---

## Why NOT sendSharesGate or receiveAssetsGate (v0.1)

### **sendSharesGate** (NOT USED)
- **Why**: Would block withdrawals because it affects burn paths
- **Impact**: If set, users couldn't burn shares to withdraw (would revert on `canSendShares()` check)
- **Decision**: Not required for v0.1 - we only need to control who can receive shares, not who can send them

### **receiveAssetsGate** (NOT USED)
- **Why**: Withdraw destination gating is not required in v0.1
- **Impact**: Users can withdraw to any address (we only care about who holds shares, not where assets go)
- **Decision**: Not required for v0.1 - we only need to control deposits and share holders

---

## Vault Creation + Gate Setting

### **Factory Deployment**
```solidity
VaultV2Factory.createVaultV2(owner, asset, salt) → vaultAddress
```

**Parameters**:
- `owner`: Vault owner (EOA for v0.1, multisig for v0.2)
- `asset`: USDC address
- `salt`: Deterministic salt for CREATE2

**Note**: Factory does NOT accept gate addresses at creation. Gates must be set after.

### **Gate Setting**

**Vault Functions**:
```solidity
vault.setSendAssetsGate(gateAddress)      // Curator function, timelocked
vault.setReceiveSharesGate(gateAddress)   // Curator function, timelocked
```

**Key Details**:
- **Role Required**: Curator (not owner)
- **Timelock**: Zero at vault creation (can set immediately)
- **Source**: VaultV2.sol line 184-186: "timelocks are zero which is useful to set up the vault quickly"

**Timelock Workflow** (if timelock > 0):
1. Curator calls `submit(data)` where `data` is encoded `setSendAssetsGate(gateAddress)`
2. Wait for timelock duration
3. Curator calls `setSendAssetsGate(gateAddress)` (checks `executableAt[data]`)

**For v0.1** (timelock = 0):
- Curator can call `setSendAssetsGate()` and `setReceiveSharesGate()` directly
- No submit/accept workflow needed
- Gates are set immediately

### **Deployment Approach**

**Option A: Multi-Transaction (Recommended for v0.1)**
```solidity
// Transaction 1: Deploy gate
Deploy AllowlistGate(admin) → gateAddress

// Transaction 2: Deploy vault
Deploy VaultV2 via factory → vaultAddress

// Transaction 3: Set gates
vault.setSendAssetsGate(gateAddress)
vault.setReceiveSharesGate(gateAddress)

// Transaction 4: Allowlist fee recipients (if fees configured)
gate.setAllowed(performanceFeeRecipient, true)
gate.setAllowed(managementFeeRecipient, true)
```

**Operational Requirement**: Do NOT publicize the vault address until gates are set. For private demo, this effectively eliminates the ungated window.

**Option B: Deployer Contract (True Atomicity)**
If true atomicity is required, deploy a minimal deployer contract that:
1. Deploys AllowlistGate
2. Deploys VaultV2 via factory
3. Sets both gates
4. Allowlists fee recipients
5. Returns all addresses

This ensures all operations happen in a single transaction. Keep the deployer contract minimal (~50-100 lines).

---

## AllowlistGate Contract Specification

### **State Variables**
```solidity
address public admin;                              // Admin EOA (v0.1), can transfer to multisig (v0.2)
mapping(address => bool) public allowed;          // Allowlist mapping
```

### **Functions**

#### **Gate Functions** (Required by Morpho)
```solidity
function canSendAssets(address account) external view returns (bool)
function canReceiveShares(address account) external view returns (bool)
```

**Implementation**:
- Return `allowed[account]`
- **MUST NEVER REVERT** (default deny on failure)
- Mapping reads won't revert, so no try-catch needed

#### **Admin Functions**
```solidity
function setAllowed(address user, bool isAllowed) external
function transferOwnership(address newAdmin) external
function acceptOwnership() external  // If using 2-step pattern
```

**Access Control**: Only `admin` can call these functions.

### **Non-Negotiables**
- ✅ Gate functions (`canSendAssets`, `canReceiveShares`) MUST NEVER REVERT under any circumstance (default deny on failure)
- ✅ Admin setter functions (`setAllowed`, `transferOwnership`) CAN and SHOULD revert on authorization failures
- ✅ No external calls in gate functions
- ✅ No payable logic
- ✅ No SDKs, no backends
- ✅ Keep it as small and auditable as possible

### **Admin Transfer Pattern**

**Option A: Simple Transfer** (Recommended for v0.1)
```solidity
function transferOwnership(address newAdmin) external {
    require(msg.sender == admin, "Unauthorized");
    require(newAdmin != address(0), "Zero address");
    admin = newAdmin;
}
```

**Option B: 2-Step Transfer** (More secure, optional for v0.1)
```solidity
address public pendingAdmin;

function transferOwnership(address newAdmin) external {
    require(msg.sender == admin, "Unauthorized");
    pendingAdmin = newAdmin;
}

function acceptOwnership() external {
    require(msg.sender == pendingAdmin, "Unauthorized");
    admin = pendingAdmin;
    pendingAdmin = address(0);
}
```

**Recommendation**: Start with Option A (simple) for v0.1, can upgrade to Option B in v0.2.

---

## File Structure

```
contracts/
├── src/
│   └── gates/
│       └── AllowlistGate.sol                   # Only custom contract (~100-150 lines)
├── script/
│   ├── DeployGate.s.sol                       # Deploy gate
│   └── DeployVault.s.sol                     # Deploy vault + set gates (batched)
├── test/
│   ├── AllowlistGate.t.sol                    # Test gate in isolation
│   └── VaultIntegration.t.sol                # Test vault + gate together
└── lib/
    └── morpho-vault-v2/                       # Morpho repo (source of truth)
        └── src/
            ├── interfaces/
            │   └── IGate.sol                  # Gate interfaces
            ├── VaultV2.sol                    # Stock vault
            └── VaultV2Factory.sol             # Factory
```

---

## Key Assumptions

### **Morpho Vault V2**
- ✅ Gate interfaces confirmed: `canSendAssets(address) → bool` and `canReceiveShares(address) → bool`
- ✅ Factory does not accept gates at creation
- ✅ Gates can be set immediately (timelock = 0 at creation)
- ✅ Gate checks are hard-enforced in `enter()`, `transfer()`, `transferFrom()`
- ✅ No ungated window if deployment + gate setting are batched
- ✅ Single gate contract can implement both interfaces (see GateExample.sol)

### **AllowlistGate**
- ✅ Simple mapping-based allowlist
- ✅ Admin EOA for v0.1 (can transfer to multisig in v0.2)
- ✅ Gate functions never revert (default deny)
- ✅ No external dependencies

### **Development**
- ✅ Mainnet fork for testing
- ✅ Foundry for development
- ✅ Minimal custom code (gate only)
- ✅ Stock Morpho Vault V2 (no wrapper)

---

## Testing Requirements

- ✅ Deposits revert from non-approved wallets
- ✅ Deposits succeed from approved wallets
- ✅ Shares cannot be minted to non-approved wallets
- ✅ Shares cannot be transferred to non-approved wallets
- ✅ Gate works in isolation (unit tests)
- ✅ Gate works with vault (integration tests)
- ✅ No ungated deposit window (deployment test)
- ✅ Admin can update allowlist post-deploy
- ✅ Admin can transfer ownership

---

## v0.1 Deliverable

1. **Deploy/configure Morpho Vault V2** (USDC)
   - Target: Morpho mF-ONE → USDC market (or stub if slow)

2. **Build minimal AllowlistGate**
   - Hard-block deposits from non-approved wallets
   - Prevent shares from being minted/transferred to non-approved wallets
   - Admin can update allowlist
   - Admin can transfer ownership

3. **Configure vault's gates**
   - Set `sendAssetsGate` (deposit gating)
   - Set `receiveSharesGate` (holder gating)
   - No ungated window
   - Timelock = 0 for v0.1

4. **Keep allocation/ejection stock**
   - Use Morpho's native controls
   - No custom admin code
   - v0.1 operator = EOA (upgrade to multisig in v0.2)

---

## Upgrade Path (v0.2)

1. **Admin Transfer**: 
   - Current admin (EOA) calls `transferOwnership(multisigAddress)`
   - Multisig becomes new admin
   - No code changes needed

2. **Future Enhancements** (if needed):
   - Add Aave Horizon strategy adaptor
   - Swap allowlist → Quadrata/EAS-based verification
   - Add ERC-7540-style redemption flows

---

## Development Flow

1. **Local mainnet fork** (Anvil + MAINNET_RPC_URL)
2. **Testnet** (if Morpho Vault V2 exists there)
3. **Mainnet** (only after v0.1 complete and validated)

---

## Compiler Compatibility

**Morpho Vault V2**: Uses `pragma solidity 0.8.28` (from `VaultV2.sol`)

**Gate Interfaces**: Use `pragma solidity >=0.5.0` (from `IGate.sol`)

**Our Implementation**: Will use `pragma solidity ^0.8.0` or `0.8.28` to match Morpho's compiler version for consistency.

---

## References

- Morpho Vault V2: `github.com/morpho-org/vault-v2`
- Morpho Docs: `docs.morpho.org/curate/concepts/gates/`
- Gate Example: `lib/morpho-vault-v2/test/examples/GateExample.sol`
