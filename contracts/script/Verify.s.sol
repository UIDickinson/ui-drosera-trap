// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "../src/v2/FairLaunchGuardianTrapSimple.sol";
import "../src/v2/FairLaunchGuardianTrapEventLog.sol";
import "../src/v2/FairLaunchGuardianTrapAdvanced.sol";
import "../src/v2/FairLaunchResponder.sol";
import "../src/v2/FairLaunchConfig.sol";

/**
 * @title VerifyTrap
 * @notice Script to verify V2 trap deployment and configuration
 */
contract VerifyTrap is Script {
    
    function run() external view {
        address trapAddress = vm.envAddress("TRAP_ADDRESS");
        string memory strategy = vm.envOr("STRATEGY", string("simple"));
        
        console.log("=== Verifying V2 Trap Deployment ===");
        console.log("Trap Address:", trapAddress);
        console.log("Strategy:", strategy);
        console.log("");
        
        // Show FairLaunchConfig values
        console.log("FairLaunchConfig:");
        console.log("  Token:", FairLaunchConfig.tokenAddress());
        console.log("  Pool:", FairLaunchConfig.liquidityPool());
        console.log("  tokenIsToken0:", FairLaunchConfig.tokenIsToken0());
        console.log("");
        
        if (keccak256(bytes(strategy)) == keccak256(bytes("simple"))) {
            _verifySimpleTrap(trapAddress);
        } else if (keccak256(bytes(strategy)) == keccak256(bytes("eventlog"))) {
            _verifyEventLogTrap(trapAddress);
        } else if (keccak256(bytes(strategy)) == keccak256(bytes("advanced"))) {
            _verifyAdvancedTrap(trapAddress);
        } else {
            console.log("Unknown strategy. Defaulting to simple.");
            _verifySimpleTrap(trapAddress);
        }
        
        console.log("");
        console.log("=== Verification Complete ===");
    }
    
    function _verifySimpleTrap(address trapAddress) internal view {
        FairLaunchGuardianTrapSimple trap = FairLaunchGuardianTrapSimple(trapAddress);
        
        (address token, address pool) = trap.getConfig();
        console.log("Simple Trap Configuration:");
        console.log("  Token:", token);
        console.log("  Pool:", pool);
        console.log("");
        
        // Test collect()
        console.log("Testing collect() function...");
        try trap.collect() returns (bytes memory data) {
            console.log("collect() successful - returned", data.length, "bytes");
        } catch {
            console.log("collect() failed - check implementation");
        }
    }
    
    function _verifyEventLogTrap(address trapAddress) internal view {
        FairLaunchGuardianTrapEventLog trap = FairLaunchGuardianTrapEventLog(trapAddress);
        
        (address token, address pool, bool isToken0) = trap.getConfig();
        console.log("EventLog Trap Configuration:");
        console.log("  Token:", token);
        console.log("  Pool:", pool);
        console.log("  tokenIsToken0:", isToken0);
        console.log("");
        
        // Test collect()
        console.log("Testing collect() function...");
        try trap.collect() returns (bytes memory data) {
            console.log("collect() successful - returned", data.length, "bytes");
        } catch {
            console.log("collect() failed - check implementation");
        }
    }
    
    function _verifyAdvancedTrap(address trapAddress) internal view {
        FairLaunchGuardianTrapAdvanced trap = FairLaunchGuardianTrapAdvanced(trapAddress);
        
        console.log("Advanced Trap Configuration:");
        console.log("  Token:", trap.getTokenAddress());
        console.log("  Pool:", trap.getLiquidityPool());
        console.log("");
        
        // Test collect()
        console.log("Testing collect() function...");
        try trap.collect() returns (bytes memory data) {
            console.log("collect() successful - returned", data.length, "bytes");
        } catch {
            console.log("collect() failed - check implementation");
        }
    }
}

/**
 * @title VerifyResponder
 * @notice Script to verify V2 responder deployment
 */
contract VerifyResponder is Script {
    
    function run() external view {
        address responderAddress = vm.envAddress("RESPONDER_ADDRESS");
        
        console.log("=== Verifying V2 Responder Deployment ===");
        console.log("Responder Address:", responderAddress);
        console.log("");
        
        FairLaunchResponder responder = FairLaunchResponder(responderAddress);
        
        console.log("Responder Configuration:");
        console.log("  Token:", responder.guardedToken());
        console.log("  Pool:", responder.guardedPool());
        console.log("  Drosera:", responder.droseraAddress());
        console.log("  Total Incidents:", responder.totalIncidents());
        console.log("");
        
        console.log("=== Verification Complete ===");
    }
}