// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

/**
 * @title DiamondRWAYieldStorage
 * @notice Storage library for Diamond RWA Yield Engine
 * @dev Uses Diamond Storage pattern to avoid storage collisions
 * All storage for the RWA yield vault is namespaced under a unique position
 */
library DiamondRWAYieldStorage {
    /// @notice Storage position calculated as keccak256("diamond.rwa.yield.storage")
    /// @dev This ensures storage doesn't collide with other facets
    bytes32 constant STORAGE_POSITION = keccak256("diamond.rwa.yield.storage");

    /**
     * @notice Information about a whitelisted RWA token
     * @param name Human-readable name (e.g., "Ondo OUSG")
     * @param tokenAddress Contract address of the RWA token
     * @param isActive Whether this RWA is currently enabled
     * @param addedTimestamp When this RWA was whitelisted
     */
    struct RWAInfo {
        string name;
        address tokenAddress;
        bool isActive;
        uint256 addedTimestamp;
    }

    /**
     * @notice Main storage layout for the Diamond RWA Yield vault
     * @dev This struct contains all state variables for the vault
     */
    struct Layout {
        // ===== Core Vault State =====
        
        /// @notice Total shares minted across all users (ERC4626 style)
        uint256 totalShares;
        
        /// @notice Total USDC deposited in the vault (principal + earned yield)
        uint256 totalAssets;
        
        /// @notice Address of USDC token (0xaf88d065e77c8cC2239327C5EDb3A432268e5831 on Arbitrum)
        address usdcToken;
        
        /// @notice Address of the currently active RWA strategy
        address currentRWA;
        
        // ===== User Accounting =====
        
        /// @notice Maps user address to their share balance
        mapping(address => uint256) userShares;
        
        // ===== RWA Management =====
        
        /// @notice List of all whitelisted RWA addresses
        address[] rwaList;
        
        /// @notice Maps RWA address to its information
        mapping(address => RWAInfo) rwaInfo;
        
        /// @notice Quick lookup: is this address a whitelisted RWA?
        mapping(address => bool) isWhitelisted;
        
        // ===== Configuration & Limits =====
        
        /// @notice Minimum deposit amount (to prevent dust attacks)
        uint256 minDepositAmount;
        
        /// @notice Flag to pause deposits/withdrawals in emergency
        bool isPaused;
        
        /// @notice Last time the strategy was upgraded (for analytics)
        uint256 lastUpgradeTimestamp;
        
        /// @notice Total number of strategy upgrades performed
        uint256 upgradeCount;
    }

    /**
     * @notice Returns the storage layout position
     * @dev This is the Diamond Storage pattern accessor function
     * @return l Storage reference to the Layout struct
     */
    function layout() internal pure returns (Layout storage l) {
        bytes32 position = STORAGE_POSITION;
        assembly {
            l.slot := position
        }
    }
}
