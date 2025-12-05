// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {Script, console} from "forge-std/Script.sol";
import {Diamond} from "src/Diamond.sol";
import {IDiamondCut} from "src/facets/baseFacets/cut/IDiamondCut.sol";
import {DiamondCutFacet} from "src/facets/baseFacets/cut/DiamondCutFacet.sol";
import {DiamondLoupeFacet} from "src/facets/baseFacets/loupe/DiamondLoupeFacet.sol";
import {OwnershipFacet} from "src/facets/baseFacets/ownership/OwnershipFacet.sol";
import {DiamondRWAYieldFacet} from "src/facets/utilityFacets/diamondRWA/DiamondRWAYieldFacet.sol";
import {IDiamondRWA} from "src/facets/utilityFacets/diamondRWA/IDiamondRWA.sol";
import {MockRWAToken, MockOndoOUSG, MockOndoUSDY, MockFigureTreasury} from "src/mocks/MockRWAToken.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title FullDemo
 * @notice Complete end-to-end demo script for hackathon presentation
 * @dev This script:
 *      1. Deploys Diamond with all facets
 *      2. Deploys mock RWAs (OUSG 5.1%, USDY 4.8%, Figure 8.7%)
 *      3. Initializes vault with OUSG
 *      4. Simulates user deposit
 *      5. Shows vault earning yield
 *      6. Executes THE MAGIC SWITCH to upgrade to Figure (higher APY)
 *      7. Shows improved yield
 *      
 * Perfect for 30-second hackathon demo video!
 * 
 * Usage:
 *   forge script script/FullDemo.s.sol --broadcast --rpc-url $RPC_URL
 */
contract FullDemo is Script {
    // Contracts
    Diamond public diamond;
    DiamondRWAYieldFacet public rwaFacet;
    MockOndoOUSG public mockOUSG;
    MockOndoUSDY public mockUSDY;
    MockFigureTreasury public mockFigure;
    IERC20 public usdc;

    // Test amounts
    uint256 constant DEPOSIT_AMOUNT = 10000e6; // 10,000 USDC
    uint256 constant WARP_TIME = 365 days; // 1 year

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        console.log("\n====================================================");
        console.log("  DIAMOND RWA YIELD ENGINE - FULL DEMO");
        console.log("  The Magic Switch: Upgrade to Better Yields");
        console.log("====================================================\n");

        console.log("Deployer:", deployer);
        console.log("Chain ID:", block.chainid);
        console.log("");

        vm.startBroadcast(deployerPrivateKey);

        // ============================================
        // PHASE 1: DEPLOYMENT
        // ============================================
        console.log("[PHASE 1] Deploying Diamond & Mock RWAs");
        console.log("------------------------------------------");
        
        _deployDiamond(deployer);
        _deployMockRWAs();
        _addRWAFacet();
        _initializeVault();

        console.log("");
        console.log("[SUCCESS] Deployment complete!");
        console.log("Diamond Address:", address(diamond));
        console.log("");

        // ============================================
        // PHASE 2: INITIAL DEPOSIT
        // ============================================
        console.log("[PHASE 2] User Deposits to Vault");
        console.log("------------------------------------------");
        
        _fundAndDeposit(deployer);

        console.log("");
        console.log("[SUCCESS] Deposit complete!");
        console.log("");

        // ============================================
        // PHASE 3: TIME PASSES (YIELD ACCRUES)
        // ============================================
        console.log("[PHASE 3] Time Passes - Earning 5.1% APY");
        console.log("------------------------------------------");
        
        _simulateTimePass();

        console.log("");
        console.log("[SUCCESS] One year passed!");
        console.log("");

        // ============================================
        // PHASE 4: THE MAGIC SWITCH
        // ============================================
        console.log("[PHASE 4] THE MAGIC SWITCH");
        console.log("==========================================");
        
        _executeUpgrade();

        console.log("");
        console.log("[SUCCESS] Upgraded to 8.7% APY!");
        console.log("");

        // ============================================
        // PHASE 5: FINAL STATE
        // ============================================
        console.log("[PHASE 5] Final Results");
        console.log("------------------------------------------");
        
        _showFinalState();

        vm.stopBroadcast();

        console.log("\n====================================================");
        console.log("  [SUCCESS] Demo Complete!");
        console.log("  Key Achievement: Upgraded yield from 5.1% to 8.7%");
        console.log("  in ONE transaction with ZERO downtime!");
        console.log("====================================================\n");
    }

    // ============================================
    // DEPLOYMENT HELPERS
    // ============================================

    function _deployDiamond(address owner) internal {
        // Deploy base facets
        DiamondCutFacet cutFacet = new DiamondCutFacet();
        DiamondLoupeFacet loupeFacet = new DiamondLoupeFacet();
        OwnershipFacet ownershipFacet = new OwnershipFacet();

        console.log("  Cut Facet:       ", address(cutFacet));
        console.log("  Loupe Facet:     ", address(loupeFacet));
        console.log("  Ownership Facet: ", address(ownershipFacet));

        // Create facet cuts
        IDiamondCut.FacetCut[] memory cuts = new IDiamondCut.FacetCut[](3);
        cuts[0] = _createCutFacetCut(address(cutFacet));
        cuts[1] = _createLoupeFacetCut(address(loupeFacet));
        cuts[2] = _createOwnershipFacetCut(address(ownershipFacet));

        // Deploy Diamond
        diamond = new Diamond(owner, cuts);
        console.log("  Diamond:         ", address(diamond));
    }

    function _deployMockRWAs() internal {
        // Get USDC address (or deploy mock)
        usdc = IERC20(_getUSDCAddress());
        console.log("  USDC:            ", address(usdc));

        // Deploy mock RWAs
        mockOUSG = new MockOndoOUSG(address(usdc));
        mockUSDY = new MockOndoUSDY(address(usdc));
        mockFigure = new MockFigureTreasury(address(usdc));

        console.log("  Mock OUSG:       ", address(mockOUSG), "(5.1% APY)");
        console.log("  Mock USDY:       ", address(mockUSDY), "(4.8% APY)");
        console.log("  Mock Figure:     ", address(mockFigure), "(8.7% APY)");
    }

    function _addRWAFacet() internal {
        rwaFacet = new DiamondRWAYieldFacet();
        console.log("  RWA Facet:       ", address(rwaFacet));

        IDiamondCut.FacetCut[] memory rwaCut = new IDiamondCut.FacetCut[](1);
        rwaCut[0] = _createRWAFacetCut(address(rwaFacet));
        
        IDiamondCut(address(diamond)).diamondCut(rwaCut, address(0), "");
    }

    function _initializeVault() internal {
        IDiamondRWA vault = IDiamondRWA(address(diamond));
        vault.initialize(address(usdc), address(mockOUSG), "Mock Ondo OUSG");
        
        // Whitelist other RWAs
        vault.addRWAToWhitelist(address(mockUSDY), "Mock Ondo USDY");
        vault.addRWAToWhitelist(address(mockFigure), "Mock Figure Treasury");
    }

    // ============================================
    // DEMO FLOW HELPERS
    // ============================================

    function _fundAndDeposit(address user) internal {
        IDiamondRWA vault = IDiamondRWA(address(diamond));

        // Fund user with USDC (mint if mock, or get from somewhere)
        _fundUser(user, DEPOSIT_AMOUNT);

        // Approve and deposit
        usdc.approve(address(diamond), DEPOSIT_AMOUNT);
        uint256 shares = vault.deposit(DEPOSIT_AMOUNT);

        console.log("  Deposited:       ", _formatUSDC(DEPOSIT_AMOUNT));
        console.log("  Shares Received: ", _formatUSDC(shares));
        console.log("  Current APY:      5.1%");
    }

    function _simulateTimePass() internal {
        uint256 timeBefore = block.timestamp;
        vm.warp(block.timestamp + WARP_TIME);
        uint256 timeAfter = block.timestamp;

        console.log("  Time before:     ", timeBefore);
        console.log("  Time after:      ", timeAfter);
        console.log("  Duration:         365 days");
        
        // Fund the mock with yield
        uint256 expectedYield = (DEPOSIT_AMOUNT * 510) / 10000; // 5.1%
        _fundUser(address(this), expectedYield);
        usdc.approve(address(mockOUSG), expectedYield);
        mockOUSG.fundYield(expectedYield);
        
        console.log("  Yield Accrued:   ", _formatUSDC(expectedYield));
    }

    function _executeUpgrade() internal {
        IDiamondRWA vault = IDiamondRWA(address(diamond));

        address oldRWA = vault.getCurrentRWA();
        (string memory oldName,,,) = vault.getRWAInfo(oldRWA);
        uint256 oldAPY = vault.getCurrentAPY();
        
        console.log("  FROM:", oldName);
        console.log("        APY:", _formatAPY(oldAPY));
        console.log("  TO:   Mock Figure Treasury (8.7%)");
        console.log("");
        console.log("  Executing upgradeToRWA()...");

        vault.upgradeToRWA(address(mockFigure));

        (string memory newName,,,) = vault.getRWAInfo(address(mockFigure));
        uint256 newAPY = vault.getCurrentAPY();
        
        console.log("  New RWA:", newName);
        console.log("  New APY:", _formatAPY(newAPY));
        console.log("  APY Increase: +", _formatAPY(newAPY - oldAPY));
    }

    function _showFinalState() internal {
        IDiamondRWA vault = IDiamondRWA(address(diamond));

        uint256 totalAssets = vault.getTotalAssets();
        uint256 totalShares = vault.getTotalShares();
        address currentRWA = vault.getCurrentRWA();
        (string memory name,,,) = vault.getRWAInfo(currentRWA);
        uint256 apy = vault.getCurrentAPY();

        console.log("  Current Strategy:", name);
        console.log("  Current APY:     ", _formatAPY(apy));
        console.log("  Total Assets:    ", _formatUSDC(totalAssets));
        console.log("  Total Shares:    ", _formatUSDC(totalShares));
    }

    // ============================================
    // UTILITY FUNCTIONS
    // ============================================

    function _getUSDCAddress() internal returns (address) {
        // Try to get real USDC, or deploy mock
        if (block.chainid == 42161) {
            // Arbitrum
            return 0xaf88d065e77c8cC2239327C5EDb3A432268e5831;
        } else {
            // Deploy mock USDC for testing
            return address(new MockUSDC());
        }
    }

    function _fundUser(address user, uint256 amount) internal {
        try MockUSDC(address(usdc)).mint(user, amount) {
            // Success - mock USDC
        } catch {
            // Real USDC - would need to get from somewhere
            // For demo, just log
            console.log("  Note: Using real USDC, ensure sufficient balance");
        }
    }

    function _formatUSDC(uint256 amount) internal pure returns (string memory) {
        uint256 whole = amount / 1e6;
        uint256 decimal = (amount % 1e6) / 1e4;
        
        if (decimal == 0) {
            return string(abi.encodePacked(vm.toString(whole), " USDC"));
        } else if (decimal < 10) {
            return string(abi.encodePacked(vm.toString(whole), ".0", vm.toString(decimal), " USDC"));
        } else {
            return string(abi.encodePacked(vm.toString(whole), ".", vm.toString(decimal), " USDC"));
        }
    }

    function _formatAPY(uint256 basisPoints) internal pure returns (string memory) {
        uint256 whole = basisPoints / 100;
        uint256 decimal = basisPoints % 100;
        
        if (decimal == 0) {
            return string(abi.encodePacked(vm.toString(whole), ".0%"));
        } else if (decimal < 10) {
            return string(abi.encodePacked(vm.toString(whole), ".0", vm.toString(decimal), "%"));
        } else {
            return string(abi.encodePacked(vm.toString(whole), ".", vm.toString(decimal), "%"));
        }
    }

    // ============================================
    // FACET CUT HELPERS
    // ============================================

    function _createCutFacetCut(address facet) internal pure returns (IDiamondCut.FacetCut memory) {
        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = IDiamondCut.diamondCut.selector;
        return IDiamondCut.FacetCut({
            facetAddress: facet,
            action: IDiamondCut.FacetCutAction.Add,
            functionSelectors: selectors
        });
    }

    function _createLoupeFacetCut(address facet) internal pure returns (IDiamondCut.FacetCut memory) {
        bytes4[] memory selectors = new bytes4[](4);
        selectors[0] = 0xcdffacc6; // facets()
        selectors[1] = 0x52ef6b2c; // facetFunctionSelectors()
        selectors[2] = 0xadfca15e; // facetAddresses()
        selectors[3] = 0x7a0ed627; // facetAddress()
        return IDiamondCut.FacetCut({
            facetAddress: facet,
            action: IDiamondCut.FacetCutAction.Add,
            functionSelectors: selectors
        });
    }

    function _createOwnershipFacetCut(address facet) internal pure returns (IDiamondCut.FacetCut memory) {
        bytes4[] memory selectors = new bytes4[](2);
        selectors[0] = 0x8da5cb5b; // owner()
        selectors[1] = 0xf2fde38b; // transferOwnership()
        return IDiamondCut.FacetCut({
            facetAddress: facet,
            action: IDiamondCut.FacetCutAction.Add,
            functionSelectors: selectors
        });
    }

    function _createRWAFacetCut(address facet) internal pure returns (IDiamondCut.FacetCut memory) {
        bytes4[] memory selectors = new bytes4[](16);
        selectors[0] = IDiamondRWA.initialize.selector;
        selectors[1] = IDiamondRWA.deposit.selector;
        selectors[2] = IDiamondRWA.withdraw.selector;
        selectors[3] = IDiamondRWA.upgradeToRWA.selector;
        selectors[4] = IDiamondRWA.addRWAToWhitelist.selector;
        selectors[5] = IDiamondRWA.removeRWAFromWhitelist.selector;
        selectors[6] = IDiamondRWA.setPause.selector;
        selectors[7] = IDiamondRWA.setMinDeposit.selector;
        selectors[8] = IDiamondRWA.getTotalAssets.selector;
        selectors[9] = IDiamondRWA.getTotalShares.selector;
        selectors[10] = IDiamondRWA.getUserShares.selector;
        selectors[11] = IDiamondRWA.previewDeposit.selector;
        selectors[12] = IDiamondRWA.previewWithdraw.selector;
        selectors[13] = IDiamondRWA.getCurrentRWA.selector;
        selectors[14] = IDiamondRWA.getWhitelistedRWAs.selector;
        selectors[15] = IDiamondRWA.getRWAInfo.selector;
        
        return IDiamondCut.FacetCut({
            facetAddress: facet,
            action: IDiamondCut.FacetCutAction.Add,
            functionSelectors: selectors
        });
    }
}

// Mock USDC for testing
contract MockUSDC is IERC20 {
    string public name = "USD Coin";
    string public symbol = "USDC";
    uint8 public decimals = 6;
    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
        totalSupply += amount;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        return true;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        allowance[from][msg.sender] -= amount;
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        return true;
    }
}
