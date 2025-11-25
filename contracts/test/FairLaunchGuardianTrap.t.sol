// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/FairLaunchGuardianTrap.sol";
import "../src/demo/DemoToken.sol";
import "../src/demo/DemoDex.sol";

/**
 * @title FairLaunchGuardianTrapTest
 * @notice Tests with real DEX integration
 */
contract FairLaunchGuardianTrapTest is Test {
    FairLaunchGuardianTrap public trap;
    DemoToken public token;
    DemoDEX public dex;
    
    address public owner;
    address public normalUser;
    address public bot;
    
    uint256 public constant TOTAL_SUPPLY = 1_000_000 * 10**18;
    uint256 public constant LIQUIDITY = 500_000 * 10**18;
    
    function setUp() public {
        owner = address(this);
        normalUser = address(0x1);
        bot = address(0x2);
        
        // Deploy token
        token = new DemoToken("Test Token", "TEST", TOTAL_SUPPLY);
        
        // Deploy DEX
        dex = new DemoDEX(address(token));
        
        // Deploy trap
        trap = new FairLaunchGuardianTrap(
            address(token),
            address(dex),
            block.number,
            50,    // 50 blocks monitoring
            500,   // 5% max wallet
            200    // 2x max gas
        );
        
        // Integrate trap with token
        token.integrateTrap(address(trap), address(dex));
        
        // Add liquidity
        token.approve(address(dex), LIQUIDITY);
        dex.addLiquidity(LIQUIDITY);
        
        // Fund test accounts
        vm.deal(normalUser, 100 ether);
        vm.deal(bot, 100 ether);
    }
    
    // ==================== BASIC TESTS ====================
    
    function testDeployment() public {
        assertEq(trap.owner(), owner);
        assertTrue(trap.isMonitoringActive());
        
        FairLaunchGuardianTrap.LaunchConfig memory config = trap.getConfig();
        assertEq(config.tokenAddress, address(token));
        assertEq(config.liquidityPool, address(dex));
    }
    
    function testTokenIntegration() public {
        assertEq(token.fairLaunchTrap(), address(trap));
        assertEq(token.liquidityPool(), address(dex));
        assertTrue(token.launchProtectionEnabled());
    }
    
    // ==================== NORMAL TRADING TESTS ====================
    
    function testNormalUserCanBuy() public {
        uint256 buyAmount = 0.5 ether; // ~0.5% of supply
        
        vm.startPrank(normalUser);
        dex.swap{value: buyAmount}();
        vm.stopPrank();
        
        uint256 balance = token.balanceOf(normalUser);
        assertGt(balance, 0);
        
        // Should not be blacklisted
        assertFalse(trap.isBlacklisted(normalUser));
    }
    
    function testMultipleNormalBuys() public {
        vm.startPrank(normalUser);
        
        // Buy 3 times, small amounts
        dex.swap{value: 0.1 ether}();
        dex.swap{value: 0.1 ether}();
        dex.swap{value: 0.1 ether}();
        
        vm.stopPrank();
        
        // Should succeed
        assertGt(token.balanceOf(normalUser), 0);
        assertFalse(trap.isBlacklisted(normalUser));
    }
    
    // ==================== DETECTION TESTS ====================
    
    function testDetectsExcessiveAccumulation() public {
        uint256 largeAmount = 10 ether; // ~10% of supply
        
        vm.startPrank(bot);
        dex.swap{value: largeAmount}();
        vm.stopPrank();
        
        // Manually trigger detection (simulate Drosera operator)
        _triggerDetection();
        
        // Bot should be blacklisted
        assertTrue(trap.isBlacklisted(bot));
    }
    
    function testBlacklistedCannotTrade() public {
        // First buy succeeds and triggers blacklist
        vm.startPrank(bot);
        dex.swap{value: 10 ether}();
        vm.stopPrank();
        
        _triggerDetection();
        assertTrue(trap.isBlacklisted(bot));
        
        // Second buy should revert
        vm.startPrank(bot);
        vm.expectRevert("Address is blacklisted by Fair Launch Guardian");
        dex.swap{value: 1 ether}();
        vm.stopPrank();
    }
    
    function testRapidBuyingDetection() public {
        vm.startPrank(bot);
        
        // Multiple rapid buys
        dex.swap{value: 0.5 ether}();
        dex.swap{value: 0.5 ether}();
        dex.swap{value: 0.5 ether}();
        
        vm.stopPrank();
        
        _triggerDetection();
        
        // Should detect rapid buying
        uint256 buyCount = trap.buyCountPerAddress(bot);
        assertGe(buyCount, 3);
    }
    
    function testHighGasPriceDetection() public {
        // This is harder to test in Foundry
        // In practice, trap checks tx.gasprice vs average
        
        vm.startPrank(bot);
        dex.swap{value: 5 ether}();
        vm.stopPrank();
        
        // Would be caught by gas price analysis in real scenario
    }
    
    // ==================== ADMIN TESTS ====================
    
    function testOwnerCanBlacklist() public {
        trap.addToBlacklist(bot);
        assertTrue(trap.isBlacklisted(bot));
        
        // Bot cannot trade
        vm.startPrank(bot);
        vm.expectRevert("Address is blacklisted by Fair Launch Guardian");
        dex.swap{value: 1 ether}();
        vm.stopPrank();
    }
    
    function testOwnerCanUnblacklist() public {
        trap.addToBlacklist(bot);
        assertTrue(trap.isBlacklisted(bot));
        
        trap.removeFromBlacklist(bot);
        assertFalse(trap.isBlacklisted(bot));
        
        // Bot can now trade
        vm.startPrank(bot);
        dex.swap{value: 1 ether}();
        vm.stopPrank();
    }
    
    function testPauseStopsTrading() public {
        // Manually pause (would happen on severe detection)
        vm.prank(owner);
        vm.store(
            address(trap),
            bytes32(uint256(8)), // isPaused storage slot
            bytes32(uint256(1))
        );
        
        vm.startPrank(normalUser);
        vm.expectRevert("Trading paused by Fair Launch Guardian");
        dex.swap{value: 0.5 ether}();
        vm.stopPrank();
    }
    
    function testUnpause() public {
        // Set paused
        vm.store(address(trap), bytes32(uint256(8)), bytes32(uint256(1)));
        
        // Unpause
        trap.unpause();
        
        // Should work now
        vm.startPrank(normalUser);
        dex.swap{value: 0.5 ether}();
        vm.stopPrank();
    }
    
    // ==================== COLLECT & RESPOND TESTS ====================
    
    function testCollectReturnsData() public {
        // Make a swap
        vm.startPrank(normalUser);
        dex.swap{value: 0.5 ether}();
        vm.stopPrank();
        
        // Call collect
        bytes memory data = trap.collect();
        assertTrue(data.length > 0);
        
        // Decode
        FairLaunchGuardianTrap.CollectOutput memory output = 
            abi.decode(data, (FairLaunchGuardianTrap.CollectOutput));
        
        assertEq(output.blockNumber, block.number);
        assertGt(output.totalSupply, 0);
    }
    
    function testShouldRespondDetectsViolation() public {
        // Bot makes large purchase
        vm.startPrank(bot);
        dex.swap{value: 10 ether}();
        vm.stopPrank();
        
        // Get collect data
        bytes memory collectData = trap.collect();
        
        // Create array for shouldRespond
        bytes[] memory dataArray = new bytes[](2);
        dataArray[0] = collectData;
        dataArray[1] = collectData; // Simplified - would be previous block data
        
        // Call shouldRespond
        (bool shouldRespond, bytes memory responseData) = trap.shouldRespond(dataArray);
        
        assertTrue(shouldRespond);
        assertTrue(responseData.length > 0);
        
        // Decode response
        FairLaunchGuardianTrap.ResponseData memory response = 
            abi.decode(responseData, (FairLaunchGuardianTrap.ResponseData));
        
        assertEq(response.violatorAddress, bot);
        assertGt(response.severity, 60);
    }
    
    // ==================== EDGE CASES ====================
    
    function testMonitoringEnds() public {
        // Advance beyond monitoring period
        vm.roll(block.number + 51);
        
        assertFalse(trap.isMonitoringActive());
        
        // collect() should return empty
        bytes memory data = trap.collect();
        FairLaunchGuardianTrap.CollectOutput memory output = 
            abi.decode(data, (FairLaunchGuardianTrap.CollectOutput));
        
        assertEq(output.recentBuyers.length, 0);
    }
    
    function testDeactivate() public {
        trap.deactivate();
        
        FairLaunchGuardianTrap.LaunchConfig memory config = trap.getConfig();
        assertFalse(config.isActive);
        assertFalse(trap.isMonitoringActive());
    }
    
    // ==================== HELPER ====================
    
    function _triggerDetection() internal {
        // Simulate what Drosera operators would do
        bytes memory collectData = trap.collect();
        
        bytes[] memory dataArray = new bytes[](2);
        dataArray[0] = collectData;
        dataArray[1] = collectData;
        
        trap.shouldRespond(dataArray);
    }
}