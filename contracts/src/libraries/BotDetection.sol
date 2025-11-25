// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./LaunchMetrics.sol";

/**
 * @title BotDetection
 * @notice Library with bot detection algorithms
 */
library BotDetection {
    using LaunchMetrics for uint256;
    
    struct BuyPattern {
        address buyer;
        uint256 amount;
        uint256 gasPrice;
        uint256 blockNumber;
    }
    
    /**
     * @notice Check if buying pattern indicates bot activity
     * @param patterns Array of buy patterns
     * @param rapidBuyThreshold Number of buys to trigger detection
     * @param blockWindow Window in blocks
     * @return isBot True if bot pattern detected
     * @return buyCount Number of buys in window
     */
    function isRapidBuyPattern(
        BuyPattern[] memory patterns,
        uint256 rapidBuyThreshold,
        uint256 blockWindow
    ) internal pure returns (bool isBot, uint256 buyCount) {
        if (patterns.length < rapidBuyThreshold) {
            return (false, patterns.length);
        }
        
        // Find first and last buy blocks
        uint256 firstBlock = type(uint256).max;
        uint256 lastBlock = 0;
        
        for (uint256 i = 0; i < patterns.length; i++) {
            if (patterns[i].blockNumber < firstBlock) {
                firstBlock = patterns[i].blockNumber;
            }
            if (patterns[i].blockNumber > lastBlock) {
                lastBlock = patterns[i].blockNumber;
            }
        }
        
        uint256 blocksSpan = lastBlock > firstBlock ? lastBlock - firstBlock : 0;
        buyCount = patterns.length;
        
        isBot = (buyCount >= rapidBuyThreshold) && (blocksSpan <= blockWindow);
    }
    
    /**
     * @notice Check if multiple buyers are coordinating
     * @param amounts Array of buy amounts
     * @param coordinatedThreshold Minimum buyers to flag
     * @param similarityPercent Percentage similarity required
     * @return isCoordinated True if coordinated attack detected
     * @return similarCount Number of similar amounts
     */
    function isCoordinatedAttack(
        uint256[] memory amounts,
        uint256 coordinatedThreshold,
        uint256 similarityPercent
    ) internal pure returns (bool isCoordinated, uint256 similarCount) {
        if (amounts.length < coordinatedThreshold) {
            return (false, 0);
        }
        
        // Use first amount as reference
        uint256 referenceAmount = amounts[0];
        similarCount = 1; // First amount is always similar to itself
        
        // Count how many amounts are similar to reference
        for (uint256 i = 1; i < amounts.length; i++) {
            if (LaunchMetrics.areSimilar(amounts[i], referenceAmount, similarityPercent)) {
                similarCount++;
            }
        }
        
        // Coordinated if enough similar amounts
        isCoordinated = (amounts.length >= coordinatedThreshold) && (similarCount >= 3);
    }
    
    /**
     * @notice Calculate bot likelihood score (0-100)
     * @param buyCount Number of buys
     * @param blockSpan Blocks span
     * @param gasPremiumBP Gas premium in basis points
     * @return score Bot likelihood score
     */
    function calculateBotScore(
        uint256 buyCount,
        uint256 blockSpan,
        uint256 gasPremiumBP
    ) internal pure returns (uint256 score) {
        uint256 rapidScore = 0;
        uint256 gasScore = 0;
        
        // Score based on rapid buying (max 50 points)
        if (blockSpan <= 3 && buyCount >= 5) {
            rapidScore = 50;
        } else if (blockSpan <= 5 && buyCount >= 3) {
            rapidScore = 30;
        } else if (blockSpan <= 10 && buyCount >= 2) {
            rapidScore = 15;
        }
        
        // Score based on gas premium (max 50 points)
        if (gasPremiumBP >= 1000) { // 10x or more
            gasScore = 50;
        } else if (gasPremiumBP >= 500) { // 5x or more
            gasScore = 40;
        } else if (gasPremiumBP >= 200) { // 2x or more
            gasScore = 25;
        }
        
        score = rapidScore + gasScore;
        return score > 100 ? 100 : score;
    }
}