// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../../src/v2/FairLaunchGuardianTrapAdvanced.sol";
import "../../src/v2/EventLogHelper.sol";

contract FairLaunchGuardianTrapAdvancedTest is Test {
    FairLaunchGuardianTrapAdvanced private trap;

    function setUp() public {
        trap = new FairLaunchGuardianTrapAdvanced();
    }

    function testDetectsCoordinatedCluster() public {
        address[] memory wallets = new address[](3);
        wallets[0] = address(0xA110);
        wallets[1] = address(0xA111);
        wallets[2] = address(0xA112);

        // Build two rounds of swaps to ensure each wallet has buyCount >= 2
        // First round
        (
            bytes32[][] memory topics1,
            bytes[] memory dataArray1,
            uint256[] memory blockNumbers1,
            uint256[] memory timestamps1
        ) = _buildSwapBundle(wallets, 40_000 ether, 12 ether, 120, 1_200);

        uint256[] memory gasPrices1 = new uint256[](wallets.length);
        gasPrices1[0] = 40 gwei;
        gasPrices1[1] = 41 gwei;
        gasPrices1[2] = 39 gwei;

        // Second round (same wallets buying again)
        (
            bytes32[][] memory topics2,
            bytes[] memory dataArray2,
            uint256[] memory blockNumbers2,
            uint256[] memory timestamps2
        ) = _buildSwapBundle(wallets, 35_000 ether, 10 ether, 125, 1_210);

        uint256[] memory gasPrices2 = new uint256[](wallets.length);
        gasPrices2[0] = 40 gwei;
        gasPrices2[1] = 42 gwei;
        gasPrices2[2] = 38 gwei;

        // Merge all swaps into current snapshot
        uint256 totalSwaps = wallets.length * 2;
        bytes32[][] memory allTopics = new bytes32[][](totalSwaps);
        bytes[] memory allData = new bytes[](totalSwaps);
        uint256[] memory allBlocks = new uint256[](totalSwaps);
        uint256[] memory allTimestamps = new uint256[](totalSwaps);
        uint256[] memory allGas = new uint256[](totalSwaps);

        for (uint256 i = 0; i < wallets.length; i++) {
            allTopics[i] = topics1[i];
            allData[i] = dataArray1[i];
            allBlocks[i] = blockNumbers1[i];
            allTimestamps[i] = timestamps1[i];
            allGas[i] = gasPrices1[i];

            allTopics[wallets.length + i] = topics2[i];
            allData[wallets.length + i] = dataArray2[i];
            allBlocks[wallets.length + i] = blockNumbers2[i];
            allTimestamps[wallets.length + i] = timestamps2[i];
            allGas[wallets.length + i] = gasPrices2[i];
        }

        bytes memory current = trap.buildCollectPayloadFromEvents(
            130,
            1_260,
            1_000_000 ether,
            450_000 ether,
            450_000 ether,
            180 ether,
            allTopics,
            allData,
            allBlocks,
            allTimestamps,
            allGas
        );

        bytes memory previous = trap.buildCollectPayloadFromEvents(
            129,
            1_250,
            1_000_000 ether,
            460_000 ether,
            460_000 ether,
            185 ether,
            new bytes32[][](0),
            new bytes[](0),
            new uint256[](0),
            new uint256[](0),
            new uint256[](0)
        );

        bytes[] memory window = new bytes[](2);
        window[0] = current;
        window[1] = previous;

        (bool triggered, bytes memory responseBytes) = trap.shouldRespond(window);
        assertTrue(triggered, "Coordinated cluster should trigger");

        FairLaunchGuardianTrapAdvanced.ResponseData memory response = abi.decode(
            responseBytes,
            (FairLaunchGuardianTrapAdvanced.ResponseData)
        );

        assertEq(response.detectionType, trap.DETECTION_COORDINATED_ATTACK(), "Wrong detection type");
        assertGt(response.accumulatedPercentBP, trap.EXCESSIVE_ACCUMULATION_BP(), "Accumulation below threshold");
        assertGe(response.confidence, 80, "Confidence too low");
        assertGe(response.severity, 75, "Severity too low");
    }

    function testDetectsGasManipulationWithPremium() public {
        address[] memory wallets = new address[](2);
        wallets[0] = address(0xB220);
        wallets[1] = address(0xB221);

        (
            bytes32[][] memory topics,
            bytes[] memory dataArray,
            uint256[] memory blockNumbers,
            uint256[] memory timestamps
        ) = _buildSwapBundle(wallets, 12_000 ether, 8 ether, 220, 2_200);

        uint256[] memory gasPrices = new uint256[](wallets.length);
        gasPrices[0] = 30 gwei;
        gasPrices[1] = 120 gwei; // 300% premium to trigger detection

        bytes memory current = trap.buildCollectPayloadFromEvents(
            230,
            2_260,
            1_000_000 ether,
            480_000 ether,
            480_000 ether,
            200 ether,
            topics,
            dataArray,
            blockNumbers,
            timestamps,
            gasPrices
        );

        bytes memory previous = trap.buildCollectPayloadFromEvents(
            229,
            2_250,
            1_000_000 ether,
            480_000 ether,
            480_000 ether,
            200 ether,
            new bytes32[][](0),
            new bytes[](0),
            new uint256[](0),
            new uint256[](0),
            new uint256[](0)
        );

        bytes[] memory window = new bytes[](2);
        window[0] = current;
        window[1] = previous;

        (bool triggered, bytes memory responseBytes) = trap.shouldRespond(window);
        assertTrue(triggered, "Gas manipulation should trigger");

        FairLaunchGuardianTrapAdvanced.ResponseData memory response = abi.decode(
            responseBytes,
            (FairLaunchGuardianTrapAdvanced.ResponseData)
        );

        assertEq(response.detectionType, trap.DETECTION_FRONT_RUNNING_GAS(), "Wrong detection type");
        assertEq(response.violatorAddress, wallets[1], "High gas wallet should be flagged");
        assertGt(response.accumulatedPercentBP, trap.GAS_MANIPULATION_THRESHOLD_BP(), "Gas premium below threshold");
        assertEq(response.relatedAddresses.length, 0, "No related addresses expected");
        assertGe(response.confidence, 85, "Confidence too low for response");
    }

    function _buildSwapBundle(
        address[] memory senders,
        uint256 tokenOut,
        uint256 ethIn,
        uint256 baseBlock,
        uint256 baseTimestamp
    ) internal pure returns (
        bytes32[][] memory topics,
        bytes[] memory dataArray,
        uint256[] memory blockNumbers,
        uint256[] memory timestamps
    ) {
        uint256 length = senders.length;
        topics = new bytes32[][](length);
        dataArray = new bytes[](length);
        blockNumbers = new uint256[](length);
        timestamps = new uint256[](length);

        for (uint256 i = 0; i < length; i++) {
            topics[i] = new bytes32[](3);
            topics[i][0] = EventLogHelper.SWAP_EVENT_SIGNATURE;
            topics[i][1] = bytes32(uint256(uint160(senders[i])));
            topics[i][2] = bytes32(uint256(uint160(senders[i])));

            dataArray[i] = abi.encode(uint256(0), ethIn, tokenOut, uint256(0));
            blockNumbers[i] = baseBlock + i;
            timestamps[i] = baseTimestamp + i;
        }
    }
}
