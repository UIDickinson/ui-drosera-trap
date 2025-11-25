// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "../src/FairLaunchGuardianTrap.sol";

/**
 * @title SimulateDetection
 * @notice Script to test detection logic without deploying
 */
contract SimulateDetection is Script {
    
    function run() external {
        console.log("=== Simulating Detection Logic ===");
        
        // Create mock collect data
        bytes[] memory mockData = new bytes[](3);
        
        // Mock data for 3 blocks
        address[] memory buyers1 = new address[](1);
        buyers1[0] = address(0x123);
        uint256[] memory amounts1 = new uint256[](1);
        amounts1[0] = 8000; // 8% of supply
        uint256[] memory gas1 = new uint256[](1);
        gas1[0] = 100 gwei;
        
        mockData[0] = abi.encode(FairLaunchGuardianTrap.CollectOutput({
            blockNumber: 1002,
            recentBuyers: buyers1,
            buyAmounts: amounts1,
            gasPrices: gas1,
            totalSupply: 100000,
            liquidityPoolBalance: 50000,
            averageGasPrice: 50 gwei
        }));
        
        // Similar for blocks 1 and 2
        mockData[1] = mockData[0];
        mockData[2] = mockData[0];
        
        console.log("Mock data created for 3 blocks");
        console.log("Buyer:", buyers1[0]);
        console.log("Amount: 8000 (8% of 100,000 supply)");
        console.log("This should trigger EXCESSIVE_ACCUMULATION");
        console.log("");
        console.log("To test with real trap, deploy and call shouldRespond()");
    }
}