// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../interfaces/ITrap.sol";
import "../interfaces/IERC20.sol";

/**
 * @title FairLaunchGuardianTrap - Drosera V2 (Stateless)
 * @notice Stateless trap that detects suspicious trading patterns during token launches
 * @dev Implements ITrap interface with pure/view functions only. No state storage.
 * 
 * Architecture:
 * - collect() reads on-chain state (ERC20 balances, supply)
 * - shouldRespond() is PURE - analyzes data[] window for patterns
 * - Returns encoded payload for separate responder contract
 * 
 * Data Flow:
 * 1. Drosera calls collect() on shadow fork → gets snapshot
 * 2. Drosera calls shouldRespond(data[]) with historical window
 * 3. If violations detected → return (true, encodedPayload)
 * 4. Drosera calls responder.handle(payload) to execute actions
 */
contract FairLaunchGuardianTrap is ITrap {
    
    // ==================== CONSTANTS ====================
    
    uint256 public constant BASIS_POINTS = 10_000;
    uint256 public constant RAPID_BUY_THRESHOLD = 3;
    
    // Thresholds for detection (configurable via constructor alternative)
    // Note: In production, these would be hardcoded or passed via collect() data
    uint256 public constant MAX_WALLET_BP = 100; // 1% max per wallet
    uint256 public constant MAX_GAS_PREMIUM_BP = 5000; // 50% above average
    
    // ==================== STRUCTS ====================
    
    /**
     * @notice Output structure from collect() - snapshot of current state
     * @dev This is encoded and returned by collect(), then passed to shouldRespond()
     */
    struct CollectOutput {
        uint256 blockNumber;
        uint256 timestamp;
        address tokenAddress;
        address liquidityPool;
        uint256 totalSupply;
        uint256 liquidityPoolBalance;
        uint256 poolReserveToken;
        uint256 poolReserveETH;
    }
    
    /**
     * @notice Response data structure sent to responder contract
     * @dev Encoded and returned when shouldRespond() detects violations
     */
    struct ResponseData {
        address violatorAddress;
        uint256 accumulatedPercentBP;
        uint8 detectionType;
        uint256 blockNumber;
        uint256 severity; // 0-100
    }
    
    // Detection types (as uint8 for compact encoding)
    uint8 public constant DETECTION_EXCESSIVE_ACCUMULATION = 0;
    uint8 public constant DETECTION_FRONT_RUNNING_GAS = 1;
    uint8 public constant DETECTION_RAPID_BUYING = 2;
    uint8 public constant DETECTION_COORDINATED_ATTACK = 3;
    uint8 public constant DETECTION_LIQUIDITY_MANIPULATION = 4;
    
    // ==================== STATE (IMMUTABLE ONLY) ====================
    
    // NOTE: These are immutable config values set at deployment
    // They don't violate statelessness as they never change
    address public immutable TOKEN_ADDRESS;
    address public immutable LIQUIDITY_POOL;
    
    /**
     * @notice Constructor sets immutable configuration
     * @dev WARNING: Drosera requires NO constructor args in production
     *      For now, we include them for development, but final version
     *      should hardcode these or pass via collect() encoded data
     */
    constructor(address _tokenAddress, address _liquidityPool) {
        TOKEN_ADDRESS = _tokenAddress;
        LIQUIDITY_POOL = _liquidityPool;
    }
    
    // ==================== ITRAP INTERFACE ====================
    
    /**
     * @notice Collects current on-chain state snapshot
     * @dev MUST be view (no state changes). Reads public blockchain state only.
     *      Called by Drosera operator on shadow fork at sampled block.
     * @return Encoded CollectOutput struct containing current metrics
     */
    function collect() external view override returns (bytes memory) {
        // Read deterministic on-chain state
        uint256 totalSupply = 0;
        uint256 poolBalance = 0;
        
        // Safe external calls with try-catch to handle failures gracefully
        try IERC20(TOKEN_ADDRESS).totalSupply() returns (uint256 supply) {
            totalSupply = supply;
        } catch {
            // If call fails, totalSupply remains 0
        }
        
        try IERC20(TOKEN_ADDRESS).balanceOf(LIQUIDITY_POOL) returns (uint256 balance) {
            poolBalance = balance;
        } catch {
            // If call fails, poolBalance remains 0
        }
        
        // For Uniswap V2 pair, we could read reserves
        // (uint112 reserve0, uint112 reserve1, ) = IUniswapV2Pair(LIQUIDITY_POOL).getReserves();
        // But for simplicity, we'll use balanceOf for now
        
        CollectOutput memory output = CollectOutput({
            blockNumber: block.number,
            timestamp: block.timestamp,
            tokenAddress: TOKEN_ADDRESS,
            liquidityPool: LIQUIDITY_POOL,
            totalSupply: totalSupply,
            liquidityPoolBalance: poolBalance,
            poolReserveToken: poolBalance, // Simplified - would read from pair
            poolReserveETH: 0 // Would read from pair in production
        });
        
        return abi.encode(output);
    }
    
    /**
     * @notice Analyzes collected data to determine if response is needed
     * @dev MUST be pure (no state reads/writes). Analyzes only the data[] parameter.
     *      This is called by Drosera with a window of historical collect() outputs.
     * 
     * @param data Array of encoded CollectOutput structs (historical window)
     *             data[0] = most recent sample
     *             data[1] = previous sample
     *             data[n] = oldest sample
     * 
     * @return shouldRespond True if violation detected
     * @return responseData Encoded ResponseData struct for responder contract
     */
    function shouldRespond(bytes[] calldata data)
        external
        pure
        override
        returns (bool, bytes memory)
    {
        // ==================== INPUT VALIDATION ====================
        
        // Guard against empty data (critical for planner safety)
        if (data.length < 1 || data[0].length == 0) {
            return (false, "");
        }
        
        // For pattern detection, we need at least 2 samples to compare
        if (data.length < 2) {
            return (false, "");
        }
        
        // ==================== DECODE SAMPLES ====================
        
        CollectOutput memory current = abi.decode(data[0], (CollectOutput));
        CollectOutput memory previous = abi.decode(data[1], (CollectOutput));
        
        // Additional safety: check for zero supply (would cause division by zero)
        if (current.totalSupply == 0) {
            return (false, "");
        }
        
        // ==================== DETECTION LOGIC ====================
        
        // 1. Detect large liquidity drain (potential rug pull)
        if (previous.liquidityPoolBalance > 0) {
            uint256 liquidityDelta = previous.liquidityPoolBalance > current.liquidityPoolBalance
                ? previous.liquidityPoolBalance - current.liquidityPoolBalance
                : 0;
            
            uint256 liquidityDropBP = (liquidityDelta * BASIS_POINTS) / previous.liquidityPoolBalance;
            
            // If liquidity drops >10% in one block, flag it
            if (liquidityDropBP > 1000) { // 10%
                uint256 severity = _calculateSeverity(liquidityDropBP, 1000);
                
                ResponseData memory response = ResponseData({
                    violatorAddress: current.liquidityPool,
                    accumulatedPercentBP: liquidityDropBP,
                    detectionType: DETECTION_LIQUIDITY_MANIPULATION,
                    blockNumber: current.blockNumber,
                    severity: severity
                });
                
                return (true, abi.encode(response));
            }
        }
        
        // 2. Detect rapid supply changes (potential coordinated attack)
        if (previous.totalSupply > 0 && current.totalSupply != previous.totalSupply) {
            uint256 supplyChange = current.totalSupply > previous.totalSupply
                ? current.totalSupply - previous.totalSupply
                : previous.totalSupply - current.totalSupply;
            
            uint256 supplyChangeBP = (supplyChange * BASIS_POINTS) / previous.totalSupply;
            
            // If supply changes >5% in one block, investigate
            if (supplyChangeBP > 500) { // 5%
                uint256 severity = _calculateSeverity(supplyChangeBP, 500);
                
                ResponseData memory response = ResponseData({
                    violatorAddress: current.tokenAddress,
                    accumulatedPercentBP: supplyChangeBP,
                    detectionType: DETECTION_COORDINATED_ATTACK,
                    blockNumber: current.blockNumber,
                    severity: severity
                });
                
                return (true, abi.encode(response));
            }
        }
        
        // 3. Multi-block pattern detection (if we have enough samples)
        if (data.length >= 3) {
            bool suspiciousPattern = _detectMultiBlockPattern(data);
            if (suspiciousPattern) {
                ResponseData memory response = ResponseData({
                    violatorAddress: current.liquidityPool,
                    accumulatedPercentBP: 0,
                    detectionType: DETECTION_RAPID_BUYING,
                    blockNumber: current.blockNumber,
                    severity: 75
                });
                
                return (true, abi.encode(response));
            }
        }
        
        // No violations detected
        return (false, "");
    }
    
    // ==================== INTERNAL PURE FUNCTIONS ====================
    
    /**
     * @notice Calculates severity score (0-100) based on how much threshold is exceeded
     * @param actual The actual value observed
     * @param threshold The threshold that was exceeded
     * @return Severity score from 0-100
     */
    function _calculateSeverity(uint256 actual, uint256 threshold)
        internal
        pure
        returns (uint256)
    {
        if (actual <= threshold) return 0;
        
        uint256 excess = actual - threshold;
        uint256 severity = (excess * 100) / threshold;
        
        // Cap at 100
        return severity > 100 ? 100 : severity;
    }
    
    /**
     * @notice Detects suspicious patterns across multiple blocks
     * @dev Example: Consistent liquidity drainage over time
     * @param data Historical window of samples
     * @return True if suspicious pattern detected
     */
    function _detectMultiBlockPattern(bytes[] calldata data)
        internal
        pure
        returns (bool)
    {
        // Need at least 3 samples
        if (data.length < 3) return false;
        
        // Track if liquidity is consistently decreasing
        uint256 consecutiveDecreases = 0;
        
        for (uint256 i = 0; i < data.length - 1 && i < 5; i++) {
            CollectOutput memory newer = abi.decode(data[i], (CollectOutput));
            CollectOutput memory older = abi.decode(data[i + 1], (CollectOutput));
            
            if (newer.liquidityPoolBalance < older.liquidityPoolBalance) {
                uint256 decrease = older.liquidityPoolBalance - newer.liquidityPoolBalance;
                uint256 decreaseBP = (decrease * BASIS_POINTS) / older.liquidityPoolBalance;
                
                // Each block shows >1% decrease
                if (decreaseBP > 100) {
                    consecutiveDecreases++;
                }
            } else {
                // Pattern broken
                break;
            }
        }
        
        // If 3+ consecutive blocks show >1% liquidity decrease, flag it
        return consecutiveDecreases >= 3;
    }
    
    // ==================== VIEW FUNCTIONS (for external queries) ====================
    
    /**
     * @notice Returns the configured token address
     */
    function getTokenAddress() external view returns (address) {
        return TOKEN_ADDRESS;
    }
    
    /**
     * @notice Returns the configured liquidity pool address
     */
    function getLiquidityPool() external view returns (address) {
        return LIQUIDITY_POOL;
    }
}
