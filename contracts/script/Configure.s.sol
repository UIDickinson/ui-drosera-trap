// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/FairLaunchGuardianTrap.sol";

/**
 * @title ConfigureTrap
 * @notice Script to configure an already deployed trap
 */
contract ConfigureTrap is Script {
    
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address trapAddress = vm.envAddress("TRAP_ADDRESS");
        
        console.log("=== Configuring Trap ===");
        console.log("Trap Address:", trapAddress);
        
        FairLaunchGuardianTrap trap = FairLaunchGuardianTrap(trapAddress);
        
        vm.startBroadcast(deployerPrivateKey);
        
        // Example: Deactivate trap
        // trap.deactivate();
        
        // Add more configuration commands here as needed
        
        vm.stopBroadcast();
        
        console.log("Configuration complete!");
    }
}