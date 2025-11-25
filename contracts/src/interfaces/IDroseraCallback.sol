// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title IDroseraCallback
 * @notice Interface for contracts that receive trap responses
 */
interface IDroseraCallback {
    /**
     * @notice Called by Drosera when a trap detects a violation
     * @param trapAddress Address of the trap that detected the violation
     * @param responseData Encoded response data from shouldRespond()
     */
    function onTrapResponse(
        address trapAddress,
        bytes calldata responseData
    ) external;
    
    /**
     * @notice Called to verify the callback contract is valid
     */
    function supportsCallback() external pure returns (bool);
}