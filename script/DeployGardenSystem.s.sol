// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "forge-std/Script.sol";
import {GardenRegistry} from "../src/GardenRegistry.sol";
import {GardenFactory} from "../src/GardenFactory.sol";
import {
    DiamondCutFacet
} from "../src/facets/baseFacets/cut/DiamondCutFacet.sol";
import {
    OwnershipFacet
} from "../src/facets/baseFacets/ownership/OwnershipFacet.sol";
import {
    DiamondRWAYieldFacetV2
} from "../src/facets/utilityFacets/diamondRWA/DiamondRWAYieldFacetV2.sol";
import {
    GovernanceFacet
} from "../src/facets/utilityFacets/governance/GovernanceFacet.sol";

/**
 * @title DeployGardenSystem
 * @notice Deploys the complete Garden system: Registry + Factory + Template Facets
 * @dev Run with: forge script script/DeployGardenSystem.s.sol --broadcast
 */
contract DeployGardenSystem is Script {
    // Real RWA token addresses (mainnet)
    address constant BACKED_IB01 = 0x5C70b814AD2a84fe803851132E9Ed0A9D1cE6374; // T-Bills (8.7% APY)
    address constant ONDO_USDY = 0x96F6eF951840721AdBF46Ac996b59E0235CB985C; // Ondo USDY (4.8% APY)
    address constant ONDO_OUSG = 0x1B19C19393e2d034D8Ff31ff34c81252FcBbee92; // Ondo OUSG (5.1% APY)
    address constant MATRIXDOCK_STBT =
        0x530824DA86689C9C17CdC2871Ff29B058345b44a; // MatrixDock STBT (6.2% APY)

    function run() external {
        address deployer;

        // Try to get PRIVATE_KEY, fallback to msg.sender for local testing
        try vm.envUint("PRIVATE_KEY") returns (uint256 deployerPrivateKey) {
            deployer = vm.addr(deployerPrivateKey);
            console.log("[+] Deploying Garden System...");
            console.log("[+] Deployer:", deployer);
            vm.startBroadcast(deployerPrivateKey);
        } catch {
            deployer = msg.sender;
            console.log("[+] Deploying Garden System (local)...");
            console.log("[+] Deployer:", deployer);
            vm.startBroadcast();
        }
        // ============================================
        // STEP 1: Deploy Template Facets (reused by all gardens)
        // ============================================

        console.log("\n[+] Deploying template facets...");

        DiamondCutFacet diamondCutFacet = new DiamondCutFacet();
        console.log("[+] DiamondCutFacet:", address(diamondCutFacet));

        OwnershipFacet ownershipFacet = new OwnershipFacet();
        console.log("[+] OwnershipFacet:", address(ownershipFacet));

        DiamondRWAYieldFacetV2 rwaFacet = new DiamondRWAYieldFacetV2();
        console.log("[+] DiamondRWAYieldFacetV2:", address(rwaFacet));

        GovernanceFacet governanceFacet = new GovernanceFacet();
        console.log("[+] GovernanceFacet:", address(governanceFacet));

        // ============================================
        // STEP 2: Deploy Registry
        // ============================================

        console.log("\n[+] Deploying GardenRegistry...");

        // Deploy registry with temporary factory address (will update)
        GardenRegistry registry = new GardenRegistry(deployer);
        console.log("[+] GardenRegistry:", address(registry));

        // ============================================
        // STEP 3: Deploy Factory
        // ============================================

        console.log("\n[+] Deploying GardenFactory...");

        GardenFactory factory = new GardenFactory(
            address(registry),
            address(0x1)
        );
        console.log("[+] GardenFactory:", address(factory));

        // Update registry to recognize factory
        registry.updateFactory(address(factory));
        console.log("[+] Registry updated with factory address");

        // ============================================
        // STEP 4: Configure Factory
        // ============================================

        console.log("\n[+] Configuring factory...");

        // Set template facets
        factory.setFacetTemplates(
            address(diamondCutFacet),
            address(ownershipFacet),
            address(rwaFacet),
            address(governanceFacet)
        );
        console.log("[+] Template facets configured");

        // Configure CONSERVATIVE strategy (T-Bills only - safest)
        factory.configureStrategy(
            GardenRegistry.StrategyType.CONSERVATIVE,
            BACKED_IB01, // Primary: T-Bills (8.7% APY)
            address(0), // No secondary RWA
            10 * 1e6, // 10 USDC minimum
            "Conservative Garden - T-Bills Only"
        );
        console.log(
            "[+] CONSERVATIVE strategy configured (Backed IB01 T-Bills)"
        );

        // Configure BALANCED strategy (T-Bills + Stablecoin)
        factory.configureStrategy(
            GardenRegistry.StrategyType.BALANCED,
            BACKED_IB01, // Primary: T-Bills (8.7% APY)
            ONDO_USDY, // Secondary: Ondo USDY (4.8% APY)
            10 * 1e6, // 10 USDC minimum
            "Balanced Garden - Mixed RWAs"
        );
        console.log("[+] BALANCED strategy configured (IB01 + USDY)");

        // Configure AGGRESSIVE strategy (High-yield RWAs)
        factory.configureStrategy(
            GardenRegistry.StrategyType.AGGRESSIVE,
            ONDO_OUSG, // Primary: Ondo OUSG (5.1% APY)
            MATRIXDOCK_STBT, // Secondary: STBT (6.2% APY)
            10 * 1e6, // 10 USDC minimum
            "Aggressive Garden - High-Yield RWAs"
        );
        console.log("[+] AGGRESSIVE strategy configured (OUSG + STBT)");

        // ============================================
        // STEP 5: Deploy Initial 3 Gardens
        // ============================================

        console.log("\n[+] Deploying initial gardens...");

        address conservativeGarden = factory.deployGarden(
            GardenRegistry.StrategyType.CONSERVATIVE,
            ""
        );
        console.log("[+] Conservative Garden deployed:", conservativeGarden);

        address balancedGarden = factory.deployGarden(
            GardenRegistry.StrategyType.BALANCED,
            ""
        );
        console.log("[+] Balanced Garden deployed:", balancedGarden);

        address aggressiveGarden = factory.deployGarden(
            GardenRegistry.StrategyType.AGGRESSIVE,
            ""
        );
        console.log("[+] Aggressive Garden deployed:", aggressiveGarden);

        vm.stopBroadcast();

        // ============================================
        // DEPLOYMENT SUMMARY
        // ============================================

        console.log("\n============================================");
        console.log("GARDEN SYSTEM DEPLOYED SUCCESSFULLY");
        console.log("============================================");
        console.log("Registry:", address(registry));
        console.log("Factory:", address(factory));
        console.log("---");
        console.log("Template Facets:");
        console.log("  DiamondCutFacet:", address(diamondCutFacet));
        console.log("  RWAFacetV2:", address(rwaFacet));
        console.log("  GovernanceFacet:", address(governanceFacet));
        console.log("---");
        console.log("Gardens:");
        console.log("  Conservative (T-Bills):", conservativeGarden);
        console.log("  Balanced (Mixed):", balancedGarden);
        console.log("  Aggressive (High-Yield):", aggressiveGarden);
        console.log("============================================");
        console.log("\nNext steps:");
        console.log(
            "1. Users can deposit into any garden: DiamondRWA(garden).deposit(amount)"
        );
        console.log("2. View all gardens: GardenRegistry.getAllGardens()");
        console.log("3. Compare APYs: GardenRegistry.getAllGardenStats()");
        console.log("4. Vote on RWA changes via governance in each garden");
    }
}
