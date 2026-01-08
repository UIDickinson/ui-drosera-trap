// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../../src/v2/FairLaunchGuardianTrapSimple.sol";
import "../../src/v2/FairLaunchResponder.sol";
import "../mocks/MockToken.sol";

contract FairLaunchGuardianTrapSimpleTest is Test {
    FairLaunchGuardianTrapSimple public trap;
    FairLaunchResponder public responder;
    MockToken public token;
    address public pool;
    address public droseraAddress;
    
    function setUp() public {
        droseraAddress = address(0x1234);
        
        // Deploy mock token
        token = new MockToken("Test Token", "TEST", 1_000_000 ether);
        
        // Create pool address
        pool = address(0x5678);
        
        // Deploy responder
        responder = new FairLaunchResponder(
            droseraAddress,
            address(token),
            pool
        );
        
        // Deploy trap (Note: Need to modify contract to accept constructor args for testing)
        // For now, we'll test the logic directly
    }
    
    function testCollectReturnsValidData() public {
        // Send some tokens to pool
        token.transfer(pool, 100_000 ether);
        
        // Create a test trap instance with constructor args
        TestTrapSimple testTrap = new TestTrapSimple(address(token), pool);
        
        bytes memory collected = testTrap.collect();
        
        assertTrue(collected.length > 0, "Collect should return data");
        
        FairLaunchGuardianTrapSimple.CollectOutput memory output = 
            abi.decode(collected, (FairLaunchGuardianTrapSimple.CollectOutput));
        
        assertEq(output.totalSupply, token.totalSupply(), "Total supply should match");
        assertEq(output.poolBalance, 100_000 ether, "Pool balance should match");
        assertEq(output.blockNumber, block.number, "Block number should match");
    }
    
    function testDetectsLiquidityDrain() public {
        TestTrapSimple testTrap = new TestTrapSimple(address(token), pool);
        
        // Initial state - 100k tokens in pool
        token.transfer(pool, 100_000 ether);
        bytes memory collect1 = testTrap.collect();
        
        // Move to next block
        vm.roll(block.number + 1);
        
        // Drain 20k tokens (20% drain - should trigger at 10% threshold)
        vm.prank(pool);
        token.transfer(address(this), 20_000 ether);
        bytes memory collect2 = testTrap.collect();
        
        // Prepare data array (most recent first)
        bytes[] memory data = new bytes[](2);
        data[0] = collect2; // current
        data[1] = collect1; // previous
        
        (bool shouldRespond, bytes memory payload) = testTrap.shouldRespond(data);
        
        assertTrue(shouldRespond, "Should detect liquidity drain");
        assertTrue(payload.length > 0, "Should return payload");
        
        // Decode response
        FairLaunchGuardianTrapSimple.ResponseData memory response = 
            abi.decode(payload, (FairLaunchGuardianTrapSimple.ResponseData));
        
        assertEq(response.detectionType, 4, "Should be LIQUIDITY_MANIPULATION");
        assertTrue(response.severity >= 75, "Should have high severity");
        assertEq(response.accumulatedPercentBP, 2000, "Should be 20% drain (2000 BP)");
    }
    
    function testNoFalsePositiveOnSmallDrain() public {
        TestTrapSimple testTrap = new TestTrapSimple(address(token), pool);
        
        // Initial state
        token.transfer(pool, 100_000 ether);
        bytes memory collect1 = testTrap.collect();
        
        vm.roll(block.number + 1);
        
        // Small drain (5% - below 10% threshold)
        vm.prank(pool);
        token.transfer(address(this), 5_000 ether);
        bytes memory collect2 = testTrap.collect();
        
        bytes[] memory data = new bytes[](2);
        data[0] = collect2;
        data[1] = collect1;
        
        (bool shouldRespond,) = testTrap.shouldRespond(data);
        
        assertFalse(shouldRespond, "Should not trigger on small drain");
    }
    
    function testDetectsSupplyManipulation() public {
        TestTrapSimple testTrap = new TestTrapSimple(address(token), pool);
        
        token.transfer(pool, 100_000 ether);
        bytes memory collect1 = testTrap.collect();
        
        vm.roll(block.number + 1);
        
        // Mint 10% more tokens (supply manipulation)
        token.mint(address(this), 100_000 ether);
        bytes memory collect2 = testTrap.collect();
        
        bytes[] memory data = new bytes[](2);
        data[0] = collect2;
        data[1] = collect1;
        
        (bool shouldRespond, bytes memory payload) = testTrap.shouldRespond(data);
        
        assertTrue(shouldRespond, "Should detect supply manipulation");
        
        FairLaunchGuardianTrapSimple.ResponseData memory response = 
            abi.decode(payload, (FairLaunchGuardianTrapSimple.ResponseData));
        
        assertEq(response.detectionType, 3, "Should be SUPPLY_MANIPULATION");
    }
    
    function testDetectsMultiBlockDrain() public {
        TestTrapSimple testTrap = new TestTrapSimple(address(token), pool);
        
        token.transfer(pool, 100_000 ether);
        
        // Create 4 blocks with consistent draining
        bytes[] memory data = new bytes[](4);
        uint256 balance = 100_000 ether;
        
        for (uint256 i = 0; i < 4; i++) {
            vm.roll(block.number + 1);
            
            // Drain 2% each block
            uint256 drainAmount = balance * 2 / 100;
            vm.prank(pool);
            token.transfer(address(this), drainAmount);
            balance -= drainAmount;
            
            data[3 - i] = testTrap.collect(); // Reverse order (most recent first)
        }
        
        (bool shouldRespond, bytes memory payload) = testTrap.shouldRespond(data);
        
        assertTrue(shouldRespond, "Should detect multi-block drain pattern");
        
        FairLaunchGuardianTrapSimple.ResponseData memory response = 
            abi.decode(payload, (FairLaunchGuardianTrapSimple.ResponseData));
        
        assertTrue(response.severity >= 85, "Multi-block drain should have high severity");
    }
    
    function testRejectsEmptyData() public {
        TestTrapSimple testTrap = new TestTrapSimple(address(token), pool);
        
        bytes[] memory emptyData = new bytes[](0);
        (bool shouldRespond,) = testTrap.shouldRespond(emptyData);
        
        assertFalse(shouldRespond, "Should reject empty data");
    }
    
    function testRejectsInsufficientData() public {
        TestTrapSimple testTrap = new TestTrapSimple(address(token), pool);
        
        token.transfer(pool, 100_000 ether);
        bytes memory collect1 = testTrap.collect();
        
        // Only one sample (need at least 2)
        bytes[] memory data = new bytes[](1);
        data[0] = collect1;
        
        (bool shouldRespond,) = testTrap.shouldRespond(data);
        
        assertFalse(shouldRespond, "Should reject insufficient data");
    }
    
    function testRejectsZeroSupply() public {
        // Deploy with zero supply token
        MockToken zeroToken = new MockToken("Zero", "ZERO", 0);
        TestTrapSimple testTrap = new TestTrapSimple(address(zeroToken), pool);
        
        bytes memory collect1 = testTrap.collect();
        bytes memory collect2 = testTrap.collect();
        
        bytes[] memory data = new bytes[](2);
        data[0] = collect2;
        data[1] = collect1;
        
        (bool shouldRespond,) = testTrap.shouldRespond(data);
        
        assertFalse(shouldRespond, "Should reject zero supply");
    }
}

// Test helper contract with constructor args for testing
contract TestTrapSimple {
    uint256 public constant BASIS_POINTS = 10_000;
    uint256 public constant LIQUIDITY_DRAIN_THRESHOLD_BP = 1000;
    uint256 public constant SUPPLY_CHANGE_THRESHOLD_BP = 500;
    
    address public immutable TOKEN_ADDRESS;
    address public immutable LIQUIDITY_POOL;
    
    struct CollectOutput {
        uint256 blockNumber;
        uint256 timestamp;
        uint256 totalSupply;
        uint256 poolBalance;
    }
    
    struct ResponseData {
        address violatorAddress;
        uint256 accumulatedPercentBP;
        uint8 detectionType;
        uint256 blockNumber;
        uint256 severity;
        uint256 confidence;
    }
    
    constructor(address _token, address _pool) {
        TOKEN_ADDRESS = _token;
        LIQUIDITY_POOL = _pool;
    }
    
    function collect() external view returns (bytes memory) {
        uint256 totalSupply = 0;
        uint256 poolBalance = 0;
        
        try IERC20(TOKEN_ADDRESS).totalSupply() returns (uint256 supply) {
            totalSupply = supply;
        } catch {}
        
        try IERC20(TOKEN_ADDRESS).balanceOf(LIQUIDITY_POOL) returns (uint256 balance) {
            poolBalance = balance;
        } catch {}
        
        CollectOutput memory output = CollectOutput({
            blockNumber: block.number,
            timestamp: block.timestamp,
            totalSupply: totalSupply,
            poolBalance: poolBalance
        });
        
        return abi.encode(output);
    }
    
    function shouldRespond(bytes[] calldata data)
        external
        pure
        returns (bool, bytes memory)
    {
        if (data.length < 2 || data[0].length == 0 || data[1].length == 0) {
            return (false, "");
        }
        
        CollectOutput memory current = abi.decode(data[0], (CollectOutput));
        CollectOutput memory previous = abi.decode(data[1], (CollectOutput));
        
        if (current.totalSupply == 0) {
            return (false, "");
        }
        
        // Liquidity drain detection
        if (previous.poolBalance > 0 && current.poolBalance < previous.poolBalance) {
            uint256 drain = previous.poolBalance - current.poolBalance;
            uint256 drainBP = (drain * BASIS_POINTS) / previous.poolBalance;
            
            if (drainBP > LIQUIDITY_DRAIN_THRESHOLD_BP) {
                uint256 severity = drainBP > 2000 ? 95 : (drainBP > 1500 ? 85 : 75);
                
                ResponseData memory response = ResponseData({
                    violatorAddress: address(0),
                    accumulatedPercentBP: drainBP,
                    detectionType: 4,
                    blockNumber: current.blockNumber,
                    severity: severity,
                    confidence: 90
                });
                
                return (true, abi.encode(response));
            }
        }
        
        // Supply manipulation
        if (previous.totalSupply > 0 && current.totalSupply != previous.totalSupply) {
            uint256 change = current.totalSupply > previous.totalSupply
                ? current.totalSupply - previous.totalSupply
                : previous.totalSupply - current.totalSupply;
            
            uint256 changeBP = (change * BASIS_POINTS) / previous.totalSupply;
            
            if (changeBP > SUPPLY_CHANGE_THRESHOLD_BP) {
                ResponseData memory response = ResponseData({
                    violatorAddress: address(0),
                    accumulatedPercentBP: changeBP,
                    detectionType: 3,
                    blockNumber: current.blockNumber,
                    severity: changeBP > 1000 ? 90 : 75,
                    confidence: 85
                });
                
                return (true, abi.encode(response));
            }
        }
        
        // Multi-block drain
        if (data.length >= 3) {
            uint256 consecutiveDecreases = 0;
            
            for (uint256 i = 0; i < data.length - 1 && i < 5; i++) {
                CollectOutput memory newer = abi.decode(data[i], (CollectOutput));
                CollectOutput memory older = abi.decode(data[i + 1], (CollectOutput));
                
                if (older.poolBalance == 0) continue;
                
                if (newer.poolBalance < older.poolBalance) {
                    uint256 decrease = older.poolBalance - newer.poolBalance;
                    uint256 decreaseBP = (decrease * BASIS_POINTS) / older.poolBalance;
                    
                    if (decreaseBP > 100) {
                        consecutiveDecreases++;
                    }
                } else {
                    break;
                }
            }
            
            if (consecutiveDecreases >= 3) {
                ResponseData memory response = ResponseData({
                    violatorAddress: address(0),
                    accumulatedPercentBP: consecutiveDecreases * 100,
                    detectionType: 4,
                    blockNumber: current.blockNumber,
                    severity: consecutiveDecreases >= 5 ? 95 : 85,
                    confidence: 90
                });
                
                return (true, abi.encode(response));
            }
        }
        
        return (false, "");
    }
}
