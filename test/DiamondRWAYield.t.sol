// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {Test, console} from "forge-std/Test.sol";
import {Diamond} from "src/Diamond.sol";
import {IDiamondCut} from "src/facets/baseFacets/cut/IDiamondCut.sol";
import {DiamondCutFacet} from "src/facets/baseFacets/cut/DiamondCutFacet.sol";
import {DiamondLoupeFacet} from "src/facets/baseFacets/loupe/DiamondLoupeFacet.sol";
import {OwnershipFacet} from "src/facets/baseFacets/ownership/OwnershipFacet.sol";
import {DiamondRWAYieldFacet} from "src/facets/utilityFacets/diamondRWA/DiamondRWAYieldFacet.sol";
import {IDiamondRWA} from "src/facets/utilityFacets/diamondRWA/IDiamondRWA.sol";
import {MockRWAToken, MockOndoOUSG, MockOndoUSDY, MockFigureTreasury} from "src/mocks/MockRWAToken.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/**
 * @title MockUSDC
 * @notice Simple mock USDC for testing
 */
contract MockUSDC is ERC20 {
    constructor() ERC20("USD Coin", "USDC") {
        _mint(msg.sender, 1000000e6); // 1M USDC
    }

    function decimals() public pure override returns (uint8) {
        return 6;
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

/**
 * @title DiamondRWAYieldTest
 * @notice Unit tests for Diamond RWA Yield vault
 */
contract DiamondRWAYieldTest is Test {
    Diamond public diamond;
    DiamondRWAYieldFacet public rwaFacet;
    MockUSDC public usdc;
    MockOndoOUSG public mockOUSG;
    MockOndoUSDY public mockUSDY;
    MockFigureTreasury public mockFigure;

    address public owner = address(this);
    address public user1 = address(0x1);
    address public user2 = address(0x2);

    event Deposit(address indexed user, uint256 assets, uint256 shares);
    event Withdraw(address indexed user, uint256 shares, uint256 assets);
    event StrategyUpgraded(address indexed oldRWA, address indexed newRWA, uint256 newAPY, uint256 timestamp);

    function setUp() public {
        // Deploy mock USDC
        usdc = new MockUSDC();
        console.log("Mock USDC deployed:", address(usdc));

        // Deploy mock RWAs
        mockOUSG = new MockOndoOUSG(address(usdc));
        mockUSDY = new MockOndoUSDY(address(usdc));
        mockFigure = new MockFigureTreasury(address(usdc));
        console.log("Mock RWAs deployed");

        // Deploy Diamond with base facets
        DiamondCutFacet cutFacet = new DiamondCutFacet();
        DiamondLoupeFacet loupeFacet = new DiamondLoupeFacet();
        OwnershipFacet ownershipFacet = new OwnershipFacet();

        IDiamondCut.FacetCut[] memory baseCuts = new IDiamondCut.FacetCut[](3);
        baseCuts[0] = _createCutFacetCut(address(cutFacet));
        baseCuts[1] = _createLoupeFacetCut(address(loupeFacet));
        baseCuts[2] = _createOwnershipFacetCut(address(ownershipFacet));

        diamond = new Diamond(owner, baseCuts);
        console.log("Diamond deployed:", address(diamond));

        // Deploy and add RWA facet
        rwaFacet = new DiamondRWAYieldFacet();
        IDiamondCut.FacetCut[] memory rwaCut = new IDiamondCut.FacetCut[](1);
        rwaCut[0] = _createRWAFacetCut(address(rwaFacet));
        
        IDiamondCut(address(diamond)).diamondCut(rwaCut, address(0), "");
        console.log("RWA Facet added to Diamond");

        // Initialize vault
        IDiamondRWA(address(diamond)).initialize(address(usdc), address(mockOUSG), "Mock Ondo OUSG");
        console.log("Vault initialized");

        // Setup test users with USDC
        usdc.mint(user1, 100000e6); // 100k USDC
        usdc.mint(user2, 100000e6);
        
        vm.prank(user1);
        usdc.approve(address(diamond), type(uint256).max);
        
        vm.prank(user2);
        usdc.approve(address(diamond), type(uint256).max);
    }

    // ============================================
    // DEPOSIT TESTS
    // ============================================

    function testDeposit() public {
        uint256 depositAmount = 10000e6; // 10,000 USDC

        vm.startPrank(user1);
        
        uint256 shares = IDiamondRWA(address(diamond)).deposit(depositAmount);
        
        vm.stopPrank();

        // First deposit should be 1:1
        assertEq(shares, depositAmount, "First deposit should get 1:1 shares");
        assertEq(IDiamondRWA(address(diamond)).getUserShares(user1), depositAmount, "User shares incorrect");
        assertEq(IDiamondRWA(address(diamond)).getTotalShares(), depositAmount, "Total shares incorrect");
        assertEq(IDiamondRWA(address(diamond)).getTotalAssets(), depositAmount, "Total assets incorrect");
    }

    function testDepositEmitsEvent() public {
        uint256 depositAmount = 10000e6;

        vm.expectEmit(true, false, false, true);
        emit Deposit(user1, depositAmount, depositAmount);

        vm.prank(user1);
        IDiamondRWA(address(diamond)).deposit(depositAmount);
    }

    function testCannotDepositZero() public {
        vm.prank(user1);
        vm.expectRevert(IDiamondRWA.ZeroAmount.selector);
        IDiamondRWA(address(diamond)).deposit(0);
    }

    function testCannotDepositBelowMinimum() public {
        uint256 tooSmall = 5e6; // 5 USDC (min is 10)

        vm.prank(user1);
        vm.expectRevert();
        IDiamondRWA(address(diamond)).deposit(tooSmall);
    }

    function testMultipleDeposits() public {
        // User1 deposits
        vm.prank(user1);
        uint256 shares1 = IDiamondRWA(address(diamond)).deposit(10000e6);

        // Check initial state
        uint256 totalAssetsBefore = IDiamondRWA(address(diamond)).getTotalAssets();
        console.log("Total assets before time warp:", totalAssetsBefore);

        // Simulate time passing and yield accrual in the RWA
        vm.warp(block.timestamp + 30 days);
        
        // The RWA has accrued yield, but vault's totalAssets doesn't update until interaction
        // So second depositor still gets 1:1 shares from vault's perspective
        // This is expected behavior - vault only updates on deposits/withdrawals
        
        vm.prank(user2);
        uint256 shares2 = IDiamondRWA(address(diamond)).deposit(10000e6);

        // Both users should have same shares since vault doesn't auto-update from RWA yield
        assertEq(shares1, shares2, "Both depositors get same vault shares");
        console.log("User1 shares:", shares1);
        console.log("User2 shares:", shares2);
    }

    // ============================================
    // WITHDRAW TESTS
    // ============================================

    function testWithdraw() public {
        uint256 depositAmount = 10000e6;

        // Deposit first
        vm.prank(user1);
        uint256 shares = IDiamondRWA(address(diamond)).deposit(depositAmount);

        // Withdraw
        vm.prank(user1);
        uint256 assets = IDiamondRWA(address(diamond)).withdraw(shares);

        assertEq(assets, depositAmount, "Should receive same amount back (no yield yet)");
        assertEq(IDiamondRWA(address(diamond)).getUserShares(user1), 0, "User should have no shares left");
    }

    function testWithdrawWithYield() public {
        uint256 depositAmount = 10000e6;

        // Deposit
        vm.prank(user1);
        uint256 shares = IDiamondRWA(address(diamond)).deposit(depositAmount);

        // Simulate 1 year passing (should earn ~5.1% APY from mock OUSG)
        vm.warp(block.timestamp + 365 days);

        // Fund the mock with yield (5.1% of 10k = 510 USDC)
        // In real RWAs, this comes from bond/treasury income
        uint256 expectedYield = (depositAmount * 510) / 10000; // 5.1%
        usdc.mint(address(this), expectedYield);
        usdc.approve(address(mockOUSG), expectedYield);
        mockOUSG.fundYield(expectedYield);

        // Withdraw
        vm.prank(user1);
        uint256 assets = IDiamondRWA(address(diamond)).withdraw(shares);

        // Should receive more than deposited due to yield
        assertTrue(assets > depositAmount, "Should receive yield");
        console.log("Deposited:", depositAmount);
        console.log("Withdrew:", assets);
        console.log("Yield earned:", assets - depositAmount);
    }

    function testCannotWithdrawMoreThanOwned() public {
        vm.prank(user1);
        IDiamondRWA(address(diamond)).deposit(10000e6);

        vm.prank(user1);
        vm.expectRevert();
        IDiamondRWA(address(diamond)).withdraw(20000e6); // Try to withdraw 2x
    }

    // ============================================
    // STRATEGY UPGRADE TESTS (THE MAGIC SWITCH!)
    // ============================================

    function testUpgradeStrategy() public {
        // User deposits into OUSG (5.1% APY)
        vm.prank(user1);
        IDiamondRWA(address(diamond)).deposit(10000e6);

        // Check initial APY
        uint256 oldAPY = IDiamondRWA(address(diamond)).getCurrentAPY();
        assertEq(oldAPY, 510, "Should start with 5.1% APY");

        // Whitelist Figure Treasury (8.7% APY)
        IDiamondRWA(address(diamond)).addRWAToWhitelist(address(mockFigure), "Mock Figure Treasury");

        // THE MAGIC SWITCH - Upgrade to higher yield RWA
        vm.expectEmit(true, true, false, false);
        emit StrategyUpgraded(address(mockOUSG), address(mockFigure), 870, block.timestamp);
        
        IDiamondRWA(address(diamond)).upgradeToRWA(address(mockFigure));

        // Check new APY
        uint256 newAPY = IDiamondRWA(address(diamond)).getCurrentAPY();
        assertEq(newAPY, 870, "Should now have 8.7% APY");
        assertEq(IDiamondRWA(address(diamond)).getCurrentRWA(), address(mockFigure), "Current RWA should be Figure");

        // User didn't have to do anything!
        assertEq(IDiamondRWA(address(diamond)).getUserShares(user1), 10000e6, "User shares unchanged");
    }

    function testOnlyOwnerCanUpgrade() public {
        IDiamondRWA(address(diamond)).addRWAToWhitelist(address(mockFigure), "Mock Figure");

        vm.prank(user1);
        vm.expectRevert();
        IDiamondRWA(address(diamond)).upgradeToRWA(address(mockFigure));
    }

    // ============================================
    // VIEW FUNCTION TESTS
    // ============================================

    function testGetBestAPY() public {
        // Whitelist all RWAs
        IDiamondRWA(address(diamond)).addRWAToWhitelist(address(mockUSDY), "Mock USDY");
        IDiamondRWA(address(diamond)).addRWAToWhitelist(address(mockFigure), "Mock Figure");

        (uint256 bestAPY, address bestRWA) = IDiamondRWA(address(diamond)).getBestAPY();

        assertEq(bestAPY, 870, "Best APY should be Figure at 8.7%");
        assertEq(bestRWA, address(mockFigure), "Best RWA should be Figure");
    }

    function testPreviewDeposit() public {
        uint256 amount = 10000e6;
        uint256 previewShares = IDiamondRWA(address(diamond)).previewDeposit(amount);
        
        vm.prank(user1);
        uint256 actualShares = IDiamondRWA(address(diamond)).deposit(amount);

        assertEq(previewShares, actualShares, "Preview should match actual");
    }

    // ============================================
    // HELPER FUNCTIONS
    // ============================================

    function _createCutFacetCut(address facet) internal pure returns (IDiamondCut.FacetCut memory) {
        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = IDiamondCut.diamondCut.selector;
        return IDiamondCut.FacetCut({
            facetAddress: facet,
            action: IDiamondCut.FacetCutAction.Add,
            functionSelectors: selectors
        });
    }

    function _createLoupeFacetCut(address facet) internal pure returns (IDiamondCut.FacetCut memory) {
        bytes4[] memory selectors = new bytes4[](5);
        selectors[0] = bytes4(keccak256("facets()"));
        selectors[1] = bytes4(keccak256("facetFunctionSelectors(address)"));
        selectors[2] = bytes4(keccak256("facetAddresses()"));
        selectors[3] = bytes4(keccak256("facetAddress(bytes4)"));
        selectors[4] = bytes4(keccak256("supportsInterface(bytes4)"));
        return IDiamondCut.FacetCut({
            facetAddress: facet,
            action: IDiamondCut.FacetCutAction.Add,
            functionSelectors: selectors
        });
    }

    function _createOwnershipFacetCut(address facet) internal pure returns (IDiamondCut.FacetCut memory) {
        bytes4[] memory selectors = new bytes4[](2);
        selectors[0] = bytes4(keccak256("owner()"));
        selectors[1] = bytes4(keccak256("transferOwnership(address)"));
        return IDiamondCut.FacetCut({
            facetAddress: facet,
            action: IDiamondCut.FacetCutAction.Add,
            functionSelectors: selectors
        });
    }

    function _createRWAFacetCut(address facet) internal pure returns (IDiamondCut.FacetCut memory) {
        bytes4[] memory selectors = new bytes4[](20);
        selectors[0] = IDiamondRWA.deposit.selector;
        selectors[1] = IDiamondRWA.withdraw.selector;
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
        selectors[14] = IDiamondRWA.addRWAToWhitelist.selector;
        selectors[15] = IDiamondRWA.removeRWAFromWhitelist.selector;
        selectors[16] = IDiamondRWA.upgradeToRWA.selector;
        selectors[17] = IDiamondRWA.setPause.selector;
        selectors[18] = IDiamondRWA.setMinDeposit.selector;
        selectors[19] = IDiamondRWA.initialize.selector;
        
        return IDiamondCut.FacetCut({
            facetAddress: facet,
            action: IDiamondCut.FacetCutAction.Add,
            functionSelectors: selectors
        });
    }
}
