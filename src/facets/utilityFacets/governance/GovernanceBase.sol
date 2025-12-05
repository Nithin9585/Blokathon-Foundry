// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {GovernanceStorage} from "./GovernanceStorage.sol";
import {IGovernance} from "./IGovernance.sol";
import {DiamondRWAYieldStorage} from "../diamondRWA/DiamondRWAYieldStorage.sol";

/**
 * @title GovernanceBase
 * @author BLOK Capital DAO
 * @notice Internal logic for DAO governance using vault shares as voting power
 */
abstract contract GovernanceBase {
    using GovernanceStorage for GovernanceStorage.Layout;

    // ============================================
    // INTERNAL VOTING POWER FUNCTIONS
    // ============================================

    /// @notice Get current voting power (uses vault share balance)
    function _getVotes(address account) internal view returns (uint256) {
        DiamondRWAYieldStorage.Layout storage rwa = DiamondRWAYieldStorage
            .layout();
        return rwa.userShares[account];
    }

    /// @notice Get historical voting power at a specific block
    function _getPriorVotes(
        address account,
        uint256 blockNumber
    ) internal view returns (uint256) {
        require(blockNumber < block.number, "Not yet determined");

        GovernanceStorage.Layout storage s = GovernanceStorage.layout();
        uint256 nCheckpoints = s.numCheckpoints[account];

        if (nCheckpoints == 0) {
            return 0;
        }

        // Check most recent checkpoint
        if (s.checkpoints[account][nCheckpoints - 1].fromBlock <= blockNumber) {
            return s.checkpoints[account][nCheckpoints - 1].votes;
        }

        // Check if no voting power at that block
        if (s.checkpoints[account][0].fromBlock > blockNumber) {
            return 0;
        }

        // Binary search
        uint256 lower = 0;
        uint256 upper = nCheckpoints - 1;
        while (upper > lower) {
            uint256 center = upper - (upper - lower) / 2;
            GovernanceStorage.Checkpoint memory cp = s.checkpoints[account][
                center
            ];
            if (cp.fromBlock == blockNumber) {
                return cp.votes;
            } else if (cp.fromBlock < blockNumber) {
                lower = center;
            } else {
                upper = center - 1;
            }
        }
        return s.checkpoints[account][lower].votes;
    }

    /// @notice Write checkpoint when voting power changes
    function _writeCheckpoint(address account, uint256 newVotes) internal {
        GovernanceStorage.Layout storage s = GovernanceStorage.layout();
        uint256 nCheckpoints = s.numCheckpoints[account];

        if (
            nCheckpoints > 0 &&
            s.checkpoints[account][nCheckpoints - 1].fromBlock == block.number
        ) {
            // Update existing checkpoint
            s.checkpoints[account][nCheckpoints - 1].votes = newVotes;
        } else {
            // Create new checkpoint
            s.checkpoints[account][nCheckpoints] = GovernanceStorage
                .Checkpoint({fromBlock: block.number, votes: newVotes});
            s.numCheckpoints[account] = nCheckpoints + 1;
        }
    }

    // ============================================
    // PROPOSAL STATE LOGIC
    // ============================================

    function _state(
        uint256 proposalId
    ) internal view returns (IGovernance.ProposalState) {
        GovernanceStorage.Layout storage s = GovernanceStorage.layout();
        IGovernance.Proposal memory proposal = s.proposals[proposalId];

        if (proposal.canceled) {
            return IGovernance.ProposalState.Canceled;
        } else if (block.number <= proposal.startBlock) {
            return IGovernance.ProposalState.Pending;
        } else if (block.number <= proposal.endBlock) {
            return IGovernance.ProposalState.Active;
        } else if (
            proposal.forVotes <= proposal.againstVotes ||
            proposal.forVotes < s.quorumVotes
        ) {
            return IGovernance.ProposalState.Defeated;
        } else if (proposal.eta == 0) {
            return IGovernance.ProposalState.Succeeded;
        } else if (proposal.executed) {
            return IGovernance.ProposalState.Executed;
        } else if (block.timestamp >= proposal.eta + 7 days) {
            return IGovernance.ProposalState.Expired;
        } else {
            return IGovernance.ProposalState.Queued;
        }
    }

    // ============================================
    // PROPOSAL CREATION
    // ============================================

    function _propose(
        address proposer,
        address targetRWA,
        string memory description
    ) internal returns (uint256) {
        GovernanceStorage.Layout storage s = GovernanceStorage.layout();

        require(
            _getVotes(proposer) >= s.proposalThreshold,
            "Below proposal threshold"
        );

        uint256 proposalId = ++s.proposalCount;

        IGovernance.Proposal storage newProposal = s.proposals[proposalId];
        newProposal.id = proposalId;
        newProposal.proposer = proposer;
        newProposal.targetRWA = targetRWA;
        newProposal.description = description;
        newProposal.startBlock = block.number + s.votingDelay;
        newProposal.endBlock = newProposal.startBlock + s.votingPeriod;

        return proposalId;
    }

    // ============================================
    // VOTING
    // ============================================

    function _castVote(
        address voter,
        uint256 proposalId,
        uint8 support
    ) internal returns (uint256) {
        GovernanceStorage.Layout storage s = GovernanceStorage.layout();

        require(
            _state(proposalId) == IGovernance.ProposalState.Active,
            "Voting is closed"
        );
        require(support <= 2, "Invalid vote type");

        IGovernance.Proposal storage proposal = s.proposals[proposalId];
        GovernanceStorage.VoteReceipt storage receipt = s.receipts[proposalId][
            voter
        ];

        require(!receipt.hasVoted, "Already voted");

        uint256 votes = _getPriorVotes(voter, proposal.startBlock);

        if (support == 0) {
            proposal.againstVotes += votes;
        } else if (support == 1) {
            proposal.forVotes += votes;
        } else {
            proposal.abstainVotes += votes;
        }

        receipt.hasVoted = true;
        receipt.support = support;
        receipt.votes = votes;

        return votes;
    }

    // ============================================
    // QUEUE & EXECUTE
    // ============================================

    function _queue(uint256 proposalId) internal returns (uint256) {
        GovernanceStorage.Layout storage s = GovernanceStorage.layout();

        require(
            _state(proposalId) == IGovernance.ProposalState.Succeeded,
            "Proposal not succeeded"
        );

        uint256 eta = block.timestamp + s.timelockDelay;
        s.proposals[proposalId].eta = eta;

        return eta;
    }

    function _execute(uint256 proposalId) internal returns (uint256) {
        GovernanceStorage.Layout storage s = GovernanceStorage.layout();
        IGovernance.Proposal storage proposal = s.proposals[proposalId];

        require(
            _state(proposalId) == IGovernance.ProposalState.Queued,
            "Not queued"
        );
        require(block.timestamp >= proposal.eta, "Timelock not expired");
        require(block.timestamp <= proposal.eta + 7 days, "Proposal expired");

        proposal.executed = true;

        return proposalId;
    }

    function _cancel(uint256 proposalId) internal {
        GovernanceStorage.Layout storage s = GovernanceStorage.layout();
        IGovernance.ProposalState state = _state(proposalId);

        require(
            state != IGovernance.ProposalState.Executed,
            "Cannot cancel executed proposal"
        );

        s.proposals[proposalId].canceled = true;
    }

    // ============================================
    // HELPER FUNCTIONS
    // ============================================

    function _msgSender() internal view returns (address) {
        return msg.sender;
    }
}
