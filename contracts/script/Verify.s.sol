// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "../src/FairLaunchGuardianTrap.sol";

/**
 * @title VerifyTrap
 * @notice Script to verify trap deployment and configuration
 */
contract VerifyTrap is Script {
    
    function run() external view {
        address trapAddress = vm.envAddress("TRAP_ADDRESS");
        
        console.log("=== Verifying Trap Deployment ===");
        console.log("Trap Address:", trapAddress);
        console.log("");
        
        FairLaunchGuardianTrap trap = FairLaunchGuardianTrap(trapAddress);
        
        // Get configuration
        FairLaunchGuardianTrap.LaunchConfig memory config = trap.getConfig();
        
        console.log("Configuration:");
        console.log("  Token Address:", config.tokenAddress);
        console.log("  Liquidity Pool:", config.liquidityPool);
        console.log("  Launch Block:", config.launchBlock);
        console.log("  Monitoring Duration:", config.monitoringDuration);
        console.log("  Max Wallet BP:", config.maxWalletBasisPoints);
        console.log("  Max Gas Premium BP:", config.maxGasPremiumBasisPoints);
        console.log("  Is Active:", config.isActive);
        console.log("");
        
        // Check if monitoring is active
        bool isMonitoring = trap.isMonitoringActive();
        console.log("Monitoring Active:", isMonitoring);
        
        // Test collect()
        console.log("");
        console.log("Testing collect() function...");
        try trap.collect() returns (bytes memory data) {
            console.log("collect() successful - returned", data.length, "bytes");
        } catch {
            console.log("collect() failed - check implementation");
        }
        
        console.log("");
        console.log("=== Verification Complete ===");
    }
}