// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {DiamondRWAYieldStorage} from "./DiamondRWAYieldStorage.sol";
import {IDiamondRWA} from "./IDiamondRWA.sol";

/**
 * @title DiamondRWAYieldBase
 * @notice Base contract containing internal logic for Diamond RWA Yield vault
 * @dev Implements core vault mechanics: share calculation, RWA interactions, safety checks
 * Inherits from this contract to reuse vault logic across facets
 */
abstract contract DiamondRWAYieldBase {
    using SafeERC20 for IERC20;

    // ============================================
    // INTERNAL HELPER FUNCTIONS
    // ============================================

    /**
     * @notice Internal deposit logic - mints shares and deposits into RWA
     * @dev Called by public deposit() function after validations
     * @param user Address receiving the shares
     * @param usdcAmount Amount of USDC to deposit
     * @return shares Amount of shares minted
     */
    function _deposit(address user, uint256 usdcAmount) internal returns (uint256 shares) {
        DiamondRWAYieldStorage.Layout storage s = DiamondRWAYieldStorage.layout();

        // Calculate shares based on current vault ratio
        shares = _calculateShares(usdcAmount);

        // Update storage
        s.totalShares += shares;
        s.totalAssets += usdcAmount;
        s.userShares[user] += shares;

        // Transfer USDC from user to vault
        IERC20(s.usdcToken).safeTransferFrom(user, address(this), usdcAmount);

        // Deposit USDC into current RWA strategy
        if (s.currentRWA != address(0)) {
            _interactWithRWA(s.currentRWA, usdcAmount, true);
        }

        emit IDiamondRWA.Deposit(user, usdcAmount, shares);
    }

    /**
     * @notice Internal withdraw logic - burns shares and returns USDC
     * @dev Called by public withdraw() function after validations
     * @param user Address withdrawing
     * @param sharesToBurn Amount of shares to burn
     * @return assets Amount of USDC returned
     */
    function _withdraw(address user, uint256 sharesToBurn) internal returns (uint256 assets) {
        DiamondRWAYieldStorage.Layout storage s = DiamondRWAYieldStorage.layout();

        // Sync vault's totalAssets with actual RWA value to capture accrued yield
        if (s.currentRWA != address(0)) {
            uint256 actualRWAValue = _getRWAValue(s.currentRWA);
            s.totalAssets = actualRWAValue;
        }

        // Calculate USDC value of shares (now includes accrued yield from RWA)
        assets = _calculateAssets(sharesToBurn);

        // Withdraw from RWA BEFORE updating storage (needs current totalAssets for calculation)
        if (s.currentRWA != address(0)) {
            _interactWithRWA(s.currentRWA, assets, false);
        }

        // Update storage AFTER withdrawal
        s.totalShares -= sharesToBurn;
        s.totalAssets -= assets;
        s.userShares[user] -= sharesToBurn;

        // Transfer USDC to user
        IERC20(s.usdcToken).safeTransfer(user, assets);

        emit IDiamondRWA.Withdraw(user, sharesToBurn, assets);
    }

    /**
     * @notice Calculate shares to mint for a given USDC deposit
     * @dev ERC4626 formula: shares = (assets * totalShares) / totalAssets
     *      Special case: First deposit gets 1:1 shares
     * @param assets Amount of USDC being deposited
     * @return shares Amount of shares to mint
     */
    function _calculateShares(uint256 assets) internal view returns (uint256 shares) {
        DiamondRWAYieldStorage.Layout storage s = DiamondRWAYieldStorage.layout();

        if (s.totalShares == 0 || s.totalAssets == 0) {
            // First deposit: 1:1 ratio
            return assets;
        }

        // Subsequent deposits: proportional to vault growth
        // shares = (assets * totalShares) / totalAssets
        shares = (assets * s.totalShares) / s.totalAssets;
    }

    /**
     * @notice Calculate USDC value for a given amount of shares
     * @dev ERC4626 formula: assets = (shares * totalAssets) / totalShares
     * @param shares Amount of shares to convert
     * @return assets USDC value of the shares
     */
    function _calculateAssets(uint256 shares) internal view returns (uint256 assets) {
        DiamondRWAYieldStorage.Layout storage s = DiamondRWAYieldStorage.layout();

        if (s.totalShares == 0) {
            return 0;
        }

        // assets = (shares * totalAssets) / totalShares
        assets = (shares * s.totalAssets) / s.totalShares;
    }

    /**
     * @notice Interact with an RWA token (deposit or withdraw)
     * @dev Handles both deposits and withdrawals to/from RWA protocols
     *      Uses generic IRWAToken interface that works with most RWAs
     * @param rwa Address of the RWA token
     * @param amount Amount of USDC to deposit/withdraw
     * @param isDeposit True for deposit, false for withdraw
     */
    function _interactWithRWA(address rwa, uint256 amount, bool isDeposit) internal {
        DiamondRWAYieldStorage.Layout storage s = DiamondRWAYieldStorage.layout();

        if (isDeposit) {
            // Approve RWA to spend USDC
            IERC20(s.usdcToken).safeIncreaseAllowance(rwa, amount);

            // Deposit USDC into RWA using generic interface
            // Most RWAs implement deposit(uint256) -> uint256 pattern
            (bool success, bytes memory data) = rwa.call(
                abi.encodeWithSignature("deposit(uint256)", amount)
            );
            
            if (!success) {
                // Fallback: Try alternative mint/subscribe patterns
                (success,) = rwa.call(abi.encodeWithSignature("mint(uint256)", amount));
                if (!success) {
                    (success,) = rwa.call(abi.encodeWithSignature("subscribe(uint256)", amount));
                    require(success, "RWA deposit failed");
                }
            }
        } else {
            // For withdrawals, we need to calculate RWA shares to redeem
            // Get vault's RWA balance
            (bool success, bytes memory data) = rwa.call(
                abi.encodeWithSignature("balanceOf(address)", address(this))
            );
            require(success, "Failed to get RWA balance");
            
            uint256 rwaBalance = abi.decode(data, (uint256));
            
            // Calculate proportional shares to withdraw
            // withdrawShares = (amount * rwaBalance) / totalAssets
            uint256 sharesToWithdraw = (amount * rwaBalance) / s.totalAssets;
            
            // Withdraw from RWA
            (success,) = rwa.call(
                abi.encodeWithSignature("withdraw(uint256)", sharesToWithdraw)
            );
            
            if (!success) {
                // Fallback: Try alternative burn/redeem patterns
                (success,) = rwa.call(abi.encodeWithSignature("burn(uint256)", sharesToWithdraw));
                if (!success) {
                    (success,) = rwa.call(abi.encodeWithSignature("redeem(uint256)", sharesToWithdraw));
                    require(success, "RWA withdrawal failed");
                }
            }
        }
    }

    /**
     * @notice Migrate entire vault balance from old RWA to new RWA
     * @dev This is the "magic switch" - upgrades all users to new yield in one transaction
     * @param oldRWA Address of current RWA strategy
     * @param newRWA Address of new RWA strategy
     */
    function _migrateStrategy(address oldRWA, address newRWA) internal {
        DiamondRWAYieldStorage.Layout storage s = DiamondRWAYieldStorage.layout();

        uint256 totalBalance = s.totalAssets;

        // Step 1: Withdraw everything from old RWA
        if (oldRWA != address(0) && totalBalance > 0) {
            _interactWithRWA(oldRWA, totalBalance, false);
        }

        // Step 2: Update current RWA
        s.currentRWA = newRWA;
        s.lastUpgradeTimestamp = block.timestamp;
        s.upgradeCount++;

        // Step 3: Deposit everything into new RWA
        if (newRWA != address(0) && totalBalance > 0) {
            _interactWithRWA(newRWA, totalBalance, true);
        }

        // Get new APY for event (simplified - actual implementation would query RWA)
        uint256 newAPY = _queryRWAYield(newRWA);

        emit IDiamondRWA.StrategyUpgraded(oldRWA, newRWA, newAPY, block.timestamp);
    }

    /**
     * @notice Query the current APY of an RWA token
     * @dev Attempts to call standard currentAPY() function on RWA
     *      Falls back to 0 if RWA doesn't implement this interface
     * @param rwa Address of the RWA token
     * @return apy Current yield in basis points (e.g., 510 = 5.1%)
     */
    function _queryRWAYield(address rwa) internal view returns (uint256 apy) {
        if (rwa == address(0)) return 0;
        
        // Try to call currentAPY() on the RWA
        (bool success, bytes memory data) = rwa.staticcall(
            abi.encodeWithSignature("currentAPY()")
        );
        
        if (success && data.length >= 32) {
            apy = abi.decode(data, (uint256));
        } else {
            // Fallback: Try alternative yield query methods
            (success, data) = rwa.staticcall(abi.encodeWithSignature("yieldRate()"));
            if (success && data.length >= 32) {
                apy = abi.decode(data, (uint256));
            } else {
                (success, data) = rwa.staticcall(abi.encodeWithSignature("apy()"));
                if (success && data.length >= 32) {
                    apy = abi.decode(data, (uint256));
                }
            }
        }
        
        return apy;
    }

    /**
     * @notice Get the current USDC value of vault's holdings in an RWA
     * @dev Queries RWA balance and converts to USDC value
     * @param rwa Address of the RWA
     * @return value Current USDC value
     */
    function _getRWAValue(address rwa) internal view returns (uint256 value) {
        // Get vault's RWA share balance
        (bool success, bytes memory data) = rwa.staticcall(
            abi.encodeWithSignature("balanceOf(address)", address(this))
        );
        
        if (!success || data.length < 32) return 0;
        
        uint256 rwaShares = abi.decode(data, (uint256));
        
        // Try to get USDC value of shares using previewWithdraw
        (success, data) = rwa.staticcall(
            abi.encodeWithSignature("previewWithdraw(uint256)", rwaShares)
        );
        
        if (success && data.length >= 32) {
            value = abi.decode(data, (uint256));
        } else {
            // Fallback: assume 1:1 if preview not available
            value = rwaShares;
        }
    }

    /**
     * @notice Find the highest APY among whitelisted RWAs
     * @dev Queries all active RWAs and returns best option
     * @return bestAPY Highest yield in basis points
     * @return bestRWA Address of RWA with highest yield
     */
    function _getBestAPY() internal view returns (uint256 bestAPY, address bestRWA) {
        DiamondRWAYieldStorage.Layout storage s = DiamondRWAYieldStorage.layout();

        for (uint256 i = 0; i < s.rwaList.length; i++) {
            address rwa = s.rwaList[i];
            
            if (!s.rwaInfo[rwa].isActive) continue;

            uint256 currentAPY = _queryRWAYield(rwa);
            
            if (currentAPY > bestAPY) {
                bestAPY = currentAPY;
                bestRWA = rwa;
            }
        }
    }

    // ============================================
    // VALIDATION HELPERS
    // ============================================

    /**
     * @notice Check if vault is paused and revert if so
     */
    function _requireNotPaused() internal view {
        if (DiamondRWAYieldStorage.layout().isPaused) {
            revert IDiamondRWA.VaultPaused();
        }
    }

    /**
     * @notice Check if deposit meets minimum amount requirement
     */
    function _requireMinimumDeposit(uint256 amount) internal view {
        DiamondRWAYieldStorage.Layout storage s = DiamondRWAYieldStorage.layout();
        if (amount < s.minDepositAmount) {
            revert IDiamondRWA.DepositTooSmall(amount, s.minDepositAmount);
        }
    }

    /**
     * @notice Check if user has sufficient shares
     */
    function _requireSufficientShares(address user, uint256 requested) internal view {
        uint256 balance = DiamondRWAYieldStorage.layout().userShares[user];
        if (requested > balance) {
            revert IDiamondRWA.InsufficientShares(requested, balance);
        }
    }

    /**
     * @notice Check if RWA is whitelisted
     */
    function _requireWhitelisted(address rwa) internal view {
        if (!DiamondRWAYieldStorage.layout().isWhitelisted[rwa]) {
            revert IDiamondRWA.RWANotWhitelisted(rwa);
        }
    }

    /**
     * @notice Check if address is not zero
     */
    function _requireNonZeroAddress(address addr) internal pure {
        if (addr == address(0)) {
            revert IDiamondRWA.ZeroAddress();
        }
    }

    /**
     * @notice Check if amount is not zero
     */
    function _requireNonZeroAmount(uint256 amount) internal pure {
        if (amount == 0) {
            revert IDiamondRWA.ZeroAmount();
        }
    }
}
