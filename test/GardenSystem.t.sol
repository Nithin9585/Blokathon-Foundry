// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "forge-std/Test.sol";
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
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title GardenSystemTest
 * @notice Tests for Garden Factory + Registry system
 */
contract GardenSystemTest is Test {
    GardenRegistry public registry;
    GardenFactory public factory;

    DiamondCutFacet public diamondCutFacet;
    OwnershipFacet public ownershipFacet;
    DiamondRWAYieldFacetV2 public rwaFacet;
    GovernanceFacet public governanceFacet;

    address public owner = address(this);
    address public user1 = address(0x1);
    address public user2 = address(0x2);

    // Mock RWA tokens
    address public mockRWA1 = address(0x100);
    address public mockRWA2 = address(0x200);
    address public mockRWA3 = address(0x300);

    function setUp() public {
        // Deploy template facets
        diamondCutFacet = new DiamondCutFacet();
        ownershipFacet = new OwnershipFacet();
        rwaFacet = new DiamondRWAYieldFacetV2();
        governanceFacet = new GovernanceFacet();

        // Deploy registry
        registry = new GardenRegistry(owner);

        // Deploy factory
        factory = new GardenFactory(address(registry), address(0x1));

        // Update registry to recognize factory
        registry.updateFactory(address(factory));

        // Configure factory
        factory.setFacetTemplates(
            address(diamondCutFacet),
            address(ownershipFacet),
            address(rwaFacet),
            address(governanceFacet)
        );

        // Configure strategies
        factory.configureStrategy(
            GardenRegistry.StrategyType.CONSERVATIVE,
            mockRWA1,
            address(0),
            10 * 1e6,
            "Conservative Garden"
        );

        factory.configureStrategy(
            GardenRegistry.StrategyType.BALANCED,
            mockRWA1,
            mockRWA2,
            10 * 1e6,
            "Balanced Garden"
        );

        factory.configureStrategy(
            GardenRegistry.StrategyType.AGGRESSIVE,
            mockRWA2,
            mockRWA3,
            10 * 1e6,
            "Aggressive Garden"
        );
    }

    // ============================================
    // REGISTRY TESTS
    // ============================================

    function testRegistryInitialization() public {
        assertEq(registry.factory(), address(factory));
        assertEq(registry.owner(), owner);
        assertEq(registry.getGardenCount(), 0);
    }

    function testUpdateFactory() public {
        address newFactory = address(0x999);
        registry.updateFactory(newFactory);
        assertEq(registry.factory(), newFactory);
    }

    function testCannotRegisterGardenFromNonFactory() public {
        vm.prank(user1);
        vm.expectRevert(GardenRegistry.Unauthorized.selector);
        registry.registerGarden(
            address(0x123),
            GardenRegistry.StrategyType.CONSERVATIVE,
            "Test"
        );
    }

    // ============================================
    // FACTORY TESTS
    // ============================================

    function testFactoryInitialization() public {
        assertEq(address(factory.registry()), address(registry));
        assertEq(factory.owner(), owner);
        assertTrue(factory.areFacetsSet());
    }

    function testStrategyConfiguration() public {
        GardenFactory.StrategyConfig memory config = factory.getStrategyConfig(
            GardenRegistry.StrategyType.CONSERVATIVE
        );

        assertEq(config.primaryRWA, mockRWA1);
        assertEq(config.secondaryRWA, address(0));
        assertEq(config.minDeposit, 10 * 1e6);
        assertEq(config.name, "Conservative Garden");
    }

    function testCannotDeployWithoutFacets() public {
        // Deploy new factory without facets
        GardenFactory badFactory = new GardenFactory(
            address(registry),
            address(0x1)
        );

        vm.expectRevert(GardenFactory.FacetsNotSet.selector);
        badFactory.deployGarden(
            GardenRegistry.StrategyType.CONSERVATIVE,
            "Test"
        );
    }

    function testCannotDeployInvalidStrategy() public {
        // Try to configure strategy with zero address - should revert
        vm.expectRevert(GardenFactory.ZeroAddress.selector);
        factory.configureStrategy(
            GardenRegistry.StrategyType.CONSERVATIVE,
            address(0), // Invalid - zero address
            address(0),
            10 * 1e6,
            "Bad"
        );
    }

    // ============================================
    // GARDEN DEPLOYMENT TESTS
    // ============================================

    function testDeployConservativeGarden() public {
        address garden = factory.deployGarden(
            GardenRegistry.StrategyType.CONSERVATIVE,
            ""
        );

        assertTrue(garden != address(0));
        assertTrue(registry.isGardenRegistered(garden));
        assertEq(registry.getGardenCount(), 1);

        (
            address gardenAddress,
            GardenRegistry.StrategyType strategy,
            string memory name,
            uint256 deployedAt,
            bool isActive
        ) = registry.gardenInfo(garden);
        assertEq(
            uint256(strategy),
            uint256(GardenRegistry.StrategyType.CONSERVATIVE)
        );
        assertEq(name, "Conservative Garden");
        assertTrue(isActive);
    }

    function testDeployBalancedGarden() public {
        address garden = factory.deployGarden(
            GardenRegistry.StrategyType.BALANCED,
            ""
        );

        assertTrue(garden != address(0));
        assertEq(registry.getGardenCount(), 1);

        (, GardenRegistry.StrategyType strategy, , , ) = registry.gardenInfo(
            garden
        );
        assertEq(
            uint256(strategy),
            uint256(GardenRegistry.StrategyType.BALANCED)
        );
    }

    function testDeployAggressiveGarden() public {
        address garden = factory.deployGarden(
            GardenRegistry.StrategyType.AGGRESSIVE,
            ""
        );

        assertTrue(garden != address(0));
        assertEq(registry.getGardenCount(), 1);

        (, GardenRegistry.StrategyType strategy, , , ) = registry.gardenInfo(
            garden
        );
        assertEq(
            uint256(strategy),
            uint256(GardenRegistry.StrategyType.AGGRESSIVE)
        );
    }

    function testDeployMultipleGardens() public {
        address garden1 = factory.deployGarden(
            GardenRegistry.StrategyType.CONSERVATIVE,
            "Conservative 1"
        );
        address garden2 = factory.deployGarden(
            GardenRegistry.StrategyType.BALANCED,
            "Balanced 1"
        );
        address garden3 = factory.deployGarden(
            GardenRegistry.StrategyType.AGGRESSIVE,
            "Aggressive 1"
        );

        assertEq(registry.getGardenCount(), 3);

        address[] memory allGardens = registry.getAllGardens();
        assertEq(allGardens.length, 3);
        assertEq(allGardens[0], garden1);
        assertEq(allGardens[1], garden2);
        assertEq(allGardens[2], garden3);
    }

    function testGetGardensByStrategy() public {
        // Deploy 2 conservative, 1 balanced
        address conserv1 = factory.deployGarden(
            GardenRegistry.StrategyType.CONSERVATIVE,
            ""
        );
        address conserv2 = factory.deployGarden(
            GardenRegistry.StrategyType.CONSERVATIVE,
            ""
        );
        address balanced = factory.deployGarden(
            GardenRegistry.StrategyType.BALANCED,
            ""
        );

        address[] memory conservative = registry.getGardensByStrategy(
            GardenRegistry.StrategyType.CONSERVATIVE
        );
        assertEq(conservative.length, 2);
        assertEq(conservative[0], conserv1);
        assertEq(conservative[1], conserv2);

        address[] memory balancedList = registry.getGardensByStrategy(
            GardenRegistry.StrategyType.BALANCED
        );
        assertEq(balancedList.length, 1);
        assertEq(balancedList[0], balanced);
    }

    function testCustomGardenName() public {
        address garden = factory.deployGarden(
            GardenRegistry.StrategyType.CONSERVATIVE,
            "My Custom Garden"
        );

        (, , string memory name, , ) = registry.gardenInfo(garden);
        assertEq(name, "My Custom Garden");
    }

    // ============================================
    // GARDEN STATS TESTS
    // ============================================

    function testGetGardenStats() public {
        address garden = factory.deployGarden(
            GardenRegistry.StrategyType.CONSERVATIVE,
            ""
        );

        // Note: Stats will be 0 because we're not actually depositing in this test
        // In a real scenario, you'd deposit USDC and check actual values
        GardenRegistry.GardenStats memory stats = registry.getGardenStats(
            garden
        );

        assertEq(stats.gardenAddress, garden);
        assertEq(
            uint256(stats.strategy),
            uint256(GardenRegistry.StrategyType.CONSERVATIVE)
        );
        assertEq(stats.name, "Conservative Garden");
        assertTrue(stats.isActive);
    }

    function testGetAllGardenStats() public {
        factory.deployGarden(GardenRegistry.StrategyType.CONSERVATIVE, "");
        factory.deployGarden(GardenRegistry.StrategyType.BALANCED, "");
        factory.deployGarden(GardenRegistry.StrategyType.AGGRESSIVE, "");

        GardenRegistry.GardenStats[] memory allStats = registry
            .getAllGardenStats();

        assertEq(allStats.length, 3);
        assertEq(
            uint256(allStats[0].strategy),
            uint256(GardenRegistry.StrategyType.CONSERVATIVE)
        );
        assertEq(
            uint256(allStats[1].strategy),
            uint256(GardenRegistry.StrategyType.BALANCED)
        );
        assertEq(
            uint256(allStats[2].strategy),
            uint256(GardenRegistry.StrategyType.AGGRESSIVE)
        );
    }

    // ============================================
    // ADMIN TESTS
    // ============================================

    function testDeactivateGarden() public {
        address garden = factory.deployGarden(
            GardenRegistry.StrategyType.CONSERVATIVE,
            ""
        );

        registry.deactivateGarden(garden);

        (, , , , bool isActive) = registry.gardenInfo(garden);
        assertFalse(isActive);
    }

    function testCannotDeactivateUnregisteredGarden() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                GardenRegistry.GardenNotRegistered.selector,
                address(0x999)
            )
        );
        registry.deactivateGarden(address(0x999));
    }

    function testTransferOwnership() public {
        factory.transferOwnership(user1);
        assertEq(factory.owner(), user1);

        registry.transferOwnership(user2);
        assertEq(registry.owner(), user2);
    }
}
