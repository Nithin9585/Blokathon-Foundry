// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title MockRWAToken
 * @notice Mock RWA token for testing Diamond RWA Yield vault
 * @dev Simulates a real RWA protocol with:
 *      - Deposit/withdraw functionality
 *      - Configurable APY
 *      - Yield accrual over time
 * Use this for demos and testing before integrating real RWAs
 */
contract MockRWAToken {
    using SafeERC20 for IERC20;

    // ============================================
    // STATE VARIABLES
    // ============================================

    /// @notice Name of this RWA token
    string public name;

    /// @notice USDC token address
    address public immutable usdcToken;

    /// @notice Current APY in basis points (e.g., 510 = 5.1%)
    uint256 public apy;

    /// @notice Total USDC deposited in this RWA
    uint256 public totalAssets;

    /// @notice Total RWA shares minted
    uint256 public totalShares;

    /// @notice User balances (RWA shares)
    mapping(address => uint256) public balances;

    /// @notice Last time yield was accrued
    uint256 public lastAccrualTime;

    // ============================================
    // EVENTS
    // ============================================

    event Deposited(address indexed user, uint256 usdcAmount, uint256 shares);
    event Withdrawn(address indexed user, uint256 shares, uint256 usdcAmount);
    event APYUpdated(uint256 oldAPY, uint256 newAPY);

    // ============================================
    // CONSTRUCTOR
    // ============================================

    /**
     * @notice Create a new mock RWA token
     * @param _name Name of the RWA (e.g., "Mock Ondo OUSG")
     * @param _usdcToken USDC token address
     * @param _initialAPY Starting APY in basis points
     */
    constructor(string memory _name, address _usdcToken, uint256 _initialAPY) {
        name = _name;
        usdcToken = _usdcToken;
        apy = _initialAPY;
        lastAccrualTime = block.timestamp;
    }

    // ============================================
    // CORE FUNCTIONS
    // ============================================

    /**
     * @notice Deposit USDC to receive RWA shares
     * @param amount Amount of USDC to deposit
     * @return shares Amount of RWA shares minted
     */
    function deposit(uint256 amount) external returns (uint256 shares) {
        require(amount > 0, "Amount must be > 0");

        // Accrue yield before calculating shares
        _accrueYield();

        // Calculate shares (1:1 on first deposit, proportional thereafter)
        if (totalShares == 0 || totalAssets == 0) {
            shares = amount;
        } else {
            shares = (amount * totalShares) / totalAssets;
        }

        // Update state
        totalShares += shares;
        totalAssets += amount;
        balances[msg.sender] += shares;

        // Transfer USDC from user
        IERC20(usdcToken).safeTransferFrom(msg.sender, address(this), amount);

        emit Deposited(msg.sender, amount, shares);
    }

    /**
     * @notice Withdraw USDC by redeeming RWA shares
     * @param shareAmount Amount of RWA shares to redeem
     * @return assets Amount of USDC returned
     */
    function withdraw(uint256 shareAmount) external returns (uint256 assets) {
        require(shareAmount > 0, "Amount must be > 0");
        require(balances[msg.sender] >= shareAmount, "Insufficient balance");

        // Accrue yield before calculating assets
        _accrueYield();

        // Calculate USDC value of shares
        assets = (shareAmount * totalAssets) / totalShares;

        // Update state
        totalShares -= shareAmount;
        totalAssets -= assets;
        balances[msg.sender] -= shareAmount;

        // Transfer USDC to user
        IERC20(usdcToken).safeTransfer(msg.sender, assets);

        emit Withdrawn(msg.sender, shareAmount, assets);
    }

    /**
     * @notice Withdraw all shares - convenience function
     * @return assets Amount of USDC returned
     */
    function withdrawAll() external returns (uint256 assets) {
        uint256 shares = balances[msg.sender];
        return this.withdraw(shares);
    }

    // ============================================
    // VIEW FUNCTIONS
    // ============================================

    /**
     * @notice Get RWA share balance of an account
     */
    function balanceOf(address account) external view returns (uint256) {
        return balances[account];
    }

    /**
     * @notice Get current APY
     */
    function currentAPY() external view returns (uint256) {
        return apy;
    }

    /**
     * @notice Preview how much USDC a share amount is worth (includes accrued yield)
     */
    function previewWithdraw(uint256 shareAmount) external view returns (uint256 assets) {
        if (totalShares == 0) return 0;
        
        // Calculate what totalAssets would be after accruing yield
        uint256 projectedAssets = totalAssets;
        if (totalAssets > 0) {
            uint256 timeElapsed = block.timestamp - lastAccrualTime;
            if (timeElapsed > 0) {
                uint256 yieldEarned = (totalAssets * apy * timeElapsed) / (10000 * 365 days);
                projectedAssets += yieldEarned;
            }
        }
        
        return (shareAmount * projectedAssets) / totalShares;
    }

    /**
     * @notice Preview how many shares a USDC deposit would receive
     */
    function previewDeposit(uint256 assetAmount) external view returns (uint256 shares) {
        if (totalShares == 0 || totalAssets == 0) return assetAmount;
        return (assetAmount * totalShares) / totalAssets;
    }

    // ============================================
    // ADMIN FUNCTIONS (for testing)
    // ============================================

    /**
     * @notice Update the APY (for demo purposes)
     * @param newAPY New APY in basis points
     */
    function setAPY(uint256 newAPY) external {
        uint256 oldAPY = apy;
        apy = newAPY;
        emit APYUpdated(oldAPY, newAPY);
    }

    /**
     * @notice Fund the mock with USDC to simulate yield generation
     * @dev In real RWAs, yield comes from bonds/treasuries. This simulates that.
     * @param amount Amount of USDC to add as yield
     */
    function fundYield(uint256 amount) external {
        require(amount > 0, "Amount must be > 0");
        IERC20(usdcToken).safeTransferFrom(msg.sender, address(this), amount);
        // Don't update totalAssets here - yield is added through _accrueYield()
    }

    // ============================================
    // INTERNAL FUNCTIONS
    // ============================================

    /**
     * @notice Accrue yield based on time elapsed and current APY
     * @dev Simulates yield generation: totalAssets increases over time
     */
    function _accrueYield() internal {
        if (totalAssets == 0) {
            lastAccrualTime = block.timestamp;
            return;
        }

        uint256 timeElapsed = block.timestamp - lastAccrualTime;
        if (timeElapsed == 0) return;

        // Calculate yield: (totalAssets * APY * timeElapsed) / (10000 * 365 days)
        // APY is in basis points (5.1% = 510)
        uint256 yieldEarned = (totalAssets * apy * timeElapsed) / (10000 * 365 days);

        totalAssets += yieldEarned;
        lastAccrualTime = block.timestamp;
    }
}

/**
 * @title MockOndoOUSG
 * @notice Mock implementation of Ondo OUSG with ~5.1% APY
 */
contract MockOndoOUSG is MockRWAToken {
    constructor(address _usdcToken) MockRWAToken("Mock Ondo OUSG", _usdcToken, 510) {}
}

/**
 * @title MockOndoUSDY
 * @notice Mock implementation of Ondo USDY with ~4.8% APY
 */
contract MockOndoUSDY is MockRWAToken {
    constructor(address _usdcToken) MockRWAToken("Mock Ondo USDY", _usdcToken, 480) {}
}

/**
 * @title MockFigureTreasury
 * @notice Mock implementation of Figure Markets Treasury with ~8.7% APY
 */
contract MockFigureTreasury is MockRWAToken {
    constructor(address _usdcToken) MockRWAToken("Mock Figure Treasury", _usdcToken, 870) {}
}
