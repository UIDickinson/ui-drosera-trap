// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../interfaces/ITrap.sol";
import "../interfaces/IERC20.sol";

/**
 * @title FairLaunchGuardianTrapSimple
 * @notice Simplified production trap using only state reading (NO constructor args)
 * @dev This is the SIMPLEST data strategy - good for MVP/testing
 * 
 * Data Strategy: Simple State Reading
 * - Reads ERC20 balanceOf() and totalSupply()
 * - No event parsing required
 * - No external integrations needed
 * - Works with any ERC20 token
 * 
 * Benefits:
 * ✅ No constructor args (Drosera compatible)
 * ✅ Simple to deploy and test
 * ✅ No integration required
 * ✅ Deterministic
 * 
 * Limitations:
 * ⚠️ Limited detection capabilities (can't see individual trades)
 * ⚠️ Best for detecting large liquidity drains only
 * 
 * DEPLOYMENT: Update TOKEN_ADDRESS and LIQUIDITY_POOL before compiling!
 */
contract FairLaunchGuardianTrapSimple is ITrap {
    
    // ==================== CONSTANTS ====================
    
    uint256 public constant BASIS_POINTS = 10_000;
    uint256 public constant LIQUIDITY_DRAIN_THRESHOLD_BP = 1000; // 10%
    uint256 public constant SUPPLY_CHANGE_THRESHOLD_BP = 500; // 5%
    
    // ==================== CONFIGURATION ====================
    
    // PRODUCTION: These addresses are set for Hoodi testnet deployment
    // These MUST be literal addresses (compile-time constants for Drosera)
    address public constant TOKEN_ADDRESS = 0xBE820752AE8E48010888E89862cbb97aF506d183; // DemoToken on Hoodi
    address public constant LIQUIDITY_POOL = 0xE225187b6f9F107d558B9585D5F5D94Aae6F4F71; // DemoDEX on Hoodi
    
    // ALTERNATIVE: For multi-token monitoring, create factory or use different deployment per token
    
    // ==================== STRUCTS ====================
    
    struct CollectOutput {
        uint256 blockNumber;
        uint256 timestamp;
        uint256 totalSupply;
        uint256 poolBalance;
    }
    
    struct ResponseData {
        address violatorAddress;
        uint256 accumulatedPercentBP;
        uint8 detectionType;
        uint256 blockNumber;
        uint256 severity;
        uint256 confidence;
    }
    
    // Detection types
    uint8 public constant DETECTION_LIQUIDITY_MANIPULATION = 4;
    uint8 public constant DETECTION_SUPPLY_MANIPULATION = 3;
    
    // ==================== ITRAP IMPLEMENTATION ====================
    
    /**
     * @notice Collects simple on-chain state snapshot
     * @dev Reads only totalSupply and pool balance - fully deterministic
     */
    function collect() external view override returns (bytes memory) {
        uint256 totalSupply = 0;
        uint256 poolBalance = 0;
        
        // Safe reads with try-catch
        try IERC20(TOKEN_ADDRESS).totalSupply() returns (uint256 supply) {
            totalSupply = supply;
        } catch {}
        
        try IERC20(TOKEN_ADDRESS).balanceOf(LIQUIDITY_POOL) returns (uint256 balance) {
            poolBalance = balance;
        } catch {}
        
        CollectOutput memory output = CollectOutput({
            blockNumber: block.number,
            timestamp: block.timestamp,
            totalSupply: totalSupply,
            poolBalance: poolBalance
        });
        
        return abi.encode(output);
    }
    
    /**
     * @notice Detects violations from simple state changes
     * @dev Pure function analyzing only historical data
     */
    function shouldRespond(bytes[] calldata data)
        external
        pure
        override
        returns (bool, bytes memory)
    {
        // Input validation
        if (data.length < 2 || data[0].length == 0 || data[1].length == 0) {
            return (false, "");
        }
        
        CollectOutput memory current = abi.decode(data[0], (CollectOutput));
        CollectOutput memory previous = abi.decode(data[1], (CollectOutput));
        
        if (current.totalSupply == 0) {
            return (false, "");
        }
        
        // 1. Detect liquidity drain
        {
            (bool detected, ResponseData memory response) = _detectLiquidityDrain(
                current,
                previous
            );
            if (detected) return (true, abi.encode(response));
        }
        
        // 2. Detect supply manipulation
        {
            (bool detected, ResponseData memory response) = _detectSupplyChange(
                current,
                previous
            );
            if (detected) return (true, abi.encode(response));
        }
        
        // 3. Multi-block drain pattern (if more samples available)
        if (data.length >= 3) {
            (bool detected, ResponseData memory response) = _detectMultiBlockDrain(data);
            if (detected) return (true, abi.encode(response));
        }
        
        return (false, "");
    }
    
    // ==================== DETECTION LOGIC ====================
    
    function _detectLiquidityDrain(
        CollectOutput memory current,
        CollectOutput memory previous
    ) internal pure returns (bool, ResponseData memory) {
        if (previous.poolBalance == 0 || current.poolBalance >= previous.poolBalance) {
            return (false, ResponseData(address(0), 0, 0, 0, 0, 0));
        }
        
        uint256 drain = previous.poolBalance - current.poolBalance;
        uint256 drainBP = (drain * BASIS_POINTS) / previous.poolBalance;
        
        if (drainBP <= LIQUIDITY_DRAIN_THRESHOLD_BP) {
            return (false, ResponseData(address(0), 0, 0, 0, 0, 0));
        }
        
        uint256 severity = drainBP > 2000 ? 95 : (drainBP > 1500 ? 85 : 75);
        uint256 confidence = 90;
        
        ResponseData memory response = ResponseData({
            violatorAddress: LIQUIDITY_POOL,
            accumulatedPercentBP: drainBP,
            detectionType: DETECTION_LIQUIDITY_MANIPULATION,
            blockNumber: current.blockNumber,
            severity: severity,
            confidence: confidence
        });
        
        return (true, response);
    }
    
    function _detectSupplyChange(
        CollectOutput memory current,
        CollectOutput memory previous
    ) internal pure returns (bool, ResponseData memory) {
        if (previous.totalSupply == 0 || current.totalSupply == previous.totalSupply) {
            return (false, ResponseData(address(0), 0, 0, 0, 0, 0));
        }
        
        uint256 change = current.totalSupply > previous.totalSupply
            ? current.totalSupply - previous.totalSupply
            : previous.totalSupply - current.totalSupply;
        
        uint256 changeBP = (change * BASIS_POINTS) / previous.totalSupply;
        
        if (changeBP <= SUPPLY_CHANGE_THRESHOLD_BP) {
            return (false, ResponseData(address(0), 0, 0, 0, 0, 0));
        }
        
        uint256 severity = changeBP > 1000 ? 90 : 75;
        uint256 confidence = 85;
        
        ResponseData memory response = ResponseData({
            violatorAddress: TOKEN_ADDRESS,
            accumulatedPercentBP: changeBP,
            detectionType: DETECTION_SUPPLY_MANIPULATION,
            blockNumber: current.blockNumber,
            severity: severity,
            confidence: confidence
        });
        
        return (true, response);
    }
    
    function _detectMultiBlockDrain(
        bytes[] calldata data
    ) internal pure returns (bool, ResponseData memory) {
        uint256 consecutiveDecreases = 0;
        
        for (uint256 i = 0; i < data.length - 1 && i < 5; i++) {
            CollectOutput memory newer = abi.decode(data[i], (CollectOutput));
            CollectOutput memory older = abi.decode(data[i + 1], (CollectOutput));
            
            if (older.poolBalance == 0) continue;
            
            if (newer.poolBalance < older.poolBalance) {
                uint256 decrease = older.poolBalance - newer.poolBalance;
                uint256 decreaseBP = (decrease * BASIS_POINTS) / older.poolBalance;
                
                if (decreaseBP > 100) { // >1% per block
                    consecutiveDecreases++;
                }
            } else {
                break;
            }
        }
        
        if (consecutiveDecreases < 3) {
            return (false, ResponseData(address(0), 0, 0, 0, 0, 0));
        }
        
        CollectOutput memory current = abi.decode(data[0], (CollectOutput));
        
        uint256 severity = consecutiveDecreases >= 5 ? 95 : 85;
        uint256 confidence = 90;
        
        ResponseData memory response = ResponseData({
            violatorAddress: LIQUIDITY_POOL,
            accumulatedPercentBP: consecutiveDecreases * 100,
            detectionType: DETECTION_LIQUIDITY_MANIPULATION,
            blockNumber: current.blockNumber,
            severity: severity,
            confidence: confidence
        });
        
        return (true, response);
    }
    
    // ==================== VIEW FUNCTIONS ====================
    
    function getConfig() external pure returns (address token, address pool) {
        return (TOKEN_ADDRESS, LIQUIDITY_POOL);
    }
}
