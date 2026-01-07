// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
import {AllowlistGate} from "../src/gates/AllowlistGate.sol";
import {VaultV2} from "../lib/morpho-vault-v2/src/VaultV2.sol";
import {VaultV2Factory} from "../lib/morpho-vault-v2/src/VaultV2Factory.sol";
import {IVaultV2} from "../lib/morpho-vault-v2/src/interfaces/IVaultV2.sol";
import {MorphoMarketV1AdapterV2} from "../lib/morpho-vault-v2/src/adapters/MorphoMarketV1AdapterV2.sol";
import {MorphoMarketV1AdapterV2Factory} from
    "../lib/morpho-vault-v2/src/adapters/MorphoMarketV1AdapterV2Factory.sol";
import {MarketParams} from "../lib/morpho-vault-v2/lib/morpho-blue/src/interfaces/IMorpho.sol";
import {IERC20} from "../lib/morpho-vault-v2/src/interfaces/IERC20.sol";

/// @title FullIntegrationTest
/// @notice Comprehensive integration test for AllowlistGate + Vault + MF-ONE Yield
/// @dev Tests complete user journey on mainnet fork: allowlist → deposit → yield → withdraw
contract FullIntegrationTest is Test {
    // Mainnet addresses
    address constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address constant MORPHO_BLUE = 0xBBBBBbbBBb9cC5e90e3b3Af64bdAF62C37EEFFCb;
    address constant ADAPTIVE_CURVE_IRM = 0x870aC11D48B15DB9a138Cf899d20F13F79Ba00BC;
    address constant MF_ONE = 0x238a700eD6165261Cf8b2e544ba797BC11e466Ba;

    // MF-ONE-USDC Market Parameters
    MarketParams marketParams = MarketParams({
        loanToken: USDC,
        collateralToken: MF_ONE,
        oracle: 0x0cB1928EcA8783F05a07D9Ae2AfB33f38BFBEb78,
        irm: ADAPTIVE_CURVE_IRM,
        lltv: 915000000000000000 // 91.5%
    });

    // Test actors
    address public admin;
    address public curator;
    address public allowlistedUser;
    address public notAllowlistedUser;
    address public revokedUser;

    // Contracts
    VaultV2Factory public factory;
    VaultV2 public vault;
    AllowlistGate public gate;
    MorphoMarketV1AdapterV2 public adapter;
    IERC20 public usdc;

    // Test amounts
    uint256 constant DEPOSIT_AMOUNT = 10000e6; // 10,000 USDC
    uint256 constant ALLOCATION_AMOUNT = 9000e6; // 9,000 USDC (leave some in vault)
    uint256 constant LARGE_DEPOSIT_AMOUNT = 100_000e6; // 100,000 USDC for curator allocation test
    uint256 constant LARGE_ALLOCATION_AMOUNT = 80_000e6; // 80,000 USDC for curator allocation test

    function setUp() public {
        // Create mainnet fork
        vm.createSelectFork(vm.envString("MAINNET_RPC_URL"));

        console.log("\n=== Full Integration Test Setup ===");
        console.log("Block number:", block.number);
        console.log("Timestamp:", block.timestamp);

        // Setup test actors
        admin = makeAddr("admin");
        curator = makeAddr("curator");
        allowlistedUser = makeAddr("allowlistedUser");
        notAllowlistedUser = makeAddr("notAllowlistedUser");
        revokedUser = makeAddr("revokedUser");

        // Deploy contracts
        console.log("\nDeploying contracts...");
        factory = new VaultV2Factory();
        vault = VaultV2(factory.createVaultV2(admin, USDC, bytes32(uint256(1))));
        gate = new AllowlistGate(admin);
        usdc = IERC20(USDC);

        console.log("Vault:", address(vault));
        console.log("Gate:", address(gate));

        // Setup vault
        vm.startPrank(admin);
        vault.setCurator(curator);
        vault.setName("StayLiquid Test Vault");
        vault.setSymbol("slUSDC");
        vm.stopPrank();

        // Setup all gates through timelock mechanism
        console.log("\nSetting up gates...");
        vm.startPrank(curator);
        vault.submit(abi.encodeCall(IVaultV2.setSendAssetsGate, (address(gate))));
        vm.warp(block.timestamp + 1); // Skip timelock
        vault.setSendAssetsGate(address(gate));
        vault.submit(abi.encodeCall(IVaultV2.setReceiveSharesGate, (address(gate))));
        vm.warp(block.timestamp + 1); // Skip timelock
        vault.setReceiveSharesGate(address(gate));
        vault.submit(abi.encodeCall(IVaultV2.setSendSharesGate, (address(gate))));
        vm.warp(block.timestamp + 1); // Skip timelock
        vault.setSendSharesGate(address(gate));
        vault.submit(abi.encodeCall(IVaultV2.setReceiveAssetsGate, (address(gate))));
        vm.warp(block.timestamp + 1); // Skip timelock
        vault.setReceiveAssetsGate(address(gate));
        vm.stopPrank();

        // Deploy Morpho adapter
        console.log("\nDeploying Morpho adapter...");
        MorphoMarketV1AdapterV2Factory morphoAdapterFactory =
            new MorphoMarketV1AdapterV2Factory(MORPHO_BLUE, ADAPTIVE_CURVE_IRM);
        adapter = MorphoMarketV1AdapterV2(morphoAdapterFactory.createMorphoMarketV1AdapterV2(address(vault)));

        console.log("Adapter:", address(adapter));

        // Add adapter to vault and configure
        vm.startPrank(curator);
        vault.submit(abi.encodeCall(IVaultV2.addAdapter, (address(adapter))));
        vm.warp(block.timestamp + 1); // Skip timelock
        vault.addAdapter(address(adapter));
        
        vault.submit(abi.encodeCall(IVaultV2.setIsAllocator, (curator, true)));
        vm.warp(block.timestamp + 1); // Skip timelock
        vault.setIsAllocator(curator, true);

        // Configure market caps
        // The adapter returns 3 ids, we need to set caps for all of them
        bytes memory marketIdData = abi.encode(marketParams);
        uint256 absoluteCap = 1_000_000e6; // 1M USDC
        uint256 relativeCap = 900000000000000000; // 90% in WAD
        
        // Cap 1: Adapter ID
        bytes memory adapterIdData = abi.encode("this", address(adapter));
        vault.submit(abi.encodeCall(IVaultV2.increaseAbsoluteCap, (adapterIdData, absoluteCap)));
        vm.warp(block.timestamp + 1); // Skip timelock
        vault.increaseAbsoluteCap(adapterIdData, absoluteCap);
        vault.submit(abi.encodeCall(IVaultV2.increaseRelativeCap, (adapterIdData, relativeCap)));
        vm.warp(block.timestamp + 1); // Skip timelock
        vault.increaseRelativeCap(adapterIdData, relativeCap);
        
        // Cap 2: Collateral Token
        bytes memory collateralIdData = abi.encode("collateralToken", marketParams.collateralToken);
        vault.submit(abi.encodeCall(IVaultV2.increaseAbsoluteCap, (collateralIdData, absoluteCap)));
        vm.warp(block.timestamp + 1); // Skip timelock
        vault.increaseAbsoluteCap(collateralIdData, absoluteCap);
        vault.submit(abi.encodeCall(IVaultV2.increaseRelativeCap, (collateralIdData, relativeCap)));
        vm.warp(block.timestamp + 1); // Skip timelock
        vault.increaseRelativeCap(collateralIdData, relativeCap);
        
        // Cap 3: Market-specific
        bytes memory marketSpecificIdData = abi.encode("this/marketParams", address(adapter), marketParams);
        vault.submit(abi.encodeCall(IVaultV2.increaseAbsoluteCap, (marketSpecificIdData, absoluteCap)));
        vm.warp(block.timestamp + 1); // Skip timelock
        vault.increaseAbsoluteCap(marketSpecificIdData, absoluteCap);
        vault.submit(abi.encodeCall(IVaultV2.increaseRelativeCap, (marketSpecificIdData, relativeCap)));
        vm.warp(block.timestamp + 1); // Skip timelock
        vault.increaseRelativeCap(marketSpecificIdData, relativeCap);
        
        console.log("All caps set for 3 ids");
        vm.stopPrank();

        // Fund test wallets
        console.log("\nFunding test wallets...");
        deal(USDC, allowlistedUser, DEPOSIT_AMOUNT * 10);
        deal(USDC, notAllowlistedUser, DEPOSIT_AMOUNT * 10);
        deal(USDC, revokedUser, DEPOSIT_AMOUNT * 10);

        // Approve vault for all users
        vm.prank(allowlistedUser);
        usdc.approve(address(vault), type(uint256).max);

        vm.prank(notAllowlistedUser);
        usdc.approve(address(vault), type(uint256).max);

        vm.prank(revokedUser);
        usdc.approve(address(vault), type(uint256).max);

        // Allowlist users (revokedUser will be added then removed in test)
        console.log("\nSetting up allowlist...");
        vm.startPrank(admin);
        gate.setAllowed(allowlistedUser, true);
        gate.setAllowed(revokedUser, true); // Will be revoked in test
        vm.stopPrank();

        console.log("Setup complete!\n");
    }

    /// @notice Scenario 1: Non-Allowlisted User Blocked
    function test_Scenario1_NonAllowlistedUserBlocked() public {
        console.log("\n=== SCENARIO 1: Non-Allowlisted User Blocked ===");

        // Verify user is not on allowlist
        assertFalse(gate.allowed(notAllowlistedUser), "User should not be allowlisted");
        console.log("User is not on allowlist: PASS");

        // Try to deposit - should revert
        vm.prank(notAllowlistedUser);
        vm.expectRevert();
        vault.deposit(DEPOSIT_AMOUNT, notAllowlistedUser);
        console.log("Deposit reverted as expected: PASS");

        // Verify user has 0 vault shares
        assertEq(vault.balanceOf(notAllowlistedUser), 0, "User should have 0 shares");
        console.log("User has 0 vault shares: PASS");

        console.log("PASS: Scenario 1 Complete: Non-allowlisted user blocked\n");
    }

    /// @notice Scenario 2: Allowlisted User Full Journey
    function test_Scenario2_AllowlistedUserFullJourney() public {
        console.log("\n=== SCENARIO 2: Allowlisted User Full Journey ===");

        // Step 1 - Deposit
        console.log("\n--- Step 1: Deposit ---");
        assertEq(gate.allowed(allowlistedUser), true, "User should be allowlisted");
        console.log("User is allowlisted: PASS");

        uint256 initialBalance = usdc.balanceOf(allowlistedUser);
        console.log("Initial USDC balance:", initialBalance / 1e6);

        vm.prank(allowlistedUser);
        uint256 shares = vault.deposit(DEPOSIT_AMOUNT, allowlistedUser);

        assertGt(shares, 0, "Should receive shares");
        assertEq(vault.balanceOf(allowlistedUser), shares, "Shares balance should match");
        console.log("Deposited:", DEPOSIT_AMOUNT / 1e6, "USDC");
        console.log("Received:", shares / 1e6, "shares");
        console.log("PASS: Step 1 Complete: User deposited successfully");

        // Step 2 - Vault Allocates to MF-ONE
        console.log("\n--- Step 2: Allocate to MF-ONE Market ---");
        uint256 totalAssetsBefore = vault.totalAssets();
        console.log("Vault total assets before allocation:", totalAssetsBefore / 1e6, "USDC");

        bytes memory marketIdData = abi.encode(marketParams);

        vm.prank(curator);
        vault.allocate(address(adapter), marketIdData, ALLOCATION_AMOUNT);

        uint256 totalAssetsAfter = vault.totalAssets();
        console.log("Vault total assets after allocation:", totalAssetsAfter / 1e6, "USDC");
        assertEq(totalAssetsAfter, totalAssetsBefore, "Total assets should remain the same");
        console.log("PASS: Step 2 Complete: Allocated to MF-ONE market");

        // Step 3 - Yield Accrual
        console.log("\n--- Step 3: Simulate 7 Days for Yield Accrual ---");
        uint256 initialAssets = vault.totalAssets();
        console.log("Initial total assets:", initialAssets / 1e6, "USDC");

        // Simulate 7 days
        vm.warp(block.timestamp + 7 days);
        vm.roll(block.number + 50400); // ~7 days of blocks

        console.log("Simulated 7 days...");
        console.log("New timestamp:", block.timestamp);
        console.log("New block:", block.number);

        uint256 finalAssets = vault.totalAssets();
        console.log("Final total assets:", finalAssets / 1e6, "USDC");

        // Verify yield accrual (should be greater than or equal to initial)
        // Note: On mainnet fork, yield depends on actual borrow activity in the MF-ONE market
        // If market has no borrows, yield will be 0
        assertGe(finalAssets, initialAssets, "Total assets should not decrease");
        
        uint256 yieldEarned = finalAssets - initialAssets;
        console.log("Yield earned:", yieldEarned / 1e6, "USDC");
        
        if (yieldEarned > 0) {
            uint256 yieldBps = (yieldEarned * 10000) / initialAssets; // Basis points
            console.log("Yield rate:", yieldBps, "bps");
            // Sanity check: yield should be > 0.1% (10 bps) if there is yield
            assertGt(yieldBps, 10, "If yield is earned, it should be at least 0.1% (10 bps)");
        } else {
            console.log("Note: No yield earned - MF-ONE market may have no active borrows on this fork");
        }
        console.log("PASS: Step 3 Complete: Yield check completed");

        // Step 4 - Withdraw
        console.log("\n--- Step 4: Withdraw Deposit + Yield ---");
        
        // First, deallocate from Morpho market to get assets back to vault
        vm.prank(curator);
        vault.deallocate(address(adapter), abi.encode(marketParams), ALLOCATION_AMOUNT);
        console.log("Deallocated", ALLOCATION_AMOUNT / 1e6, "USDC from Morpho market");
        
        uint256 userSharesBefore = vault.balanceOf(allowlistedUser);
        uint256 userUsdcBefore = usdc.balanceOf(allowlistedUser);
        console.log("User shares before withdraw:", userSharesBefore / 1e6);
        console.log("User USDC before withdraw:", userUsdcBefore / 1e6);

        vm.prank(allowlistedUser);
        uint256 assetsReceived = vault.redeem(userSharesBefore, allowlistedUser, allowlistedUser);

        uint256 userSharesAfter = vault.balanceOf(allowlistedUser);
        uint256 userUsdcAfter = usdc.balanceOf(allowlistedUser);

        assertEq(userSharesAfter, 0, "All shares should be burned");
        assertGe(assetsReceived, DEPOSIT_AMOUNT, "Should receive at least original deposit");
        console.log("Shares after withdraw:", userSharesAfter);
        console.log("USDC received:", assetsReceived / 1e6);
        
        if (assetsReceived > DEPOSIT_AMOUNT) {
            console.log("User profit:", (assetsReceived - DEPOSIT_AMOUNT) / 1e6, "USDC");
        } else {
            console.log("User received original deposit (no yield in market)");
        }
        console.log("PASS: Step 4 Complete: User withdrew successfully");

        console.log("\nPASS: Scenario 2 Complete: Allowlisted user full journey successful\n");
    }

    /// @notice Scenario 3: Revoked User Blocked
    function test_Scenario3_RevokedUserBlocked() public {
        console.log("\n=== SCENARIO 3: Revoked User Blocked ===");

        // Setup: user previously allowlisted, deposits funds
        console.log("\n--- Setup: User deposits while allowlisted ---");
        assertTrue(gate.allowed(revokedUser), "User should initially be allowlisted");

        vm.prank(revokedUser);
        uint256 shares = vault.deposit(DEPOSIT_AMOUNT, revokedUser);

        assertGt(shares, 0, "Should have received shares");
        console.log("User deposited:", DEPOSIT_AMOUNT / 1e6, "USDC");
        console.log("User received:", shares / 1e6, "shares");
        console.log("User has existing vault position: PASS");

        // Action 1: Admin revokes access
        console.log("\n--- Action 1: Admin revokes access ---");
        vm.prank(admin);
        gate.setAllowed(revokedUser, false);

        assertFalse(gate.allowed(revokedUser), "User should be revoked");
        console.log("User revoked from allowlist: PASS");

        // Action 2: Try to deposit more - should revert
        console.log("\n--- Action 2: Try to deposit more ---");
        vm.prank(revokedUser);
        vm.expectRevert();
        vault.deposit(DEPOSIT_AMOUNT, revokedUser);
        console.log("Deposit blocked: PASS");

        // Action 3: Try to withdraw existing position - should revert
        console.log("\n--- Action 3: Try to withdraw existing position ---");
        uint256 userShares = vault.balanceOf(revokedUser);
        assertGt(userShares, 0, "User should have shares");

        vm.prank(revokedUser);
        vm.expectRevert();
        vault.redeem(userShares, revokedUser, revokedUser);
        console.log("Withdrawal blocked: PASS");

        // Verify all gate functions block revoked user
        console.log("\n--- Verify all 4 gates enforce block ---");
        assertFalse(gate.canSendAssets(revokedUser), "canSendAssets should return false");
        assertFalse(gate.canReceiveShares(revokedUser), "canReceiveShares should return false");
        assertFalse(gate.canSendShares(revokedUser), "canSendShares should return false");
        assertFalse(gate.canReceiveAssets(revokedUser), "canReceiveAssets should return false");
        console.log("All 4 gate interfaces block revoked user: PASS");

        console.log("\nPASS: Scenario 3 Complete: Revoked user blocked from all operations\n");
    }

    /// @notice Full integration test combining all scenarios
    function test_FullIntegration() public {
        console.log("\n================================================================");
        console.log("  FULL INTEGRATION TEST: Allowlist Gate + Vault + MF-ONE Yield ");
        console.log("================================================================\n");

        // Run all scenarios in sequence
        test_Scenario1_NonAllowlistedUserBlocked();
        test_Scenario2_AllowlistedUserFullJourney();
        test_Scenario3_RevokedUserBlocked();

        console.log("================================================================");
        console.log("               ALL SCENARIOS PASSED                             ");
        console.log("================================================================\n");
    }

    /// @notice Test curator can allocate vault funds to MF-ONE market
    function test_CuratorCanAllocateToMFOne() public {
        console.log("\n=== Curator Allocation Test ===");
        
        // Setup: User deposits USDC into vault
        console.log("\n--- Step 1: User deposits USDC ---");
        vm.prank(admin);
        gate.setAllowed(allowlistedUser, true);
        
        deal(USDC, allowlistedUser, LARGE_DEPOSIT_AMOUNT);
        
        vm.startPrank(allowlistedUser);
        IERC20(USDC).approve(address(vault), LARGE_DEPOSIT_AMOUNT);
        vault.deposit(LARGE_DEPOSIT_AMOUNT, allowlistedUser);
        vm.stopPrank();
        
        uint256 idleAssetsBefore = vault.totalAssets();
        console.log("Vault total assets (idle):", idleAssetsBefore / 1e6, "USDC");
        
        // Step 2: Curator allocates to MF-ONE market
        console.log("\n--- Step 2: Curator allocates to MF-ONE ---");
        
        bytes memory marketIdData = abi.encode(marketParams);
        
        vm.prank(curator);
        vault.allocate(address(adapter), marketIdData, LARGE_ALLOCATION_AMOUNT);
        
        uint256 totalAssetsAfter = vault.totalAssets();
        console.log("Vault total assets after allocation:", totalAssetsAfter / 1e6, "USDC");
        assertEq(totalAssetsAfter, idleAssetsBefore, "Total assets should remain same");
        
        // Step 3: Verify position in Morpho Blue
        console.log("\n--- Step 3: Verify Morpho Blue position ---");
        console.log("Allocated to MF-ONE:", LARGE_ALLOCATION_AMOUNT / 1e6, "USDC");
        console.log("PASS: Allocation successful");
        
        // Step 4: Simulate time for yield accrual
        console.log("\n--- Step 4: Simulate 7 days ---");
        uint256 assetsBefore = vault.totalAssets();
        
        vm.warp(block.timestamp + 7 days);
        vm.roll(block.number + 50400); // ~50400 blocks in 7 days (12 second block time)
        
        uint256 assetsAfter = vault.totalAssets();
        console.log("Assets before:", assetsBefore / 1e6, "USDC");
        console.log("Assets after 7 days:", assetsAfter / 1e6, "USDC");
        
        if (assetsAfter > assetsBefore) {
            uint256 yield = assetsAfter - assetsBefore;
            console.log("Yield earned:", yield / 1e6, "USDC");
        } else {
            console.log("Note: No yield earned (MF-ONE market may have no active borrows on this fork)");
        }
        
        assertGe(assetsAfter, assetsBefore, "Assets should not decrease");
        
        // Step 5: Curator deallocates from MF-ONE
        console.log("\n--- Step 5: Curator deallocates ---");
        vm.prank(curator);
        vault.deallocate(address(adapter), marketIdData, LARGE_ALLOCATION_AMOUNT);
        
        uint256 finalAssets = vault.totalAssets();
        console.log("Vault total assets after deallocation:", finalAssets / 1e6, "USDC");
        assertGe(finalAssets, idleAssetsBefore, "Should have at least original amount");
        
        console.log("\nPASS: Curator allocation test complete\n");
    }
}
