// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {Script, console} from "forge-std/Script.sol";
import {IDiamondRWA} from "src/facets/utilityFacets/diamondRWA/IDiamondRWA.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title UpgradeToNewRWA
 * @notice Demo script showing THE MAGIC SWITCH - upgrade vault to higher APY RWA in ONE click
 * @dev This is the 30-second demo for the hackathon:
 *      1. Show current RWA and APY (e.g., Ondo OUSG 5.1%)
 *      2. Show available better RWAs (e.g., Figure Treasury 8.7%)
 *      3. Execute upgradeToRWA() - THE MAGIC SWITCH
 *      4. Show new RWA and APY
 *      
 * Usage:
 *   forge script script/UpgradeToNewRWA.s.sol --broadcast --rpc-url $ARBITRUM_RPC
 */
contract UpgradeToNewRWA is Script {
    // ============================================
    // CONFIGURATION - UPDATE THESE
    // ============================================
    
    /// @notice Diamond proxy address (from deployment)
    address public DIAMOND_ADDRESS = vm.envAddress("DIAMOND_ADDRESS");
    
    /// @notice New RWA to upgrade to
    address public NEW_RWA_ADDRESS = vm.envAddress("NEW_RWA_ADDRESS");
    
    /// @notice New RWA name (for display)
    string public NEW_RWA_NAME = vm.envString("NEW_RWA_NAME");

    // ============================================
    // MAIN SCRIPT
    // ============================================

    function run() external {
        console.log("\n=================================================");
        console.log("  DIAMOND RWA YIELD ENGINE - THE MAGIC SWITCH");
        console.log("=================================================\n");

        IDiamondRWA vault = IDiamondRWA(DIAMOND_ADDRESS);

        // Step 1: Show current state
        console.log("[STEP 1] Current Vault State");
        console.log("----------------------------");
        _displayCurrentState(vault);

        // Step 2: Show available RWAs
        console.log("\n[STEP 2] Available RWA Options");
        console.log("----------------------------");
        _displayAvailableRWAs(vault);

        // Step 3: Check if new RWA is whitelisted
        console.log("\n[STEP 3] Checking New RWA");
        console.log("----------------------------");
        bool isWhitelisted = _checkWhitelist(vault, NEW_RWA_ADDRESS);

        // Step 4: Whitelist if needed
        if (!isWhitelisted) {
            console.log("\n[STEP 4] Whitelisting New RWA");
            console.log("----------------------------");
            _whitelistRWA(vault, NEW_RWA_ADDRESS, NEW_RWA_NAME);
        }

        // Step 5: Execute THE MAGIC SWITCH
        console.log("\n[STEP 5] EXECUTING THE MAGIC SWITCH");
        console.log("=====================================");
        _executeUpgrade(vault, NEW_RWA_ADDRESS);

        // Step 6: Show results
        console.log("\n[STEP 6] Upgrade Results");
        console.log("----------------------------");
        _displayCurrentState(vault);

        console.log("\n=================================================");
        console.log("  [SUCCESS] Vault upgraded to higher yield RWA!");
        console.log("=================================================\n");
    }

    // ============================================
    // HELPER FUNCTIONS
    // ============================================

    function _displayCurrentState(IDiamondRWA vault) internal view {
        address currentRWA = vault.getCurrentRWA();
        (string memory name, address tokenAddress, bool isActive, uint256 addedTimestamp) = vault.getRWAInfo(currentRWA);
        uint256 totalAssets = vault.getTotalAssets();
        uint256 totalShares = vault.getTotalShares();
        uint256 apy = vault.getCurrentAPY();

        console.log("Current RWA:     ", name);
        console.log("RWA Address:     ", currentRWA);
        console.log("Current APY:     ", _formatAPY(apy));
        console.log("Total Assets:    ", _formatUSDC(totalAssets));
        console.log("Total Shares:    ", _formatUSDC(totalShares));
    }

    function _displayAvailableRWAs(IDiamondRWA vault) internal view {
        address[] memory rwas = vault.getWhitelistedRWAs();
        console.log("Number of whitelisted RWAs:", rwas.length);
        
        for (uint256 i = 0; i < rwas.length; i++) {
            (string memory name, address rwa,,) = vault.getRWAInfo(rwas[i]);
            console.log("");
            console.log("  RWA", i + 1);
            console.log("  Name:", name);
            console.log("  Address:", rwa);
        }

        // Show best APY
        (uint256 bestAPY, address bestRWA) = vault.getBestAPY();
        console.log("\nBest Available APY:", _formatAPY(bestAPY));
        console.log("Best RWA Address:  ", bestRWA);
    }

    function _checkWhitelist(IDiamondRWA vault, address rwa) internal view returns (bool) {
        console.log("Checking if", rwa, "is whitelisted...");
        
        address[] memory rwas = vault.getWhitelistedRWAs();
        for (uint256 i = 0; i < rwas.length; i++) {
            if (rwas[i] == rwa) {
                console.log("[SUCCESS] RWA already whitelisted");
                return true;
            }
        }
        
        console.log("[INFO] RWA not whitelisted yet");
        return false;
    }

    function _whitelistRWA(IDiamondRWA vault, address rwa, string memory name) internal {
        console.log("Whitelisting:", name);
        console.log("Address:", rwa);

        vm.startBroadcast();
        vault.addRWAToWhitelist(rwa, name);
        vm.stopBroadcast();

        console.log("[SUCCESS] RWA whitelisted");
    }

    function _executeUpgrade(IDiamondRWA vault, address newRWA) internal {
        address oldRWA = vault.getCurrentRWA();
        (string memory oldName,,,) = vault.getRWAInfo(oldRWA);
        (string memory newName,,,) = vault.getRWAInfo(newRWA);
        uint256 oldAPY = vault.getCurrentAPY();

        console.log("Upgrading from:", oldName);
        console.log("          APY:", _formatAPY(oldAPY));
        console.log("Upgrading to:", newName);
        console.log("");
        console.log("Executing upgradeToRWA()...");

        uint256 gasStart = gasleft();
        vm.startBroadcast();
        vault.upgradeToRWA(newRWA);
        vm.stopBroadcast();
        uint256 gasUsed = gasStart - gasleft();

        uint256 newAPY = vault.getCurrentAPY();
        console.log("");
        console.log("[SUCCESS] Upgrade complete!");
        console.log("Gas used:", gasUsed);
        console.log("APY increased by:", _formatAPY(newAPY - oldAPY));
    }

    // ============================================
    // FORMATTING HELPERS
    // ============================================

    function _formatUSDC(uint256 amount) internal pure returns (string memory) {
        // USDC has 6 decimals
        uint256 whole = amount / 1e6;
        uint256 decimal = (amount % 1e6) / 1e4; // 2 decimal places
        
        if (decimal == 0) {
            return string(abi.encodePacked(vm.toString(whole), " USDC"));
        } else if (decimal < 10) {
            return string(abi.encodePacked(vm.toString(whole), ".0", vm.toString(decimal), " USDC"));
        } else {
            return string(abi.encodePacked(vm.toString(whole), ".", vm.toString(decimal), " USDC"));
        }
    }

    function _formatAPY(uint256 basisPoints) internal pure returns (string memory) {
        // APY is in basis points (e.g., 510 = 5.1%)
        uint256 whole = basisPoints / 100;
        uint256 decimal = basisPoints % 100;
        
        if (decimal == 0) {
            return string(abi.encodePacked(vm.toString(whole), ".0%"));
        } else if (decimal < 10) {
            return string(abi.encodePacked(vm.toString(whole), ".0", vm.toString(decimal), "%"));
        } else {
            return string(abi.encodePacked(vm.toString(whole), ".", vm.toString(decimal), "%"));
        }
    }
}
