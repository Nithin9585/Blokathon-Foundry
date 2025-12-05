// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

/**
 * @title IDiamondRWA
 * @notice Interface for the Diamond RWA Yield Engine facet
 * @dev This facet enables single-deposit yield optimization across multiple RWA protocols
 * Key innovation: Users deposit once, admin can upgrade to higher-yielding RWAs via diamondCut
 */
interface IDiamondRWA {
    // ============================================
    // EVENTS
    // ============================================

    /**
     * @notice Emitted when a user deposits USDC into the vault
     * @param user Address of the depositor
     * @param assets Amount of USDC deposited
     * @param shares Amount of vault shares minted to user
     */
    event Deposit(address indexed user, uint256 assets, uint256 shares);

    /**
     * @notice Emitted when a user withdraws from the vault
     * @param user Address of the withdrawer
     * @param shares Amount of vault shares burned
     * @param assets Amount of USDC returned (principal + yield)
     */
    event Withdraw(address indexed user, uint256 shares, uint256 assets);

    /**
     * @notice Emitted when the vault upgrades to a new RWA strategy
     * @param oldRWA Address of the previous RWA token
     * @param newRWA Address of the new RWA token
     * @param newAPY The APY of the new strategy (in basis points, e.g., 510 = 5.1%)
     * @param timestamp When the upgrade occurred
     */
    event StrategyUpgraded(
        address indexed oldRWA,
        address indexed newRWA,
        uint256 newAPY,
        uint256 timestamp
    );

    /**
     * @notice Emitted when a new RWA is added to the whitelist
     * @param rwaToken Address of the RWA token
     * @param name Human-readable name
     */
    event RWAWhitelisted(address indexed rwaToken, string name);

    /**
     * @notice Emitted when an RWA is removed from the whitelist
     * @param rwaToken Address of the RWA token
     */
    event RWARemoved(address indexed rwaToken);

    /**
     * @notice Emitted when vault is paused or unpaused
     * @param isPaused New pause state
     */
    event VaultPauseChanged(bool isPaused);

    // ============================================
    // ERRORS
    // ============================================

    /// @notice Thrown when deposit/withdraw is attempted while vault is paused
    error VaultPaused();

    /// @notice Thrown when deposit amount is below minimum
    error DepositTooSmall(uint256 amount, uint256 minimum);

    /// @notice Thrown when user tries to withdraw more shares than they own
    error InsufficientShares(uint256 requested, uint256 balance);

    /// @notice Thrown when trying to interact with non-whitelisted RWA
    error RWANotWhitelisted(address rwa);

    /// @notice Thrown when trying to whitelist an already whitelisted RWA
    error RWAAlreadyWhitelisted(address rwa);

    /// @notice Thrown when zero address is provided
    error ZeroAddress();

    /// @notice Thrown when zero amount is provided
    error ZeroAmount();

    /// @notice Thrown when vault has no active RWA strategy set
    error NoActiveStrategy();

    // ============================================
    // CORE VAULT FUNCTIONS
    // ============================================

    /**
     * @notice Deposit USDC into the vault and receive shares
     * @dev Transfers USDC from msg.sender, mints shares, deposits into active RWA
     * @param usdcAmount Amount of USDC to deposit (must be >= minDepositAmount)
     * @return shares Amount of vault shares minted
     */
    function deposit(uint256 usdcAmount) external returns (uint256 shares);

    /**
     * @notice Withdraw USDC from the vault by burning shares
     * @dev Burns shares, withdraws from RWA if needed, returns USDC + earned yield
     * @param shares Amount of vault shares to burn
     * @return assets Amount of USDC returned to user
     */
    function withdraw(uint256 shares) external returns (uint256 assets);

    // ============================================
    // VIEW FUNCTIONS
    // ============================================

    /**
     * @notice Get the highest APY available from whitelisted RWAs
     * @dev Queries all active RWAs and returns the best yield
     * @return bestAPY Highest APY in basis points (e.g., 510 = 5.1%)
     * @return bestRWA Address of the RWA offering the highest yield
     */
    function getBestAPY()
        external
        view
        returns (uint256 bestAPY, address bestRWA);

    /**
     * @notice Get the current APY of the active strategy
     * @return apy Current yield in basis points
     */
    function getCurrentAPY() external view returns (uint256 apy);

    /**
     * @notice Schedule an upgrade to a new RWA strategy (V2 governance-controlled)
     * @param newRWA Address of the new RWA token to switch to
     */
    function scheduleUpgrade(address newRWA) external;

    /**
     * @notice Get total value of all assets in the vault
     * @dev ERC4626 standard - includes principal + accrued yield
     * @return total Total USDC value in vault
     */
    function getTotalAssets() external view returns (uint256 total);

    /**
     * @notice Get total shares minted across all users
     * @return total Total shares outstanding
     */
    function getTotalShares() external view returns (uint256 total);

    /**
     * @notice Get a user's share balance
     * @param user Address to query
     * @return balance User's vault share balance
     */
    function getUserShares(
        address user
    ) external view returns (uint256 balance);

    /**
     * @notice Preview how many shares a deposit would receive
     * @param assets Amount of USDC to deposit
     * @return shares Expected shares to be minted
     */
    function previewDeposit(
        uint256 assets
    ) external view returns (uint256 shares);

    /**
     * @notice Preview how much USDC a withdrawal would receive
     * @param shares Amount of shares to burn
     * @return assets Expected USDC to be returned
     */
    function previewWithdraw(
        uint256 shares
    ) external view returns (uint256 assets);

    /**
     * @notice Get the currently active RWA strategy address
     * @return rwa Address of current RWA token
     */
    function getCurrentRWA() external view returns (address rwa);

    /**
     * @notice Get list of all whitelisted RWA addresses
     * @return rwas Array of RWA token addresses
     */
    function getWhitelistedRWAs() external view returns (address[] memory rwas);

    /**
     * @notice Check if an RWA is whitelisted
     * @param rwa Address to check
     * @return isWhitelisted True if whitelisted
     */
    function isRWAWhitelisted(
        address rwa
    ) external view returns (bool isWhitelisted);

    /**
     * @notice Get information about a specific RWA
     * @param rwa Address of the RWA
     * @return name Human-readable name
     * @return tokenAddress Contract address
     * @return isActive Whether it's currently enabled
     * @return addedTimestamp When it was whitelisted
     */
    function getRWAInfo(
        address rwa
    )
        external
        view
        returns (
            string memory name,
            address tokenAddress,
            bool isActive,
            uint256 addedTimestamp
        );

    /**
     * @notice Check if vault is paused
     * @return isPaused True if paused
     */
    function isPaused() external view returns (bool isPaused);

    // ============================================
    // ADMIN FUNCTIONS (Diamond Owner Only)
    // ============================================

    /**
     * @notice Add a new RWA to the whitelist
     * @dev Only callable by Diamond owner
     * @param rwaToken Address of the RWA token contract
     * @param name Human-readable name (e.g., "Ondo OUSG")
     */
    function addRWAToWhitelist(address rwaToken, string calldata name) external;

    /**
     * @notice Remove an RWA from the whitelist
     * @dev Only callable by Diamond owner. Cannot remove if it's the current active RWA.
     * @param rwaToken Address of the RWA to remove
     */
    function removeRWAFromWhitelist(address rwaToken) external;

    /**
     * @notice Upgrade the vault to a new RWA strategy (THE MAGIC SWITCH)
     * @dev Only callable by Diamond owner. This is the core innovation:
     *      - Withdraws all assets from old RWA
     *      - Deposits into new RWA
     *      - All users instantly earn new higher yield
     * @param newRWA Address of the new RWA to upgrade to (must be whitelisted)
     */
    function upgradeToRWA(address newRWA) external;

    /**
     * @notice Pause or unpause the vault
     * @dev Only callable by Diamond owner. Emergency stop mechanism.
     * @param _pause True to pause, false to unpause
     */
    function setPause(bool _pause) external;

    /**
     * @notice Set minimum deposit amount
     * @dev Only callable by Diamond owner
     * @param _minDeposit New minimum deposit in USDC (e.g., 100e6 = $100)
     */
    function setMinDeposit(uint256 _minDeposit) external;

    /**
     * @notice Initialize the vault with USDC address and first RWA
     * @dev Only callable once by Diamond owner during deployment
     * @param _usdcToken Address of USDC on this chain
     * @param _initialRWA First RWA strategy to use
     * @param _rwaName Name of the initial RWA
     */
    function initialize(
        address _usdcToken,
        address _initialRWA,
        string calldata _rwaName
    ) external;
}
