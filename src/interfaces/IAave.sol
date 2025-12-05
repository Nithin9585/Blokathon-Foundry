// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

/**
 * @title IAavePool
 * @notice Minimal interface for Aave V3 Pool
 */
interface IAavePool {
    /**
     * @notice Supplies an `amount` of underlying asset into the reserve
     * @param asset The address of the underlying asset to supply
     * @param amount The amount to be supplied
     * @param onBehalfOf The address that will receive the aTokens
     * @param referralCode Code used to register the integrator
     */
    function supply(
        address asset,
        uint256 amount,
        address onBehalfOf,
        uint16 referralCode
    ) external;

    /**
     * @notice Withdraws an `amount` of underlying asset from the reserve
     * @param asset The address of the underlying asset to withdraw
     * @param amount The underlying amount to be withdrawn
     * @param to The address that will receive the underlying
     * @return The final amount withdrawn
     */
    function withdraw(
        address asset,
        uint256 amount,
        address to
    ) external returns (uint256);
}

/**
 * @title IAToken
 * @notice Minimal interface for Aave aTokens
 */
interface IAToken {
    function balanceOf(address user) external view returns (uint256);
    function scaledBalanceOf(address user) external view returns (uint256);
}
