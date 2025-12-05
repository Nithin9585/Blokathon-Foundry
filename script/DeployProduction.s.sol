// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {Script, console} from "forge-std/Script.sol";
import {Diamond} from "../src/Diamond.sol";
import {DiamondRWAYieldFacetV2} from "../src/facets/utilityFacets/diamondRWA/DiamondRWAYieldFacetV2.sol";
import {IDiamondCut} from "../src/facets/baseFacets/cut/IDiamondCut.sol";
import {Constants} from "../src/libraries/Constants.sol";

/**
 * @title DeployProduction
 * @notice Production deployment script with V2 facet (24hr timelock governance)
 * @dev Deploy to Ethereum mainnet for real RWA access
 * 
 * Usage:
 *   forge script script/DeployProduction.s.sol \
 *     --rpc-url $ETH_RPC_URL \
 *     --broadcast \
 *     --verify
 * 
 * After deployment:
 *   1. Transfer ownership to multisig (Gnosis Safe)
 *   2. Whitelist RWAs (Ondo OUSG, Backed IB01, etc)
 *   3. Set up monitoring (Tenderly, Defender)
 *   4. Launch bug bounty
 */
contract DeployProduction is Script {
    Diamond public diamond;
    DiamondRWAYieldFacetV2 public facetV2;
    
    // Mainnet addresses
    address constant USDC_MAINNET = Constants.USDC_ETHEREUM;
    address constant ONDO_OUSG = Constants.ONDO_OUSG_ETHEREUM;
    address constant ONDO_USDY = Constants.ONDO_USDY_ETHEREUM;
    address constant BACKED_IB01 = Constants.BACKED_IB01_ETHEREUM;
    address constant MATRIXDOCK_STBT = Constants.MATRIXDOCK_STBT_ETHEREUM;
    
    // Multisig address (SET THIS BEFORE DEPLOYMENT!)
    address public MULTISIG_OWNER = address(0); // TODO: Set Gnosis Safe address
    
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        
        console.log("=== Diamond RWA Production Deployment ===");
        console.log("Deployer:", deployer);
        console.log("Chain ID:", block.chainid);
        console.log("Block:", block.number);
        
        // Validate mainnet
        require(
            block.chainid == 1 || block.chainid == 11155111, // Ethereum or Sepolia
            "Deploy to mainnet or testnet only"
        );
        
        vm.startBroadcast(deployerPrivateKey);
        
        // Step 1: Deploy Diamond
        console.log("\n[1/5] Deploying Diamond...");
        IDiamondCut.FacetCut[] memory emptyFacetCuts = new IDiamondCut.FacetCut[](0);
        diamond = new Diamond(deployer, emptyFacetCuts);
        console.log("Diamond deployed:", address(diamond));
        
        // Step 2: Deploy V2 Facet (with timelock governance)
        console.log("\n[2/5] Deploying RWAYieldFacetV2...");
        facetV2 = new DiamondRWAYieldFacetV2();
        console.log("FacetV2 deployed:", address(facetV2));
        
        // Step 3: Add facet to Diamond
        console.log("\n[3/5] Adding V2 facet to Diamond...");
        
        // Get all function selectors from V2 facet
        bytes4[] memory selectors = new bytes4[](14);
        selectors[0] = DiamondRWAYieldFacetV2.initialize.selector;
        selectors[1] = DiamondRWAYieldFacetV2.deposit.selector;
        selectors[2] = DiamondRWAYieldFacetV2.withdraw.selector;
        selectors[3] = DiamondRWAYieldFacetV2.scheduleUpgrade.selector;
        selectors[4] = DiamondRWAYieldFacetV2.executeScheduledUpgrade.selector;
        selectors[5] = DiamondRWAYieldFacetV2.cancelScheduledUpgrade.selector;
        selectors[7] = DiamondRWAYieldFacetV2.requestWithdrawal.selector;
        selectors[8] = DiamondRWAYieldFacetV2.emergencyPause.selector;
        selectors[9] = DiamondRWAYieldFacetV2.emergencyWithdrawAll.selector;
        selectors[10] = DiamondRWAYieldFacetV2.getTotalAssets.selector;
        selectors[11] = DiamondRWAYieldFacetV2.previewDeposit.selector;
        selectors[12] = DiamondRWAYieldFacetV2.previewWithdraw.selector;
        selectors[13] = DiamondRWAYieldFacetV2.getCurrentAPY.selector;
        selectors[13] = DiamondRWAYieldFacetV2.getPendingUpgrade.selector;
        
        IDiamondCut.FacetCut[] memory cuts = new IDiamondCut.FacetCut[](1);
        cuts[0] = IDiamondCut.FacetCut({
            facetAddress: address(facetV2),
            action: IDiamondCut.FacetCutAction.Add,
            functionSelectors: selectors
        });
        
        IDiamondCut(address(diamond)).diamondCut(cuts, address(0), "");
        console.log("V2 facet added successfully");
        
        // Step 4: Initialize with Ondo OUSG (most liquid)
        console.log("\n[4/5] Initializing vault...");
        DiamondRWAYieldFacetV2(address(diamond)).initialize(
            USDC_MAINNET,
            ONDO_OUSG,
            "Ondo OUSG - US Treasuries (5.1% APY)"
        );
        console.log("Vault initialized with Ondo OUSG");
        
        // Step 5: Transfer ownership to multisig (if set)
        console.log("\\n[5/5] Ownership transfer...");
        if (MULTISIG_OWNER != address(0)) {
            // NOTE: Ownership transfer requires OwnershipFacet to be added first
            // For production, add OwnershipFacet and then transfer ownership
            console.log("WARNING: Ownership transfer requires OwnershipFacet");
            console.log("Manual step required: Add OwnershipFacet, then transfer to:", MULTISIG_OWNER);
            // diamond.transferOwnership(MULTISIG_OWNER);
        } else {
            console.log("WARNING: MULTISIG_OWNER not set!");
            console.log("Ownership remains with deployer:", deployer);
            console.log("REMEMBER TO TRANSFER TO MULTISIG AFTER SETUP!");
        }
        
        vm.stopBroadcast();
        
        // Print deployment summary
        console.log("\n=== Deployment Summary ===");
        console.log("Diamond:", address(diamond));
        console.log("RWAYieldFacetV2:", address(facetV2));
        console.log("Initial RWA:", ONDO_OUSG);
        console.log("Owner:", MULTISIG_OWNER != address(0) ? MULTISIG_OWNER : deployer);
        
        console.log("\n=== Next Steps ===");
        console.log("1. Verify contracts on Etherscan");
        console.log("2. Set up Gnosis Safe multisig");
        console.log("3. Transfer ownership if not done");
        console.log("4. Whitelist additional RWAs:");
        console.log("   - Ondo USDY:", ONDO_USDY);
        console.log("   - Backed IB01:", BACKED_IB01);
        console.log("   - MatrixDock STBT:", MATRIXDOCK_STBT);
        console.log("5. Set up monitoring (Tenderly/Defender)");
        console.log("6. Launch bug bounty");
        console.log("7. Integrate KYC provider");
        console.log("8. Deploy frontend");
        
        console.log("\n=== Production Features ===");
        console.log("- 24-hour timelock on upgrades");
        console.log("- 1% max slippage protection");
        console.log("- Withdrawal queue for locked RWAs");
        console.log("- Emergency pause with reason");
        console.log("- Multisig governance ready");
        
        // Save deployment addresses
        string memory output = string.concat(
            '{\n',
            '  "diamond": "', vm.toString(address(diamond)), '",\n',
            '  "facetV2": "', vm.toString(address(facetV2)), '",\n',
            '  "usdc": "', vm.toString(USDC_MAINNET), '",\n',
            '  "initialRWA": "', vm.toString(ONDO_OUSG), '",\n',
            '  "owner": "', vm.toString(MULTISIG_OWNER != address(0) ? MULTISIG_OWNER : deployer), '",\n',
            '  "chainId": ', vm.toString(block.chainid), ',\n',
            '  "deployedAt": ', vm.toString(block.timestamp), '\n',
            '}'
        );
        
        vm.writeFile("./deployments/production.json", output);
        console.log("\nDeployment saved to: deployments/production.json");
    }
}
