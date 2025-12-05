// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {IGovernance} from "./IGovernance.sol";

/**
 * @title GovernanceStorage
 * @author BLOK Capital DAO
 * @notice Storage for DAO governance system
 */
library GovernanceStorage {
    bytes32 constant DIAMOND_STORAGE_POSITION =
        keccak256("diamond.governance.storage");

    struct Layout {
        // Proposal tracking
        mapping(uint256 => IGovernance.Proposal) proposals;
        uint256 proposalCount;
        // Voting records
        mapping(uint256 => mapping(address => VoteReceipt)) receipts;
        // Governance parameters
        uint256 votingDelay; // Blocks to wait before voting starts (e.g., 1 = ~12 seconds)
        uint256 votingPeriod; // Blocks voting is open (e.g., 50400 = ~7 days)
        uint256 proposalThreshold; // Min voting power to create proposal
        uint256 quorumVotes; // Min votes needed to pass
        uint256 timelockDelay; // Seconds to wait before execution (e.g., 86400 = 1 day)
        // Voting power snapshots (uses vault share balances)
        mapping(address => mapping(uint256 => Checkpoint)) checkpoints;
        mapping(address => uint256) numCheckpoints;
    }

    struct VoteReceipt {
        bool hasVoted;
        uint8 support; // 0=against, 1=for, 2=abstain
        uint256 votes;
    }

    struct Checkpoint {
        uint256 fromBlock;
        uint256 votes;
    }

    function layout() internal pure returns (Layout storage l) {
        bytes32 slot = DIAMOND_STORAGE_POSITION;
        assembly {
            l.slot := slot
        }
    }
}
