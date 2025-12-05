// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {Diamond} from "src/Diamond.sol";
import {IDiamondCut} from "src/facets/baseFacets/cut/IDiamondCut.sol";
import {
    GovernanceFacet
} from "src/facets/utilityFacets/governance/GovernanceFacet.sol";

/**
 * @title DeployGovernance
 * @notice Script to add DAO governance to existing Diamond RWA vault
 * @dev This upgrades the Diamond to enable community-controlled RWA strategy upgrades
 *
 * USAGE:
 * forge script script/DeployGovernance.s.sol:DeployGovernance --rpc-url <RPC_URL> --broadcast
 *
 * GOVERNANCE PARAMETERS (adjust before deployment):
 * - votingDelay: 1 block (~12 seconds) - Time before voting starts
 * - votingPeriod: 50400 blocks (~7 days) - Duration of voting
 * - proposalThreshold: 100e6 (100 USDC worth of shares) - Min to create proposal
 * - quorumVotes: 1000e6 (1000 USDC worth) - Min votes to pass
 * - timelockDelay: 86400 seconds (24 hours) - Delay before execution
 */
contract DeployGovernance is Script {
    // ============================================
    // GOVERNANCE PARAMETERS (CUSTOMIZE THESE)
    // ============================================

    uint256 constant VOTING_DELAY = 1; // 1 block (~12 sec delay before voting)
    uint256 constant VOTING_PERIOD = 50400; // ~7 days (assuming 12 sec blocks)
    uint256 constant PROPOSAL_THRESHOLD = 100e6; // 100 USDC worth of shares needed to propose
    uint256 constant QUORUM_VOTES = 1000e6; // 1000 USDC worth of votes needed to pass
    uint256 constant TIMELOCK_DELAY = 86400; // 24 hours before execution

    // ============================================
    // DEPLOYMENT
    // ============================================

    function run() external {
        // Get deployer private key from environment
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        // Get existing Diamond address (set in .env or replace here)
        address diamondAddress = vm.envAddress("DIAMOND_ADDRESS");

        console.log("===========================================");
        console.log("DEPLOYING DAO GOVERNANCE");
        console.log("===========================================");
        console.log("Deployer:", deployer);
        console.log("Diamond:", diamondAddress);
        console.log("");

        vm.startBroadcast(deployerPrivateKey);

        // Step 1: Deploy GovernanceFacet
        console.log("Step 1: Deploying GovernanceFacet...");
        GovernanceFacet governanceFacet = new GovernanceFacet();
        console.log("GovernanceFacet deployed at:", address(governanceFacet));
        console.log("");

        // Step 2: Prepare Diamond Cut
        console.log("Step 2: Adding GovernanceFacet to Diamond...");

        IDiamondCut.FacetCut[] memory cut = new IDiamondCut.FacetCut[](1);

        bytes4[] memory governanceSelectors = new bytes4[](13);
        governanceSelectors[0] = GovernanceFacet.initializeGovernance.selector;
        governanceSelectors[1] = GovernanceFacet.propose.selector;
        governanceSelectors[2] = GovernanceFacet.castVote.selector;
        governanceSelectors[3] = GovernanceFacet.castVoteWithReason.selector;
        governanceSelectors[4] = GovernanceFacet.queue.selector;
        governanceSelectors[5] = GovernanceFacet.execute.selector;
        governanceSelectors[6] = GovernanceFacet.cancel.selector;
        governanceSelectors[7] = GovernanceFacet.getProposal.selector;
        governanceSelectors[8] = GovernanceFacet.state.selector;
        governanceSelectors[9] = GovernanceFacet.getVotes.selector;
        governanceSelectors[10] = GovernanceFacet.getProposalParams.selector;
        governanceSelectors[11] = GovernanceFacet.hasVoted.selector;
        governanceSelectors[12] = GovernanceFacet.setVotingDelay.selector;

        cut[0] = IDiamondCut.FacetCut({
            facetAddress: address(governanceFacet),
            action: IDiamondCut.FacetCutAction.Add,
            functionSelectors: governanceSelectors
        });

        IDiamondCut(diamondAddress).diamondCut(cut, address(0), "");
        console.log("GovernanceFacet added to Diamond");
        console.log("");

        // Step 3: Initialize Governance
        console.log("Step 3: Initializing governance parameters...");
        GovernanceFacet(diamondAddress).initializeGovernance(
            VOTING_DELAY,
            VOTING_PERIOD,
            PROPOSAL_THRESHOLD,
            QUORUM_VOTES,
            TIMELOCK_DELAY
        );

        vm.stopBroadcast();

        // ============================================
        // DEPLOYMENT SUMMARY
        // ============================================

        console.log("");
        console.log("===========================================");
        console.log("GOVERNANCE DEPLOYED SUCCESSFULLY!");
        console.log("===========================================");
        console.log("Diamond Address:", diamondAddress);
        console.log("GovernanceFacet:", address(governanceFacet));
        console.log("");
        console.log("Governance Parameters:");
        console.log("- Voting Delay:", VOTING_DELAY, "blocks (~12 seconds)");
        console.log("- Voting Period:", VOTING_PERIOD, "blocks (~7 days)");
        console.log("- Proposal Threshold:", PROPOSAL_THRESHOLD / 1e6, "USDC");
        console.log("- Quorum Votes:", QUORUM_VOTES / 1e6, "USDC");
        console.log("- Timelock Delay:", TIMELOCK_DELAY / 3600, "hours");
        console.log("");
        console.log("===========================================");
        console.log("NEXT STEPS:");
        console.log("===========================================");
        console.log("1. Test proposal creation:");
        console.log("   GovernanceFacet(diamond).propose(newRWA, description)");
        console.log("");
        console.log("2. Vote on proposal:");
        console.log("   GovernanceFacet(diamond).castVote(proposalId, 1)");
        console.log("");
        console.log("3. After voting ends, queue it:");
        console.log("   GovernanceFacet(diamond).queue(proposalId)");
        console.log("");
        console.log("4. After timelock, execute:");
        console.log("   GovernanceFacet(diamond).execute(proposalId)");
        console.log("===========================================");
    }
}
