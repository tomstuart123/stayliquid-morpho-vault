// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {AllowlistGate} from "../src/gates/AllowlistGate.sol";
import {stdJson} from "forge-std/StdJson.sol";

/// @title ManageAllowlist
/// @notice Batch management script for AllowlistGate
/// @dev Reads addresses from JSON config and executes batch setAllowed operations
contract ManageAllowlist is Script {
    using stdJson for string;

    /// @notice Error thrown when gate address is not set
    error GateAddressNotSet();

    /// @notice Error thrown when config file is not found or invalid
    error InvalidConfig(string reason);

    /// @notice Error thrown when no addresses to process
    error NoAddressesToProcess();

    /// @notice Error thrown when address is invalid
    error InvalidAddress(string addressStr);

    function run() external {
        // Read configuration from environment
        address gateAddress;
        try vm.envAddress("GATE_ADDRESS") returns (address addr) {
            gateAddress = addr;
        } catch {
            revert GateAddressNotSet();
        }
        
        if (gateAddress == address(0)) revert GateAddressNotSet();

        string memory configPath = vm.envOr("ALLOWLIST_CONFIG_PATH", string("allowlist-config.json"));

        console.log("=== Allowlist Batch Management ===");
        console.log("Gate Address:", gateAddress);
        console.log("Config File:", configPath);
        console.log("");

        // Read and parse JSON config
        string memory json;
        try vm.readFile(configPath) returns (string memory fileContent) {
            json = fileContent;
        } catch {
            revert InvalidConfig("Config file not found");
        }

        // Parse mode
        string memory mode;
        try vm.parseJsonString(json, ".mode") returns (string memory parsedMode) {
            mode = parsedMode;
        } catch {
            revert InvalidConfig("Missing or invalid 'mode' field");
        }

        // Validate mode
        bool isAdd = false;
        if (keccak256(bytes(mode)) == keccak256(bytes("add"))) {
            isAdd = true;
        } else if (keccak256(bytes(mode)) == keccak256(bytes("remove"))) {
            isAdd = false;
        } else {
            revert InvalidConfig("Mode must be 'add' or 'remove'");
        }

        // Parse addresses array
        address[] memory addresses;
        try vm.parseJsonAddressArray(json, ".addresses") returns (address[] memory parsedAddresses) {
            addresses = parsedAddresses;
        } catch {
            revert InvalidConfig("Missing or invalid 'addresses' array");
        }

        if (addresses.length == 0) {
            revert NoAddressesToProcess();
        }

        // Validate all addresses are non-zero
        for (uint256 i = 0; i < addresses.length; i++) {
            if (addresses[i] == address(0)) {
                revert InvalidAddress("Zero address found in config");
            }
        }

        // Display operation details
        console.log("Mode:", mode);
        console.log("Addresses to process:", addresses.length);
        console.log("");

        // List all addresses
        console.log("Addresses:");
        for (uint256 i = 0; i < addresses.length; i++) {
            console.log("  ", i + 1, ".", addresses[i]);
        }
        console.log("");

        // Execute batch operation
        AllowlistGate gate = AllowlistGate(gateAddress);

        vm.startBroadcast();

        console.log("Executing batch operation...");
        for (uint256 i = 0; i < addresses.length; i++) {
            gate.setAllowed(addresses[i], isAdd);
        }

        vm.stopBroadcast();

        // Summary
        console.log("");
        console.log("=== Operation Complete ===");
        if (isAdd) {
            console.log("Successfully added", addresses.length, "addresses to allowlist");
        } else {
            console.log("Successfully removed", addresses.length, "addresses from allowlist");
        }
        console.log("");
        console.log("Next Steps:");
        console.log("- Verify addresses using: cast call $GATE_ADDRESS 'allowed(address)' <address>");
        console.log("- Test vault operations with allowlisted users");
    }
}
