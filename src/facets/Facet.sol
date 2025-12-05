//SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/*###############################################################################

    @title Facet
    @author BLOK Capital DAO
    @notice Abstract base contract providing common functionality for all facets
    @dev All facets should inherit from this contract to access the following:
         - Reentrancy protection using ReentrancyGuardUpgradeable
         - Owner-only access control using onlyDiamondOwner modifier
         - Diamond storage pattern to access ownership state

    ▗▄▄▖ ▗▖    ▗▄▖ ▗▖ ▗▖     ▗▄▄▖ ▗▄▖ ▗▄▄▖▗▄▄▄▖▗▄▄▄▖▗▄▖ ▗▖       ▗▄▄▄  ▗▄▖  ▗▄▖ 
    ▐▌ ▐▌▐▌   ▐▌ ▐▌▐▌▗▞▘    ▐▌   ▐▌ ▐▌▐▌ ▐▌ █    █ ▐▌ ▐▌▐▌       ▐▌  █▐▌ ▐▌▐▌ ▐▌
    ▐▛▀▚▖▐▌   ▐▌ ▐▌▐▛▚▖     ▐▌   ▐▛▀▜▌▐▛▀▘  █    █ ▐▛▀▜▌▐▌       ▐▌  █▐▛▀▜▌▐▌ ▐▌
    ▐▙▄▞▘▐▙▄▄▖▝▚▄▞▘▐▌ ▐▌    ▝▚▄▄▖▐▌ ▐▌▐▌  ▗▄█▄▖  █ ▐▌ ▐▌▐▙▄▄▖    ▐▙▄▄▀▐▌ ▐▌▝▚▄▞▘


################################################################################*/

import {
    ReentrancyGuardUpgradeable
} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {
    OwnershipStorage
} from "src/facets/baseFacets/ownership/OwnershipStorage.sol";
import {
    GovernanceStorage
} from "src/facets/utilityFacets/governance/GovernanceStorage.sol";
import {IGovernance} from "src/facets/utilityFacets/governance/IGovernance.sol";

/// @notice Thrown when caller is not the diamond owner
error Diamond_UnauthorizedCaller();

/// @notice Thrown when caller is not governance or proposal execution
error Diamond_NotGovernance();

/// @notice Thrown when a function is called while the garden is connected to an index
error Facet_CannotCallIfConnectedToIndex();

abstract contract Facet is ReentrancyGuardUpgradeable {
    /// @notice Restricts function access to the diamond contract owner
    /// @dev Checks msg.sender against owner stored in OwnershipStorage
    modifier onlyDiamondOwner() {
        if (msg.sender != OwnershipStorage.layout().owner) {
            revert Diamond_UnauthorizedCaller();
        }
        _;
    }

    /// @notice Restricts function access to governance (DAO)
    /// @dev Allows either direct call from Diamond (during proposal execution) or owner (admin override)
    modifier onlyGovernance() {
        if (
            msg.sender != address(this) &&
            msg.sender != OwnershipStorage.layout().owner
        ) {
            revert Diamond_NotGovernance();
        }
        _;
    }

    /// @notice Helper to get contract owner
    function _contractOwner() internal view returns (address) {
        return OwnershipStorage.layout().owner;
    }
}
