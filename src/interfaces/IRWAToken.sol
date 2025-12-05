// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

/**
 * @title IRWAToken
 * @notice Generic interface for Real World Asset (RWA) tokens
 * @dev Standardized interface to interact with various RWA protocols
 * Different RWAs may implement different interfaces - this provides a common abstraction
 */
interface IRWAToken {
    /**
     * @notice Deposit USDC to receive RWA tokens
     * @param amount Amount of USDC to deposit
     * @return shares Amount of RWA tokens received
     */
    function deposit(uint256 amount) external returns (uint256 shares);

    /**
     * @notice Withdraw USDC by redeeming RWA tokens
     * @param amount Amount of RWA tokens to redeem
     * @return assets Amount of USDC received
     */
    function withdraw(uint256 amount) external returns (uint256 assets);

    /**
     * @notice Get RWA token balance of an address
     * @param account Address to query
     * @return balance RWA token balance
     */
    function balanceOf(address account) external view returns (uint256 balance);

    /**
     * @notice Get current Annual Percentage Yield
     * @dev APY in basis points (e.g., 510 = 5.1%)
     * @return apy Current yield rate
     */
    function currentAPY() external view returns (uint256 apy);

    /**
     * @notice Get total assets under management
     * @return total Total USDC value in the RWA
     */
    function totalAssets() external view returns (uint256 total);
}

/**
 * @title IOndoOUSG
 * @notice Interface for Ondo Finance OUSG (Short-Term US Government Treasuries)
 * @dev Specific interface for Ondo's OUSG token
 */
interface IOndoOUSG {
    /**
     * @notice Subscribe (mint) OUSG tokens with USDC
     * @param usdcAmount Amount of USDC to invest
     */
    function subscribe(uint256 usdcAmount) external;

    /**
     * @notice Redeem OUSG tokens for USDC
     * @param ousgAmount Amount of OUSG to redeem
     */
    function redeem(uint256 ousgAmount) external;

    /**
     * @notice Get OUSG balance
     */
    function balanceOf(address account) external view returns (uint256);

    /**
     * @notice Get USDC value of OUSG tokens
     * @param ousgAmount Amount of OUSG
     * @return usdcValue Equivalent USDC value
     */
    function getUSDCValue(uint256 ousgAmount) external view returns (uint256 usdcValue);
}

/**
 * @title IOndoUSDY
 * @notice Interface for Ondo Finance USDY (US Dollar Yield)
 * @dev Specific interface for Ondo's USDY stablecoin
 */
interface IOndoUSDY {
    /**
     * @notice Mint USDY with USDC
     * @param usdcAmount Amount of USDC to deposit
     */
    function mint(uint256 usdcAmount) external;

    /**
     * @notice Burn USDY to receive USDC
     * @param usdyAmount Amount of USDY to burn
     */
    function burn(uint256 usdyAmount) external;

    /**
     * @notice Get USDY balance
     */
    function balanceOf(address account) external view returns (uint256);

    /**
     * @notice Get current yield rate
     */
    function yieldRate() external view returns (uint256);
}

/**
 * @title ICentrifugePool
 * @notice Interface for Centrifuge RWA pools
 * @dev Centrifuge uses Tinlake/Centrifuge Chain for RWA lending
 */
interface ICentrifugePool {
    /**
     * @notice Supply stablecoins to the pool
     * @param amount Amount to supply
     */
    function supplyOrder(uint256 amount) external;

    /**
     * @notice Redeem investment tokens for stablecoins
     * @param amount Amount to redeem
     */
    function redeemOrder(uint256 amount) external;

    /**
     * @notice Get investment token balance
     */
    function balanceOf(address account) external view returns (uint256);

    /**
     * @notice Get pool APY
     */
    function poolAPY() external view returns (uint256);
}

/**
 * @title IBackedToken
 * @notice Interface for Backed Finance tokenized securities
 * @dev Backed provides tokenized ETFs and bonds (e.g., bIB01 = Blackrock IB01)
 */
interface IBackedToken {
    /**
     * @notice Mint backed tokens with USDC
     * @param usdcAmount Amount of USDC
     */
    function mint(uint256 usdcAmount) external;

    /**
     * @notice Redeem backed tokens for USDC
     * @param tokenAmount Amount of tokens to redeem
     */
    function redeem(uint256 tokenAmount) external;

    /**
     * @notice Get token balance
     */
    function balanceOf(address account) external view returns (uint256);

    /**
     * @notice Get underlying asset value
     */
    function netAssetValue() external view returns (uint256);
}
