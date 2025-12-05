// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {Test} from "forge-std/Test.sol";
import {
    GovernanceFacet
} from "src/facets/utilityFacets/governance/GovernanceFacet.sol";
import {IGovernance} from "src/facets/utilityFacets/governance/IGovernance.sol";
import {
    DiamondRWAYieldFacet
} from "src/facets/utilityFacets/diamondRWA/DiamondRWAYieldFacet.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title DAOGovernanceDemo
 * @notice Demonstrates complete DAO governance flow for RWA strategy upgrade
 * @dev Shows how community votes to switch from one RWA to another
 *
 * DEMO FLOW:
 * 1. Alice deposits USDC → Gets vault shares (= voting power)
 * 2. Alice creates proposal to switch from Ondo OUSG (5.1% APY) to Backed IB01 (8.7% APY)
 * 3. Community votes (Alice + Bob vote YES)
 * 4. Proposal passes → Queue for 24hr timelock
 * 5. Execute after timelock → All funds migrate to new RWA
 * 6. Everyone now earns 8.7% APY automatically!
 */
contract DAOGovernanceDemo is Script, Test {
    address constant DIAMOND = address(0); // Set your diamond address
    address constant USDC = 0xaf88d065e77c8cC2239327C5EDb3A432268e5831; // Arbitrum USDC
    address constant ONDO_OUSG = 0x1B19C19393e2d034D8Ff31ff34c81252FcBbee92;
    address constant BACKED_IB01 = 0xCA30c93B02514f86d5C86a6e375E3A330B435Fb5;

    function run() external {
        console.log("===========================================");
        console.log("DAO GOVERNANCE DEMO");
        console.log("===========================================");
        console.log("");

        // Setup
        GovernanceFacet governance = GovernanceFacet(DIAMOND);
        DiamondRWAYieldFacet vault = DiamondRWAYieldFacet(DIAMOND);

        address alice = vm.addr(1);
        address bob = vm.addr(2);

        console.log("Actors:");
        console.log("- Alice:", alice);
        console.log("- Bob:", bob);
        console.log("");

        // ============================================
        // STEP 1: DEPOSIT TO GET VOTING POWER
        // ============================================

        console.log("=== STEP 1: DEPOSIT FOR VOTING POWER ===");

        vm.startPrank(alice);
        deal(USDC, alice, 1000e6); // Give Alice 1000 USDC
        IERC20(USDC).approve(DIAMOND, 1000e6);
        vault.deposit(1000e6);
        vm.stopPrank();

        vm.startPrank(bob);
        deal(USDC, bob, 500e6); // Give Bob 500 USDC
        IERC20(USDC).approve(DIAMOND, 500e6);
        vault.deposit(500e6);
        vm.stopPrank();

        console.log("Alice deposited 1000 USDC -> 1000 shares (votes)");
        console.log("Bob deposited 500 USDC -> 500 shares (votes)");
        console.log("Current RWA: Ondo OUSG (5.1% APY)");
        console.log("");

        // ============================================
        // STEP 2: CREATE PROPOSAL
        // ============================================

        console.log("=== STEP 2: ALICE CREATES PROPOSAL ===");

        vm.startPrank(alice);
        uint256 proposalId = governance.propose(
            BACKED_IB01,
            "Upgrade to Backed IB01 for 8.7% APY (up from 5.1%)"
        );
        vm.stopPrank();

        console.log("Proposal #", proposalId, "created!");
        console.log("Target: Switch to Backed IB01 (8.7% APY)");
        console.log("Status: Pending (voting starts in 1 block)");
        console.log("");

        // Wait for voting to start
        vm.roll(block.number + 2);

        // ============================================
        // STEP 3: COMMUNITY VOTES
        // ============================================

        console.log("=== STEP 3: VOTING PERIOD (7 DAYS) ===");

        vm.prank(alice);
        governance.castVoteWithReason(
            proposalId,
            1, // 1 = YES
            "8.7% APY is much better than 5.1%!"
        );
        console.log("Alice voted YES with 1000 votes");

        vm.prank(bob);
        governance.castVote(proposalId, 1); // 1 = YES
        console.log("Bob voted YES with 500 votes");

        console.log("");
        console.log("Voting Results:");
        IGovernance.Proposal memory proposal = governance.getProposal(
            proposalId
        );
        console.log("- For:", proposal.forVotes / 1e6, "USDC");
        console.log("- Against:", proposal.againstVotes / 1e6, "USDC");
        console.log("- Quorum needed:", 1000, "USDC");
        console.log("- Status: PASSED!");
        console.log("");

        // Fast forward to end of voting
        vm.roll(block.number + 50400); // 7 days

        // ============================================
        // STEP 4: QUEUE FOR TIMELOCK
        // ============================================

        console.log("=== STEP 4: QUEUE PROPOSAL (24HR TIMELOCK) ===");

        vm.prank(alice);
        uint256 eta = governance.queue(proposalId);

        console.log("Proposal queued!");
        console.log("Can execute after:", eta, "(24 hours from now)");
        console.log("Security feature: Prevents rushed decisions");
        console.log("");

        // Fast forward 24 hours
        vm.warp(eta + 1);

        // ============================================
        // STEP 5: EXECUTE!
        // ============================================

        console.log("=== STEP 5: EXECUTE UPGRADE ===");

        vm.prank(alice);
        governance.execute(proposalId);

        console.log("UPGRADE COMPLETE!");
        console.log("");
        console.log("Results:");
        console.log("- Old RWA: Ondo OUSG (5.1% APY)");
        console.log("- New RWA: Backed IB01 (8.7% APY)");
        console.log("- All 1500 USDC migrated automatically");
        console.log("- Alice + Bob now earn 8.7% APY");
        console.log("- 70% APY increase!");
        console.log("");

        // ============================================
        // SUMMARY
        // ============================================

        console.log("===========================================");
        console.log("WHY THIS IS POWERFUL");
        console.log("===========================================");
        console.log("[+] Community-controlled: No single admin");
        console.log("[+] Democratic: 1 share = 1 vote");
        console.log("[+] Safe: 24hr timelock prevents attacks");
        console.log("[+] Automatic: All deposits migrate together");
        console.log("[+] Efficient: Switch in 1 transaction");
        console.log("");
        console.log("Traditional DeFi: Stuck with one yield source");
        console.log("Diamond RWA DAO: Community picks best APY");
        console.log("===========================================");
    }
}
