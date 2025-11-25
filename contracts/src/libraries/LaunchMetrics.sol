// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title LaunchMetrics
 * @notice Helper library for calculating launch-related metrics
 */
library LaunchMetrics {
    uint256 public constant BASIS_POINTS = 10000; // 100% = 10000 BP
    
    /**
     * @notice Calculate percentage in basis points
     * @param part The part value
     * @param total The total value
     * @return Percentage in basis points (10000 = 100%)
     */
    function calculatePercentBP(uint256 part, uint256 total) internal pure returns (uint256) {
        if (total == 0) return 0;
        return (part * BASIS_POINTS) / total;
    }
    
    /**
     * @notice Calculate gas premium in basis points
     * @param actualGas The gas price paid
     * @param averageGas The average gas price
     * @return Premium in basis points (10000 = 100% premium = 2x gas)
     */
    function calculateGasPremiumBP(uint256 actualGas, uint256 averageGas) internal pure returns (uint256) {
        if (averageGas == 0) return 0;
        if (actualGas <= averageGas) return 0;
        
        uint256 premium = actualGas - averageGas;
        return (premium * BASIS_POINTS) / averageGas;
    }
    
    /**
     * @notice Calculate severity score (0-100) based on how much limit was exceeded
     * @param actual The actual value
     * @param limit The limit value
     * @return Severity score from 0-100
     */
    function calculateSeverity(uint256 actual, uint256 limit) internal pure returns (uint256) {
        if (actual <= limit) return 0;
        
        uint256 excess = actual - limit;
        uint256 severity = (excess * 100) / limit;
        
        return severity > 100 ? 100 : severity;
    }
    
    /**
     * @notice Check if values are within a percentage range of each other
     * @param value1 First value
     * @param value2 Second value
     * @param tolerancePercent Tolerance in percentage (e.g., 10 = 10%)
     * @return True if values are similar within tolerance
     */
    function areSimilar(uint256 value1, uint256 value2, uint256 tolerancePercent) internal pure returns (bool) {
        if (value1 == value2) return true;
        
        uint256 larger = value1 > value2 ? value1 : value2;
        uint256 smaller = value1 < value2 ? value1 : value2;
        uint256 diff = larger - smaller;
        
        // Check if difference is within tolerance
        return (diff * 100) <= (smaller * tolerancePercent);
    }
    
    /**
     * @notice Calculate average from array of values
     * @param values Array of values
     * @return Average value
     */
    function calculateAverage(uint256[] memory values) internal pure returns (uint256) {
        if (values.length == 0) return 0;
        
        uint256 sum = 0;
        for (uint256 i = 0; i < values.length; i++) {
            sum += values[i];
        }
        
        return sum / values.length;
    }
}