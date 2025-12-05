// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

/**
 * @title IGovernance
 * @author BLOK Capital DAO
 * @notice Interface for DAO governance controlling RWA strategy upgrades
 */
interface IGovernance {
    // ============================================
    // ENUMS
    // ============================================

    enum ProposalState {
        Pending, // Proposal created, voting hasn't started
        Active, // Voting period is active
        Canceled, // Proposal was canceled
        Defeated, // Proposal failed to reach quorum or majority
        Succeeded, // Proposal passed, ready for timelock
        Queued, // Proposal queued in timelock
        Expired, // Timelock expired without execution
        Executed // Proposal executed successfully
    }

    // ============================================
    // STRUCTS
    // ============================================

    struct Proposal {
        uint256 id;
        address proposer;
        address targetRWA; // RWA token to switch to
        string description;
        uint256 forVotes;
        uint256 againstVotes;
        uint256 abstainVotes;
        uint256 startBlock;
        uint256 endBlock;
        uint256 eta; // Execution time (after timelock)
        bool executed;
        bool canceled;
    }

    struct ProposalParams {
        uint256 votingDelay; // Delay before voting starts (blocks)
        uint256 votingPeriod; // Length of voting period (blocks)
        uint256 proposalThreshold; // Min tokens to create proposal
        uint256 quorumVotes; // Min votes needed to pass
        uint256 timelockDelay; // Delay after passing before execution
    }

    // ============================================
    // EVENTS
    // ============================================

    event ProposalCreated(
        uint256 indexed proposalId,
        address indexed proposer,
        address targetRWA,
        uint256 startBlock,
        uint256 endBlock,
        string description
    );

    event VoteCast(
        address indexed voter,
        uint256 indexed proposalId,
        uint8 support,
        uint256 votes,
        string reason
    );

    event ProposalCanceled(uint256 indexed proposalId);
    event ProposalQueued(uint256 indexed proposalId, uint256 eta);
    event ProposalExecuted(uint256 indexed proposalId);

    event ProposalThresholdSet(uint256 oldThreshold, uint256 newThreshold);
    event VotingDelaySet(uint256 oldDelay, uint256 newDelay);
    event VotingPeriodSet(uint256 oldPeriod, uint256 newPeriod);
    event QuorumVotesSet(uint256 oldQuorum, uint256 newQuorum);

    // ============================================
    // ERRORS
    // ============================================

    error NotGovernance();
    error BelowProposalThreshold();
    error ProposalNotActive();
    error ProposalNotSucceeded();
    error ProposalNotQueued();
    error TimelockNotExpired();
    error AlreadyVoted();
    error InvalidVoteType();
    error QuorumNotReached();

    // ============================================
    // EXTERNAL FUNCTIONS
    // ============================================

    /// @notice Create a proposal to upgrade RWA strategy
    /// @param targetRWA Address of the new RWA token
    /// @param description Human-readable proposal description
    /// @return proposalId The ID of the created proposal
    function propose(
        address targetRWA,
        string memory description
    ) external returns (uint256);

    /// @notice Cast a vote on an active proposal
    /// @param proposalId The ID of the proposal
    /// @param support Vote type: 0=against, 1=for, 2=abstain
    function castVote(
        uint256 proposalId,
        uint8 support
    ) external returns (uint256);

    /// @notice Cast a vote with a reason
    function castVoteWithReason(
        uint256 proposalId,
        uint8 support,
        string calldata reason
    ) external returns (uint256);

    /// @notice Queue a successful proposal for execution
    function queue(uint256 proposalId) external returns (uint256);

    /// @notice Execute a queued proposal after timelock
    function execute(uint256 proposalId) external payable returns (uint256);

    /// @notice Cancel a proposal (only proposer or governance)
    function cancel(uint256 proposalId) external;

    /// @notice Get proposal details
    function getProposal(
        uint256 proposalId
    ) external view returns (Proposal memory);

    /// @notice Get current proposal state
    function state(uint256 proposalId) external view returns (ProposalState);

    /// @notice Get voting power of an address at a specific block
    function getVotes(
        address account,
        uint256 blockNumber
    ) external view returns (uint256);

    /// @notice Get governance parameters
    function getProposalParams() external view returns (ProposalParams memory);

    /// @notice Check if account has voted on proposal
    function hasVoted(
        uint256 proposalId,
        address account
    ) external view returns (bool);
}
