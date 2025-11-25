// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "../src/FairLaunchGuardianTrap.sol";
import "../test/mocks/MockToken.sol";
import "../test/mocks/MockDEX.sol";

/**
 * @title DeployFairLaunchGuardian
 * @notice Main deployment script for Fair Launch Guardian Trap
 * @dev Run with: forge script script/Deploy.s.sol:DeployFairLaunchGuardian --rpc-url $RPC_URL --broadcast
 */
contract DeployFairLaunchGuardian is Script {
    
    function run() external {
        // Load environment variables
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        
        // Configuration - Load from environment or use defaults
        address tokenAddress = vm.envOr("TOKEN_ADDRESS", address(0));
        address liquidityPool = vm.envOr("LIQUIDITY_POOL", address(0));
        uint256 launchBlock = vm.envOr("LAUNCH_BLOCK", block.number);
        uint256 monitoringDuration = vm.envOr("MONITORING_DURATION", uint256(50));
        uint256 maxWalletBP = vm.envOr("MAX_WALLET_BP", uint256(500)); // 5%
        uint256 maxGasPremiumBP = vm.envOr("MAX_GAS_PREMIUM_BP", uint256(200)); // 2x
        
        // Validation
        require(tokenAddress != address(0), "TOKEN_ADDRESS not set in .env");
        require(liquidityPool != address(0), "LIQUIDITY_POOL not set in .env");
        require(monitoringDuration > 0 && monitoringDuration <= 200, "Invalid monitoring duration");
        require(maxWalletBP > 0 && maxWalletBP <= 10000, "Invalid max wallet BP");
        
        console.log("========================================");
        console.log("  Fair Launch Guardian Deployment");
        console.log("========================================");
        console.log("");
        console.log("Deployer:", vm.addr(deployerPrivateKey));
        console.log("Network:", block.chainid);
        console.log("");
        console.log("Configuration:");
        console.log("  Token Address:", tokenAddress);
        console.log("  Liquidity Pool:", liquidityPool);
        console.log("  Launch Block:", launchBlock);
        console.log("  Monitoring Duration (blocks):", monitoringDuration);
        console.log("  Max Wallet BP:", maxWalletBP);
        console.log("  Max Gas Premium BP:", maxGasPremiumBP);
        console.log("");
        
        // Start broadcasting transactions
        vm.startBroadcast(deployerPrivateKey);
        
        // Deploy the trap
        FairLaunchGuardianTrap trap = new FairLaunchGuardianTrap(
            tokenAddress,
            liquidityPool,
            launchBlock,
            monitoringDuration,
            maxWalletBP,
            maxGasPremiumBP
        );
        
        vm.stopBroadcast();
        
        // Output deployment info
        console.log("========================================");
        console.log("  Deployment Successful!");
        console.log("========================================");
        console.log("");
        console.log("Trap Address:", address(trap));
        console.log("");
        console.log("Next Steps:");
        console.log("1. Save the trap address to your .env file:");
        console.log("   TRAP_ADDRESS=", address(trap));
        console.log("");
        console.log("2. Verify contract on block explorer:");
        console.log("   forge verify-contract", address(trap));
        console.log("   src/FairLaunchGuardianTrap.sol:FairLaunchGuardianTrap");
        console.log("   --chain-id", block.chainid);
        console.log("");
        console.log("3. Register on Drosera:");
        console.log("   Visit: https://app.drosera.io");
        console.log("   Register trap:", address(trap));
        console.log("");
        console.log("4. Test your trap:");
        console.log("   forge script script/Verify.s.sol --rpc-url $RPC_URL");
        console.log("");
        console.log("========================================");
    }
}

/**
 * @title DeployWithMockToken
 * @notice Deploy trap with mock token and DEX for complete testing
 * @dev Useful for testing without external dependencies
 */
contract DeployWithMockToken is Script {
    
    function run() external returns (address, address, address) {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        
        console.log("========================================");
        console.log("  Deploying Test Environment");
        console.log("========================================");
        console.log("");
        console.log("Deployer:", vm.addr(deployerPrivateKey));
        console.log("");
        
        vm.startBroadcast(deployerPrivateKey);
        
        // 1. Deploy mock token
        console.log("Step 1/4: Deploying mock token...");
        MockToken token = new MockToken(
            "Test Launch Token",
            "TLT",
            1000000 * 10**18  // 1 million tokens
        );
        console.log("  Token deployed:", address(token));
        console.log("  Name:", token.name());
        console.log("  Symbol:", token.symbol());
        console.log("  Total Supply:", token.totalSupply() / 10**18, "TLT");
        console.log("");
        
        // 2. Deploy mock DEX
        console.log("Step 2/4: Deploying mock DEX...");
        MockDEX dex = new MockDEX(address(token));
        console.log("  DEX deployed:", address(dex));
        console.log("");
        
        // 3. Add liquidity to DEX
        console.log("Step 3/4: Adding liquidity...");
        uint256 liquidityAmount = 500000 * 10**18; // 500k tokens
        bool success = token.transfer(address(dex), liquidityAmount);
        require(success, "Token transfer failed");
        console.log("  Liquidity added (tokens):", liquidityAmount / 10**18);
        console.log("  DEX Reserve (tokens):", dex.getReserve() / 10**18);
        console.log("");
        
        // 4. Deploy trap
        console.log("Step 4/4: Deploying trap...");
        FairLaunchGuardianTrap trap = new FairLaunchGuardianTrap(
            address(token),
            address(dex),
            block.number,       // Launch now
            50,                 // Monitor for 50 blocks
            500,                // 5% max wallet
            200                 // 2x max gas
        );
        console.log("  Trap deployed:", address(trap));
        console.log("");
        
        vm.stopBroadcast();
        
        // Output summary
        console.log("========================================");
        console.log("  Test Environment Ready!");
        console.log("========================================");
        console.log("");
        console.log("Contracts:");
        console.log("  Token:", address(token));
        console.log("  DEX:", address(dex));
        console.log("  Trap:", address(trap));
        console.log("");
        console.log("Save to .env:");
        console.log("  TOKEN_ADDRESS=", address(token));
        console.log("  LIQUIDITY_POOL=", address(dex));
        console.log("  TRAP_ADDRESS=", address(trap));
        console.log("");
        console.log("Test the setup:");
        console.log("  1. Buy some tokens:");
        console.log("     cast send", address(dex), '"swap()"');
        console.log("     --value 0.1ether --rpc-url $RPC_URL");
        console.log("");
        console.log("  2. Check your balance:");
        console.log("     cast call", address(token), '"balanceOf(address)"');
        console.log("     $YOUR_ADDRESS --rpc-url $RPC_URL");
        console.log("");
        console.log("  3. Simulate attack:");
        console.log("     See scripts/simulate-attack.js");
        console.log("");
        console.log("========================================");
        
        return (address(token), address(dex), address(trap));
    }
}

/**
 * @title DeployMinimal
 * @notice Minimal deployment for quick testing
 */
contract DeployMinimal is Script {
    
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address tokenAddress = vm.envAddress("TOKEN_ADDRESS");
        address liquidityPool = vm.envAddress("LIQUIDITY_POOL");
        
        console.log("Deploying trap...");
        console.log("Token:", tokenAddress);
        console.log("Pool:", liquidityPool);
        
        vm.startBroadcast(deployerPrivateKey);
        
        FairLaunchGuardianTrap trap = new FairLaunchGuardianTrap(
            tokenAddress,
            liquidityPool,
            block.number,
            50,   // 50 blocks
            500,  // 5%
            200   // 2x
        );
        
        vm.stopBroadcast();
        
        console.log("Trap deployed:", address(trap));
    }
}

/**
 * @title DeployCustomConfig
 * @notice Deploy with fully custom configuration
 */
contract DeployCustomConfig is Script {
    
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        
        // Custom configuration (modify as needed)
        address tokenAddress = 0x1234567890123456789012345678901234567890; // CHANGE THIS
        address liquidityPool = 0x0987654321098765432109876543210987654321; // CHANGE THIS
        uint256 launchBlock = block.number + 10; // Launch in 10 blocks
        uint256 monitoringDuration = 100;        // Monitor for 100 blocks
        uint256 maxWalletBP = 300;               // 3% max (strict)
        uint256 maxGasPremiumBP = 150;           // 1.5x gas (strict)
        
        console.log("Custom Configuration Deployment");
        console.log("Token:", tokenAddress);
        console.log("Pool:", liquidityPool);
        console.log("Launch Block:", launchBlock);
        console.log("Monitoring (blocks):", monitoringDuration);
        console.log("Max Wallet (BP):", maxWalletBP);
        console.log("Max Gas (BP):", maxGasPremiumBP);
        
        vm.startBroadcast(deployerPrivateKey);
        
        FairLaunchGuardianTrap trap = new FairLaunchGuardianTrap(
            tokenAddress,
            liquidityPool,
            launchBlock,
            monitoringDuration,
            maxWalletBP,
            maxGasPremiumBP
        );
        
        vm.stopBroadcast();
        
        console.log("");
        console.log("Trap deployed:", address(trap));
        console.log("Launch starts at block:", launchBlock);
        console.log("Current block:", block.number);
        console.log("Blocks until launch:", launchBlock - block.number);
    }
}