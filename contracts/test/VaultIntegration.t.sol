// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {AllowlistGate} from "../src/gates/AllowlistGate.sol";
import {VaultV2} from "../lib/morpho-vault-v2/src/VaultV2.sol";
import {VaultV2Factory} from "../lib/morpho-vault-v2/src/VaultV2Factory.sol";
import {IVaultV2} from "../lib/morpho-vault-v2/src/interfaces/IVaultV2.sol";
import {IERC20} from "../lib/morpho-vault-v2/src/interfaces/IERC20.sol";

/// @title VaultIntegration
/// @notice Integration tests for AllowlistGate with real Morpho Vault V2 on mainnet fork
contract VaultIntegrationTest is Test {
    // Mainnet addresses
    address constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address constant USDC_WHALE = 0x4B16c5dE96EB2117bBE5fd171E4d203624B014aa;

    // Test actors
    address public admin;
    address public curator;
    address public allowlistedUser1;
    address public allowlistedUser2;
    address public nonAllowlistedUser;

    // Contracts
    VaultV2Factory public factory;
    VaultV2 public vault;
    AllowlistGate public gate;
    IERC20 public usdc;

    // Test amounts
    uint256 constant DEPOSIT_AMOUNT = 1000 * 1e6; // 1000 USDC
    uint256 constant TRANSFER_AMOUNT = 100 * 1e6; // 100 USDC worth of shares

    function setUp() public {
        // Create mainnet fork
        vm.createSelectFork(vm.envString("MAINNET_RPC_URL"));

        // Setup test actors
        admin = makeAddr("admin");
        curator = makeAddr("curator");
        allowlistedUser1 = makeAddr("allowlistedUser1");
        allowlistedUser2 = makeAddr("allowlistedUser2");
        nonAllowlistedUser = makeAddr("nonAllowlistedUser");

        // Deploy contracts
        factory = new VaultV2Factory();
        vault = VaultV2(factory.createVaultV2(admin, USDC, bytes32(uint256(1))));
        gate = new AllowlistGate(admin);
        usdc = IERC20(USDC);

        // Setup vault
        vm.startPrank(admin);
        vault.setCurator(curator);
        vault.setName("Test Vault");
        vault.setSymbol("TVT");
        vm.stopPrank();

        // Setup gates through timelock mechanism
        vm.startPrank(curator);
        vault.submit(abi.encodeCall(IVaultV2.setSendAssetsGate, (address(gate))));
        vault.setSendAssetsGate(address(gate));
        vault.submit(abi.encodeCall(IVaultV2.setReceiveSharesGate, (address(gate))));
        vault.setReceiveSharesGate(address(gate));
        vm.stopPrank();

        // Fund test wallets from USDC whale
        vm.startPrank(USDC_WHALE);
        usdc.transfer(allowlistedUser1, DEPOSIT_AMOUNT * 10);
        usdc.transfer(allowlistedUser2, DEPOSIT_AMOUNT * 10);
        usdc.transfer(nonAllowlistedUser, DEPOSIT_AMOUNT * 10);
        vm.stopPrank();

        // Allowlist users
        vm.startPrank(admin);
        gate.setAllowed(allowlistedUser1, true);
        gate.setAllowed(allowlistedUser2, true);
        vm.stopPrank();

        // Approve vault for all users
        vm.prank(allowlistedUser1);
        usdc.approve(address(vault), type(uint256).max);

        vm.prank(allowlistedUser2);
        usdc.approve(address(vault), type(uint256).max);

        vm.prank(nonAllowlistedUser);
        usdc.approve(address(vault), type(uint256).max);
    }

    /// @notice Test that non-allowlisted user cannot deposit
    function test_NonAllowlistedCannotDeposit() public {
        vm.prank(nonAllowlistedUser);
        vm.expectRevert();
        vault.deposit(DEPOSIT_AMOUNT, nonAllowlistedUser);
    }

    /// @notice Test that allowlisted user can deposit successfully
    function test_AllowlistedCanDeposit() public {
        uint256 balanceBefore = usdc.balanceOf(allowlistedUser1);
        uint256 sharesBefore = vault.balanceOf(allowlistedUser1);

        vm.prank(allowlistedUser1);
        uint256 shares = vault.deposit(DEPOSIT_AMOUNT, allowlistedUser1);

        assertGt(shares, 0, "Should receive shares");
        assertEq(usdc.balanceOf(allowlistedUser1), balanceBefore - DEPOSIT_AMOUNT, "USDC should be transferred");
        assertEq(vault.balanceOf(allowlistedUser1), sharesBefore + shares, "Shares should be minted");
    }

    /// @notice Test that cannot deposit for non-allowlisted receiver
    function test_CannotDepositToNonAllowlistedReceiver() public {
        vm.prank(allowlistedUser1);
        vm.expectRevert();
        vault.deposit(DEPOSIT_AMOUNT, nonAllowlistedUser);
    }

    /// @notice Test that cannot transfer shares to non-allowlisted user
    function test_CannotTransferSharesToNonAllowlisted() public {
        // First, allowlisted user deposits
        vm.prank(allowlistedUser1);
        vault.deposit(DEPOSIT_AMOUNT, allowlistedUser1);

        // Try to transfer to non-allowlisted user
        uint256 sharesToTransfer = vault.balanceOf(allowlistedUser1) / 10;
        vm.prank(allowlistedUser1);
        vm.expectRevert();
        vault.transfer(nonAllowlistedUser, sharesToTransfer);
    }

    /// @notice Test that can transfer shares between allowlisted users
    function test_CanTransferSharesBetweenAllowlisted() public {
        // First, allowlisted user deposits
        vm.prank(allowlistedUser1);
        vault.deposit(DEPOSIT_AMOUNT, allowlistedUser1);

        uint256 sharesToTransfer = vault.balanceOf(allowlistedUser1) / 10;
        uint256 user1BalanceBefore = vault.balanceOf(allowlistedUser1);
        uint256 user2BalanceBefore = vault.balanceOf(allowlistedUser2);

        // Transfer to another allowlisted user
        vm.prank(allowlistedUser1);
        vault.transfer(allowlistedUser2, sharesToTransfer);

        assertEq(
            vault.balanceOf(allowlistedUser1), user1BalanceBefore - sharesToTransfer, "User1 shares should decrease"
        );
        assertEq(
            vault.balanceOf(allowlistedUser2), user2BalanceBefore + sharesToTransfer, "User2 shares should increase"
        );
    }

    /// @notice Test that admin can update allowlist after vault deployed
    function test_AdminCanUpdateAllowlistPostDeploy() public {
        // Initially non-allowlisted user cannot deposit
        vm.prank(nonAllowlistedUser);
        vm.expectRevert();
        vault.deposit(DEPOSIT_AMOUNT, nonAllowlistedUser);

        // Admin adds user to allowlist
        vm.prank(admin);
        gate.setAllowed(nonAllowlistedUser, true);

        // Now user can deposit
        vm.prank(nonAllowlistedUser);
        uint256 shares = vault.deposit(DEPOSIT_AMOUNT, nonAllowlistedUser);
        assertGt(shares, 0, "Should receive shares after being allowlisted");

        // Admin removes user from allowlist
        vm.prank(admin);
        gate.setAllowed(nonAllowlistedUser, false);

        // User cannot deposit again
        vm.prank(nonAllowlistedUser);
        vm.expectRevert();
        vault.deposit(DEPOSIT_AMOUNT, nonAllowlistedUser);
    }

    /// @notice Test that allowlisted user can withdraw/redeem
    function test_AllowlistedCanWithdraw() public {
        // First, user deposits
        vm.prank(allowlistedUser1);
        uint256 shares = vault.deposit(DEPOSIT_AMOUNT, allowlistedUser1);

        uint256 usdcBalanceBefore = usdc.balanceOf(allowlistedUser1);
        uint256 sharesBalanceBefore = vault.balanceOf(allowlistedUser1);

        // User withdraws half
        uint256 withdrawAmount = DEPOSIT_AMOUNT / 2;
        vm.prank(allowlistedUser1);
        uint256 sharesRedeemed = vault.withdraw(withdrawAmount, allowlistedUser1, allowlistedUser1);

        assertGt(sharesRedeemed, 0, "Should redeem shares");
        assertEq(
            usdc.balanceOf(allowlistedUser1), usdcBalanceBefore + withdrawAmount, "Should receive USDC back"
        );
        assertEq(
            vault.balanceOf(allowlistedUser1),
            sharesBalanceBefore - sharesRedeemed,
            "Shares should be burned"
        );

        // User redeems remaining shares
        uint256 remainingShares = vault.balanceOf(allowlistedUser1);
        vm.prank(allowlistedUser1);
        uint256 assetsReceived = vault.redeem(remainingShares, allowlistedUser1, allowlistedUser1);

        assertGt(assetsReceived, 0, "Should receive assets");
        assertEq(vault.balanceOf(allowlistedUser1), 0, "All shares should be redeemed");
    }
}
