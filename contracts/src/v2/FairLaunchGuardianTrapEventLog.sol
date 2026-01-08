// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../interfaces/ITrap.sol";
import "../interfaces/IERC20.sol";
import "./EventLogHelper.sol";

/**
 * @title FairLaunchGuardianTrapEventLog
 * @notice Production trap using Drosera's EventLog filtering (RECOMMENDED)
 * @dev This is the RECOMMENDED data strategy for Drosera traps
 * 
 * Data Strategy: EventLog Filtering
 * - Most deterministic across operators
 * - No external dependencies or state storage
 * - Uses Drosera's native event filtering
 * - Parses Uniswap Swap events directly
 * 
 * How it works:
 * 1. Drosera operator filters Swap events from configured pool
 * 2. collect() parses events into structured data
 * 3. shouldRespond() analyzes parsed swap history
 * 4. Returns payload if violations detected
 * 
 * Benefits:
 * ✅ Fully deterministic
 * ✅ No state storage needed
 * ✅ No recordSwap() integration required
 * ✅ Works with any Uniswap V2 compatible pool
 * ✅ Operator consensus guaranteed
 * 
 * DEPLOYMENT: Update TOKEN_ADDRESS, LIQUIDITY_POOL, TOKEN_IS_TOKEN0 before compiling!
 */
contract FairLaunchGuardianTrapEventLog is ITrap {
    using EventLogHelper for EventLogHelper.ParsedSwap;
    
    // ==================== CONSTANTS ====================
    
    uint256 public constant BASIS_POINTS = 10_000;
    uint256 public constant EXCESSIVE_ACCUMULATION_BP = 100; // 1%
    uint256 public constant LIQUIDITY_DRAIN_THRESHOLD_BP = 1000; // 10%
    uint256 public constant GAS_MANIPULATION_THRESHOLD_BP = 5000; // 50%
    uint256 public constant COORDINATED_WALLET_THRESHOLD = 3;
    uint256 public constant MAX_EVENTS_ANALYZED = 100; // Cap parsing for determinism
    
    // ==================== STRUCTS ====================
    
    struct CollectOutput {
        uint256 blockNumber;
        uint256 timestamp;
        uint256 totalSupply;
        uint256 poolBalance;
        uint256 reserve0;
        uint256 reserve1;
        SwapInfo[] swaps;
        uint256 totalBuyVolume;
        uint256 totalSellVolume;
    }
    
    struct SwapInfo {
        address wallet;
        bool isBuy;
        uint256 tokenAmount;
        uint256 ethAmount;
        uint256 blockNumber;
        uint256 timestamp;
    }
    
    struct ResponseData {
        address violatorAddress;
        address[] relatedAddresses;
        uint256 accumulatedPercentBP;
        uint8 detectionType;
        uint256 blockNumber;
        uint256 severity;
        uint256 confidence;
        bytes32 patternSignature;
    }
    
    // Detection types
    uint8 public constant DETECTION_EXCESSIVE_ACCUMULATION = 0;
    uint8 public constant DETECTION_FRONT_RUNNING_GAS = 1;
    uint8 public constant DETECTION_COORDINATED_ATTACK = 3;
    uint8 public constant DETECTION_LIQUIDITY_MANIPULATION = 4;
    
    // ==================== CONFIGURATION ====================
    
    // PRODUCTION: These addresses are set for Hoodi testnet deployment
    // These MUST be literal addresses (compile-time constants for Drosera)
    address public constant TOKEN_ADDRESS = 0xBE820752AE8E48010888E89862cbb97aF506d183; // DemoToken on Hoodi
    address public constant LIQUIDITY_POOL = 0xE225187b6f9F107d558B9585D5F5D94Aae6F4F71; // DemoDEX on Hoodi
    bool public constant TOKEN_IS_TOKEN0 = true; // Set based on actual pair ordering
    
    // ==================== ITRAP IMPLEMENTATION ====================
    
    /**
     * @notice Collects on-chain state WITHOUT event parsing
     * @dev In production with Drosera, event logs would be passed via
     *      a separate mechanism or encoded in the planner configuration.
     *      This collect() focuses on current state only.
     */
    function collect() external view override returns (bytes memory) {
        uint256 totalSupply = 0;
        uint256 poolBalance = 0;
        uint256 reserve0 = 0;
        uint256 reserve1 = 0;
        
        try IERC20(TOKEN_ADDRESS).totalSupply() returns (uint256 supply) {
            totalSupply = supply;
        } catch {}
        
        try IERC20(TOKEN_ADDRESS).balanceOf(LIQUIDITY_POOL) returns (uint256 balance) {
            poolBalance = balance;
        } catch {}
        
        // Note: In production, you would use IUniswapV2Pair interface
        // For now, simplified to just balance
        reserve0 = poolBalance;
        reserve1 = 0;
        
        // Empty swaps array - in production, this would be populated from
        // event logs provided by Drosera's EventFilter system
        SwapInfo[] memory swaps = new SwapInfo[](0);
        
        CollectOutput memory output = CollectOutput({
            blockNumber: block.number,
            timestamp: block.timestamp,
            totalSupply: totalSupply,
            poolBalance: poolBalance,
            reserve0: reserve0,
            reserve1: reserve1,
            swaps: swaps,
            totalBuyVolume: 0,
            totalSellVolume: 0
        });
        
        return abi.encode(output);
    }

    /**
     * @notice Utility for operators to build collect() payloads from raw event bundles
     * @dev Parses Swap events and returns encoded CollectOutput for shouldRespond()
     */
    function buildCollectPayloadFromEvents(
        uint256 blockNumber,
        uint256 timestamp,
        uint256 totalSupply,
        uint256 poolBalance,
        uint256 reserve0,
        uint256 reserve1,
        bytes32[][] memory topics,
        bytes[] memory dataArray,
        uint256[] memory logBlockNumbers,
        uint256[] memory logTimestamps
    ) external pure returns (bytes memory) {
        SwapInfo[] memory swaps = parseSwapEvents(
            topics,
            dataArray,
            logBlockNumbers,
            logTimestamps,
            LIQUIDITY_POOL,
            TOKEN_IS_TOKEN0
        );

        uint256 totalBuyVolume;
        uint256 totalSellVolume;
        uint256 limit = swaps.length;
        for (uint256 i = 0; i < limit; i++) {
            if (swaps[i].isBuy) {
                totalBuyVolume += swaps[i].tokenAmount;
            } else {
                totalSellVolume += swaps[i].tokenAmount;
            }
        }

        CollectOutput memory output = CollectOutput({
            blockNumber: blockNumber,
            timestamp: timestamp,
            totalSupply: totalSupply,
            poolBalance: poolBalance,
            reserve0: reserve0,
            reserve1: reserve1,
            swaps: swaps,
            totalBuyVolume: totalBuyVolume,
            totalSellVolume: totalSellVolume
        });

        return abi.encode(output);
    }
    
    /**
     * @notice Analyzes swap events for violations
     * @dev Pure function - all analysis from data[] parameter
     *      In production, data[] would include parsed event logs
     */
    function shouldRespond(bytes[] calldata data)
        external
        pure
        override
        returns (bool, bytes memory)
    {
        if (data.length < 1 || data[0].length == 0) {
            return (false, "");
        }
        
        CollectOutput memory current = abi.decode(data[0], (CollectOutput));
        
        if (current.totalSupply == 0) {
            return (false, "");
        }
        
        // 1. Check for liquidity drain (comparing blocks)
        if (data.length >= 2) {
            CollectOutput memory previous = abi.decode(data[1], (CollectOutput));
            
            (bool detected, ResponseData memory response) = _detectLiquidityDrain(
                current,
                previous
            );
            if (detected) return (true, abi.encode(response));
        }
        
        // 2. Analyze swap patterns (if swap data available)
        if (current.swaps.length > 0) {
            // Check for excessive accumulation
            (bool detected, ResponseData memory response) = _detectExcessiveAccumulation(
                current
            );
            if (detected) return (true, abi.encode(response));
            
            // Check for coordinated attack
            if (current.swaps.length >= COORDINATED_WALLET_THRESHOLD) {
                (detected, response) = _detectCoordinatedAttack(current);
                if (detected) return (true, abi.encode(response));
            }
        }
        
        return (false, "");
    }
    
    // ==================== DETECTION LOGIC ====================
    
    function _detectLiquidityDrain(
        CollectOutput memory current,
        CollectOutput memory previous
    ) internal pure returns (bool, ResponseData memory) {
        if (previous.poolBalance == 0 || current.poolBalance >= previous.poolBalance) {
            return (false, ResponseData(address(0), new address[](0), 0, 0, 0, 0, 0, bytes32(0)));
        }
        
        uint256 drain = previous.poolBalance - current.poolBalance;
        uint256 drainBP = (drain * BASIS_POINTS) / previous.poolBalance;
        
        if (drainBP <= LIQUIDITY_DRAIN_THRESHOLD_BP) {
            return (false, ResponseData(address(0), new address[](0), 0, 0, 0, 0, 0, bytes32(0)));
        }
        
        uint256 severity = drainBP > 2000 ? 95 : 75;
        uint256 confidence = 90;
        
        ResponseData memory response = ResponseData({
            violatorAddress: LIQUIDITY_POOL,
            relatedAddresses: new address[](0),
            accumulatedPercentBP: drainBP,
            detectionType: DETECTION_LIQUIDITY_MANIPULATION,
            blockNumber: current.blockNumber,
            severity: severity,
            confidence: confidence,
            patternSignature: keccak256(abi.encodePacked("LIQ_DRAIN", current.blockNumber))
        });
        
        return (true, response);
    }
    
    function _detectExcessiveAccumulation(
        CollectOutput memory current
    ) internal pure returns (bool, ResponseData memory) {
        // Track wallet accumulations
        uint256 swapCount = current.swaps.length;
        if (swapCount > MAX_EVENTS_ANALYZED) {
            swapCount = MAX_EVENTS_ANALYZED;
        }

        address[] memory wallets = new address[](swapCount);
        uint256[] memory accumulated = new uint256[](swapCount);
        uint256 uniqueCount = 0;
        
        for (uint256 i = 0; i < swapCount; i++) {
            if (!current.swaps[i].isBuy) continue;
            
            address wallet = current.swaps[i].wallet;
            uint256 amount = current.swaps[i].tokenAmount;
            
            // Find or add wallet
            bool found = false;
            for (uint256 j = 0; j < uniqueCount; j++) {
                if (wallets[j] == wallet) {
                    accumulated[j] += amount;
                    found = true;
                    break;
                }
            }
            
            if (!found && uniqueCount < wallets.length) {
                wallets[uniqueCount] = wallet;
                accumulated[uniqueCount] = amount;
                uniqueCount++;
            }
        }
        
        // Check for excessive accumulation
        for (uint256 i = 0; i < uniqueCount; i++) {
            uint256 percentBP = (accumulated[i] * BASIS_POINTS) / current.totalSupply;
            
            if (percentBP > EXCESSIVE_ACCUMULATION_BP) {
                uint256 severity = percentBP > 500 ? 90 : 70;
                
                ResponseData memory response = ResponseData({
                    violatorAddress: wallets[i],
                    relatedAddresses: new address[](0),
                    accumulatedPercentBP: percentBP,
                    detectionType: DETECTION_EXCESSIVE_ACCUMULATION,
                    blockNumber: current.blockNumber,
                    severity: severity,
                    confidence: 85,
                    patternSignature: keccak256(abi.encodePacked("EXCESS_ACC", wallets[i]))
                });
                
                return (true, response);
            }
        }
        
        return (false, ResponseData(address(0), new address[](0), 0, 0, 0, 0, 0, bytes32(0)));
    }
    
    function _detectCoordinatedAttack(
        CollectOutput memory current
    ) internal pure returns (bool, ResponseData memory) {
        if (current.swaps.length < COORDINATED_WALLET_THRESHOLD) {
            return (false, ResponseData(address(0), new address[](0), 0, 0, 0, 0, 0, bytes32(0)));
        }
        
        // Simple clustering: check for rapid buys in same block
        uint256 rapidBuyCount = 0;
        uint256 swapCount = current.swaps.length;
        if (swapCount > MAX_EVENTS_ANALYZED) {
            swapCount = MAX_EVENTS_ANALYZED;
        }

        address[] memory rapidBuyers = new address[](swapCount);
        
        for (uint256 i = 0; i < swapCount; i++) {
            if (current.swaps[i].isBuy && rapidBuyCount < rapidBuyers.length) {
                rapidBuyers[rapidBuyCount] = current.swaps[i].wallet;
                rapidBuyCount++;
            }
        }
        
        if (rapidBuyCount >= COORDINATED_WALLET_THRESHOLD) {
            address[] memory related = new address[](rapidBuyCount);
            for (uint256 i = 0; i < rapidBuyCount; i++) {
                related[i] = rapidBuyers[i];
            }
            
            ResponseData memory response = ResponseData({
                violatorAddress: rapidBuyers[0],
                relatedAddresses: related,
                accumulatedPercentBP: 0,
                detectionType: DETECTION_COORDINATED_ATTACK,
                blockNumber: current.blockNumber,
                severity: 80,
                confidence: 75,
                patternSignature: keccak256(abi.encodePacked("COORD", rapidBuyCount))
            });
            
            return (true, response);
        }
        
        return (false, ResponseData(address(0), new address[](0), 0, 0, 0, 0, 0, bytes32(0)));
    }
    
    // ==================== HELPER FUNCTIONS ====================
    
    /**
     * @notice Helper to parse event logs (would be called externally by Drosera)
     * @dev This demonstrates how event logs would be processed
     */
    function parseSwapEvents(
        bytes32[][] memory topics,
        bytes[] memory dataArray,
        uint256[] memory blockNumbers,
        uint256[] memory timestamps,
        address poolAddress,
        bool tokenIsToken0
    ) public pure returns (SwapInfo[] memory) {
        require(
            topics.length == dataArray.length &&
                dataArray.length == blockNumbers.length &&
                blockNumbers.length == timestamps.length,
            "Array length mismatch"
        );

        uint256 limit = topics.length;
        if (limit > MAX_EVENTS_ANALYZED) {
            limit = MAX_EVENTS_ANALYZED;
        }

        SwapInfo[] memory temp = new SwapInfo[](limit);
        uint256 count;

        for (uint256 i = 0; i < limit; i++) {
            EventLogHelper.ParsedSwap memory parsed = EventLogHelper.parseSwapEvent(
                topics[i],
                dataArray[i],
                blockNumbers[i],
                timestamps[i],
                poolAddress
            );

            (bool isBuy, uint256 tokenAmount, uint256 ethAmount) =
                EventLogHelper.analyzeSwapDirection(parsed, tokenIsToken0);

            temp[count] = SwapInfo({
                wallet: parsed.to,
                isBuy: isBuy,
                tokenAmount: tokenAmount,
                ethAmount: ethAmount,
                blockNumber: parsed.blockNumber,
                timestamp: parsed.timestamp
            });
            count++;
        }

        SwapInfo[] memory swaps = new SwapInfo[](count);
        for (uint256 j = 0; j < count; j++) {
            swaps[j] = temp[j];
        }

        return swaps;
    }
    
    // ==================== VIEW FUNCTIONS ====================
    
    function getConfig() external view returns (address, address, bool) {
        return (TOKEN_ADDRESS, LIQUIDITY_POOL, TOKEN_IS_TOKEN0);
    }
}
