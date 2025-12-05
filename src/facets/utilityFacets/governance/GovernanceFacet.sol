// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {Facet} from "src/facets/Facet.sol";
import {GovernanceBase} from "./GovernanceBase.sol";
import {GovernanceStorage} from "./GovernanceStorage.sol";
import {IGovernance} from "./IGovernance.sol";
import {IDiamondRWA} from "../diamondRWA/IDiamondRWA.sol";

/**
 * @title GovernanceFacet
 * @author BLOK Capital DAO
 * @notice DAO governance facet that controls RWA strategy upgrades via token voting
 * @dev Voting power = vault share balance (1 share = 1 vote)
 *
 * GOVERNANCE FLOW:
 * 1. User with enough shares creates proposal → propose(newRWA, "Switch to Backed IB01")
 * 2. Voting period opens (7 days) → castVote(proposalId, 1) // 1=for, 0=against, 2=abstain
 * 3. If passed (quorum + majority) → queue(proposalId) // Starts 24hr timelock
 * 4. After timelock → execute(proposalId) // Upgrades to new RWA
 */
contract GovernanceFacet is Facet, GovernanceBase, IGovernance {
    // ============================================
    // INITIALIZATION
    // ============================================

    /// @notice Initialize governance parameters (call once after deployment)
    function initializeGovernance(
        uint256 _votingDelay,
        uint256 _votingPeriod,
        uint256 _proposalThreshold,
        uint256 _quorumVotes,
        uint256 _timelockDelay
    ) external onlyDiamondOwner {
        GovernanceStorage.Layout storage s = GovernanceStorage.layout();

        s.votingDelay = _votingDelay;
        s.votingPeriod = _votingPeriod;
        s.proposalThreshold = _proposalThreshold;
        s.quorumVotes = _quorumVotes;
        s.timelockDelay = _timelockDelay;
    }

    // ============================================
    // PROPOSAL CREATION
    // ============================================

    /// @inheritdoc IGovernance
    function propose(
        address targetRWA,
        string memory description
    ) external override returns (uint256) {
        uint256 proposalId = _propose(msg.sender, targetRWA, description);

        GovernanceStorage.Layout storage s = GovernanceStorage.layout();
        IGovernance.Proposal memory proposal = s.proposals[proposalId];

        emit ProposalCreated(
            proposalId,
            msg.sender,
            targetRWA,
            proposal.startBlock,
            proposal.endBlock,
            description
        );

        return proposalId;
    }

    // ============================================
    // VOTING
    // ============================================

    /// @inheritdoc IGovernance
    function castVote(
        uint256 proposalId,
        uint8 support
    ) external override returns (uint256) {
        return castVoteWithReason(proposalId, support, "");
    }

    /// @inheritdoc IGovernance
    function castVoteWithReason(
        uint256 proposalId,
        uint8 support,
        string memory reason
    ) public override returns (uint256) {
        uint256 votes = _castVote(msg.sender, proposalId, support);

        emit VoteCast(msg.sender, proposalId, support, votes, reason);

        return votes;
    }

    // ============================================
    // EXECUTION
    // ============================================

    /// @inheritdoc IGovernance
    function queue(uint256 proposalId) external override returns (uint256) {
        uint256 eta = _queue(proposalId);

        emit ProposalQueued(proposalId, eta);

        return eta;
    }

    /// @inheritdoc IGovernance
    function execute(
        uint256 proposalId
    ) external payable override returns (uint256) {
        _execute(proposalId);

        GovernanceStorage.Layout storage s = GovernanceStorage.layout();
        IGovernance.Proposal memory proposal = s.proposals[proposalId];

        // Execute the RWA upgrade through the Diamond
        IDiamondRWA(address(this)).upgradeToRWA(proposal.targetRWA);

        emit ProposalExecuted(proposalId);

        return proposalId;
    }

    /// @inheritdoc IGovernance
    function cancel(uint256 proposalId) external override {
        GovernanceStorage.Layout storage s = GovernanceStorage.layout();
        IGovernance.Proposal memory proposal = s.proposals[proposalId];

        require(
            msg.sender == proposal.proposer ||
                _hasRole(msg.sender, "GOVERNANCE_ADMIN"),
            "Not authorized"
        );

        _cancel(proposalId);

        emit ProposalCanceled(proposalId);
    }

    // ============================================
    // VIEW FUNCTIONS
    // ============================================

    /// @inheritdoc IGovernance
    function getProposal(
        uint256 proposalId
    ) external view override returns (IGovernance.Proposal memory) {
        GovernanceStorage.Layout storage s = GovernanceStorage.layout();
        return s.proposals[proposalId];
    }

    /// @inheritdoc IGovernance
    function state(
        uint256 proposalId
    ) external view override returns (IGovernance.ProposalState) {
        return _state(proposalId);
    }

    /// @inheritdoc IGovernance
    function getVotes(
        address account,
        uint256 blockNumber
    ) external view override returns (uint256) {
        if (blockNumber >= block.number) {
            return _getVotes(account);
        }
        return _getPriorVotes(account, blockNumber);
    }

    /// @inheritdoc IGovernance
    function getProposalParams()
        external
        view
        override
        returns (IGovernance.ProposalParams memory)
    {
        GovernanceStorage.Layout storage s = GovernanceStorage.layout();
        return
            IGovernance.ProposalParams({
                votingDelay: s.votingDelay,
                votingPeriod: s.votingPeriod,
                proposalThreshold: s.proposalThreshold,
                quorumVotes: s.quorumVotes,
                timelockDelay: s.timelockDelay
            });
    }

    /// @inheritdoc IGovernance
    function hasVoted(
        uint256 proposalId,
        address account
    ) external view override returns (bool) {
        GovernanceStorage.Layout storage s = GovernanceStorage.layout();
        return s.receipts[proposalId][account].hasVoted;
    }

    // ============================================
    // ADMIN FUNCTIONS
    // ============================================

    function setVotingDelay(uint256 newDelay) external onlyDiamondOwner {
        GovernanceStorage.Layout storage s = GovernanceStorage.layout();
        uint256 oldDelay = s.votingDelay;
        s.votingDelay = newDelay;
        emit VotingDelaySet(oldDelay, newDelay);
    }

    function setVotingPeriod(uint256 newPeriod) external onlyDiamondOwner {
        GovernanceStorage.Layout storage s = GovernanceStorage.layout();
        uint256 oldPeriod = s.votingPeriod;
        s.votingPeriod = newPeriod;
        emit VotingPeriodSet(oldPeriod, newPeriod);
    }

    function setProposalThreshold(
        uint256 newThreshold
    ) external onlyDiamondOwner {
        GovernanceStorage.Layout storage s = GovernanceStorage.layout();
        uint256 oldThreshold = s.proposalThreshold;
        s.proposalThreshold = newThreshold;
        emit ProposalThresholdSet(oldThreshold, newThreshold);
    }

    function setQuorumVotes(uint256 newQuorum) external onlyDiamondOwner {
        GovernanceStorage.Layout storage s = GovernanceStorage.layout();
        uint256 oldQuorum = s.quorumVotes;
        s.quorumVotes = newQuorum;
        emit QuorumVotesSet(oldQuorum, newQuorum);
    }

    // ============================================
    // HELPER FUNCTIONS
    // ============================================

    function _hasRole(
        address account,
        string memory roleString
    ) internal view returns (bool) {
        return account == _contractOwner();
    }
}
