// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {AllowlistGate} from "../src/gates/AllowlistGate.sol";

/// @title AllowlistGateTest
/// @notice Unit tests for AllowlistGate contract
contract AllowlistGateTest is Test {
    AllowlistGate public gate;
    address public admin = address(0x1);
    address public user1 = address(0x2);
    address public user2 = address(0x3);
    address public nonAdmin = address(0x4);

    function setUp() public {
        gate = new AllowlistGate(admin);
    }

    /// @notice Test default deny behavior
    function test_DefaultDeny() public view {
        // canSendAssets returns false for non-allowed addresses
        assertFalse(gate.canSendAssets(user1));
        assertFalse(gate.canSendAssets(user2));
        assertFalse(gate.canSendAssets(admin));

        // canReceiveShares returns false for non-allowed addresses
        assertFalse(gate.canReceiveShares(user1));
        assertFalse(gate.canReceiveShares(user2));
        assertFalse(gate.canReceiveShares(admin));

        // canSendShares returns false for non-allowed addresses
        assertFalse(gate.canSendShares(user1));
        assertFalse(gate.canSendShares(user2));
        assertFalse(gate.canSendShares(admin));

        // canReceiveAssets returns false for non-allowed addresses
        assertFalse(gate.canReceiveAssets(user1));
        assertFalse(gate.canReceiveAssets(user2));
        assertFalse(gate.canReceiveAssets(admin));
    }

    /// @notice Test admin can setAllowed to allowlist a user
    function test_AdminCanSetAllowed_Allowlist() public {
        vm.prank(admin);
        gate.setAllowed(user1, true);

        assertTrue(gate.allowed(user1));
        assertTrue(gate.canSendAssets(user1));
        assertTrue(gate.canReceiveShares(user1));
        assertTrue(gate.canSendShares(user1));
        assertTrue(gate.canReceiveAssets(user1));
    }

    /// @notice Test admin can setAllowed to remove a user from allowlist
    function test_AdminCanSetAllowed_Remove() public {
        // First allowlist
        vm.prank(admin);
        gate.setAllowed(user1, true);
        assertTrue(gate.allowed(user1));

        // Then remove
        vm.prank(admin);
        gate.setAllowed(user1, false);
        assertFalse(gate.allowed(user1));
        assertFalse(gate.canSendAssets(user1));
        assertFalse(gate.canReceiveShares(user1));
        assertFalse(gate.canSendShares(user1));
        assertFalse(gate.canReceiveAssets(user1));
    }

    /// @notice Test admin can setAllowed multiple users
    function test_AdminCanSetAllowed_MultipleUsers() public {
        vm.prank(admin);
        gate.setAllowed(user1, true);

        vm.prank(admin);
        gate.setAllowed(user2, true);

        assertTrue(gate.allowed(user1));
        assertTrue(gate.allowed(user2));
        assertTrue(gate.canSendAssets(user1));
        assertTrue(gate.canSendAssets(user2));
        assertTrue(gate.canReceiveShares(user1));
        assertTrue(gate.canReceiveShares(user2));
        assertTrue(gate.canSendShares(user1));
        assertTrue(gate.canSendShares(user2));
        assertTrue(gate.canReceiveAssets(user1));
        assertTrue(gate.canReceiveAssets(user2));
    }

    /// @notice Test non-admin cannot setAllowed
    function test_NonAdminCannotSetAllowed() public {
        vm.prank(nonAdmin);
        vm.expectRevert(AllowlistGate.Unauthorized.selector);
        gate.setAllowed(user1, true);

        // Verify user1 is still not allowed
        assertFalse(gate.allowed(user1));
    }

    /// @notice Test admin can transferOwnership
    function test_AdminCanTransferOwnership() public {
        address newAdmin = address(0x5);

        vm.prank(admin);
        gate.transferOwnership(newAdmin);

        assertEq(gate.admin(), newAdmin);
    }

    /// @notice Test non-admin cannot transferOwnership
    function test_NonAdminCannotTransferOwnership() public {
        address newAdmin = address(0x5);

        vm.prank(nonAdmin);
        vm.expectRevert(AllowlistGate.Unauthorized.selector);
        gate.transferOwnership(newAdmin);

        // Verify admin is unchanged
        assertEq(gate.admin(), admin);
    }

    /// @notice Test transferOwnership with zero address reverts
    function test_TransferOwnershipZeroAddress() public {
        vm.prank(admin);
        vm.expectRevert(AllowlistGate.ZeroAddress.selector);
        gate.transferOwnership(address(0));

        // Verify admin is unchanged
        assertEq(gate.admin(), admin);
    }

    /// @notice Test new admin can setAllowed after ownership transfer
    function test_NewAdminCanSetAllowed() public {
        address newAdmin = address(0x5);

        // Transfer ownership
        vm.prank(admin);
        gate.transferOwnership(newAdmin);

        // New admin can setAllowed
        vm.prank(newAdmin);
        gate.setAllowed(user1, true);

        assertTrue(gate.allowed(user1));
    }

    /// @notice Test old admin cannot setAllowed after ownership transfer
    function test_OldAdminCannotSetAllowed() public {
        address newAdmin = address(0x5);

        // Transfer ownership
        vm.prank(admin);
        gate.transferOwnership(newAdmin);

        // Old admin cannot setAllowed
        vm.prank(admin);
        vm.expectRevert(AllowlistGate.Unauthorized.selector);
        gate.setAllowed(user1, true);
    }

    /// @notice Test events are emitted correctly
    function test_EventsEmitted() public {
        // Test AllowedSet event
        vm.expectEmit(true, false, false, false);
        emit AllowlistGate.AllowedSet(user1, true);
        vm.prank(admin);
        gate.setAllowed(user1, true);

        // Test AdminTransferred event
        address newAdmin = address(0x5);
        vm.expectEmit(true, false, false, false);
        emit AllowlistGate.AdminTransferred(admin, newAdmin);
        vm.prank(admin);
        gate.transferOwnership(newAdmin);
    }

    /// @notice Test constructor reverts on zero address admin
    function test_ConstructorZeroAddress() public {
        vm.expectRevert(AllowlistGate.ZeroAddress.selector);
        new AllowlistGate(address(0));
    }
}

