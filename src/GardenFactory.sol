// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {Diamond} from "./Diamond.sol";
import {DiamondCutFacet} from "./facets/baseFacets/cut/DiamondCutFacet.sol";
import {IDiamondCut} from "./facets/baseFacets/cut/IDiamondCut.sol";
import {OwnershipFacet} from "./facets/baseFacets/ownership/OwnershipFacet.sol";
import {IERC173} from "./interfaces/IERC173.sol";
import {
    DiamondRWAYieldFacetV2
} from "./facets/utilityFacets/diamondRWA/DiamondRWAYieldFacetV2.sol";
import {
    GovernanceFacet
} from "./facets/utilityFacets/governance/GovernanceFacet.sol";
import {GardenRegistry} from "./GardenRegistry.sol";

/**
 * @title GardenFactory
 * @notice Factory for deploying RWA yield gardens with different risk strategies
 * @dev Each garden is a separate Diamond proxy with preconfigured RWA allocations
 *
 * STRATEGY TYPES:
 * - CONSERVATIVE: T-Bills only (Backed IB01) - Lowest risk, stable returns
 * - BALANCED: Mix of T-Bills + Stablecoins (IB01 + USDY) - Medium risk
 * - AGGRESSIVE: High-yield RWAs (OUSG + STBT) - Higher risk, higher returns
 */
contract GardenFactory {
    // ============================================
    // STORAGE
    // ============================================

    /// @notice Registry tracking all deployed gardens
    GardenRegistry public immutable registry;

    /// @notice Factory owner
    address public owner;

    /// @notice Template facet addresses (deployed once, reused)
    address public diamondCutFacet;
    address public ownershipFacet;
    address public rwaFacet;
    address public governanceFacet;

    /// @notice Strategy configurations
    struct StrategyConfig {
        address primaryRWA; // Main RWA token
        address secondaryRWA; // Optional secondary RWA (0x0 if single-asset)
        uint256 minDeposit; // Minimum deposit amount
        string name; // Strategy name
    }

    mapping(GardenRegistry.StrategyType => StrategyConfig) public strategies;

    /// @notice USDC token address
    address public immutable usdcToken;

    // ============================================
    // EVENTS
    // ============================================

    event GardenDeployed(
        address indexed garden,
        GardenRegistry.StrategyType indexed strategy,
        address indexed deployer
    );

    event FacetTemplatesUpdated(
        address diamondCutFacet,
        address rwaFacet,
        address governanceFacet
    );

    event StrategyConfigured(
        GardenRegistry.StrategyType indexed strategy,
        address primaryRWA,
        address secondaryRWA,
        string name
    );

    // ============================================
    // ERRORS
    // ============================================

    error Unauthorized();
    error ZeroAddress();
    error InvalidStrategy();
    error FacetsNotSet();

    // ============================================
    // MODIFIERS
    // ============================================

    modifier onlyOwner() {
        if (msg.sender != owner) revert Unauthorized();
        _;
    }

    // ============================================
    // CONSTRUCTOR
    // ============================================

    constructor(address _registry, address _usdcToken) {
        if (_registry == address(0) || _usdcToken == address(0))
            revert ZeroAddress();
        registry = GardenRegistry(_registry);
        usdcToken = _usdcToken;
        owner = msg.sender;
    }

    // ============================================
    // SETUP FUNCTIONS
    // ============================================

    /**
     * @notice Set template facet addresses (call once after deploying facets)
     * @param _diamondCutFacet DiamondCutFacet address
     * @param _ownershipFacet OwnershipFacet address
     * @param _rwaFacet DiamondRWAYieldFacetV2 address
     * @param _governanceFacet GovernanceFacet address
     */
    function setFacetTemplates(
        address _diamondCutFacet,
        address _ownershipFacet,
        address _rwaFacet,
        address _governanceFacet
    ) external onlyOwner {
        if (
            _diamondCutFacet == address(0) ||
            _ownershipFacet == address(0) ||
            _rwaFacet == address(0) ||
            _governanceFacet == address(0)
        ) revert ZeroAddress();

        diamondCutFacet = _diamondCutFacet;
        ownershipFacet = _ownershipFacet;
        rwaFacet = _rwaFacet;
        governanceFacet = _governanceFacet;

        emit FacetTemplatesUpdated(
            _diamondCutFacet,
            _rwaFacet,
            _governanceFacet
        );
    }

    /**
     * @notice Configure strategy parameters
     * @param strategy Strategy type
     * @param primaryRWA Main RWA token address
     * @param secondaryRWA Secondary RWA address (0x0 for single-asset)
     * @param minDeposit Minimum deposit amount
     * @param name Strategy display name
     */
    function configureStrategy(
        GardenRegistry.StrategyType strategy,
        address primaryRWA,
        address secondaryRWA,
        uint256 minDeposit,
        string memory name
    ) external onlyOwner {
        if (primaryRWA == address(0)) revert ZeroAddress();

        strategies[strategy] = StrategyConfig({
            primaryRWA: primaryRWA,
            secondaryRWA: secondaryRWA,
            minDeposit: minDeposit,
            name: name
        });

        emit StrategyConfigured(strategy, primaryRWA, secondaryRWA, name);
    }

    // ============================================
    // GARDEN DEPLOYMENT
    // ============================================

    /**
     * @notice Deploy a new garden with specified strategy
     * @param strategy Risk strategy type
     * @param customName Optional custom name (empty string uses default)
     * @return garden Address of deployed Diamond garden
     */
    function deployGarden(
        GardenRegistry.StrategyType strategy,
        string memory customName
    ) external returns (address garden) {
        if (
            diamondCutFacet == address(0) ||
            ownershipFacet == address(0) ||
            rwaFacet == address(0) ||
            governanceFacet == address(0)
        ) revert FacetsNotSet();

        StrategyConfig memory config = strategies[strategy];
        if (config.primaryRWA == address(0)) revert InvalidStrategy();

        // 1. Deploy Diamond with factory as temporary owner (will transfer later)
        IDiamondCut.FacetCut[] memory initialCuts = new IDiamondCut.FacetCut[](
            2
        );

        // Add DiamondCutFacet in constructor
        bytes4[] memory cutSelectors = new bytes4[](1);
        cutSelectors[0] = IDiamondCut.diamondCut.selector;

        initialCuts[0] = IDiamondCut.FacetCut({
            facetAddress: diamondCutFacet,
            action: IDiamondCut.FacetCutAction.Add,
            functionSelectors: cutSelectors
        });

        // Add OwnershipFacet in constructor
        bytes4[] memory ownershipSelectors = new bytes4[](2);
        ownershipSelectors[0] = IERC173.transferOwnership.selector;
        ownershipSelectors[1] = IERC173.owner.selector;

        initialCuts[1] = IDiamondCut.FacetCut({
            facetAddress: ownershipFacet,
            action: IDiamondCut.FacetCutAction.Add,
            functionSelectors: ownershipSelectors
        });

        Diamond diamond = new Diamond(address(this), initialCuts);
        garden = address(diamond);

        // 2. Prepare facet cuts for RWA and Governance facets
        IDiamondCut.FacetCut[] memory cuts = new IDiamondCut.FacetCut[](2);

        // RWA Facet selectors
        bytes4[] memory rwaSelectors = new bytes4[](12);
        rwaSelectors[0] = DiamondRWAYieldFacetV2.initialize.selector;
        rwaSelectors[1] = DiamondRWAYieldFacetV2.deposit.selector;
        rwaSelectors[2] = DiamondRWAYieldFacetV2.withdraw.selector;
        rwaSelectors[3] = DiamondRWAYieldFacetV2.scheduleUpgrade.selector;
        rwaSelectors[4] = DiamondRWAYieldFacetV2
            .executeScheduledUpgrade
            .selector;
        rwaSelectors[5] = DiamondRWAYieldFacetV2
            .cancelScheduledUpgrade
            .selector;
        rwaSelectors[6] = DiamondRWAYieldFacetV2.addRWAToWhitelist.selector;
        rwaSelectors[7] = DiamondRWAYieldFacetV2
            .removeRWAFromWhitelist
            .selector;
        rwaSelectors[8] = DiamondRWAYieldFacetV2.getUserShares.selector;
        rwaSelectors[9] = DiamondRWAYieldFacetV2.getTotalAssets.selector;
        rwaSelectors[10] = DiamondRWAYieldFacetV2.getCurrentAPY.selector;
        rwaSelectors[11] = DiamondRWAYieldFacetV2.getCurrentRWA.selector;

        cuts[0] = IDiamondCut.FacetCut({
            facetAddress: rwaFacet,
            action: IDiamondCut.FacetCutAction.Add,
            functionSelectors: rwaSelectors
        });

        // Governance Facet selectors
        bytes4[] memory govSelectors = new bytes4[](13);
        govSelectors[0] = GovernanceFacet.initializeGovernance.selector;
        govSelectors[1] = GovernanceFacet.propose.selector;
        govSelectors[2] = GovernanceFacet.castVote.selector;
        govSelectors[3] = GovernanceFacet.castVoteWithReason.selector;
        govSelectors[4] = GovernanceFacet.queue.selector;
        govSelectors[5] = GovernanceFacet.execute.selector;
        govSelectors[6] = GovernanceFacet.cancel.selector;
        govSelectors[7] = GovernanceFacet.getProposal.selector;
        govSelectors[8] = GovernanceFacet.state.selector;
        govSelectors[9] = GovernanceFacet.getVotes.selector;
        govSelectors[10] = GovernanceFacet.getProposalParams.selector;
        govSelectors[11] = GovernanceFacet.hasVoted.selector;
        govSelectors[12] = GovernanceFacet.setVotingDelay.selector;

        cuts[1] = IDiamondCut.FacetCut({
            facetAddress: governanceFacet,
            action: IDiamondCut.FacetCutAction.Add,
            functionSelectors: govSelectors
        });

        // 3. Execute diamond cut to add facets
        IDiamondCut(garden).diamondCut(cuts, address(0), "");

        // 4. Initialize RWA facet with strategy-specific config
        DiamondRWAYieldFacetV2(garden).initialize(
            usdcToken,
            config.primaryRWA,
            config.name
        );

        // 5. Initialize governance with standard parameters
        GovernanceFacet(garden).initializeGovernance(
            1, // 1 block voting delay
            50400, // ~7 days voting period
            100 * 1e6, // 100 USDC proposal threshold
            1000 * 1e6, // 1000 USDC quorum
            24 hours // 24hr timelock
        );

        // 6. Whitelist secondary RWA if configured
        if (config.secondaryRWA != address(0)) {
            DiamondRWAYieldFacetV2(garden).addRWAToWhitelist(
                config.secondaryRWA,
                "Secondary RWA"
            );
        }

        // 7. Transfer ownership to deployer
        IERC173(garden).transferOwnership(msg.sender);

        // 8. Register in registry
        string memory gardenName = bytes(customName).length > 0
            ? customName
            : config.name;

        registry.registerGarden(garden, strategy, gardenName);

        emit GardenDeployed(garden, strategy, msg.sender);
    }

    // ============================================
    // VIEW FUNCTIONS
    // ============================================

    /**
     * @notice Get strategy configuration
     * @param strategy Strategy type
     * @return config Strategy configuration
     */
    function getStrategyConfig(
        GardenRegistry.StrategyType strategy
    ) external view returns (StrategyConfig memory) {
        return strategies[strategy];
    }

    /**
     * @notice Check if facet templates are set
     * @return bool True if all templates configured
     */
    function areFacetsSet() external view returns (bool) {
        return
            diamondCutFacet != address(0) &&
            ownershipFacet != address(0) &&
            rwaFacet != address(0) &&
            governanceFacet != address(0);
    }

    // ============================================
    // ADMIN FUNCTIONS
    // ============================================

    /**
     * @notice Transfer ownership
     * @param newOwner New owner address
     */
    function transferOwnership(address newOwner) external onlyOwner {
        if (newOwner == address(0)) revert ZeroAddress();
        owner = newOwner;
    }
}
