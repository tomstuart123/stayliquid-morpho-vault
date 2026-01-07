// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {ManageAllowlist} from "../script/ManageAllowlist.s.sol";
import {AllowlistGate} from "../src/gates/AllowlistGate.sol";

/// @title ManageAllowlistTest
/// @notice Tests for ManageAllowlist script error handling
/// @dev Note: Full integration tests require file system access and are tested manually
/// @dev The script's main functionality has been tested manually with various configs
contract ManageAllowlistTest is Test {
    ManageAllowlist public script;
    AllowlistGate public gate;
    address public admin = address(0x1);

    function setUp() public {
        script = new ManageAllowlist();
        gate = new AllowlistGate(admin);
    }

    /// @notice Test that script reverts when config file is not found
    function test_RevertsWhenConfigNotFound() public {
        vm.setEnv("GATE_ADDRESS", vm.toString(address(gate)));
        vm.setEnv("ALLOWLIST_CONFIG_PATH", "nonexistent-file.json");
        
        vm.expectRevert(abi.encodeWithSelector(ManageAllowlist.InvalidConfig.selector, "Config file not found"));
        script.run();
    }

    /// @notice Test that gate is correctly instantiated
    function test_GateInteraction() public view {
        // Verify gate was created with correct admin
        assertEq(gate.admin(), admin);
        
        // Verify default behavior (not allowed)
        assertFalse(gate.allowed(address(0x123)));
    }
}
