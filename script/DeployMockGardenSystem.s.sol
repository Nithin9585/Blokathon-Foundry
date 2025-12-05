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
import {MockUSDC} from "../src/mocks/MockUSDC.sol";
import {
    MockOndoOUSG,
    MockOndoUSDY,
    MockFigureTreasury
} from "../src/mocks/MockRWAToken.sol";

contract DeployMockGardenSystem is Script {
    function run() external {
        address deployer;

        try vm.envUint("PRIVATE_KEY") returns (uint256 deployerPrivateKey) {
            deployer = vm.addr(deployerPrivateKey);
            vm.startBroadcast(deployerPrivateKey);
        } catch {
            deployer = msg.sender;
            vm.startBroadcast();
        }
        console.log("Deploying Mock Garden System...");

        // 1. Deploy Mock Tokens
        MockUSDC usdc = new MockUSDC();
        console.log("MockUSDC:", address(usdc));

        MockOndoOUSG ousg = new MockOndoOUSG(address(usdc));
        console.log("MockOndoOUSG:", address(ousg));

        MockOndoUSDY usdy = new MockOndoUSDY(address(usdc));
        console.log("MockOndoUSDY:", address(usdy));

        MockFigureTreasury figure = new MockFigureTreasury(address(usdc));
        console.log("MockFigureTreasury:", address(figure));

        // 2. Deploy Template Facets
        DiamondCutFacet diamondCutFacet = new DiamondCutFacet();
        OwnershipFacet ownershipFacet = new OwnershipFacet();
        DiamondRWAYieldFacetV2 rwaFacet = new DiamondRWAYieldFacetV2();
        GovernanceFacet governanceFacet = new GovernanceFacet();

        // 3. Deploy Registry & Factory
        GardenRegistry registry = new GardenRegistry(deployer);
        GardenFactory factory = new GardenFactory(
            address(registry),
            address(usdc)
        );
        registry.updateFactory(address(factory));

        // 4. Configure Factory
        factory.setFacetTemplates(
            address(diamondCutFacet),
            address(ownershipFacet),
            address(rwaFacet),
            address(governanceFacet)
        );

        // Configure Strategies with MOCK Tokens
        factory.configureStrategy(
            GardenRegistry.StrategyType.CONSERVATIVE,
            address(figure), // Using Figure as proxy for T-Bills
            address(0),
            10 * 1e6,
            "Conservative Garden (Backed IB01)"
        );

        factory.configureStrategy(
            GardenRegistry.StrategyType.BALANCED,
            address(figure),
            address(usdy),
            10 * 1e6,
            "Balanced Garden (Ondo USDY)"
        );

        factory.configureStrategy(
            GardenRegistry.StrategyType.AGGRESSIVE,
            address(ousg),
            address(usdy),
            10 * 1e6,
            "Aggressive Garden (Ondo OUSG)"
        );

        // 5. Deploy Gardens
        address conservativeGarden = factory.deployGarden(
            GardenRegistry.StrategyType.CONSERVATIVE,
            ""
        );
        address balancedGarden = factory.deployGarden(
            GardenRegistry.StrategyType.BALANCED,
            ""
        );
        address aggressiveGarden = factory.deployGarden(
            GardenRegistry.StrategyType.AGGRESSIVE,
            ""
        );

        // SEED INITIAL TVL (So demo looks good)
        console.log("Seeding initial TVL...");

        // Mint USDC to deployer
        usdc.mint(deployer, 1_000_000 * 1e6); // 1M USDC

        // Approve gardens
        usdc.approve(conservativeGarden, type(uint256).max);
        usdc.approve(balancedGarden, type(uint256).max);
        usdc.approve(aggressiveGarden, type(uint256).max);

        // Deposit into Conservative (Seed: $500k)
        DiamondRWAYieldFacetV2(conservativeGarden).deposit(500_000 * 1e6);

        // Deposit into Balanced (Seed: $250k)
        DiamondRWAYieldFacetV2(balancedGarden).deposit(250_000 * 1e6);

        // Deposit into Aggressive (Seed: $150k)
        DiamondRWAYieldFacetV2(aggressiveGarden).deposit(150_000 * 1e6);

        console.log("Seeding complete!");

        vm.stopBroadcast();

        // 6. Write Config
        string memory json = "{";
        json = string.concat(
            json,
            '"GARDEN_REGISTRY": "',
            vm.toString(address(registry)),
            '",'
        );
        json = string.concat(
            json,
            '"GARDEN_FACTORY": "',
            vm.toString(address(factory)),
            '",'
        );
        json = string.concat(
            json,
            '"USDC": "',
            vm.toString(address(usdc)),
            '",'
        );

        json = string.concat(json, '"GARDENS": {');
        json = string.concat(
            json,
            '"CONSERVATIVE": "',
            vm.toString(conservativeGarden),
            '",'
        );
        json = string.concat(
            json,
            '"BALANCED": "',
            vm.toString(balancedGarden),
            '",'
        );
        json = string.concat(
            json,
            '"AGGRESSIVE": "',
            vm.toString(aggressiveGarden),
            '"'
        );
        json = string.concat(json, "},");

        json = string.concat(json, '"FACETS": {');
        json = string.concat(
            json,
            '"DIAMOND_CUT": "',
            vm.toString(address(diamondCutFacet)),
            '",'
        );
        json = string.concat(
            json,
            '"DIAMOND_RWA_YIELD": "',
            vm.toString(address(rwaFacet)),
            '",'
        );
        json = string.concat(
            json,
            '"GOVERNANCE": "',
            vm.toString(address(governanceFacet)),
            '"'
        );
        json = string.concat(json, "}");

        json = string.concat(json, "}");

        vm.writeFile("../frontend/src/config/deployments.json", json);
        console.log(
            "Config written to ../frontend/src/config/deployments.json"
        );
    }
}
