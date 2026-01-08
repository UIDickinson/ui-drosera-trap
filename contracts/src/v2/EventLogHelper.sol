// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title EventLogHelper
 * @notice Helper library for parsing Uniswap V2 Swap event logs
 * @dev Used by traps to decode event data from Drosera's EventFilter system
 * 
 * Uniswap V2 Swap Event Signature:
 * Swap(address indexed sender, uint amount0In, uint amount1In, uint amount0Out, uint amount1Out, address indexed to)
 * 
 * Event Signature Hash: 0xd78ad95fa46c994b6551d0da85fc275fe613ce37657fb8d5e3d130840159d822
 */
library EventLogHelper {
    
    /**
     * @notice Parsed swap event data
     */
    struct ParsedSwap {
        address sender;
        address to;
        uint256 amount0In;
        uint256 amount1In;
        uint256 amount0Out;
        uint256 amount1Out;
        uint256 blockNumber;
        uint256 timestamp;
        address poolAddress;
    }
    
    /**
     * @notice Swap event signature hash
     */
    bytes32 public constant SWAP_EVENT_SIGNATURE = 
        keccak256("Swap(address,uint256,uint256,uint256,uint256,address)");
    
    /**
     * @notice Sync event signature hash (for reserve updates)
     */
    bytes32 public constant SYNC_EVENT_SIGNATURE = 
        keccak256("Sync(uint112,uint112)");
    
    /**
     * @notice Parse a Uniswap V2 Swap event log
     * @param topics Event topics array
     * @param data Event data bytes
     * @param blockNumber Block number of event
     * @param timestamp Block timestamp
     * @param poolAddress Address of the pool that emitted the event
     * @return Parsed swap data
     */
    function parseSwapEvent(
        bytes32[] memory topics,
        bytes memory data,
        uint256 blockNumber,
        uint256 timestamp,
        address poolAddress
    ) internal pure returns (ParsedSwap memory) {
        require(topics.length >= 3, "Invalid Swap event topics");
        require(topics[0] == SWAP_EVENT_SIGNATURE, "Not a Swap event");
        
        // Extract indexed parameters from topics
        address sender = address(uint160(uint256(topics[1])));
        address to = address(uint160(uint256(topics[2])));
        
        // Decode non-indexed parameters from data
        (
            uint256 amount0In,
            uint256 amount1In,
            uint256 amount0Out,
            uint256 amount1Out
        ) = abi.decode(data, (uint256, uint256, uint256, uint256));
        
        return ParsedSwap({
            sender: sender,
            to: to,
            amount0In: amount0In,
            amount1In: amount1In,
            amount0Out: amount0Out,
            amount1Out: amount1Out,
            blockNumber: blockNumber,
            timestamp: timestamp,
            poolAddress: poolAddress
        });
    }
    
    /**
     * @notice Determine if a swap is a buy or sell
     * @param swap Parsed swap data
     * @param tokenIsToken0 True if the monitored token is token0 in the pair
     * @return isBuy True if this is a buy (user receives token)
     * @return tokenAmount Amount of tokens bought/sold
     * @return ethAmount Amount of ETH spent/received
     */
    function analyzeSwapDirection(
        ParsedSwap memory swap,
        bool tokenIsToken0
    ) internal pure returns (bool isBuy, uint256 tokenAmount, uint256 ethAmount) {
        if (tokenIsToken0) {
            // Token is token0, ETH is token1
            if (swap.amount0Out > 0) {
                // User receives token0 (buys token)
                return (true, swap.amount0Out, swap.amount1In);
            } else {
                // User sends token0 (sells token)
                return (false, swap.amount0In, swap.amount1Out);
            }
        } else {
            // Token is token1, ETH is token0
            if (swap.amount1Out > 0) {
                // User receives token1 (buys token)
                return (true, swap.amount1Out, swap.amount0In);
            } else {
                // User sends token1 (sells token)
                return (false, swap.amount1In, swap.amount0Out);
            }
        }
    }
    
    /**
     * @notice Batch parse multiple swap events
     * @param topics Array of topic arrays
     * @param dataArray Array of data bytes
     * @param blockNumbers Array of block numbers
     * @param timestamps Array of timestamps
     * @param poolAddress Pool address for all events
     * @return Array of parsed swaps
     */
    function batchParseSwapEvents(
        bytes32[][] memory topics,
        bytes[] memory dataArray,
        uint256[] memory blockNumbers,
        uint256[] memory timestamps,
        address poolAddress
    ) internal pure returns (ParsedSwap[] memory) {
        require(
            topics.length == dataArray.length &&
            dataArray.length == blockNumbers.length &&
            blockNumbers.length == timestamps.length,
            "Array length mismatch"
        );
        
        ParsedSwap[] memory swaps = new ParsedSwap[](topics.length);
        
        for (uint256 i = 0; i < topics.length; i++) {
            swaps[i] = parseSwapEvent(
                topics[i],
                dataArray[i],
                blockNumbers[i],
                timestamps[i],
                poolAddress
            );
        }
        
        return swaps;
    }
    
    /**
     * @notice Parse Sync event to get reserve updates
     * @param data Event data bytes
     * @return reserve0 Token0 reserve
     * @return reserve1 Token1 reserve
     */
    function parseSyncEvent(bytes memory data)
        internal
        pure
        returns (uint112 reserve0, uint112 reserve1)
    {
        (reserve0, reserve1) = abi.decode(data, (uint112, uint112));
    }
    
    /**
     * @notice Calculate price impact of a swap
     * @param amountIn Amount of input token
     * @param reserveIn Reserve of input token before swap
     * @param reserveOut Reserve of output token before swap
     * @return priceImpactBP Price impact in basis points
     */
    function calculatePriceImpact(
        uint256 amountIn,
        uint256 reserveIn,
        uint256 reserveOut
    ) internal pure returns (uint256 priceImpactBP) {
        if (reserveIn == 0 || reserveOut == 0) return 0;
        
        // Simplified price impact calculation
        // impact = (amountIn / reserveIn) * 10000
        priceImpactBP = (amountIn * 10000) / reserveIn;
        
        return priceImpactBP;
    }
    
    /**
     * @notice Aggregate swap statistics from multiple events
     * @param swaps Array of parsed swaps
     * @param tokenIsToken0 True if monitored token is token0
     * @return totalBuyVolume Total tokens bought
     * @return totalSellVolume Total tokens sold
     * @return uniqueBuyers Count of unique buyer addresses
     * @return uniqueSellers Count of unique seller addresses
     * @return avgGasPrice Average gas price (needs to be passed separately)
     */
    function aggregateSwapStats(
        ParsedSwap[] memory swaps,
        bool tokenIsToken0
    ) internal pure returns (
        uint256 totalBuyVolume,
        uint256 totalSellVolume,
        uint256 uniqueBuyers,
        uint256 uniqueSellers,
        uint256 avgGasPrice
    ) {
        totalBuyVolume = 0;
        totalSellVolume = 0;
        
        // Note: Unique counting is simplified - in production would need proper deduplication
        uniqueBuyers = 0;
        uniqueSellers = 0;
        
        for (uint256 i = 0; i < swaps.length; i++) {
            (bool isBuy, uint256 tokenAmount,) = analyzeSwapDirection(swaps[i], tokenIsToken0);
            
            if (isBuy) {
                totalBuyVolume += tokenAmount;
                uniqueBuyers++;
            } else {
                totalSellVolume += tokenAmount;
                uniqueSellers++;
            }
        }
        
        // Gas price would need to be passed from transaction context
        avgGasPrice = 0;
        
        return (totalBuyVolume, totalSellVolume, uniqueBuyers, uniqueSellers, avgGasPrice);
    }
}
