// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

/**
 * @title Constants
 * @notice Central repository for contract addresses and configuration values
 * @dev Update these addresses based on deployment chain
 */
library Constants {
    // ============================================
    // USDC TOKEN ADDRESSES (6 decimals)
    // ============================================

    /// @notice USDC on Arbitrum One
    address internal constant USDC_ARBITRUM = 0xaf88d065e77c8cC2239327C5EDb3A432268e5831;

    /// @notice USDC on Polygon
    address internal constant USDC_POLYGON = 0x3c499c542cEF5E3811e1192ce70d8cC03d5c3359;

    /// @notice USDC on Avalanche
    address internal constant USDC_AVALANCHE = 0xB97EF9Ef8734C71904D8002F8b6Bc66Dd9c48a6E;

    /// @notice USDC on Base
    address internal constant USDC_BASE = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;

    /// @notice USDC on BNB Chain
    address internal constant USDC_BSC = 0x8AC76a51cc950d9822D68b83fE1Ad97B32Cd580d;

    /// @notice USDC on Ethereum Mainnet (for testing/reference)
    address internal constant USDC_ETHEREUM = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;

    // ============================================
    // KNOWN RWA ADDRESSES (PRODUCTION-READY)
    // ============================================

    /// @notice Ondo OUSG on Ethereum (~5.1% APY)
    /// @dev Tokenized US Treasuries, KYC required for accredited investors
    address internal constant ONDO_OUSG_ETHEREUM = 0x1B19C19393e2d034D8Ff31ff34c81252FcBbee92;

    /// @notice Ondo USDY on Ethereum (~4.8% APY)
    /// @dev Tokenized US Bank Deposits, KYC required
    address internal constant ONDO_USDY_ETHEREUM = 0x96F6eF951840721AdBF46Ac996b59E0235CB985C;
    
    /// @notice Backed Finance IB01 on Ethereum (~5.0% APY)
    /// @dev Short-term US Treasury ETF, available to verified users
    address internal constant BACKED_IB01_ETHEREUM = 0xCA30c93B02514f86d5C86a6e375E3A330B435Fb5;
    
    /// @notice MatrixDock STBT on Ethereum (~5.2% APY)
    /// @dev Short-term US Treasury Bond Token
    address internal constant MATRIXDOCK_STBT_ETHEREUM = 0x530824DA86689C9C17CdC2871Ff29B058345b44a;

    // Note: Most RWAs are on Ethereum mainnet
    // For Arbitrum deployment, you can:
    // 1. Use cross-chain bridges (Axelar, LayerZero)
    // 2. Wait for native Arbitrum RWA launches
    // 3. Use mocks for demo (current approach)

    // ============================================
    // VAULT CONFIGURATION
    // ============================================

    /// @notice Minimum deposit amount (10 USDC with 6 decimals)
    uint256 internal constant MIN_DEPOSIT_USDC = 10e6;

    /// @notice Maximum APY in basis points (50% = 5000 bp) for sanity checks
    uint256 internal constant MAX_APY_BP = 5000;

    /// @notice Basis points denominator
    uint256 internal constant BASIS_POINTS = 10000;

    /// @notice Seconds in a year (365 days)
    uint256 internal constant SECONDS_PER_YEAR = 365 days;

    // ============================================
    // HELPER FUNCTIONS
    // ============================================

    /**
     * @notice Get USDC address for current chain
     * @param chainId Chain ID to query
     * @return USDC token address
     */
    function getUSDCAddress(uint256 chainId) internal pure returns (address) {
        if (chainId == 42161) return USDC_ARBITRUM; // Arbitrum One
        if (chainId == 137) return USDC_POLYGON; // Polygon
        if (chainId == 43114) return USDC_AVALANCHE; // Avalanche
        if (chainId == 8453) return USDC_BASE; // Base
        if (chainId == 56) return USDC_BSC; // BNB Chain
        if (chainId == 1) return USDC_ETHEREUM; // Ethereum
        
        revert("Unsupported chain");
    }

    /**
     * @notice Check if chain is supported by hackathon
     */
    function isSupportedChain(uint256 chainId) internal pure returns (bool) {
        return chainId == 42161 // Arbitrum
            || chainId == 137 // Polygon
            || chainId == 43114 // Avalanche
            || chainId == 8453 // Base
            || chainId == 56; // BSC
    }

    /**
     * @notice Get chain name for display
     */
    function getChainName(uint256 chainId) internal pure returns (string memory) {
        if (chainId == 42161) return "Arbitrum One";
        if (chainId == 137) return "Polygon";
        if (chainId == 43114) return "Avalanche";
        if (chainId == 8453) return "Base";
        if (chainId == 56) return "BNB Chain";
        if (chainId == 1) return "Ethereum";
        if (chainId == 31337) return "Anvil (Local)";
        
        return "Unknown Chain";
    }
}
