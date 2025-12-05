// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

/**
 * @title GardenRegistry
 * @notice Tracks all deployed Garden vaults and their strategies
 * @dev Allows users to discover and compare different RWA yield strategies
 */
contract GardenRegistry {
    // ============================================
    // STRUCTS
    // ============================================

    enum StrategyType {
        CONSERVATIVE, // T-Bills only (lowest risk)
        BALANCED, // Mixed RWAs (medium risk)
        AGGRESSIVE // High-yield RWAs (higher risk)
    }

    struct GardenInfo {
        address gardenAddress; // Diamond proxy address
        StrategyType strategy;
        string name;
        uint256 deployedAt;
        bool isActive;
    }

    struct GardenStats {
        address gardenAddress;
        StrategyType strategy;
        string name;
        uint256 tvl; // Total Value Locked in USDC
        uint256 apy; // Current APY in basis points (e.g., 510 = 5.1%)
        uint256 userCount; // Number of depositors
        bool isActive;
    }

    // ============================================
    // STORAGE
    // ============================================

    /// @notice All registered gardens
    address[] public gardens;

    /// @notice Garden info by address
    mapping(address => GardenInfo) public gardenInfo;

    /// @notice Gardens by strategy type
    mapping(StrategyType => address[]) public gardensByStrategy;

    /// @notice Factory contract authorized to register gardens
    address public factory;

    /// @notice Registry owner
    address public owner;

    // ============================================
    // EVENTS
    // ============================================

    event GardenRegistered(
        address indexed garden,
        StrategyType indexed strategy,
        string name
    );

    event GardenDeactivated(address indexed garden);

    event FactoryUpdated(
        address indexed oldFactory,
        address indexed newFactory
    );

    // ============================================
    // ERRORS
    // ============================================

    error Unauthorized();
    error GardenAlreadyRegistered(address garden);
    error GardenNotRegistered(address garden);
    error ZeroAddress();

    // ============================================
    // MODIFIERS
    // ============================================

    modifier onlyOwner() {
        if (msg.sender != owner) revert Unauthorized();
        _;
    }

    modifier onlyFactory() {
        if (msg.sender != factory) revert Unauthorized();
        _;
    }

    // ============================================
    // CONSTRUCTOR
    // ============================================

    constructor(address _factory) {
        if (_factory == address(0)) revert ZeroAddress();
        factory = _factory;
        owner = msg.sender;
    }

    // ============================================
    // FACTORY FUNCTIONS
    // ============================================

    /**
     * @notice Register a new garden (called by factory)
     * @param garden Diamond proxy address
     * @param strategy Strategy type
     * @param name Human-readable name
     */
    function registerGarden(
        address garden,
        StrategyType strategy,
        string memory name
    ) external onlyFactory {
        if (garden == address(0)) revert ZeroAddress();
        if (gardenInfo[garden].gardenAddress != address(0)) {
            revert GardenAlreadyRegistered(garden);
        }

        GardenInfo memory info = GardenInfo({
            gardenAddress: garden,
            strategy: strategy,
            name: name,
            deployedAt: block.timestamp,
            isActive: true
        });

        gardens.push(garden);
        gardenInfo[garden] = info;
        gardensByStrategy[strategy].push(garden);

        emit GardenRegistered(garden, strategy, name);
    }

    // ============================================
    // VIEW FUNCTIONS
    // ============================================

    /**
     * @notice Get all registered gardens
     * @return Array of garden addresses
     */
    function getAllGardens() external view returns (address[] memory) {
        return gardens;
    }

    /**
     * @notice Get gardens by strategy type
     * @param strategy Strategy to filter by
     * @return Array of garden addresses
     */
    function getGardensByStrategy(
        StrategyType strategy
    ) external view returns (address[] memory) {
        return gardensByStrategy[strategy];
    }

    /**
     * @notice Get detailed stats for a garden
     * @param garden Garden address
     * @return stats Garden statistics
     */
    function getGardenStats(
        address garden
    ) external view returns (GardenStats memory stats) {
        GardenInfo memory info = gardenInfo[garden];
        if (info.gardenAddress == address(0)) {
            revert GardenNotRegistered(garden);
        }

        // Call the garden to get live stats
        (bool success, bytes memory data) = garden.staticcall(
            abi.encodeWithSignature("getTotalAssets()")
        );
        uint256 tvl = success ? abi.decode(data, (uint256)) : 0;

        (success, data) = garden.staticcall(
            abi.encodeWithSignature("getCurrentAPY()")
        );
        uint256 apy = success ? abi.decode(data, (uint256)) : 0;

        // Note: userCount not available in V2, set to 0
        uint256 userCount = 0;

        stats = GardenStats({
            gardenAddress: garden,
            strategy: info.strategy,
            name: info.name,
            tvl: tvl,
            apy: apy,
            userCount: userCount,
            isActive: info.isActive
        });
    }

    /**
     * @notice Get stats for all gardens
     * @return Array of garden stats
     */
    function getAllGardenStats() external view returns (GardenStats[] memory) {
        GardenStats[] memory stats = new GardenStats[](gardens.length);

        for (uint256 i = 0; i < gardens.length; i++) {
            GardenInfo memory info = gardenInfo[gardens[i]];

            // Call the garden to get live stats
            (bool success, bytes memory data) = gardens[i].staticcall(
                abi.encodeWithSignature("getTotalAssets()")
            );
            uint256 tvl = success ? abi.decode(data, (uint256)) : 0;

            (success, data) = gardens[i].staticcall(
                abi.encodeWithSignature("getCurrentAPY()")
            );
            uint256 apy = success ? abi.decode(data, (uint256)) : 0;

            // Note: userCount not available in V2, set to 0
            uint256 userCount = 0;

            stats[i] = GardenStats({
                gardenAddress: gardens[i],
                strategy: info.strategy,
                name: info.name,
                tvl: tvl,
                apy: apy,
                userCount: userCount,
                isActive: info.isActive
            });
        }

        return stats;
    }

    /**
     * @notice Get total number of gardens
     * @return count Number of registered gardens
     */
    function getGardenCount() external view returns (uint256) {
        return gardens.length;
    }

    /**
     * @notice Check if a garden is registered
     * @param garden Garden address to check
     * @return bool True if registered
     */
    function isGardenRegistered(address garden) external view returns (bool) {
        return gardenInfo[garden].gardenAddress != address(0);
    }

    // ============================================
    // ADMIN FUNCTIONS
    // ============================================

    /**
     * @notice Deactivate a garden (doesn't remove, just marks inactive)
     * @param garden Garden to deactivate
     */
    function deactivateGarden(address garden) external onlyOwner {
        if (gardenInfo[garden].gardenAddress == address(0)) {
            revert GardenNotRegistered(garden);
        }

        gardenInfo[garden].isActive = false;

        emit GardenDeactivated(garden);
    }

    /**
     * @notice Update factory address
     * @param newFactory New factory address
     */
    function updateFactory(address newFactory) external onlyOwner {
        if (newFactory == address(0)) revert ZeroAddress();
        address oldFactory = factory;
        factory = newFactory;
        emit FactoryUpdated(oldFactory, newFactory);
    }

    /**
     * @notice Transfer ownership
     * @param newOwner New owner address
     */
    function transferOwnership(address newOwner) external onlyOwner {
        if (newOwner == address(0)) revert ZeroAddress();
        owner = newOwner;
    }
}
