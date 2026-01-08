// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/v2/FairLaunchGuardianTrapEventLog.sol";

/**
 * @title DeployEventLogTrap
 * @notice Deploy the EventLog trap to Hoodi testnet
 * @dev Run with: forge script script/DeployEventLogTrap.s.sol:DeployEventLogTrap --rpc-url https://ethereum-hoodi-rpc.publicnode.com --broadcast -vv
 */
contract DeployEventLogTrap is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        
        console.log("========================================");
        console.log("  EventLog Trap Deployment - Hoodi");
        console.log("========================================");
        console.log("");
        
        vm.startBroadcast(deployerPrivateKey);
        
        // Deploy EventLog Trap (stateless, uses compiled-in constants)
        console.log("Deploying FairLaunchGuardianTrapEventLog...");
        FairLaunchGuardianTrapEventLog trap = new FairLaunchGuardianTrapEventLog();
        console.log("  Trap:", address(trap));
        console.log("");
        
        vm.stopBroadcast();
        
        // Verify config
        (address configToken, address configPool,) = trap.getConfig();
        console.log("========================================");
        console.log("  Configuration Verification");
        console.log("========================================");
        console.log("  Token:", configToken);
        console.log("  Pool:", configPool);
        console.log("");
        
        console.log("========================================");
        console.log("  Deployment Complete!");
        console.log("========================================");
        console.log("");
        console.log("EventLog Trap:", address(trap));
        console.log("");
        console.log("Update drosera.toml with:");
        console.log("  trap_address = \"", address(trap), "\"");
        console.log("");
        console.log("Register with: drosera register", address(trap));
    }
}
