// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/v2/FairLaunchGuardianTrapSimple.sol";
import "../src/v2/FairLaunchResponder.sol";
import "../src/v2/FairLaunchConfig.sol";
import "../src/demo/DemoToken.sol";
import "../src/demo/DemoDex.sol";

/**
 * @title DeployDemo
 * @notice Complete demo deployment script for Foundry (V2 Architecture)
 * @dev Run with: forge script script/DeployDemo.s.sol --broadcast --rpc-url $HOODI_RPC
 * 
 * V2 Architecture:
 * - Trap is stateless (no constructor args)
 * - Responder handles actions (pause, blacklist)
 * - Token/Pool addresses are baked into FairLaunchConfig
 */
contract DeployDemo is Script {
    
    address constant DROSERA_ADDRESS = 0x91cB447BaFc6e0EA0F4Fe056F5a9b1F14bb06e5D;
    
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        
        console.log("========================================");
        console.log("  Fair Launch Guardian V2 - Demo Deploy");
        console.log("========================================");
        console.log("");
        
        vm.startBroadcast(deployerPrivateKey);
        
        // 1. Deploy Token
        console.log("Step 1: Deploying DemoToken...");
        DemoToken token = new DemoToken(
            "Demo Launch Token",
            "DLT",
            1000000 * 10**18  // 1 million tokens
        );
        console.log("  Token:", address(token));
        console.log("");
        
        // 2. Deploy DEX
        console.log("Step 2: Deploying DemoDEX...");
        DemoDEX dex = new DemoDEX(address(token));
        console.log("  DEX:", address(dex));
        console.log("");
        
        // 3. Deploy Responder (handles actions)
        console.log("Step 3: Deploying FairLaunchResponder...");
        FairLaunchResponder responder = new FairLaunchResponder(
            DROSERA_ADDRESS,
            address(token),
            address(dex)
        );
        console.log("  Responder:", address(responder));
        console.log("");
        
        // 4. Deploy Trap (stateless detection)
        console.log("Step 4: Deploying FairLaunchGuardianTrapSimple...");
        FairLaunchGuardianTrapSimple trap = new FairLaunchGuardianTrapSimple();
        console.log("  Trap:", address(trap));
        console.log("");
        
        // 5. Add liquidity
        console.log("Step 5: Adding liquidity to DEX...");
        uint256 liquidityAmount = 500000 * 10**18; // 500k tokens
        token.approve(address(dex), liquidityAmount);
        dex.addLiquidity(liquidityAmount);
        console.log("  Liquidity (tokens):", liquidityAmount / 10**18);
        console.log("");
        
        vm.stopBroadcast();
        
        // Check config alignment
        (address configToken, address configPool) = trap.getConfig();
        console.log("========================================");
        console.log("  Configuration Check");
        console.log("========================================");
        console.log("FairLaunchConfig values:");
        console.log("  Token:", configToken);
        console.log("  Pool:", configPool);
        console.log("");
        if (configToken != address(token) || configPool != address(dex)) {
            console.log("WARNING: FairLaunchConfig addresses do not match deployed contracts!");
            console.log("Update FairLaunchConfig.sol with:");
            console.log("  TOKEN_ADDRESS =", address(token));
            console.log("  LIQUIDITY_POOL =", address(dex));
        }
        console.log("");
        
        // Print summary
        console.log("========================================");
        console.log("  Deployment Complete!");
        console.log("========================================");
        console.log("");
        console.log("Deployed Contracts:");
        console.log("  Token:     ", address(token));
        console.log("  DEX:       ", address(dex));
        console.log("  Responder: ", address(responder));
        console.log("  Trap:      ", address(trap));
        console.log("");
        console.log("Update drosera.toml:");
        console.log("  response_contract =", address(responder));
        console.log("");
        console.log("Next Steps:");
        console.log("1. Update FairLaunchConfig.sol with deployed addresses");
        console.log("2. Rebuild: forge build");
        console.log("3. Register trap: drosera register", address(trap));
        console.log("");
        console.log("Save these addresses!");
        console.log("");
    }
}

/**
 * @title TestDemo
 * @notice Test the deployed demo contracts (V2)
 */
contract TestDemo is Script {
    
    function run() external {
        address tokenAddr = vm.envAddress("TOKEN_ADDRESS");
        address payable dexAddr = payable(vm.envAddress("DEX_ADDRESS"));
        address trapAddr = vm.envAddress("TRAP_ADDRESS");
        address responderAddr = vm.envAddress("RESPONDER_ADDRESS");
        
        console.log("Testing deployed V2 contracts...");
        console.log("");
        
        DemoToken token = DemoToken(tokenAddr);
        DemoDEX dex = DemoDEX(dexAddr);
        FairLaunchGuardianTrapSimple trap = FairLaunchGuardianTrapSimple(trapAddr);
        FairLaunchResponder responder = FairLaunchResponder(responderAddr);
        
        // Check token
        console.log("Token:");
        console.log("  Name:", token.name());
        console.log("  Symbol:", token.symbol());
        console.log("  Supply:", token.totalSupply() / 10**18);
        console.log("");
        
        // Check DEX
        console.log("DEX:");
        console.log("  Reserve:", dex.getReserve() / 10**18, "tokens");
        console.log("  Price:", dex.getPrice(), "wei per token");
        console.log("");
        
        // Check trap config
        console.log("Trap:");
        (address configToken, address configPool) = trap.getConfig();
        console.log("  Config Token:", configToken);
        console.log("  Config Pool:", configPool);
        console.log("");
        
        // Check responder
        console.log("Responder:");
        console.log("  Token:", responder.guardedToken());
        console.log("  Pool:", responder.guardedPool());
        console.log("  Incidents:", responder.totalIncidents());
        console.log("");
        
        console.log("All V2 systems operational!");
    }
}
