// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../../src/interfaces/IDroseraCallback.sol";

/**
 * @title MockDroseraCallback
 * @notice Mock callback contract for testing responses
 */
contract MockDroseraCallback is IDroseraCallback {
    
    struct ResponseLog {
        address trapAddress;
        bytes responseData;
        uint256 timestamp;
        uint256 blockNumber;
    }
    
    ResponseLog[] public responses;
    
    event TrapResponseReceived(
        address indexed trapAddress,
        bytes responseData,
        uint256 timestamp
    );
    
    /**
     * @notice Called when trap detects violation
     */
    function onTrapResponse(
        address trapAddress,
        bytes calldata responseData
    ) external override {
        responses.push(ResponseLog({
            trapAddress: trapAddress,
            responseData: responseData,
            timestamp: block.timestamp,
            blockNumber: block.number
        }));
        
        emit TrapResponseReceived(trapAddress, responseData, block.timestamp);
    }
    
    /**
     * @notice Check if callback is supported
     */
    function supportsCallback() external pure override returns (bool) {
        return true;
    }
    
    /**
     * @notice Get number of responses received
     */
    function getResponseCount() external view returns (uint256) {
        return responses.length;
    }
    
    /**
     * @notice Get specific response
     */
    function getResponse(uint256 index) external view returns (ResponseLog memory) {
        require(index < responses.length, "Index out of bounds");
        return responses[index];
    }
    
    /**
     * @notice Get latest response
     */
    function getLatestResponse() external view returns (ResponseLog memory) {
        require(responses.length > 0, "No responses");
        return responses[responses.length - 1];
    }
    
    /**
     * @notice Clear all responses (for testing)
     */
    function clearResponses() external {
        delete responses;
    }
}