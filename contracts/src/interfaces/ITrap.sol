// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title ITrap
 * @notice Interface that all Drosera traps must implement
 */
 
interface ITrap {
    function collect() external view returns (bytes memory data);
    
    function shouldRespond(
        bytes[] calldata data
    ) external returns (bool shouldRespond, bytes memory responseData);
}