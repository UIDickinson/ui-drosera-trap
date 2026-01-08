// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../../src/v2/FairLaunchResponder.sol";
import "../../src/v2/FairLaunchResponderAdvanced.sol";
import "../mocks/MockToken.sol";

contract FairLaunchResponderTest is Test {
    FairLaunchResponder public responder;
    address public droseraAddress;
    address public token;
    address public pool;
    address public owner;
    
    event LaunchGuardianIncident(
        address indexed violator,
        uint8 indexed detectionType,
        uint256 severity,
        uint256 blockNumber,
        uint256 accumulatedPercentBP,
        uint256 timestamp
    );
    
    event EmergencyPauseTriggered(
        address indexed target,
        uint256 blockNumber,
        uint256 timestamp
    );
    
    event AddressBlacklisted(
        address indexed violator,
        uint8 reason,
        uint256 timestamp
    );
    
    function setUp() public {
        owner = address(this);
        droseraAddress = address(0x1234);
        token = address(0x5678);
        pool = address(0x9ABC);
        
        responder = new FairLaunchResponder(
            droseraAddress,
            token,
            pool
        );
    }
    
    function testOnlyDroseraCanCallHandle() public {
        bytes memory payload = abi.encode(
            address(0xDEF), // violator
            1000, // 10%
            uint8(4), // LIQUIDITY_MANIPULATION
            block.number,
            75 // severity
        );
        
        // Try calling from non-Drosera address
        vm.expectRevert("Only Drosera can call");
        responder.handle(payload);
        
        // Should work from Drosera
        vm.prank(droseraAddress);
        responder.handle(payload);
    }
    
    function testHandleEmitsIncidentEvent() public {
        address violator = address(0xBAD);
        uint8 detectionType = 4;
        uint256 severity = 85;
        
        bytes memory payload = abi.encode(
            violator,
            2000, // 20%
            detectionType,
            block.number,
            severity
        );
        
        vm.expectEmit(true, true, false, true);
        emit LaunchGuardianIncident(
            violator,
            detectionType,
            severity,
            block.number,
            2000,
            block.timestamp
        );
        
        vm.prank(droseraAddress);
        responder.handle(payload);
    }
    
    function testHighSeverityTriggersEmergencyPause() public {
        bytes memory payload = abi.encode(
            address(0xBAD),
            2000,
            uint8(4),
            block.number,
            95 // High severity
        );
        
        vm.expectEmit(true, false, false, true);
        emit EmergencyPauseTriggered(token, block.number, block.timestamp);
        
        vm.prank(droseraAddress);
        responder.handle(payload);
        
        assertTrue(responder.isPaused(), "Should be paused");
    }
    
    function testMediumSeverityBlacklists() public {
        address violator = address(0xBAD);
        
        bytes memory payload = abi.encode(
            violator,
            1500,
            uint8(0),
            block.number,
            60 // Medium severity
        );
        
        vm.expectEmit(true, false, false, true);
        emit AddressBlacklisted(violator, 0, block.timestamp);
        
        vm.prank(droseraAddress);
        responder.handle(payload);
        
        assertTrue(responder.blacklisted(violator), "Should be blacklisted");
        assertFalse(responder.isPaused(), "Should not be paused");
    }
    
    function testLowSeverityOnlyLogs() public {
        address violator = address(0xBAD);
        
        bytes memory payload = abi.encode(
            violator,
            800,
            uint8(1),
            block.number,
            40 // Low severity
        );
        
        vm.prank(droseraAddress);
        responder.handle(payload);
        
        assertFalse(responder.blacklisted(violator), "Should not be blacklisted");
        assertFalse(responder.isPaused(), "Should not be paused");
    }
    
    function testOwnerCanUnpause() public {
        // Trigger pause
        bytes memory payload = abi.encode(
            address(0xBAD),
            2000,
            uint8(4),
            block.number,
            95
        );
        
        vm.prank(droseraAddress);
        responder.handle(payload);
        
        assertTrue(responder.isPaused(), "Should be paused");
        
        // Owner unpauses
        responder.unpause();
        
        assertFalse(responder.isPaused(), "Should be unpaused");
    }
    
    function testNonOwnerCannotUnpause() public {
        vm.expectRevert("Only owner can call");
        vm.prank(address(0x999));
        responder.unpause();
    }
    
    function testOwnerCanRemoveFromBlacklist() public {
        address violator = address(0xBAD);
        
        // Blacklist first
        bytes memory payload = abi.encode(
            violator,
            1500,
            uint8(0),
            block.number,
            60
        );
        
        vm.prank(droseraAddress);
        responder.handle(payload);
        
        assertTrue(responder.blacklisted(violator), "Should be blacklisted");
        
        // Remove
        responder.removeFromBlacklist(violator);
        
        assertFalse(responder.blacklisted(violator), "Should not be blacklisted");
    }
    
    function testIncidentHistoryTracked() public {
        bytes memory payload = abi.encode(
            address(0xBAD),
            1000,
            uint8(2),
            block.number,
            50
        );
        
        assertEq(responder.totalIncidents(), 0, "Should start at 0");
        
        vm.prank(droseraAddress);
        responder.handle(payload);
        
        assertEq(responder.totalIncidents(), 1, "Should increment");
        
        FairLaunchResponder.ResponseData memory incident = responder.getIncident(0);
        assertEq(incident.violatorAddress, address(0xBAD), "Should store violator");
        assertEq(incident.detectionType, 2, "Should store detection type");
    }
}

contract FairLaunchResponderAdvancedTest is Test {
    FairLaunchResponderAdvanced public responder;
    address public droseraAddress;
    address public token;
    address public pool;
    
    function setUp() public {
        droseraAddress = address(0x1234);
        token = address(0x5678);
        pool = address(0x9ABC);
        
        responder = new FairLaunchResponderAdvanced(
            droseraAddress,
            token,
            pool
        );
        
        // Advance past any cooldown from deployment
        vm.roll(block.number + 10);
    }
    
    // Helper function to build properly encoded payload
    function _buildPayload(
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
    
    function testConfidenceThresholds() public {
        // Low confidence - should only log
        bytes memory lowConfPayload = _buildPayload(
            address(0xBAD),
            new address[](0),
            1000,
            4,
            block.number,
            90, // high severity
            60, // low confidence
            keccak256("test")
        );
        
        vm.prank(droseraAddress);
        responder.handle(lowConfPayload);
        
        assertFalse(responder.isPaused(), "Low confidence should not pause");
        assertFalse(responder.blacklisted(address(0xBAD)), "Low confidence should not blacklist");
        
        // High confidence - should act
        vm.roll(block.number + 10); // Respect cooldown
        
        bytes memory highConfPayload = _buildPayload(
            address(0xBAD2),
            new address[](0),
            2000,
            4,
            block.number,
            95, // high severity
            90, // high confidence
            keccak256("test2")
        );
        
        vm.prank(droseraAddress);
        responder.handle(highConfPayload);
        
        assertTrue(responder.isPaused(), "High confidence should pause");
    }
    
    function testCoordinatedAttackBlacklistsAll() public {
        address[] memory relatedAddresses = new address[](3);
        relatedAddresses[0] = address(0xBAD1);
        relatedAddresses[1] = address(0xBAD2);
        relatedAddresses[2] = address(0xBAD3);
        
        bytes memory payload = _buildPayload(
            address(0xAABBCC),
            relatedAddresses,
            1000,
            3, // COORDINATED_ATTACK
            block.number,
            80,
            85,
            keccak256("coordinated")
        );
        
        vm.prank(droseraAddress);
        responder.handle(payload);
        
        assertTrue(responder.blacklisted(address(0xAABBCC)), "Main should be blacklisted");
        assertTrue(responder.blacklisted(address(0xBAD1)), "Related 1 should be blacklisted");
        assertTrue(responder.blacklisted(address(0xBAD2)), "Related 2 should be blacklisted");
        assertTrue(responder.blacklisted(address(0xBAD3)), "Related 3 should be blacklisted");
    }
    
    function testCooldownPreventsSpam() public {
        bytes memory payload = _buildPayload(
            address(0xBAD),
            new address[](0),
            1000,
            4,
            block.number,
            60,
            75,
            keccak256("test")
        );
        
        vm.startPrank(droseraAddress);
        
        // First call succeeds
        responder.handle(payload);
        
        // Second call immediately fails
        vm.expectRevert("Cooldown period active");
        responder.handle(payload);
        
        // After cooldown, succeeds
        vm.roll(block.number + 6);
        responder.handle(payload);
        
        vm.stopPrank();
    }
    
    function testThreatIntelligenceTracking() public {
        bytes32 pattern = keccak256("malicious_pattern");
        
        bytes memory payload = _buildPayload(
            address(0xBAD),
            new address[](0),
            1000,
            4,
            block.number,
            60,
            75,
            pattern
        );
        
        vm.prank(droseraAddress);
        responder.handle(payload);
        
        FairLaunchResponderAdvanced.ThreatIntel memory intel = 
            responder.getThreatIntel(pattern);
        
        assertEq(intel.occurrences, 1, "Should track occurrence");
        assertEq(intel.detectionType, 4, "Should store detection type");
        assertFalse(intel.resolved, "Should not be resolved");
    }
    
    function testOwnerCanAdjustThresholds() public {
        responder.setConfidenceThresholds(90, 80, 60);
        
        (uint256 pause, uint256 blacklist, uint256 alert) = 
            responder.getConfidenceThresholds();
        
        assertEq(pause, 90, "Pause threshold updated");
        assertEq(blacklist, 80, "Blacklist threshold updated");
        assertEq(alert, 60, "Alert threshold updated");
    }
}
