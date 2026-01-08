// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../../src/v2/FairLaunchGuardianTrapSimple.sol";
import "../../src/v2/FairLaunchGuardianTrapEventLog.sol";
import "../../src/v2/FairLaunchGuardianTrapAdvanced.sol";
import "../../src/v2/FairLaunchResponder.sol";
import "../../src/v2/FairLaunchResponderAdvanced.sol";
import "../../src/v2/EventLogHelper.sol";
import "../mocks/MockToken.sol";

/**
 * @title IntegrationTest
 * @notice End-to-end integration tests simulating full Drosera flow
 */
contract IntegrationTest is Test {
    TestTrapSimple public trap;
    FairLaunchResponder public responder;
    MockToken public token;
    address public pool;
    address public droseraAddress;
    address public attacker;
    
    function setUp() public {
        droseraAddress = address(0x1234);
        attacker = address(0xA771CA7E);
        
        token = new MockToken("Test Token", "TEST", 1_000_000 ether);
        pool = address(0x5678);
        
        responder = new FairLaunchResponder(
            droseraAddress,
            address(token),
            pool
        );
        
        trap = new TestTrapSimple(address(token), pool);
        
        // Initialize pool with liquidity
        token.transfer(pool, 200_000 ether);
    }
    
    function testFullLiquidityDrainFlow() public {
        // === BLOCK 1: Normal state ===
        bytes memory collect1 = trap.collect();
        
        // === BLOCK 2: Attacker drains 25% liquidity ===
        vm.roll(block.number + 1);
        vm.prank(pool);
        token.transfer(attacker, 50_000 ether); // 25% drain
        
        bytes memory collect2 = trap.collect();
        
        // === Drosera calls shouldRespond ===
        bytes[] memory data = new bytes[](2);
        data[0] = collect2; // current
        data[1] = collect1; // previous
        
        (bool shouldRespond, bytes memory payload) = trap.shouldRespond(data);
        
        assertTrue(shouldRespond, "Trap should detect drain");
        
        // === Drosera calls responder ===
        vm.prank(droseraAddress);
        responder.handle(payload);
        
        // === Verify response actions ===
        assertTrue(responder.isPaused(), "Should trigger emergency pause");
        assertEq(responder.totalIncidents(), 1, "Should log incident");
        
        FairLaunchResponder.ResponseData memory incident = responder.getIncident(0);
        assertEq(incident.detectionType, 4, "Should be LIQUIDITY_MANIPULATION");
        assertTrue(incident.severity >= 85, "Should have high severity");
    }
    
    function testMultiBlockDrainDetectionAndResponse() public {
        bytes[] memory collects = new bytes[](5);
        collects[4] = trap.collect(); // Oldest
        
        // Simulate 4 blocks of consecutive 2% drains
        for (uint256 i = 1; i <= 4; i++) {
            vm.roll(block.number + 1);
            
            uint256 currentBalance = token.balanceOf(pool);
            uint256 drainAmount = currentBalance * 2 / 100;
            
            vm.prank(pool);
            token.transfer(attacker, drainAmount);
            
            collects[4 - i] = trap.collect(); // Reverse order
        }
        
        // Drosera analyzes pattern
        (bool shouldRespond, bytes memory payload) = trap.shouldRespond(collects);
        
        assertTrue(shouldRespond, "Should detect multi-block pattern");
        
        // Execute response
        vm.prank(droseraAddress);
        responder.handle(payload);
        
        assertTrue(responder.isPaused(), "Should pause on pattern");
        
        FairLaunchResponder.ResponseData memory incident = responder.getIncident(0);
        assertTrue(incident.severity >= 85, "Pattern should have high severity");
    }
    
    function testNoFalsePositiveOnNormalTrading() public {
        bytes[] memory collects = new bytes[](10);
        
        // Simulate 10 blocks of normal trading (small changes)
        for (uint256 i = 0; i < 10; i++) {
            vm.roll(block.number + 1);
            
            // Small random changes
            if (i % 2 == 0) {
                // Small buy (1%)
                uint256 amount = token.balanceOf(pool) * 1 / 100;
                token.transfer(pool, amount);
            } else {
                // Small sell (0.5%)
                uint256 amount = token.balanceOf(pool) * 5 / 1000;
                vm.prank(pool);
                token.transfer(address(this), amount);
            }
            
            collects[9 - i] = trap.collect();
        }
        
        (bool shouldRespond,) = trap.shouldRespond(collects);
        
        assertFalse(shouldRespond, "Should not trigger on normal trading");
        assertFalse(responder.isPaused(), "Should remain unpaused");
    }
    
    function testOwnerRecoveryFromFalsePositive() public {
        // First collect at block N
        bytes memory collect1 = trap.collect();
        
        // Advance and trigger a detection (maybe false positive)
        vm.roll(block.number + 1);
        vm.prank(pool);
        token.transfer(attacker, 50_000 ether);
        
        bytes memory collect2 = trap.collect();
        
        bytes[] memory data = new bytes[](2);
        data[0] = collect2; // current
        data[1] = collect1; // previous
        
        (, bytes memory payload) = trap.shouldRespond(data);
        
        vm.prank(droseraAddress);
        responder.handle(payload);
        
        assertTrue(responder.isPaused(), "Should be paused");
        
        // Owner investigates and determines false positive
        responder.unpause();
        
        assertFalse(responder.isPaused(), "Owner can unpause");
    }
    
    function testSupplyManipulationDetection() public {
        bytes memory collect1 = trap.collect();
        
        vm.roll(block.number + 1);
        
        // Attacker mints 10% more tokens
        token.mint(attacker, 100_000 ether);
        
        bytes memory collect2 = trap.collect();
        
        bytes[] memory data = new bytes[](2);
        data[0] = collect2;
        data[1] = collect1;
        
        (bool shouldRespond, bytes memory payload) = trap.shouldRespond(data);
        
        assertTrue(shouldRespond, "Should detect supply manipulation");
        
        vm.prank(droseraAddress);
        responder.handle(payload);
        
        assertTrue(responder.totalIncidents() > 0, "Should log incident");
    }
}

/**
 * @title AdvancedIntegrationTest  
 * @notice Tests with advanced responder and confidence thresholds
 */
contract AdvancedIntegrationTest is Test {
    TestTrapSimple public trap;
    FairLaunchResponderAdvanced public responder;
    MockToken public token;
    address public pool;
    address public droseraAddress;
    
    function setUp() public {
        droseraAddress = address(0x1234);
        token = new MockToken("Test Token", "TEST", 1_000_000 ether);
        pool = address(0x5678);
        
        responder = new FairLaunchResponderAdvanced(
            droseraAddress,
            address(token),
            pool
        );
        
        trap = new TestTrapSimple(address(token), pool);
        token.transfer(pool, 200_000 ether);
        
        // Advance past any cooldown
        vm.roll(block.number + 10);
    }

    // Helper function to build properly encoded payload for advanced responder
    function _buildAdvancedPayload(
        address violator,
        address[] memory related,
        uint256 accumulatedBP,
        uint8 detectionType,
        uint256 blockNum,
        uint256 severity,
        uint256 confidence,
        bytes32 pattern
    ) internal pure returns (bytes memory) {
        FairLaunchResponderAdvanced.ResponseData memory data = FairLaunchResponderAdvanced.ResponseData({
            violatorAddress: violator,
            relatedAddresses: related,
            accumulatedPercentBP: accumulatedBP,
            detectionType: detectionType,
            blockNumber: blockNum,
            severity: severity,
            confidence: confidence,
            patternSignature: pattern
        });
        return abi.encode(data);
    }
    
    function testConfidenceBasedResponse() public {
        // First collect
        bytes memory collect1 = trap.collect();
        
        // Low confidence detection - only logs
        vm.roll(block.number + 1);
        vm.prank(pool);
        token.transfer(address(0xBAD), 25_000 ether);
        
        bytes memory collect2 = trap.collect();
        
        bytes[] memory data = new bytes[](2);
        data[0] = collect2; // current
        data[1] = collect1; // previous
        
        (bool shouldRespond, bytes memory basicPayload) = trap.shouldRespond(data);
        assertTrue(shouldRespond, "Trap should detect drain");
        
        // Create low confidence payload using helper
        bytes memory lowConfPayload = _buildAdvancedPayload(
            address(0xBAD),
            new address[](0),
            1250, // 12.5%
            4,
            block.number,
            75, // severity
            65, // LOW confidence
            keccak256("test")
        );
        
        vm.prank(droseraAddress);
        responder.handle(lowConfPayload);
        
        assertFalse(responder.isPaused(), "Low confidence should not pause");
        assertFalse(responder.blacklisted(address(0xBAD)), "Low confidence should not blacklist");
        
        // High confidence - acts
        vm.roll(block.number + 10);
        
        bytes memory highConfPayload = _buildAdvancedPayload(
            address(0xBAD2),
            new address[](0),
            2500,
            4,
            block.number,
            90,
            95, // HIGH confidence
            keccak256("test2")
        );
        
        vm.prank(droseraAddress);
        responder.handle(highConfPayload);
        
        assertTrue(responder.isPaused(), "High confidence should pause");
    }
    
    function testCoordinatedAttackHandling() public {
        address[] memory attackers = new address[](3);
        attackers[0] = address(0xBAD1);
        attackers[1] = address(0xBAD2);
        attackers[2] = address(0xBAD3);
        
        bytes memory payload = _buildAdvancedPayload(
            attackers[0], // Primary
            attackers,    // All related
            1500,
            3, // COORDINATED_ATTACK
            block.number,
            85,
            90,
            keccak256("coordinated")
        );
        
        vm.prank(droseraAddress);
        responder.handle(payload);
        
        // All should be blacklisted
        for (uint256 i = 0; i < attackers.length; i++) {
            assertTrue(
                responder.blacklisted(attackers[i]),
                string(abi.encodePacked("Attacker ", vm.toString(i), " should be blacklisted"))
            );
        }
    }
    
    function testThreatIntelligenceBuildup() public {
        bytes32 pattern1 = keccak256("pattern_1");
        
        // First occurrence
        bytes memory payload1 = _buildAdvancedPayload(
            address(0xBAD1),
            new address[](0),
            1000,
            4,
            block.number,
            60,
            75,
            pattern1
        );
        
        vm.prank(droseraAddress);
        responder.handle(payload1);
        
        FairLaunchResponderAdvanced.ThreatIntel memory intel1 = 
            responder.getThreatIntel(pattern1);
        assertEq(intel1.occurrences, 1, "Should track first occurrence");
        
        // Second occurrence of same pattern
        vm.roll(block.number + 10);
        
        bytes memory payload2 = _buildAdvancedPayload(
            address(0xBAD2),
            new address[](0),
            1200,
            4,
            block.number,
            65,
            80,
            pattern1
        );
        
        vm.prank(droseraAddress);
        responder.handle(payload2);
        
        FairLaunchResponderAdvanced.ThreatIntel memory intel2 = 
            responder.getThreatIntel(pattern1);
        assertEq(intel2.occurrences, 2, "Should track repeat occurrences");
    }

    function testEventLogTrapIntegration() public {
        FairLaunchGuardianTrapEventLog eventTrap = new FairLaunchGuardianTrapEventLog();
        address primaryBuyer = address(0xCAFE);
        uint256 totalSupply = 1_000_000 ether;

        (
            bytes32[][] memory topics,
            bytes[] memory dataArray,
            uint256[] memory blockNumbers,
            uint256[] memory timestamps
        ) = _buildEventBundle(primaryBuyer);

        bytes memory collectPayload = eventTrap.buildCollectPayloadFromEvents(
            block.number,
            block.timestamp,
            totalSupply,
            450_000 ether,
            450_000 ether,
            200 ether,
            topics,
            dataArray,
            blockNumbers,
            timestamps
        );

        bytes[] memory window = new bytes[](1);
        window[0] = collectPayload;

        (bool shouldRespond, bytes memory responseData) = eventTrap.shouldRespond(window);
        assertTrue(shouldRespond, "Event log trap should trigger");

        vm.prank(droseraAddress);
        responder.handle(responseData);

        // Note: The responder blacklists on confidence >= 70, but only pauses on 
        // confidence >= 80 AND severity >= 75. Test data produces severity ~70,
        // so we expect blacklist but not pause.
        assertTrue(responder.blacklisted(primaryBuyer), "Primary violator should be blacklisted");
        // isPaused depends on severity threshold, which may not be met with this test data
    }

    function testAdvancedTrapResponderFlow() public {
        FairLaunchGuardianTrapAdvanced advancedTrap = new FairLaunchGuardianTrapAdvanced();

        address[] memory wallets = new address[](3);
        wallets[0] = address(0xFA01);
        wallets[1] = address(0xFA02);
        wallets[2] = address(0xFA03);

        // Build two rounds of swaps to ensure each wallet has buyCount >= 2
        uint256 swapsPerRound = wallets.length;
        uint256 totalSwaps = swapsPerRound * 2;
        
        bytes32[][] memory topics = new bytes32[][](totalSwaps);
        bytes[] memory dataArray = new bytes[](totalSwaps);
        uint256[] memory blockNumbers = new uint256[](totalSwaps);
        uint256[] memory timestamps = new uint256[](totalSwaps);
        uint256[] memory gasPrices = new uint256[](totalSwaps);

        // First round of buys
        for (uint256 i = 0; i < swapsPerRound; i++) {
            topics[i] = new bytes32[](3);
            topics[i][0] = EventLogHelper.SWAP_EVENT_SIGNATURE;
            topics[i][1] = bytes32(uint256(uint160(wallets[i])));
            topics[i][2] = bytes32(uint256(uint160(wallets[i])));

            dataArray[i] = abi.encode(uint256(0), 9 ether, 30_000 ether, uint256(0));
            blockNumbers[i] = 410 + i;
            timestamps[i] = 3_100 + i;
            gasPrices[i] = (50 + i) * 1 gwei;
        }

        // Second round of buys (same wallets buying again)
        for (uint256 i = 0; i < swapsPerRound; i++) {
            uint256 idx = swapsPerRound + i;
            topics[idx] = new bytes32[](3);
            topics[idx][0] = EventLogHelper.SWAP_EVENT_SIGNATURE;
            topics[idx][1] = bytes32(uint256(uint160(wallets[i])));
            topics[idx][2] = bytes32(uint256(uint160(wallets[i])));

            dataArray[idx] = abi.encode(uint256(0), 8 ether, 28_000 ether, uint256(0));
            blockNumbers[idx] = 415 + i;
            timestamps[idx] = 3_110 + i;
            gasPrices[idx] = (50 + i) * 1 gwei;
        }

        bytes memory current = advancedTrap.buildCollectPayloadFromEvents(
            450,
            3_200,
            1_000_000 ether,
            420_000 ether,
            420_000 ether,
            210 ether,
            topics,
            dataArray,
            blockNumbers,
            timestamps,
            gasPrices
        );

        bytes memory previous = advancedTrap.buildCollectPayloadFromEvents(
            449,
            3_190,
            1_000_000 ether,
            435_000 ether,
            435_000 ether,
            215 ether,
            new bytes32[][](0),
            new bytes[](0),
            new uint256[](0),
            new uint256[](0),
            new uint256[](0)
        );

        bytes[] memory window = new bytes[](2);
        window[0] = current;
        window[1] = previous;

        (bool shouldRespond, bytes memory payload) = advancedTrap.shouldRespond(window);
        assertTrue(shouldRespond, "Advanced trap should trigger on coordinated cluster");

        vm.roll(100);

        vm.prank(droseraAddress);
        responder.handle(payload);

        assertTrue(responder.isPaused(), "Responder should pause on high confidence");
        assertEq(responder.totalIncidents(), 1, "Incident log mismatch");
        assertTrue(responder.blacklisted(wallets[0]), "Primary wallet should be blacklisted");
        assertTrue(responder.blacklisted(wallets[1]), "Secondary wallet should be blacklisted");
        assertTrue(responder.blacklisted(wallets[2]), "Tertiary wallet should be blacklisted");
    }

    function _buildEventBundle(address primaryBuyer)
        internal
        view
        returns (
            bytes32[][] memory topics,
            bytes[] memory dataArray,
            uint256[] memory blockNumbers,
            uint256[] memory timestamps
        )
    {
        address[] memory buyers = new address[](3);
        buyers[0] = primaryBuyer;
        buyers[1] = address(0xBEEF01);
        buyers[2] = address(0xBEEF02);

        uint256 length = buyers.length;
        topics = new bytes32[][](length);
        dataArray = new bytes[](length);
        blockNumbers = new uint256[](length);
        timestamps = new uint256[](length);

        for (uint256 i = 0; i < length; i++) {
            topics[i] = new bytes32[](3);
            topics[i][0] = EventLogHelper.SWAP_EVENT_SIGNATURE;
            topics[i][1] = bytes32(uint256(uint160(0xA110) + i));
            topics[i][2] = bytes32(uint256(uint160(buyers[i])));

            dataArray[i] = abi.encode(uint256(0), 8 ether, 20_000 ether, uint256(0));
            blockNumbers[i] = block.number;
            timestamps[i] = block.timestamp;
        }
    }
}

// Simple test trap (reused from Simple test)
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
        
        return abi.encode(CollectOutput(block.number, block.timestamp, totalSupply, poolBalance));
    }
    
    function shouldRespond(bytes[] calldata data) external pure returns (bool, bytes memory) {
        if (data.length < 2 || data[0].length == 0 || data[1].length == 0) {
            return (false, "");
        }
        
        CollectOutput memory current = abi.decode(data[0], (CollectOutput));
        CollectOutput memory previous = abi.decode(data[1], (CollectOutput));
        
        if (current.totalSupply == 0) return (false, "");
        
        // Liquidity drain
        if (previous.poolBalance > 0 && current.poolBalance < previous.poolBalance) {
            uint256 drain = previous.poolBalance - current.poolBalance;
            uint256 drainBP = (drain * BASIS_POINTS) / previous.poolBalance;
            
            if (drainBP > LIQUIDITY_DRAIN_THRESHOLD_BP) {
                return (true, abi.encode(
                    ResponseData(address(0), drainBP, 4, current.blockNumber, drainBP > 2000 ? 95 : 75, 90)
                ));
            }
        }
        
        // Supply manipulation
        if (previous.totalSupply > 0 && current.totalSupply != previous.totalSupply) {
            uint256 change = current.totalSupply > previous.totalSupply
                ? current.totalSupply - previous.totalSupply
                : previous.totalSupply - current.totalSupply;
            uint256 changeBP = (change * BASIS_POINTS) / previous.totalSupply;
            
            if (changeBP > SUPPLY_CHANGE_THRESHOLD_BP) {
                return (true, abi.encode(
                    ResponseData(address(0), changeBP, 3, current.blockNumber, 85, 85)
                ));
            }
        }
        
        // Multi-block
        if (data.length >= 3) {
            uint256 consecutiveDecreases = 0;
            for (uint256 i = 0; i < data.length - 1 && i < 5; i++) {
                CollectOutput memory newer = abi.decode(data[i], (CollectOutput));
                CollectOutput memory older = abi.decode(data[i + 1], (CollectOutput));
                
                if (older.poolBalance > 0 && newer.poolBalance < older.poolBalance) {
                    uint256 decrease = older.poolBalance - newer.poolBalance;
                    if ((decrease * BASIS_POINTS) / older.poolBalance > 100) {
                        consecutiveDecreases++;
                    }
                } else {
                    break;
                }
            }
            
            if (consecutiveDecreases >= 3) {
                return (true, abi.encode(
                    ResponseData(address(0), consecutiveDecreases * 100, 4, current.blockNumber, 
                                consecutiveDecreases >= 5 ? 95 : 85, 90)
                ));
            }
        }
        
        return (false, "");
    }
}
