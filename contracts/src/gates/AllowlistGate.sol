// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {ISendAssetsGate, IReceiveSharesGate} from "../../lib/morpho-vault-v2/src/interfaces/IGate.sol";

/// @title AllowlistGate
/// @notice Minimal allowlist gate for Morpho Vault V2
/// @dev Implements ISendAssetsGate (deposit gating) and IReceiveSharesGate (holder gating)
/// @dev Gate functions never revert - default deny on failure
/// @dev Admin setters can revert on authorization failures

contract AllowlistGate is ISendAssetsGate, IReceiveSharesGate {
    /// @notice Admin address (EOA for v0.1, can transfer to multisig in v0.2)
    address public admin;

    /// @notice Allowlist mapping
    mapping(address => bool) public allowed;

    /// @notice Event emitted when allowlist status changes
    event AllowedSet(address indexed user, bool allowed);

    /// @notice Event emitted when admin is transferred
    event AdminTransferred(address indexed oldAdmin, address indexed newAdmin);

    /// @notice Error thrown when caller is not admin
    error Unauthorized();

    /// @notice Error thrown when new admin is zero address
    error ZeroAddress();

    /// @param _admin Initial admin address
    constructor(address _admin) {
        if (_admin == address(0)) revert ZeroAddress();
        admin = _admin;
    }

    /// @notice Check if account can send assets (deposit gating)
    /// @param account Address to check (msg.sender in deposit calls)
    /// @return true if account is allowed, false otherwise
    /// @dev MUST NEVER REVERT - returns false for non-allowed addresses
    function canSendAssets(address account) external view override returns (bool) {
        return allowed[account];
    }

    /// @notice Check if account can receive shares (holder gating)
    /// @param account Address to check (onBehalf/to in share operations)
    /// @return true if account is allowed, false otherwise
    /// @dev MUST NEVER REVERT - returns false for non-allowed addresses
    function canReceiveShares(address account) external view override returns (bool) {
        return allowed[account];
    }

    /// @notice Set allowlist status for an address
    /// @param user Address to allowlist/unallowlist
    /// @param isAllowed true to allowlist, false to remove
    /// @dev Only admin can call this function
    function setAllowed(address user, bool isAllowed) external {
        if (msg.sender != admin) revert Unauthorized();
        allowed[user] = isAllowed;
        emit AllowedSet(user, isAllowed);
    }

    /// @notice Transfer admin ownership to a new address
    /// @param newAdmin New admin address
    /// @dev Only current admin can call this function
    function transferOwnership(address newAdmin) external {
        if (msg.sender != admin) revert Unauthorized();
        if (newAdmin == address(0)) revert ZeroAddress();
        address oldAdmin = admin;
        admin = newAdmin;
        emit AdminTransferred(oldAdmin, newAdmin);
    }
}

