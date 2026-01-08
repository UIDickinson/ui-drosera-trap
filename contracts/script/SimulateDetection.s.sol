// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "../src/v2/FairLaunchGuardianTrapSimple.sol";

/**
 * @title SimulateDetection
 * @notice Script to test V2 Simple trap detection logic without deploying
 */
contract SimulateDetection is Script {
    
    function run() external {
        console.log("=== Simulating V2 Simple Trap Detection Logic ===");
        console.log("");
        
        // Create mock collect data using Simple trap's CollectOutput struct
        bytes[] memory mockData = new bytes[](3);
        
        // Mock data for block 1002 - normal state
        mockData[0] = abi.encode(
            uint256(1002),      // blockNumber
            uint256(1000000),   // timestamp
            uint256(1000000 ether), // totalSupply
            uint256(500000 ether)   // poolBalance (50% in pool)
        );
        
        // Mock data for block 1003 - slight drain
        mockData[1] = abi.encode(
            uint256(1003),
            uint256(1000012),
            uint256(1000000 ether),
            uint256(480000 ether)   // 4% drain
        );
        
        // Mock data for block 1004 - significant drain (should trigger)
        mockData[2] = abi.encode(
            uint256(1004),
            uint256(1000024),
            uint256(1000000 ether),
            uint256(400000 ether)   // 20% total drain - should trigger!
        );
        
        console.log("Mock data created for 3 blocks:");
        console.log("  Block 1002: Pool balance = 500,000 tokens (50%)");
        console.log("  Block 1003: Pool balance = 480,000 tokens (48%)");
        console.log("  Block 1004: Pool balance = 400,000 tokens (40%)");
        console.log("");
        console.log("This simulates a 20% liquidity drain over 3 blocks.");
        console.log("The Simple trap should detect LIQUIDITY_MANIPULATION.");
        console.log("");
        
        // Deploy a simple trap instance to test
        FairLaunchGuardianTrapSimple trap = new FairLaunchGuardianTrapSimple();
        
        console.log("Testing shouldRespond()...");
        (bool shouldRespond, bytes memory responseData) = trap.shouldRespond(mockData);
        
        if (shouldRespond) {
            console.log("DETECTION TRIGGERED!");
            console.log("Response data length:", responseData.length);
        } else {
            console.log("No detection triggered (threshold not met or data insufficient)");
        }
        
        console.log("");
        console.log("=== Simulation Complete ===");
    }
}