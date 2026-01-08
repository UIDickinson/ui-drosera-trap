// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "../src/v2/FairLaunchGuardianTrapSimple.sol";
import "../src/v2/FairLaunchGuardianTrapEventLog.sol";
import "../src/v2/FairLaunchGuardianTrapAdvanced.sol";
import "../src/v2/FairLaunchResponder.sol";
import "../src/v2/FairLaunchResponderAdvanced.sol";
import "../src/v2/FairLaunchConfig.sol";
import "../test/mocks/MockToken.sol";
import "../test/mocks/MockDEX.sol";

/**
 * @title DeployFairLaunchGuardianV2
 * @notice Deployment script for V2 stateless architecture (Trap + Responder)
 * @dev Run with: forge script script/Deploy.s.sol:DeployFairLaunchGuardianV2 --rpc-url $RPC_URL --broadcast
 * 
 * V2 Architecture:
 * 1. Deploy Responder first (needs Drosera address)
 * 2. Deploy Trap (stateless, no constructor args for Simple variant)
 * 3. Configure drosera.toml with both addresses
 * 
 * Deployment Strategies:
 * - Simple: No constructor args, hardcoded addresses, fastest deployment
 * - EventLog: Parse Uniswap events, production-ready, RECOMMENDED
 * - Advanced: Maximum detection, 6 algorithms, high gas costs
 */
contract DeployFairLaunchGuardianV2 is Script {
    
    // Drosera configuration
    address constant DROSERA_ADDRESS = 0x91cB447BaFc6e0EA0F4Fe056F5a9b1F14bb06e5D;
    
    function run() external {
        // Load environment variables
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        
        // Configuration - Load from environment
        address tokenAddress = vm.envOr("TOKEN_ADDRESS", address(0));
        address liquidityPool = vm.envOr("LIQUIDITY_POOL", address(0));
        string memory strategy = vm.envOr("STRATEGY", string("simple")); // simple, eventlog, advanced
        bool deployAdvancedResponder = vm.envOr("ADVANCED_RESPONDER", false);

        // Configured defaults baked into traps (must be updated before compile)
        address configuredToken = FairLaunchConfig.tokenAddress();
        address configuredPool = FairLaunchConfig.liquidityPool();
        bool configuredIsToken0 = FairLaunchConfig.tokenIsToken0();
        
        // Validation
        require(tokenAddress != address(0), "TOKEN_ADDRESS not set in .env");
        require(liquidityPool != address(0), "LIQUIDITY_POOL not set in .env");
        
        console.log("========================================");
        console.log("  Fair Launch Guardian V2 Deployment");
        console.log("========================================");
        console.log("");
        console.log("Deployer:", vm.addr(deployerPrivateKey));
        console.log("Network:", block.chainid);
        console.log("Drosera:", DROSERA_ADDRESS);
        console.log("");
        console.log("Configuration:");
        console.log("  Token Address:", tokenAddress);
        console.log("  Liquidity Pool:", liquidityPool);
        console.log("  Strategy:", strategy);
        console.log("  Advanced Responder:", deployAdvancedResponder);
        console.log("  Config Token (FairLaunchConfig):", configuredToken);
        console.log("  Config Pool  (FairLaunchConfig):", configuredPool);
        console.log("  Config tokenIsToken0:", configuredIsToken0);
        console.log("");
        
        // Start broadcasting transactions
        vm.startBroadcast(deployerPrivateKey);
        
        // Step 1: Deploy Responder
        address responder;
        if (deployAdvancedResponder) {
            console.log("Deploying FairLaunchResponderAdvanced...");
            FairLaunchResponderAdvanced advancedResponder = new FairLaunchResponderAdvanced(
                DROSERA_ADDRESS,
                tokenAddress,
                liquidityPool
            );
            responder = address(advancedResponder);
        } else {
            console.log("Deploying FairLaunchResponder...");
            FairLaunchResponder basicResponder = new FairLaunchResponder(
                DROSERA_ADDRESS,
                tokenAddress,
                liquidityPool
            );
            responder = address(basicResponder);
        }
        
        // Step 2: Deploy Trap based on strategy
        address trap;
        if (keccak256(bytes(strategy)) == keccak256(bytes("simple"))) {
            console.log("Deploying FairLaunchGuardianTrapSimple...");
            FairLaunchGuardianTrapSimple simpleTrap = new FairLaunchGuardianTrapSimple();
            trap = address(simpleTrap);
            (address trapToken, address trapPool) = simpleTrap.getConfig();
            _warnIfMismatch("Simple", trapToken, trapPool, tokenAddress, liquidityPool);
        } else if (keccak256(bytes(strategy)) == keccak256(bytes("eventlog"))) {
            console.log("Deploying FairLaunchGuardianTrapEventLog...");
            FairLaunchGuardianTrapEventLog eventLogTrap = new FairLaunchGuardianTrapEventLog();
            trap = address(eventLogTrap);
            (address trapToken, address trapPool, bool trapIsToken0) = eventLogTrap.getConfig();
            bool expectedIsToken0 = tokenAddress < liquidityPool;
            _warnIfMismatch("EventLog", trapToken, trapPool, tokenAddress, liquidityPool);
            _warnIsToken0Mismatch(trapIsToken0, expectedIsToken0);
        } else if (keccak256(bytes(strategy)) == keccak256(bytes("advanced"))) {
            console.log("Deploying FairLaunchGuardianTrapAdvanced...");
            FairLaunchGuardianTrapAdvanced advancedTrap = new FairLaunchGuardianTrapAdvanced();
            trap = address(advancedTrap);
            address trapToken = advancedTrap.getTokenAddress();
            address trapPool = advancedTrap.getLiquidityPool();
            _warnIfMismatch("Advanced", trapToken, trapPool, tokenAddress, liquidityPool);
        } else {
            revert("Invalid strategy. Use: simple, eventlog, or advanced");
        }
        
        vm.stopBroadcast();
        
        // Output deployment info
        console.log("========================================");
        console.log("  Deployment Successful!");
        console.log("========================================");
        console.log("");
        console.log("Contracts Deployed:");
        console.log("  Responder:", responder);
        console.log("  Trap:", trap);
        console.log("  Strategy:", strategy);
        console.log("");
        console.log("Next Steps:");
        console.log("");
        console.log("1. Update drosera.toml:");
        console.log("   Set response_contract =", responder);
        console.log("   in the appropriate [traps.*] section");
        console.log("");
        console.log("2. Register trap with Drosera:");
        console.log("   drosera register", trap);
        console.log("   --config drosera.toml");
        console.log("   --network hoodi");
        console.log("");
        console.log("3. Verify contracts:");
        console.log("   forge verify-contract", responder);
        console.log("   forge verify-contract", trap);
        console.log("");
        console.log("4. Test the setup:");
        console.log("   forge script script/Verify.s.sol --rpc-url $RPC_URL");
        console.log("");
        console.log("========================================");
        console.log("");
        console.log("Save to .env:");
        console.log("RESPONDER_ADDRESS=", responder);
        console.log("TRAP_ADDRESS=", trap);
        console.log("");
        console.log("========================================");
    }
}

function _warnIfMismatch(
    string memory label,
    address configuredToken,
    address configuredPool,
    address expectedToken,
    address expectedPool
) {
    if (configuredToken != expectedToken || configuredPool != expectedPool) {
        console.log("WARNING:", label, "trap constants differ from provided environment values");
        console.log("  Configured Token:", configuredToken);
        console.log("  Expected Token:", expectedToken);
        console.log("  Configured Pool:", configuredPool);
        console.log("  Expected Pool:", expectedPool);
        console.log("Update the trap constants before registering with Drosera.");
    }
}

function _warnIsToken0Mismatch(bool configured, bool expected) {
    if (configured != expected) {
        console.log("WARNING: TOKEN_IS_TOKEN0 constant does not match inferred ordering (token < pool)");
        console.log("  Configured tokenIsToken0:", configured);
        console.log("  Expected tokenIsToken0:", expected);
    }
}

/**
 * @title DeployTestEnvironmentV2
 * @notice Deploy complete test environment with V2 architecture
 * @dev Includes mock token, DEX, responder, and trap
 */
contract DeployTestEnvironmentV2 is Script {
    
    address constant DROSERA_ADDRESS = 0x91cB447BaFc6e0EA0F4Fe056F5a9b1F14bb06e5D;
    
    function run() external returns (address, address, address, address) {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        string memory strategy = vm.envOr("STRATEGY", string("simple"));
        address configuredToken = FairLaunchConfig.tokenAddress();
        address configuredPool = FairLaunchConfig.liquidityPool();
        bool configuredIsToken0 = FairLaunchConfig.tokenIsToken0();
        
        console.log("========================================");
        console.log("  V2 Test Environment Deployment");
        console.log("========================================");
        console.log("");
        console.log("Deployer:", vm.addr(deployerPrivateKey));
        console.log("Strategy:", strategy);
        console.log("Config Token (FairLaunchConfig):", configuredToken);
        console.log("Config Pool  (FairLaunchConfig):", configuredPool);
        console.log("Config tokenIsToken0:", configuredIsToken0);
        console.log("");
        
        vm.startBroadcast(deployerPrivateKey);
        
        // 1. Deploy mock token
        console.log("Step 1/4: Deploying mock token...");
        MockToken token = new MockToken("Test Token", "TEST", 1_000_000 ether);
        console.log("  Token:", address(token));
        
        // 2. Deploy mock DEX (pool)
        console.log("Step 2/4: Deploying mock DEX...");
        MockDEX dex = new MockDEX(address(token));
        console.log("  Pool:", address(dex));
        
        // 3. Add liquidity
        console.log("Step 3/4: Adding liquidity...");
        token.transfer(address(dex), 500_000 ether);
        console.log("  Liquidity:", dex.getReserve() / 1 ether, "TEST");
        
        // 4. Deploy responder
        console.log("Step 4/5: Deploying responder...");
        FairLaunchResponder responder = new FairLaunchResponder(
            DROSERA_ADDRESS,
            address(token),
            address(dex)
        );
        console.log("  Responder:", address(responder));
        
        // 5. Deploy trap
        console.log("Step 5/5: Deploying trap...");
        address trap;
        if (keccak256(bytes(strategy)) == keccak256(bytes("simple"))) {
            FairLaunchGuardianTrapSimple simpleTrap = new FairLaunchGuardianTrapSimple();
            trap = address(simpleTrap);
            (address trapToken, address trapPool) = simpleTrap.getConfig();
            _warnIfMismatch("Simple", trapToken, trapPool, address(token), address(dex));
        } else if (keccak256(bytes(strategy)) == keccak256(bytes("eventlog"))) {
            FairLaunchGuardianTrapEventLog eventTrap = new FairLaunchGuardianTrapEventLog();
            trap = address(eventTrap);
            (address trapToken, address trapPool, bool trapIsToken0) = eventTrap.getConfig();
            _warnIfMismatch("EventLog", trapToken, trapPool, address(token), address(dex));
            bool expectedIsToken0 = address(token) < address(dex);
            if (trapIsToken0 != expectedIsToken0) {
                console.log("WARNING: Update TOKEN_IS_TOKEN0 constant for test trap.");
            }
        } else if (keccak256(bytes(strategy)) == keccak256(bytes("advanced"))) {
            FairLaunchGuardianTrapAdvanced advancedTrap = new FairLaunchGuardianTrapAdvanced();
            trap = address(advancedTrap);
            address trapToken = advancedTrap.getTokenAddress();
            address trapPool = advancedTrap.getLiquidityPool();
            _warnIfMismatch("Advanced", trapToken, trapPool, address(token), address(dex));
        } else {
            FairLaunchGuardianTrapSimple fallbackTrap = new FairLaunchGuardianTrapSimple();
            trap = address(fallbackTrap);
            console.log("Unknown strategy. Defaulting to Simple trap.");
        }
        console.log("  Trap:", trap);
        
        vm.stopBroadcast();
        
        console.log("");
        console.log("========================================");
        console.log("  Test Environment Ready!");
        console.log("========================================");
        console.log("");
        console.log("Contracts:");
        console.log("  Token:", address(token));
        console.log("  Pool:", address(dex));
        console.log("  Responder:", address(responder));
        console.log("  Trap:", trap);
        console.log("");
        console.log("Test commands:");
        console.log("  Simulate swap: cast send", address(dex), '"swap()" --value 0.1ether');
        console.log("  Check balance: cast call", address(token), '"balanceOf(address)" <addr>');
        console.log("");
        
        return (address(token), address(dex), address(responder), trap);
    }
}

/**
 * @title DeployMinimal
 * @notice Quick deployment for production (EventLog recommended)
 */
contract DeployMinimal is Script {
    
    address constant DROSERA_ADDRESS = 0x91cB447BaFc6e0EA0F4Fe056F5a9b1F14bb06e5D;
    
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address tokenAddress = vm.envAddress("TOKEN_ADDRESS");
        address liquidityPool = vm.envAddress("LIQUIDITY_POOL");
        
        console.log("Deploying V2 (EventLog strategy)...");
        console.log("Token:", tokenAddress);
        console.log("Pool:", liquidityPool);
        console.log("Config Token (FairLaunchConfig):", FairLaunchConfig.tokenAddress());
        console.log("Config Pool  (FairLaunchConfig):", FairLaunchConfig.liquidityPool());
        console.log("Config tokenIsToken0:", FairLaunchConfig.tokenIsToken0());
        
        vm.startBroadcast(deployerPrivateKey);
        
        // Deploy responder
        FairLaunchResponder responder = new FairLaunchResponder(
            DROSERA_ADDRESS,
            tokenAddress,
            liquidityPool
        );
        
        // Deploy trap (constants must match addresses)
        FairLaunchGuardianTrapEventLog trap = new FairLaunchGuardianTrapEventLog();
        (address configuredToken, address configuredPool, bool configuredIsToken0) = trap.getConfig();
        _warnIfMismatch("EventLog", configuredToken, configuredPool, tokenAddress, liquidityPool);
        bool expectedIsToken0 = tokenAddress < liquidityPool;
        _warnIsToken0Mismatch(configuredIsToken0, expectedIsToken0);
        
        vm.stopBroadcast();
        
        console.log("");
        console.log("Deployed:");
        console.log("  Responder:", address(responder));
        console.log("  Trap:", address(trap));
        console.log("");
        console.log("Update drosera.toml with these addresses.");
    }
}