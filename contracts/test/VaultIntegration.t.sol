// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {AllowlistGate} from "../src/gates/AllowlistGate.sol";
import {IERC20} from "forge-std/interfaces/IERC20.sol";
import {VaultV2Factory} from "../lib/morpho-vault-v2/src/VaultV2Factory.sol";

/// @title VaultIntegrationTest
/// @notice Integration tests for AllowlistGate with real Morpho Vault V2 on mainnet fork
contract VaultIntegrationTest is Test {
    // Mainnet addresses
    address constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address constant USDC_WHALE = 0x4B16c5dE96EB2117bBE5fd171E4d203624B014aa;
    
    // Test contracts
    AllowlistGate public gate;
    address public vault;
    
    // Test addresses
    address public admin = address(0x1);
    address public allowlistedUser = address(0x2);
    address public nonAllowlistedUser = address(0x3);
    
    function setUp() public {
        // Fork mainnet using GitHub Secret
        vm.createSelectFork(vm.envString("MAINNET_RPC_URL"));
        
        // Deploy gate
        gate = new AllowlistGate(admin);
        
        // Deploy VaultV2Factory and create vault
        VaultV2Factory factory = new VaultV2Factory();
        bytes32 salt = keccak256("stayliquid-test");
        vault = factory.createVaultV2(admin, USDC, salt);
        
        // Admin sets curator to admin (for simplified setup)
        vm.prank(admin);
        (bool success0,) = vault.call(
            abi.encodeWithSignature("setCurator(address)", admin)
        );
        require(success0, "setCurator failed");
        
        // Submit setSendAssetsGate transaction (timelock defaults to 0)
        bytes memory setSendAssetsGateData = abi.encodeWithSignature("setSendAssetsGate(address)", address(gate));
        vm.prank(admin);
        (bool success1,) = vault.call(
            abi.encodeWithSignature("submit(bytes)", setSendAssetsGateData)
        );
        require(success1, "submit setSendAssetsGate failed");
        
        // Execute setSendAssetsGate (immediately executable since timelock is 0)
        vm.prank(admin);
        (bool success2,) = vault.call(setSendAssetsGateData);
        require(success2, "setSendAssetsGate failed");
        
        // Submit setReceiveSharesGate transaction
        bytes memory setReceiveSharesGateData = abi.encodeWithSignature("setReceiveSharesGate(address)", address(gate));
        vm.prank(admin);
        (bool success3,) = vault.call(
            abi.encodeWithSignature("submit(bytes)", setReceiveSharesGateData)
        );
        require(success3, "submit setReceiveSharesGate failed");
        
        // Execute setReceiveSharesGate
        vm.prank(admin);
        (bool success4,) = vault.call(setReceiveSharesGateData);
        require(success4, "setReceiveSharesGate failed");
        
        // Allowlist one user
        vm.prank(admin);
        gate.setAllowed(allowlistedUser, true);
        
        // Fund test wallets
        vm.startPrank(USDC_WHALE);
        IERC20(USDC).transfer(allowlistedUser, 10_000e6);      // 10k USDC
        IERC20(USDC).transfer(nonAllowlistedUser, 10_000e6);   // 10k USDC
        vm.stopPrank();
    }
    
    /// @notice Test that allowlisted user can deposit successfully
    function test_AllowlistedCanDeposit() public {
        uint256 depositAmount = 1_000e6;
        
        vm.startPrank(allowlistedUser);
        IERC20(USDC).approve(vault, depositAmount);
        
        (bool success, bytes memory data) = vault.call(
            abi.encodeWithSignature("deposit(uint256,address)", depositAmount, allowlistedUser)
        );
        require(success, "Deposit failed");
        
        uint256 shares = abi.decode(data, (uint256));
        vm.stopPrank();
        
        assertGt(shares, 0, "Should receive shares");
    }
    
    /// @notice Test that non-allowlisted user cannot deposit
    function test_NonAllowlistedCannotDeposit() public {
        uint256 depositAmount = 1_000e6;
        
        vm.startPrank(nonAllowlistedUser);
        IERC20(USDC).approve(vault, depositAmount);
        
        vm.expectRevert();
        vault.call(
            abi.encodeWithSignature("deposit(uint256,address)", depositAmount, nonAllowlistedUser)
        );
        
        vm.stopPrank();
    }
    
    /// @notice Test that shares cannot be transferred to non-allowlisted addresses
    function test_CannotTransferSharesToNonAllowlisted() public {
        // Deposit first
        uint256 depositAmount = 1_000e6;
        vm.startPrank(allowlistedUser);
        IERC20(USDC).approve(vault, depositAmount);
        (bool success, bytes memory data) = vault.call(
            abi.encodeWithSignature("deposit(uint256,address)", depositAmount, allowlistedUser)
        );
        require(success);
        uint256 shares = abi.decode(data, (uint256));
        
        // Try transfer to non-allowlisted (should revert)
        vm.expectRevert();
        vault.call(
            abi.encodeWithSignature("transfer(address,uint256)", nonAllowlistedUser, shares / 2)
        );
        
        vm.stopPrank();
    }
    
    /// @notice Test that admin can update allowlist post-deployment
    function test_AdminCanUpdateAllowlistPostDeploy() public {
        uint256 depositAmount = 1_000e6;
        
        // Initially blocked
        vm.startPrank(nonAllowlistedUser);
        IERC20(USDC).approve(vault, depositAmount);
        vm.expectRevert();
        vault.call(
            abi.encodeWithSignature("deposit(uint256,address)", depositAmount, nonAllowlistedUser)
        );
        vm.stopPrank();
        
        // Admin adds to allowlist
        vm.prank(admin);
        gate.setAllowed(nonAllowlistedUser, true);
        
        // Now can deposit
        vm.startPrank(nonAllowlistedUser);
        (bool success,) = vault.call(
            abi.encodeWithSignature("deposit(uint256,address)", depositAmount, nonAllowlistedUser)
        );
        require(success, "Deposit after allowlist failed");
        vm.stopPrank();
    }
}
