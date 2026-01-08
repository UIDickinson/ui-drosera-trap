// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../../src/v2/FairLaunchGuardianTrapEventLog.sol";
import "../../src/v2/EventLogHelper.sol";

contract FairLaunchGuardianTrapEventLogTest is Test {
    FairLaunchGuardianTrapEventLog private trap;

    function setUp() public {
        trap = new FairLaunchGuardianTrapEventLog();
    }

    function testDetectsExcessiveAccumulationFromEvents() public {
        address buyer = address(0xBEEF);
        uint256 totalSupply = 1_000_000 ether;
        uint256 poolBalance = 500_000 ether;
        uint256 reserve0 = 500_000 ether;
        uint256 reserve1 = 100 ether;

        (
            bytes32[][] memory topics,
            bytes[] memory dataArray,
            uint256[] memory blockNumbers,
            uint256[] memory timestamps
        ) = _singleBuyEvent(address(0xAAA1), buyer, 25_000 ether, 12 ether);

        bytes memory payload = trap.buildCollectPayloadFromEvents(
            block.number,
            block.timestamp,
            totalSupply,
            poolBalance,
            reserve0,
            reserve1,
            topics,
            dataArray,
            blockNumbers,
            timestamps
        );

        bytes[] memory window = new bytes[](1);
        window[0] = payload;

        (bool triggered, bytes memory responseBytes) = trap.shouldRespond(window);
        assertTrue(triggered, "Event-driven accumulation should trigger");

        FairLaunchGuardianTrapEventLog.ResponseData memory response = abi.decode(
            responseBytes,
            (FairLaunchGuardianTrapEventLog.ResponseData)
        );

        assertEq(response.detectionType, trap.DETECTION_EXCESSIVE_ACCUMULATION(), "Wrong detection type");
        assertEq(response.violatorAddress, buyer, "Buyer should be flagged");
        assertGt(response.accumulatedPercentBP, trap.EXCESSIVE_ACCUMULATION_BP(), "Accumulation below threshold");
        assertEq(response.relatedAddresses.length, 0, "No related addresses expected");
        assertTrue(response.patternSignature != bytes32(0), "Pattern signature not set");
    }

    function testDetectsCoordinatedAttack() public {
        address[] memory buyers = new address[](3);
        buyers[0] = address(0xB001);
        buyers[1] = address(0xB002);
        buyers[2] = address(0xB003);

        (
            bytes32[][] memory topics,
            bytes[] memory dataArray,
            uint256[] memory blockNumbers,
            uint256[] memory timestamps
        ) = _multipleBuyEvents(buyers, 5_000 ether, 6 ether);

        bytes memory payload = trap.buildCollectPayloadFromEvents(
            block.number,
            block.timestamp,
            1_000_000 ether,
            400_000 ether,
            400_000 ether,
            200 ether,
            topics,
            dataArray,
            blockNumbers,
            timestamps
        );

        bytes[] memory window = new bytes[](1);
        window[0] = payload;

        (bool triggered, bytes memory responseBytes) = trap.shouldRespond(window);
        assertTrue(triggered, "Coordinated attack should trigger");

        FairLaunchGuardianTrapEventLog.ResponseData memory response = abi.decode(
            responseBytes,
            (FairLaunchGuardianTrapEventLog.ResponseData)
        );

        assertEq(response.detectionType, trap.DETECTION_COORDINATED_ATTACK(), "Wrong detection type");
        assertEq(response.relatedAddresses.length, buyers.length, "All buyers should be related");
        assertEq(response.violatorAddress, buyers[0], "Primary violator mismatch");
    }

    function _singleBuyEvent(
        address sender,
        address recipient,
        uint256 tokenOut,
        uint256 ethIn
    ) internal view returns (
        bytes32[][] memory topics,
        bytes[] memory dataArray,
        uint256[] memory blockNumbers,
        uint256[] memory timestamps
    ) {
        topics = new bytes32[][](1);
        topics[0] = new bytes32[](3);
        topics[0][0] = EventLogHelper.SWAP_EVENT_SIGNATURE;
        topics[0][1] = bytes32(uint256(uint160(sender)));
        topics[0][2] = bytes32(uint256(uint160(recipient)));

        dataArray = new bytes[](1);
        dataArray[0] = abi.encode(uint256(0), ethIn, tokenOut, uint256(0));

        blockNumbers = new uint256[](1);
        blockNumbers[0] = block.number;

        timestamps = new uint256[](1);
        timestamps[0] = block.timestamp;
    }

    function _multipleBuyEvents(
        address[] memory buyers,
        uint256 tokenOut,
        uint256 ethIn
    ) internal view returns (
        bytes32[][] memory topics,
        bytes[] memory dataArray,
        uint256[] memory blockNumbers,
        uint256[] memory timestamps
    ) {
        uint256 length = buyers.length;
        topics = new bytes32[][](length);
        dataArray = new bytes[](length);
        blockNumbers = new uint256[](length);
        timestamps = new uint256[](length);

        for (uint256 i = 0; i < length; i++) {
            topics[i] = new bytes32[](3);
            topics[i][0] = EventLogHelper.SWAP_EVENT_SIGNATURE;
            topics[i][1] = bytes32(uint256(uint160(0xA100) + i));
            topics[i][2] = bytes32(uint256(uint160(buyers[i])));

            dataArray[i] = abi.encode(uint256(0), ethIn, tokenOut, uint256(0));
            blockNumbers[i] = block.number;
            timestamps[i] = block.timestamp;
        }
    }
}
