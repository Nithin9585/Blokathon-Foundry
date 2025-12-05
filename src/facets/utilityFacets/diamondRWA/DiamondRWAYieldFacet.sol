// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {Facet} from "src/facets/Facet.sol";
import {DiamondRWAYieldBase} from "./DiamondRWAYieldBase.sol";
import {DiamondRWAYieldStorage} from "./DiamondRWAYieldStorage.sol";
import {IDiamondRWA} from "./IDiamondRWA.sol";

/**
 * @title DiamondRWAYieldFacet
 * @notice Main facet for Diamond RWA Yield Engine
 * @dev Implements all external functions from IDiamondRWA interface
 * Uses Diamond Storage pattern to avoid storage collisions
 *
 * The "Magic Switch": Admin can upgrade entire vault to higher-yielding RWA
 * with single transaction - all users benefit instantly without moving funds
 */
contract DiamondRWAYieldFacet is Facet, DiamondRWAYieldBase, IDiamondRWA {
    // ============================================
    // INITIALIZATION
    // ============================================

    /**
     * @notice Initialize the vault (only called once during deployment)
     * @param _usdcToken Address of USDC token on this chain
     * @param _initialRWA First RWA strategy to use
     * @param _rwaName Name of the initial RWA
     */
    function initialize(
        address _usdcToken,
        address _initialRWA,
        string calldata _rwaName
    ) external override onlyDiamondOwner {
        DiamondRWAYieldStorage.Layout storage s = DiamondRWAYieldStorage
            .layout();

        // Ensure not already initialized
        require(s.usdcToken == address(0), "Already initialized");

        _requireNonZeroAddress(_usdcToken);
        _requireNonZeroAddress(_initialRWA);

        // Set USDC token
        s.usdcToken = _usdcToken;

        // Set default minimum deposit (e.g., $10 USDC)
        s.minDepositAmount = 10e6; // 10 USDC (6 decimals)

        // Whitelist and activate initial RWA
        s.isWhitelisted[_initialRWA] = true;
        s.rwaList.push(_initialRWA);
        s.rwaInfo[_initialRWA] = DiamondRWAYieldStorage.RWAInfo({
            name: _rwaName,
            tokenAddress: _initialRWA,
            isActive: true,
            addedTimestamp: block.timestamp
        });

        s.currentRWA = _initialRWA;

        emit RWAWhitelisted(_initialRWA, _rwaName);
    }

    // ============================================
    // CORE VAULT FUNCTIONS
    // ============================================

    /**
     * @notice Deposit USDC into the vault and receive shares
     * @param usdcAmount Amount of USDC to deposit
     * @return shares Amount of vault shares minted
     */
    function deposit(
        uint256 usdcAmount
    ) external override nonReentrant returns (uint256 shares) {
        _requireNotPaused();
        _requireNonZeroAmount(usdcAmount);
        _requireMinimumDeposit(usdcAmount);

        return _deposit(msg.sender, usdcAmount);
    }

    /**
     * @notice Withdraw USDC from the vault by burning shares
     * @param shares Amount of vault shares to burn
     * @return assets Amount of USDC returned
     */
    function withdraw(
        uint256 shares
    ) external override nonReentrant returns (uint256 assets) {
        _requireNotPaused();
        _requireNonZeroAmount(shares);
        _requireSufficientShares(msg.sender, shares);

        return _withdraw(msg.sender, shares);
    }

    // ============================================
    // VIEW FUNCTIONS
    // ============================================

    function getBestAPY()
        external
        view
        override
        returns (uint256 bestAPY, address bestRWA)
    {
        return _getBestAPY();
    }

    function getCurrentAPY() external view override returns (uint256 apy) {
        DiamondRWAYieldStorage.Layout storage s = DiamondRWAYieldStorage
            .layout();
        return _queryRWAYield(s.currentRWA);
    }

    function getTotalAssets() external view override returns (uint256 total) {
        return DiamondRWAYieldStorage.layout().totalAssets;
    }

    function getTotalShares() external view override returns (uint256 total) {
        return DiamondRWAYieldStorage.layout().totalShares;
    }

    function getUserShares(
        address user
    ) external view override returns (uint256 balance) {
        return DiamondRWAYieldStorage.layout().userShares[user];
    }

    function previewDeposit(
        uint256 assets
    ) external view override returns (uint256 shares) {
        return _calculateShares(assets);
    }

    function previewWithdraw(
        uint256 shares
    ) external view override returns (uint256 assets) {
        return _calculateAssets(shares);
    }

    function getCurrentRWA() external view override returns (address rwa) {
        return DiamondRWAYieldStorage.layout().currentRWA;
    }

    function getWhitelistedRWAs()
        external
        view
        override
        returns (address[] memory rwas)
    {
        return DiamondRWAYieldStorage.layout().rwaList;
    }

    function isRWAWhitelisted(
        address rwa
    ) external view override returns (bool isWhitelisted) {
        return DiamondRWAYieldStorage.layout().isWhitelisted[rwa];
    }

    function getRWAInfo(
        address rwa
    )
        external
        view
        override
        returns (
            string memory name,
            address tokenAddress,
            bool isActive,
            uint256 addedTimestamp
        )
    {
        DiamondRWAYieldStorage.RWAInfo memory info = DiamondRWAYieldStorage
            .layout()
            .rwaInfo[rwa];
        return (
            info.name,
            info.tokenAddress,
            info.isActive,
            info.addedTimestamp
        );
    }

    function isPaused() external view override returns (bool) {
        return DiamondRWAYieldStorage.layout().isPaused;
    }

    // ============================================
    // ADMIN FUNCTIONS
    // ============================================

    /**
     * @notice Add a new RWA to the whitelist
     * @param rwaToken Address of the RWA token
     * @param name Human-readable name
     */
    function addRWAToWhitelist(
        address rwaToken,
        string calldata name
    ) external override onlyDiamondOwner {
        _requireNonZeroAddress(rwaToken);

        DiamondRWAYieldStorage.Layout storage s = DiamondRWAYieldStorage
            .layout();

        if (s.isWhitelisted[rwaToken]) {
            revert RWAAlreadyWhitelisted(rwaToken);
        }

        s.isWhitelisted[rwaToken] = true;
        s.rwaList.push(rwaToken);
        s.rwaInfo[rwaToken] = DiamondRWAYieldStorage.RWAInfo({
            name: name,
            tokenAddress: rwaToken,
            isActive: true,
            addedTimestamp: block.timestamp
        });

        emit RWAWhitelisted(rwaToken, name);
    }

    /**
     * @notice Remove an RWA from the whitelist
     * @param rwaToken Address of the RWA to remove
     */
    function removeRWAFromWhitelist(
        address rwaToken
    ) external override onlyDiamondOwner {
        DiamondRWAYieldStorage.Layout storage s = DiamondRWAYieldStorage
            .layout();

        _requireWhitelisted(rwaToken);

        // Cannot remove current active RWA
        require(rwaToken != s.currentRWA, "Cannot remove active RWA");

        s.isWhitelisted[rwaToken] = false;
        s.rwaInfo[rwaToken].isActive = false;

        // Remove from rwaList array
        for (uint256 i = 0; i < s.rwaList.length; i++) {
            if (s.rwaList[i] == rwaToken) {
                s.rwaList[i] = s.rwaList[s.rwaList.length - 1];
                s.rwaList.pop();
                break;
            }
        }

        emit RWARemoved(rwaToken);
    }

    /**
     * @notice Upgrade to a new RWA strategy - THE MAGIC SWITCH
     * @dev This is the core innovation - upgrades entire vault in one transaction
     * @param newRWA Address of the new RWA (must be whitelisted)
     */
    function upgradeToRWA(
        address newRWA
    ) external override onlyDiamondOwner nonReentrant {
        _requireNonZeroAddress(newRWA);
        _requireWhitelisted(newRWA);

        DiamondRWAYieldStorage.Layout storage s = DiamondRWAYieldStorage
            .layout();
        address oldRWA = s.currentRWA;

        require(oldRWA != newRWA, "Already using this RWA");

        // Execute migration
        _migrateStrategy(oldRWA, newRWA);

        emit StrategyUpgraded(
            oldRWA,
            newRWA,
            this.getCurrentAPY(),
            block.timestamp
        );
    }

    /**
     * @notice Schedule upgrade (V1 compatibility stub - calls upgradeToRWA instantly)
     * @dev V1 doesn't have timelock (instant upgrade), V2 has 24hr timelock
     * @param newRWA Address of new RWA token
     */
    function scheduleUpgrade(
        address newRWA
    ) external override onlyDiamondOwner {
        // V1: Instant upgrade (no timelock)
        this.upgradeToRWA(newRWA);
    }

    /**
     * @notice Pause or unpause the vault
     * @param _pause True to pause, false to unpause
     */
    function setPause(bool _pause) external override onlyDiamondOwner {
        DiamondRWAYieldStorage.layout().isPaused = _pause;
        emit VaultPauseChanged(_pause);
    }

    /**
     * @notice Set minimum deposit amount
     * @param _minDeposit New minimum deposit in USDC
     */
    function setMinDeposit(
        uint256 _minDeposit
    ) external override onlyDiamondOwner {
        DiamondRWAYieldStorage.layout().minDepositAmount = _minDeposit;
    }
}
