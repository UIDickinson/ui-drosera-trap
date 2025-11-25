// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/FairLaunchGuardianTrap.sol";
import "../src/demo/DemoToken.sol";
import "../src/demo/DemoDex.sol";

/**
 * @title DeployDemo
 * @notice Complete demo deployment script for Foundry
 * @dev Run with: forge script script/DeployDemo.s.sol --broadcast --rpc-url $HOODI_RPC
 */
contract DeployDemo is Script {
    
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        
        console.log("========================================");
        console.log("  Fair Launch Guardian - Demo Deploy");
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
        
        // 3. Deploy Trap
        console.log("Step 3: Deploying Fair Launch Guardian Trap...");
        FairLaunchGuardianTrap trap = new FairLaunchGuardianTrap(
            address(token),
            address(dex),
            block.number,  // Launch now
            50,            // Monitor 50 blocks
            500,           // 5% max wallet
            200            // 2x max gas
        );
        console.log("  Trap:", address(trap));
        console.log("");
        
        // 4. Integrate trap with token
        console.log("Step 4: Integrating trap with token...");
        token.integrateTrap(address(trap), address(dex));
        console.log("  Integration complete!");
        console.log("");
        
        // 5. Add liquidity
        console.log("Step 5: Adding liquidity to DEX...");
        uint256 liquidityAmount = 500000 * 10**18; // 500k tokens
        token.approve(address(dex), liquidityAmount);
        dex.addLiquidity(liquidityAmount);
        console.log("  Liquidity (tokens):", liquidityAmount / 10**18);
        console.log("");
        
        vm.stopBroadcast();
        
        // Print summary
        console.log("========================================");
        console.log("  Deployment Complete!");
        console.log("========================================");
        console.log("");
        console.log("Deployed Contracts:");
        console.log("  Token:  ", address(token));
        console.log("  DEX:    ", address(dex));
        console.log("  Trap:   ", address(trap));
        console.log("");
        console.log("Verify on Etherscan:");
        console.log("  https://hoodi.etherscan.io/address/", address(token));
        console.log("  https://hoodi.etherscan.io/address/", address(trap));
        console.log("");
        console.log("Next Steps:");
        console.log("1. Normal user buy:");
        console.log("   cast send", address(dex), '"swap()"', "--value 0.5ether --rpc-url $HOODI_RPC");
        console.log("");
        console.log("2. Bot attack (will be blocked):");
        console.log("   cast send", address(dex), '"swap()"', "--value 10ether --rpc-url $HOODI_RPC");
        console.log("");
        console.log("3. Check blacklist:");
        console.log("   cast call", address(trap), '"isBlacklisted(address)"', "<BOT_ADDRESS> --rpc-url $HOODI_RPC");
        console.log("");
        console.log("Save these addresses!");
        console.log("");
    }
}

/**
 * @title TestDemo
 * @notice Test the deployed demo contracts
 */
contract TestDemo is Script {
    
    function run() external {
        address tokenAddr = vm.envAddress("TOKEN_ADDRESS");
        address payable dexAddr = payable(vm.envAddress("DEX_ADDRESS"));
        address trapAddr = vm.envAddress("TRAP_ADDRESS");
        
        console.log("Testing deployed contracts...");
        console.log("");
        
        DemoToken token = DemoToken(tokenAddr);
        DemoDEX dex = DemoDEX(dexAddr);
        FairLaunchGuardianTrap trap = FairLaunchGuardianTrap(trapAddr);
        
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
        
        // Check trap
        console.log("Trap:");
        FairLaunchGuardianTrap.LaunchConfig memory config = trap.getConfig();
        console.log("  Active:", trap.isMonitoringActive());
        console.log("  Max Wallet BP:", config.maxWalletBasisPoints);
        console.log("  Launch Block:", config.launchBlock);
        console.log("");
        
        console.log("All systems operational!");
    }
}
