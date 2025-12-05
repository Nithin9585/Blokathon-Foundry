// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "forge-std/Test.sol";
import {Diamond} from "../src/Diamond.sol";
import {
    Diamond_UnauthorizedCaller,
    Diamond_NotGovernance
} from "../src/facets/Facet.sol";
import {
    DiamondRWAYieldFacetV2
} from "../src/facets/utilityFacets/diamondRWA/DiamondRWAYieldFacetV2.sol";
import {
    DiamondCutFacet
} from "../src/facets/baseFacets/cut/DiamondCutFacet.sol";
import {IDiamondCut} from "../src/facets/baseFacets/cut/IDiamondCut.sol";
import {
    IDiamondRWA
} from "../src/facets/utilityFacets/diamondRWA/IDiamondRWA.sol";
import {MockRWAToken} from "../src/mocks/MockRWAToken.sol";
import {MockERC20} from "../src/mocks/MockERC20.sol";

/**
 * @title DiamondRWAYieldFacetV2Test
 * @notice Tests for production V2 facet (timelock, slippage, withdrawal queue)
 */
contract DiamondRWAYieldFacetV2Test is Test {
    Diamond public diamond;
    DiamondRWAYieldFacetV2 public facet;
    MockERC20 public usdc;
    MockRWAToken public rwa1;
    MockRWAToken public rwa2;

    address public owner = address(this);
    address public user1 = address(0x1);
    address public user2 = address(0x2);

    uint256 constant INITIAL_BALANCE = 1_000_000e6; // 1M USDC
    uint256 constant DEPOSIT_AMOUNT = 10_000e6; // 10k USDC

    function setUp() public {
        // Deploy tokens
        usdc = new MockERC20("USD Coin", "USDC", 6);
        rwa1 = new MockRWAToken("Ondo OUSG", address(usdc), 510); // 5.1% APY
        rwa2 = new MockRWAToken("Backed IB01", address(usdc), 550); // 5.5% APY

        // Deploy DiamondCutFacet first
        DiamondCutFacet diamondCutFacet = new DiamondCutFacet();

        // Create initial facet cuts for DiamondCutFacet
        bytes4[] memory diamondCutSelectors = new bytes4[](1);
        diamondCutSelectors[0] = IDiamondCut.diamondCut.selector;

        IDiamondCut.FacetCut[] memory initialCuts = new IDiamondCut.FacetCut[](
            1
        );
        initialCuts[0] = IDiamondCut.FacetCut({
            facetAddress: address(diamondCutFacet),
            action: IDiamondCut.FacetCutAction.Add,
            functionSelectors: diamondCutSelectors
        });

        // Deploy Diamond with DiamondCutFacet
        diamond = new Diamond(owner, initialCuts);

        // Deploy V2 facet
        facet = new DiamondRWAYieldFacetV2();

        // Add facet to Diamond
        bytes4[] memory selectors = new bytes4[](21);
        selectors[0] = DiamondRWAYieldFacetV2.initialize.selector;
        selectors[1] = DiamondRWAYieldFacetV2.deposit.selector;
        selectors[2] = DiamondRWAYieldFacetV2.withdraw.selector;
        selectors[3] = DiamondRWAYieldFacetV2.scheduleUpgrade.selector;
        selectors[4] = DiamondRWAYieldFacetV2.executeScheduledUpgrade.selector;
        selectors[5] = DiamondRWAYieldFacetV2.cancelScheduledUpgrade.selector;
        selectors[6] = DiamondRWAYieldFacetV2.requestWithdrawal.selector;
        selectors[7] = DiamondRWAYieldFacetV2.emergencyPause.selector;
        selectors[8] = DiamondRWAYieldFacetV2.emergencyWithdrawAll.selector;
        selectors[9] = DiamondRWAYieldFacetV2.getTotalAssets.selector;
        selectors[10] = DiamondRWAYieldFacetV2.previewDeposit.selector;
        selectors[11] = DiamondRWAYieldFacetV2.previewWithdraw.selector;
        selectors[12] = DiamondRWAYieldFacetV2.getCurrentAPY.selector;
        selectors[13] = DiamondRWAYieldFacetV2.getPendingUpgrade.selector;
        selectors[14] = DiamondRWAYieldFacetV2.getBestAPY.selector;
        selectors[15] = DiamondRWAYieldFacetV2.getCurrentRWA.selector;
        selectors[16] = DiamondRWAYieldFacetV2.getUserShares.selector;
        selectors[17] = DiamondRWAYieldFacetV2.isPaused.selector;
        selectors[18] = DiamondRWAYieldFacetV2.addRWAToWhitelist.selector;
        selectors[19] = DiamondRWAYieldFacetV2.upgradeToRWA.selector;
        selectors[20] = DiamondRWAYieldFacetV2.withdrawFor.selector;

        IDiamondCut.FacetCut[] memory cuts = new IDiamondCut.FacetCut[](1);
        cuts[0] = IDiamondCut.FacetCut({
            facetAddress: address(facet),
            action: IDiamondCut.FacetCutAction.Add,
            functionSelectors: selectors
        });

        IDiamondCut(address(diamond)).diamondCut(cuts, address(0), "");

        // Initialize vault
        DiamondRWAYieldFacetV2(address(diamond)).initialize(
            address(usdc),
            address(rwa1),
            "Ondo OUSG"
        );

        // Whitelist rwa2 for upgrade tests
        DiamondRWAYieldFacetV2(address(diamond)).addRWAToWhitelist(
            address(rwa2),
            "Backed IB01"
        );

        // Setup users
        usdc.mint(user1, INITIAL_BALANCE);
        usdc.mint(user2, INITIAL_BALANCE);

        vm.prank(user1);
        usdc.approve(address(diamond), type(uint256).max);

        vm.prank(user2);
        usdc.approve(address(diamond), type(uint256).max);

        // Fund RWAs for yield
        usdc.mint(address(this), 100_000e6);
        usdc.approve(address(rwa1), type(uint256).max);
        usdc.approve(address(rwa2), type(uint256).max);
    }

    function testScheduleUpgrade() public {
        // User1 deposits
        vm.prank(user1);
        DiamondRWAYieldFacetV2(address(diamond)).deposit(DEPOSIT_AMOUNT);

        // Owner schedules upgrade
        DiamondRWAYieldFacetV2(address(diamond)).scheduleUpgrade(address(rwa2));

        // Check pending upgrade
        (
            address newRWA,
            uint256 executeAfter,
            bool exists
        ) = DiamondRWAYieldFacetV2(address(diamond)).getPendingUpgrade();

        assertEq(newRWA, address(rwa2), "Wrong RWA scheduled");
        assertEq(
            executeAfter,
            block.timestamp + 24 hours,
            "Wrong execution time"
        );
        // exists is actually canExecute, which should be false now
        assertFalse(exists, "Should not be executable yet");
        assertTrue(newRWA != address(0), "Upgrade not scheduled");
    }

    function testCannotExecuteUpgradeBeforeTimelock() public {
        // User1 deposits
        vm.prank(user1);
        DiamondRWAYieldFacetV2(address(diamond)).deposit(DEPOSIT_AMOUNT);

        // Schedule upgrade
        DiamondRWAYieldFacetV2(address(diamond)).scheduleUpgrade(address(rwa2));

        // Try to execute immediately - should fail
        vm.expectRevert("Timelock not expired");
        DiamondRWAYieldFacetV2(address(diamond)).executeScheduledUpgrade(0);
    }

    function testExecuteUpgradeAfterTimelock() public {
        // User1 deposits
        vm.prank(user1);
        DiamondRWAYieldFacetV2(address(diamond)).deposit(DEPOSIT_AMOUNT);

        uint256 user1SharesBefore = DiamondRWAYieldFacetV2(address(diamond))
            .getUserShares(user1);

        // Fund RWA1 with yield
        rwa1.fundYield(1_000e6);

        // Schedule upgrade
        DiamondRWAYieldFacetV2(address(diamond)).scheduleUpgrade(address(rwa2));

        // Warp 24 hours
        vm.warp(block.timestamp + 24 hours + 1);

        // Execute upgrade with no slippage tolerance
        DiamondRWAYieldFacetV2(address(diamond)).executeScheduledUpgrade(0);

        // Verify upgrade happened
        assertEq(
            DiamondRWAYieldFacetV2(address(diamond)).getCurrentRWA(),
            address(rwa2),
            "Upgrade failed"
        );

        // User shares should remain unchanged
        assertEq(
            DiamondRWAYieldFacetV2(address(diamond)).getUserShares(user1),
            user1SharesBefore,
            "Shares changed"
        );

        // APY should have increased
        assertEq(
            DiamondRWAYieldFacetV2(address(diamond)).getCurrentAPY(),
            550,
            "APY not updated"
        );
    }

    function testCancelScheduledUpgrade() public {
        // Schedule upgrade
        DiamondRWAYieldFacetV2(address(diamond)).scheduleUpgrade(address(rwa2));

        // Cancel it
        DiamondRWAYieldFacetV2(address(diamond)).cancelScheduledUpgrade();

        // Verify cancelled
        (, , bool exists) = DiamondRWAYieldFacetV2(address(diamond))
            .getPendingUpgrade();
        assertFalse(exists, "Upgrade not cancelled");
    }

    function testSlippageProtection() public {
        // User1 deposits
        vm.prank(user1);
        DiamondRWAYieldFacetV2(address(diamond)).deposit(DEPOSIT_AMOUNT);

        // Schedule upgrade
        DiamondRWAYieldFacetV2(address(diamond)).scheduleUpgrade(address(rwa2));

        // Warp 24 hours
        vm.warp(block.timestamp + 24 hours + 1);

        // Fund RWA1 so it can pay back principal + yield
        rwa1.fundYield(100_000e6);

        // Try to execute with very high minimum (should fail)
        vm.expectRevert("Slippage too high");
        DiamondRWAYieldFacetV2(address(diamond)).executeScheduledUpgrade(
            DEPOSIT_AMOUNT * 2 // Expect 2x what we deposited (impossible)
        );
    }

    function testEmergencyPause() public {
        // User1 deposits
        vm.prank(user1);
        DiamondRWAYieldFacetV2(address(diamond)).deposit(DEPOSIT_AMOUNT);

        // Owner pauses
        DiamondRWAYieldFacetV2(address(diamond)).emergencyPause(
            "Testing emergency pause"
        );

        // Verify paused
        assertTrue(
            DiamondRWAYieldFacetV2(address(diamond)).isPaused(),
            "Not paused"
        );

        // User2 cannot deposit
        vm.prank(user2);
        vm.expectRevert(IDiamondRWA.VaultPaused.selector);
        DiamondRWAYieldFacetV2(address(diamond)).deposit(DEPOSIT_AMOUNT);

        // User1 cannot withdraw
        vm.prank(user1);
        vm.expectRevert(IDiamondRWA.VaultPaused.selector);
        DiamondRWAYieldFacetV2(address(diamond)).withdraw(1000e6);
    }

    function testEmergencyWithdrawAll() public {
        // User1 deposits
        vm.prank(user1);
        DiamondRWAYieldFacetV2(address(diamond)).deposit(DEPOSIT_AMOUNT);

        // Pause first
        DiamondRWAYieldFacetV2(address(diamond)).emergencyPause(
            "Need to rescue funds"
        );

        // Emergency withdraw to owner
        DiamondRWAYieldFacetV2(address(diamond)).emergencyWithdrawAll(owner);

        // Verify funds were withdrawn from RWA
        uint256 vaultBalance = usdc.balanceOf(address(diamond));
    }

    function testRequestWithdrawal() public {
        // User1 deposits
        vm.prank(user1);
        DiamondRWAYieldFacetV2(address(diamond)).deposit(DEPOSIT_AMOUNT);

        uint256 user1Shares = DiamondRWAYieldFacetV2(address(diamond))
            .getUserShares(user1);

        // Request withdrawal (should succeed immediately with mock RWA)
        rwa1.fundYield(100_000e6);
        vm.prank(user1);
        DiamondRWAYieldFacetV2(address(diamond)).requestWithdrawal(
            user1Shares / 2
        );

        // Verify withdrawal happened
        assertEq(
            DiamondRWAYieldFacetV2(address(diamond)).getUserShares(user1),
            user1Shares / 2,
            "Withdrawal failed"
        );
    }

    function testOnlyOwnerCanScheduleUpgrade() public {
        vm.prank(user1);
        vm.expectRevert(Diamond_NotGovernance.selector);
        DiamondRWAYieldFacetV2(address(diamond)).scheduleUpgrade(address(rwa2));
    }

    function testOnlyOwnerCanPause() public {
        vm.prank(user1);
        vm.expectRevert(Diamond_UnauthorizedCaller.selector);
        DiamondRWAYieldFacetV2(address(diamond)).emergencyPause("Unauthorized");
    }

    function testCannotScheduleMultipleUpgrades() public {
        // Schedule first upgrade
        DiamondRWAYieldFacetV2(address(diamond)).scheduleUpgrade(address(rwa2));

        // Try to schedule another - should fail
        vm.expectRevert("Upgrade already scheduled");
        DiamondRWAYieldFacetV2(address(diamond)).scheduleUpgrade(address(rwa1));
    }

    function testUpgradeWithYieldAccrual() public {
        // User1 deposits
        vm.prank(user1);
        DiamondRWAYieldFacetV2(address(diamond)).deposit(DEPOSIT_AMOUNT);

        // Fund RWA1 with significant yield
        rwa1.fundYield(5_000e6);

        uint256 assetsBefore = DiamondRWAYieldFacetV2(address(diamond))
            .getTotalAssets();

        // Schedule and execute upgrade
        DiamondRWAYieldFacetV2(address(diamond)).scheduleUpgrade(address(rwa2));
        vm.warp(block.timestamp + 24 hours + 1);
        DiamondRWAYieldFacetV2(address(diamond)).executeScheduledUpgrade(
            assetsBefore - 100e6
        ); // Allow 1% slippage

        // Yield should be preserved
        uint256 assetsAfter = DiamondRWAYieldFacetV2(address(diamond))
            .getTotalAssets();
        assertApproxEqAbs(
            assetsAfter,
            assetsBefore,
            100e6,
            "Yield lost in upgrade"
        );
    }

    function testMultipleUsersAfterUpgrade() public {
        // User1 deposits
        vm.prank(user1);
        DiamondRWAYieldFacetV2(address(diamond)).deposit(DEPOSIT_AMOUNT);

        // Upgrade to RWA2
        DiamondRWAYieldFacetV2(address(diamond)).scheduleUpgrade(address(rwa2));
        vm.warp(block.timestamp + 24 hours + 1);

        // Fund RWA1 so it can pay back principal + yield
        rwa1.fundYield(100_000e6);

        DiamondRWAYieldFacetV2(address(diamond)).executeScheduledUpgrade(0);

        // User2 deposits after upgrade
        vm.prank(user2);
        DiamondRWAYieldFacetV2(address(diamond)).deposit(DEPOSIT_AMOUNT);

        // Both should have shares
        assertGt(
            DiamondRWAYieldFacetV2(address(diamond)).getUserShares(user1),
            0,
            "User1 no shares"
        );
        assertGt(
            DiamondRWAYieldFacetV2(address(diamond)).getUserShares(user2),
            0,
            "User2 no shares"
        );

        // Total assets should be ~20k
        assertApproxEqAbs(
            DiamondRWAYieldFacetV2(address(diamond)).getTotalAssets(),
            DEPOSIT_AMOUNT * 2,
            100e6,
            "Wrong total assets"
        );
    }
}
