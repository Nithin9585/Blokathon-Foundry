// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {BaseScript} from "./Base.s.sol";
import {Diamond} from "src/Diamond.sol";
import {IDiamondCut} from "src/facets/baseFacets/cut/IDiamondCut.sol";
import {DiamondRWAYieldFacet} from "src/facets/utilityFacets/diamondRWA/DiamondRWAYieldFacet.sol";
import {IDiamondRWA} from "src/facets/utilityFacets/diamondRWA/IDiamondRWA.sol";
import {MockRWAToken, MockOndoOUSG, MockOndoUSDY, MockFigureTreasury} from "src/mocks/MockRWAToken.sol";
import {Constants} from "src/libraries/Constants.sol";
import {console} from "forge-std/console.sol";

/**
 * @title DeployRWAFacet
 * @notice Deployment script for Diamond RWA Yield Engine
 * @dev Deploys RWA facet and optionally mock RWA tokens for testing
 * 
 * Usage:
 * # Deploy to local Anvil
 * forge script script/DeployRWAFacet.s.sol --rpc-url $RPC_URL_ANVIL --private-key $PRIVATE_KEY_ANVIL --broadcast
 * 
 * # Deploy to Arbitrum
 * forge script script/DeployRWAFacet.s.sol --rpc-url $RPC_URL_ARBITRUM --private-key $PRIVATE_KEY --broadcast --verify
 */
contract DeployRWAFacet is BaseScript {
    
    // Addresses to be filled in (either from previous deployment or fresh)
    address public diamond;
    address public usdcToken;
    bool public useMocks = true; // Set to false for mainnet with real RWAs

    function run() public broadcaster {
        setUp();

        console.log("===========================================");
        console.log("Diamond RWA Yield Engine Deployment");
        console.log("===========================================");
        console.log("Deployer:", deployer);
        console.log("Chain ID:", block.chainid);
        console.log("Chain:", Constants.getChainName(block.chainid));
        console.log("");

        // Step 1: Get USDC address for this chain
        usdcToken = _getUSDCAddress();
        console.log("USDC Token:", usdcToken);

        // Step 2: Deploy mock RWAs if needed (for testing/demo)
        address initialRWA;
        string memory rwaName;
        
        if (useMocks) {
            console.log("\nDeploying Mock RWA Tokens...");
            initialRWA = _deployMockRWAs();
            rwaName = "Mock Ondo OUSG";
        } else {
            // For mainnet: use real RWA addresses
            console.log("\nUsing Real RWA Tokens...");
            initialRWA = _getRealRWAAddress();
            rwaName = "Ondo OUSG";
        }

        // Step 3: Deploy DiamondRWAYieldFacet
        console.log("\nDeploying DiamondRWAYieldFacet...");
        DiamondRWAYieldFacet rwaFacet = new DiamondRWAYieldFacet();
        console.log("DiamondRWAYieldFacet:", address(rwaFacet));

        // Step 4: Get Diamond address (either from env or prompt)
        diamond = _getDiamondAddress();
        console.log("\nDiamond Address:", diamond);

        // Step 5: Prepare facet cut
        console.log("\nPreparing FacetCut...");
        IDiamondCut.FacetCut[] memory cuts = new IDiamondCut.FacetCut[](1);
        cuts[0] = _getRWAFacetCut(address(rwaFacet));

        // Step 6: Execute diamondCut to add RWA facet
        console.log("\nExecuting DiamondCut...");
        IDiamondCut(diamond).diamondCut(cuts, address(0), "");
        console.log("[SUCCESS] RWA Facet added to Diamond");

        // Step 7: Initialize the vault
        console.log("\nInitializing RWA Vault...");
        IDiamondRWA(diamond).initialize(usdcToken, initialRWA, rwaName);
        console.log("[SUCCESS] Vault initialized");

        // Step 8: Display summary
        _displaySummary();
    }

    /**
     * @notice Get USDC address for current chain
     */
    function _getUSDCAddress() internal view returns (address) {
        if (block.chainid == 31337) {
            // Anvil local chain - need to deploy mock USDC or use a specific address
            // For now, return a placeholder that needs to be deployed separately
            console.log("WARNING: On local Anvil - deploy mock USDC first");
            return address(0); // Will need to be set manually
        }
        
        return Constants.getUSDCAddress(block.chainid);
    }

    /**
     * @notice Deploy mock RWA tokens for testing
     */
    function _deployMockRWAs() internal returns (address) {
        MockOndoOUSG mockOUSG = new MockOndoOUSG(usdcToken);
        MockOndoUSDY mockUSDY = new MockOndoUSDY(usdcToken);
        MockFigureTreasury mockFigure = new MockFigureTreasury(usdcToken);

        console.log("  Mock Ondo OUSG:", address(mockOUSG), "(5.1% APY)");
        console.log("  Mock Ondo USDY:", address(mockUSDY), "(4.8% APY)");
        console.log("  Mock Figure Treasury:", address(mockFigure), "(8.7% APY)");

        return address(mockOUSG);
    }

    /**
     * @notice Get real RWA address (needs to be verified for each chain)
     */
    function _getRealRWAAddress() internal view returns (address) {
        // For Arbitrum mainnet - verify these addresses exist
        if (block.chainid == 42161) {
            console.log("WARNING: Real RWA addresses on Arbitrum need verification");
            return address(0); // Needs real address
        }
        
        // For Ethereum mainnet
        if (block.chainid == 1) {
            return Constants.ONDO_OUSG_ETHEREUM;
        }

        revert("Real RWAs not available on this chain - use mocks");
    }

    /**
     * @notice Get Diamond address (from env or hardcoded)
     */
    function _getDiamondAddress() internal view returns (address) {
        // Try to read from environment variable
        try vm.envAddress("DIAMOND_ADDRESS") returns (address addr) {
            return addr;
        } catch {
            console.log("WARNING: DIAMOND_ADDRESS not set in .env");
            console.log("Please set DIAMOND_ADDRESS or modify this script with your Diamond address");
            revert("DIAMOND_ADDRESS not configured");
        }
    }

    /**
     * @notice Prepare FacetCut for RWA facet
     */
    function _getRWAFacetCut(address facetAddress) internal pure returns (IDiamondCut.FacetCut memory) {
        // Get all function selectors from IDiamondRWA
        bytes4[] memory selectors = new bytes4[](21);
        
        // Core functions
        selectors[0] = IDiamondRWA.deposit.selector;
        selectors[1] = IDiamondRWA.withdraw.selector;
        
        // View functions
        selectors[2] = IDiamondRWA.getBestAPY.selector;
        selectors[3] = IDiamondRWA.getCurrentAPY.selector;
        selectors[4] = IDiamondRWA.getTotalAssets.selector;
        selectors[5] = IDiamondRWA.getTotalShares.selector;
        selectors[6] = IDiamondRWA.getUserShares.selector;
        selectors[7] = IDiamondRWA.previewDeposit.selector;
        selectors[8] = IDiamondRWA.previewWithdraw.selector;
        selectors[9] = IDiamondRWA.getCurrentRWA.selector;
        selectors[10] = IDiamondRWA.getWhitelistedRWAs.selector;
        selectors[11] = IDiamondRWA.isRWAWhitelisted.selector;
        selectors[12] = IDiamondRWA.getRWAInfo.selector;
        selectors[13] = IDiamondRWA.isPaused.selector;
        
        // Admin functions
        selectors[14] = IDiamondRWA.addRWAToWhitelist.selector;
        selectors[15] = IDiamondRWA.removeRWAFromWhitelist.selector;
        selectors[16] = IDiamondRWA.upgradeToRWA.selector;
        selectors[17] = IDiamondRWA.setPause.selector;
        selectors[18] = IDiamondRWA.setMinDeposit.selector;
        selectors[19] = IDiamondRWA.initialize.selector;

        return IDiamondCut.FacetCut({
            facetAddress: facetAddress,
            action: IDiamondCut.FacetCutAction.Add,
            functionSelectors: selectors
        });
    }

    /**
     * @notice Display deployment summary
     */
    function _displaySummary() internal view {
        console.log("\n===========================================");
        console.log("Deployment Complete!");
        console.log("===========================================");
        console.log("Diamond:", diamond);
        console.log("USDC:", usdcToken);
        console.log("Chain:", Constants.getChainName(block.chainid));
        console.log("");
        console.log("Next Steps:");
        console.log("1. Verify contracts on block explorer");
        console.log("2. Test deposit: cast send", diamond, "\"deposit(uint256)\" 100000000 --rpc-url ...");
        console.log("3. Check shares: cast call", diamond, "\"getUserShares(address)\" YOUR_ADDRESS --rpc-url ...");
        console.log("4. Add more RWAs: call addRWAToWhitelist()");
        console.log("5. Upgrade strategy: call upgradeToRWA() - THE MAGIC SWITCH!");
        console.log("===========================================");
    }
}
