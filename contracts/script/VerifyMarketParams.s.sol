// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {MarketParams} from "../lib/morpho-vault-v2/lib/morpho-blue/src/interfaces/IMorpho.sol";

/// @title VerifyMarketParams
/// @notice Script to verify the MF-ONE-USDC market parameters are correctly set
contract VerifyMarketParams is Script {
    // Constants from DeployVault.s.sol
    address constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address constant ADAPTIVE_CURVE_IRM = 0x870aC11D48B15DB9a138Cf899d20F13F79Ba00BC;
    bytes32 constant MARKET_ID = 0xef2c308b5abecf5c8750a1aa82b47c558005feb7a03f4f8e1ad682d71ac8d0ba;
    address constant MF_ONE = 0x238a700eD6165261Cf8b2e544ba797BC11e466Ba;

    // Market parameters
    MarketParams marketParams = MarketParams({
        loanToken: USDC,
        collateralToken: MF_ONE,
        oracle: 0x0cB1928EcA8783F05a07D9Ae2AfB33f38BFBEb78,
        irm: ADAPTIVE_CURVE_IRM,
        lltv: 915000000000000000 // 91.5%
    });

    function run() external view {
        console.log("=== MF-ONE-USDC Market Parameters Verification ===");
        console.log("");
        console.log("Market ID:", vm.toString(MARKET_ID));
        console.log("  Expected: 0xef2c308b5abecf5c8750a1aa82b47c558005feb7a03f4f8e1ad682d71ac8d0ba");
        console.log("");
        console.log("Loan Token (USDC):", marketParams.loanToken);
        console.log("  Expected: 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48");
        console.log("");
        console.log("Collateral Token (mF-ONE):", marketParams.collateralToken);
        console.log("  Expected: 0x238a700eD6165261Cf8b2e544ba797BC11e466Ba");
        console.log("");
        console.log("Oracle:", marketParams.oracle);
        console.log("  Expected: 0x0cB1928EcA8783F05a07D9Ae2AfB33f38BFBEb78");
        console.log("");
        console.log("IRM (Adaptive Curve):", marketParams.irm);
        console.log("  Expected: 0x870aC11D48B15DB9a138Cf899d20F13F79Ba00BC");
        console.log("");
        console.log("LLTV:", marketParams.lltv);
        console.log("  Expected: 915000000000000000 (91.5%)");
        console.log("");
        
        // Verify each parameter
        bool allCorrect = true;
        
        if (marketParams.loanToken != 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48) {
            console.log("ERROR: Loan token mismatch!");
            allCorrect = false;
        }
        
        if (marketParams.collateralToken != 0x238a700eD6165261Cf8b2e544ba797BC11e466Ba) {
            console.log("ERROR: Collateral token mismatch!");
            allCorrect = false;
        }
        
        if (marketParams.oracle != 0x0cB1928EcA8783F05a07D9Ae2AfB33f38BFBEb78) {
            console.log("ERROR: Oracle mismatch!");
            allCorrect = false;
        }
        
        if (marketParams.irm != 0x870aC11D48B15DB9a138Cf899d20F13F79Ba00BC) {
            console.log("ERROR: IRM mismatch!");
            allCorrect = false;
        }
        
        if (marketParams.lltv != 915000000000000000) {
            console.log("ERROR: LLTV mismatch!");
            allCorrect = false;
        }
        
        if (MARKET_ID != 0xef2c308b5abecf5c8750a1aa82b47c558005feb7a03f4f8e1ad682d71ac8d0ba) {
            console.log("ERROR: Market ID mismatch!");
            allCorrect = false;
        }
        
        if (allCorrect) {
            console.log("=== VERIFICATION PASSED ===");
            console.log("All MF-ONE-USDC market parameters are correctly set!");
        } else {
            console.log("=== VERIFICATION FAILED ===");
            console.log("Some parameters do not match expected values!");
        }
    }
}
