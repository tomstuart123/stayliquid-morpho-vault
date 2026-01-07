// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {AllowlistGate} from "../src/gates/AllowlistGate.sol";
import {VaultV2} from "../lib/morpho-vault-v2/src/VaultV2.sol";
import {VaultV2Factory} from "../lib/morpho-vault-v2/src/VaultV2Factory.sol";
import {IVaultV2} from "../lib/morpho-vault-v2/src/interfaces/IVaultV2.sol";
import {MorphoMarketV1AdapterV2} from "../lib/morpho-vault-v2/src/adapters/MorphoMarketV1AdapterV2.sol";
import {MorphoMarketV1AdapterV2Factory} from
    "../lib/morpho-vault-v2/src/adapters/MorphoMarketV1AdapterV2Factory.sol";
import {MarketParams} from "../lib/morpho-vault-v2/lib/morpho-blue/src/interfaces/IMorpho.sol";

/// @title DeployVault
/// @notice Production deployment script for Morpho Vault V2 + AllowlistGate
/// @dev Deploys on mainnet fork with real market allocation via Morpho Blue adapter
contract DeployVault is Script {
    // Mainnet addresses
    address constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address constant MORPHO_BLUE = 0xBBBBBbbBBb9cC5e90e3b3Af64bdAF62C37EEFFCb;
    address constant ADAPTIVE_CURVE_IRM = 0x870aC11D48B15DB9a138Cf899d20F13F79Ba00BC;

    // MF-ONE-USDC Market (verified from Morpho app)
    // Market URL: https://app.morpho.org/ethereum/market/0xef2c308b5abecf5c8750a1aa82b47c558005feb7a03f4f8e1ad682d71ac8d0ba/mf-one-usdc
    bytes32 constant MARKET_ID = 0xef2c308b5abecf5c8750a1aa82b47c558005feb7a03f4f8e1ad682d71ac8d0ba;

    // MF-ONE collateral token
    address constant MF_ONE = 0x238a700eD6165261Cf8b2e544ba797BC11e466Ba;

    // Production-verified market parameters for MF-ONE-USDC
    MarketParams marketParams = MarketParams({
        loanToken: USDC,
        collateralToken: MF_ONE,
        oracle: 0x0cB1928EcA8783F05a07D9Ae2AfB33f38BFBEb78,
        irm: ADAPTIVE_CURVE_IRM,
        lltv: 915000000000000000 // 91.5%
    });

    function run()
        external
        returns (VaultV2 vault, AllowlistGate gate, MorphoMarketV1AdapterV2 adapter, address adapterFactory)
    {
        // Read configuration from environment
        address admin = vm.envAddress("ADMIN_ADDRESS");
        address curator = vm.envOr("CURATOR_ADDRESS", admin); // Default to admin if not set

        require(admin != address(0), "ADMIN_ADDRESS not set");

        console.log("=== Morpho Vault V2 Deployment ===");
        console.log("Network: Mainnet Fork");
        console.log("Admin:", admin);
        console.log("Curator:", curator);
        console.log("Asset: USDC", USDC);
        console.log("");

        vm.startBroadcast();

        // 1. Deploy VaultV2Factory
        console.log("1. Deploying VaultV2Factory...");
        VaultV2Factory factory = new VaultV2Factory();
        console.log("   Factory deployed at:", address(factory));

        // 2. Deploy AllowlistGate
        console.log("\n2. Deploying AllowlistGate...");
        gate = new AllowlistGate(admin);
        console.log("   Gate deployed at:", address(gate));
        console.log("   Gate admin:", gate.admin());

        // 3. Deploy Vault via Factory
        console.log("\n3. Deploying Vault via Factory...");
        bytes32 salt = keccak256("stayliquid-v0.1");
        vault = VaultV2(factory.createVaultV2(admin, USDC, salt));
        console.log("   Vault deployed at:", address(vault));

        // 4. Configure Vault
        console.log("\n4. Configuring Vault...");
        vault.setName("StayLiquid Allowlisted Vault");
        vault.setSymbol("slUSDC");
        vault.setCurator(curator);
        console.log("   Name: StayLiquid Allowlisted Vault");
        console.log("   Symbol: slUSDC");
        console.log("   Curator set to:", curator);

        vm.stopBroadcast();

        // 5. Set Gates (requires timelock)
        // NOTE: Timelocks default to 0 on initial deployment, so submit() + set() can be called immediately
        // In production with non-zero timelocks, there must be a waiting period between submit() and set()
        // These operations are performed by the admin (who is also initially the curator)
        console.log("\n5. Setting Gates (as admin/curator)...");
        vm.startBroadcast();

        // Submit and accept gate changes via timelock
        vault.submit(abi.encodeCall(IVaultV2.setSendAssetsGate, (address(gate))));
        vault.setSendAssetsGate(address(gate));
        console.log("   sendAssetsGate set");

        vault.submit(abi.encodeCall(IVaultV2.setReceiveSharesGate, (address(gate))));
        vault.setReceiveSharesGate(address(gate));
        console.log("   receiveSharesGate set");

        vault.submit(abi.encodeCall(IVaultV2.setSendSharesGate, (address(gate))));
        vault.setSendSharesGate(address(gate));
        console.log("   sendSharesGate set");

        vault.submit(abi.encodeCall(IVaultV2.setReceiveAssetsGate, (address(gate))));
        vault.setReceiveAssetsGate(address(gate));
        console.log("   receiveAssetsGate set");

        vm.stopBroadcast();

        // 6. Deploy Morpho Adapter (for real market allocation)
        // NOTE: Timelocks default to 0 on initial deployment
        console.log("\n6. Deploying Morpho Market Adapter...");
        vm.startBroadcast();

        // Deploy adapter factory
        MorphoMarketV1AdapterV2Factory morphoAdapterFactory =
            new MorphoMarketV1AdapterV2Factory(MORPHO_BLUE, ADAPTIVE_CURVE_IRM);
        adapterFactory = address(morphoAdapterFactory);
        console.log("   Adapter Factory deployed at:", adapterFactory);

        // Create adapter for our vault
        adapter = MorphoMarketV1AdapterV2(morphoAdapterFactory.createMorphoMarketV1AdapterV2(address(vault)));
        console.log("   Adapter deployed at:", address(adapter));

        // Add adapter to vault (submit + execute pattern, works with zero timelock)
        vault.submit(abi.encodeCall(IVaultV2.addAdapter, (address(adapter))));
        vault.addAdapter(address(adapter));
        console.log("   Adapter added to vault");

        // Set vault as allocator (curator can allocate)
        vault.setIsAllocator(curator, true);
        console.log("   Curator set as allocator");

        vm.stopBroadcast();

        // 7. Configure Market Caps (as curator)
        // NOTE: Timelocks default to 0 on initial deployment
        // The caps control how much can be allocated to specific markets
        console.log("\n7. Configuring Market Caps...");
        vm.startBroadcast();

        // Encode market params for allocation cap configuration
        // This creates a unique identifier for this specific market configuration
        bytes memory marketIdData = abi.encode(marketParams);

        // Set allocation caps for the market
        // absoluteCap: 1M USDC maximum allocation to this market
        uint256 absoluteCap = 1_000_000e6; // 1M USDC
        vault.submit(abi.encodeCall(IVaultV2.increaseAbsoluteCap, (marketIdData, absoluteCap)));
        vault.increaseAbsoluteCap(marketIdData, absoluteCap);
        console.log("   Absolute cap set to:", absoluteCap / 1e6, "USDC");

        // relativeCap: 90% of vault assets can go to this market (in WAD: 18 decimals)
        uint256 relativeCap = 900000000000000000; // 90% in WAD
        vault.submit(abi.encodeCall(IVaultV2.increaseRelativeCap, (marketIdData, relativeCap)));
        vault.increaseRelativeCap(marketIdData, relativeCap);
        console.log("   Relative cap set to: 90%");

        vm.stopBroadcast();

        // 8. Output Summary
        console.log("\n=== Deployment Complete ===");
        console.log("Vault Address:", address(vault));
        console.log("Gate Address:", address(gate));
        console.log("Factory Address:", address(factory));
        console.log("Adapter Address:", address(adapter));
        console.log("Adapter Factory Address:", adapterFactory);
        console.log("");
        console.log("Market Configuration:");
        console.log("  Morpho Blue:", MORPHO_BLUE);
        console.log("  Market ID (MF-ONE-USDC):", vm.toString(MARKET_ID));
        console.log("  Collateral Token (mF-ONE):", MF_ONE);
        console.log("  Oracle:", marketParams.oracle);
        console.log("  LLTV: 91.5%");
        console.log("  Absolute Cap:", absoluteCap / 1e6, "USDC");
        console.log("  Relative Cap: 90%");
        console.log("");
        console.log("Next Steps:");
        console.log("1. Save these addresses for frontend integration");
        console.log("2. Add initial users to allowlist via gate.setAllowed(user, true)");
        console.log("3. Allocate funds to Morpho market via vault.allocate(adapter, marketData, amount)");
        console.log("4. Test deposit flow with allowlisted user");
        console.log("5. Verify vault is earning yield from Morpho market");
        console.log("");
        console.log("IMPORTANT: The example market params should be verified against");
        console.log("the actual market you want to use. Check https://app.morpho.org/ethereum");
        console.log("for accurate market parameters.");

        return (vault, gate, adapter, adapterFactory);
    }
}
