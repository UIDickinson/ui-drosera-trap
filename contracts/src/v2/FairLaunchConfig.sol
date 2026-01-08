// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title FairLaunchConfig
 * @notice Centralized compile-time configuration shared by traps/responder scripts
 * @dev Drosera traps cannot accept constructor arguments, so constants live here.
 *      Update the addresses/values below before compiling for a specific deployment.
 */
library FairLaunchConfig {
    // ==================== CORE ADDRESSES ====================

    // Token being protected. Replace with actual token address prior to deployment.
    address internal constant TOKEN_ADDRESS = address(0);

    // Liquidity pool (e.g., Uniswap V2 pair) monitored by traps.
    address internal constant LIQUIDITY_POOL = address(0);

    // Indicates whether the protected token is token0 in the monitored pair.
    bool internal constant TOKEN_IS_TOKEN0 = true;

    // Reference launch block for advanced heuristics. Set to deployment launch block if needed.
    uint256 internal constant LAUNCH_BLOCK = 0;

    // ==================== ACCESSORS ====================

    function tokenAddress() internal pure returns (address) {
        return TOKEN_ADDRESS;
    }

    function liquidityPool() internal pure returns (address) {
        return LIQUIDITY_POOL;
    }

    function tokenIsToken0() internal pure returns (bool) {
        return TOKEN_IS_TOKEN0;
    }

    function launchBlock() internal pure returns (uint256) {
        return LAUNCH_BLOCK;
    }
}
