// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title ITrap
 * @notice Interface that all Drosera traps must implement
 * @dev Based on Drosera specification - trap must be stateless and deterministic
 * 
 * Key Requirements:
 * - collect() must be VIEW (no state changes)
 * - shouldRespond() must be PURE (no state reads or writes)
 * - Both functions must be deterministic across operators
 */
interface ITrap {
    /**
     * @notice Collects current on-chain state snapshot
     * @dev Called by Drosera operator on shadow fork at sampled block
     * @return data Encoded snapshot of current state
     */
    function collect() external view returns (bytes memory data);
    
    /**
     * @notice Analyzes collected data to determine if response is needed
     * @dev Must be PURE - no state reads/writes for operator consensus
     * @param data Array of historical collect() outputs (window-based analysis)
     * @return shouldRespond True if violation detected
     * @return responseData Encoded payload for responder contract
     */
    function shouldRespond(
        bytes[] calldata data
    ) external pure returns (bool shouldRespond, bytes memory responseData);
}