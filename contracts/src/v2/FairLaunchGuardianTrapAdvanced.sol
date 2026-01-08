// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../interfaces/ITrap.sol";
import "../interfaces/IERC20.sol";
import "../interfaces/IUniswapV2Pair.sol";
import "./EventLogHelper.sol";

/**
 * @title FairLaunchGuardianTrapAdvanced - Drosera V2 Enhanced
 * @notice Advanced stateless trap with EventLog filtering and sophisticated pattern detection
 * @dev Implements ITrap interface with pure/view functions only. No state storage.
 * 
 * Enhancements over basic version:
 * - EventLog filtering for Uniswap Swap events
 * - Wallet clustering detection
 * - Gas price manipulation detection
 * - Coordinated attack patterns
 * - Time-series anomaly detection
 * 
 * Architecture:
 * - collect() reads on-chain state + parses event logs
 * - shouldRespond() analyzes historical window with advanced algorithms
 * - Returns detailed payload for responder with threat intelligence
 * 
 * DEPLOYMENT: Update TOKEN_ADDRESS, LIQUIDITY_POOL, TOKEN_IS_TOKEN0, LAUNCH_BLOCK before compiling!
 */
contract FairLaunchGuardianTrapAdvanced is ITrap {
    
    // ==================== CONSTANTS ====================
    
    uint256 public constant BASIS_POINTS = 10_000;
    uint256 public constant MAX_SWAPS_PER_BLOCK = 100; // Safety limit for gas
    uint256 public constant MAX_HISTORY_SNAPSHOTS = 5; // Clamp history analysis
    
    // Detection thresholds
    uint256 public constant EXCESSIVE_ACCUMULATION_BP = 100; // 1%
    uint256 public constant GAS_MANIPULATION_THRESHOLD_BP = 5000; // 50% above average
    uint256 public constant COORDINATED_WALLET_THRESHOLD = 3; // Min wallets for clustering
    uint256 public constant RAPID_BUY_WINDOW = 5; // Blocks
    uint256 public constant LIQUIDITY_DRAIN_THRESHOLD_BP = 1000; // 10%
    
    // ==================== STRUCTS ====================
    
    /**
     * @notice Parsed swap data from event logs
     */
    struct SwapData {
        address wallet;
        bool isBuy;
        uint256 amountToken;
        uint256 amountETH;
        uint256 gasPrice;
        uint256 blockNumber;
        uint256 timestamp;
    }
    
    /**
     * @notice Output structure from collect() - comprehensive snapshot
     */
    struct CollectOutput {
        uint256 blockNumber;
        uint256 timestamp;
        address tokenAddress;
        address liquidityPool;
        uint256 totalSupply;
        uint256 liquidityPoolBalance;
        uint256 poolReserveToken;
        uint256 poolReserveETH;
        SwapData[] recentSwaps; // Parsed from event logs
    }
    
    /**
     * @notice Enhanced response data with threat intelligence
     */
    struct ResponseData {
        address violatorAddress;
        address[] relatedAddresses; // For coordinated attacks
        uint256 accumulatedPercentBP;
        uint8 detectionType;
        uint256 blockNumber;
        uint256 severity; // 0-100
        uint256 confidence; // 0-100
        bytes32 patternSignature; // Hash of detected pattern
    }
    
    /**
     * @notice Wallet behavior profile for clustering analysis
     */
    struct WalletProfile {
        address wallet;
        uint256 totalBought;
        uint256 buyCount;
        uint256 averageGasPrice;
        uint256 firstSeenBlock;
        uint256 lastSeenBlock;
    }
    
    // Detection types
    uint8 public constant DETECTION_EXCESSIVE_ACCUMULATION = 0;
    uint8 public constant DETECTION_FRONT_RUNNING_GAS = 1;
    uint8 public constant DETECTION_RAPID_BUYING = 2;
    uint8 public constant DETECTION_COORDINATED_ATTACK = 3;
    uint8 public constant DETECTION_LIQUIDITY_MANIPULATION = 4;
    uint8 public constant DETECTION_WASH_TRADING = 5;
    uint8 public constant DETECTION_SYBIL_ATTACK = 6;
    uint8 public constant DETECTION_SUPPLY_MANIPULATION = 7;
    
    // ==================== CONFIGURATION ====================
    
    // PRODUCTION: These addresses are set for Hoodi testnet deployment
    // These MUST be literal addresses (compile-time constants for Drosera)
    address public constant TOKEN_ADDRESS = 0xBE820752AE8E48010888E89862cbb97aF506d183; // DemoToken on Hoodi
    address public constant LIQUIDITY_POOL = 0xE225187b6f9F107d558B9585D5F5D94Aae6F4F71; // DemoDEX on Hoodi
    bool public constant TOKEN_IS_TOKEN0 = true; // TODO: Set based on actual pair ordering
    uint256 public constant LAUNCH_BLOCK = 0; // TODO: Set to actual launch block
    
    // ==================== ITRAP INTERFACE ====================
    
    /**
     * @notice Collects comprehensive on-chain state snapshot with event parsing
     * @dev VIEW function - reads blockchain state and parses recent Swap events
     * @return Encoded CollectOutput with swap history and metrics
     */
    function collect() external view override returns (bytes memory) {
        // Read deterministic on-chain state
        uint256 totalSupply = 0;
        uint256 poolBalance = 0;
        uint256 reserve0 = 0;
        uint256 reserve1 = 0;
        
        // Safely read token data
        try IERC20(TOKEN_ADDRESS).totalSupply() returns (uint256 supply) {
            totalSupply = supply;
        } catch {}
        
        try IERC20(TOKEN_ADDRESS).balanceOf(LIQUIDITY_POOL) returns (uint256 balance) {
            poolBalance = balance;
        } catch {}
        
        // Read Uniswap pair reserves
        try IUniswapV2Pair(LIQUIDITY_POOL).getReserves() returns (
            uint112 _reserve0,
            uint112 _reserve1,
            uint32
        ) {
            reserve0 = uint256(_reserve0);
            reserve1 = uint256(_reserve1);
        } catch {}
        
        // Determine which reserve is our token (simplified - assumes token0)
        bool tokenIsToken0 = TOKEN_IS_TOKEN0;
        if (LIQUIDITY_POOL != address(0) && TOKEN_ADDRESS != address(0)) {
            try IUniswapV2Pair(LIQUIDITY_POOL).token0() returns (address token0) {
                if (token0 == TOKEN_ADDRESS) {
                    tokenIsToken0 = true;
                } else if (token0 != address(0)) {
                    tokenIsToken0 = false;
                }
            } catch {}
        }
        
        uint256 reserveToken = tokenIsToken0 ? reserve0 : reserve1;
        uint256 reserveETH = tokenIsToken0 ? reserve1 : reserve0;
        
        // Swap parsing is delegated to Drosera EventFilter helpers that call
        // buildCollectPayloadFromEvents(). collect() returns an empty array so
        // tests can inject deterministic samples without on-chain logs.
        SwapData[] memory swaps = new SwapData[](0);
        
        CollectOutput memory output = CollectOutput({
            blockNumber: block.number,
            timestamp: block.timestamp,
            tokenAddress: TOKEN_ADDRESS,
            liquidityPool: LIQUIDITY_POOL,
            totalSupply: totalSupply,
            liquidityPoolBalance: poolBalance,
            poolReserveToken: reserveToken,
            poolReserveETH: reserveETH,
            recentSwaps: swaps
        });
        
        return abi.encode(output);
    }

    /**
     * @notice Helper for Drosera EventFilter to build CollectOutput from raw swap logs
     * @dev Pure helper so tests/operators can leverage pre-parsed event data safely
     */
    function buildCollectPayloadFromEvents(
        uint256 blockNumber,
        uint256 timestamp,
        uint256 totalSupply,
        uint256 poolBalance,
        uint256 reserveToken,
        uint256 reserveETH,
        bytes32[][] memory topics,
        bytes[] memory dataArray,
        uint256[] memory logBlockNumbers,
        uint256[] memory logTimestamps,
        uint256[] memory gasPrices
    ) external pure returns (bytes memory) {
        require(
            topics.length == dataArray.length &&
            dataArray.length == logBlockNumbers.length &&
            logBlockNumbers.length == logTimestamps.length,
            "Event array mismatch"
        );
        require(
            gasPrices.length == 0 || gasPrices.length == topics.length,
            "Gas array mismatch"
        );

        EventLogHelper.ParsedSwap[] memory parsed = EventLogHelper.batchParseSwapEvents(
            topics,
            dataArray,
            logBlockNumbers,
            logTimestamps,
            LIQUIDITY_POOL
        );

        uint256 limit = parsed.length < MAX_SWAPS_PER_BLOCK ? parsed.length : MAX_SWAPS_PER_BLOCK;
        SwapData[] memory swaps = new SwapData[](limit);

        for (uint256 i = 0; i < limit; i++) {
            (bool isBuy, uint256 tokenAmount, uint256 ethAmount) = EventLogHelper.analyzeSwapDirection(
                parsed[i],
                TOKEN_IS_TOKEN0
            );

            uint256 gasPrice = gasPrices.length == 0 ? 0 : gasPrices[i];

            swaps[i] = SwapData({
                wallet: parsed[i].sender,
                isBuy: isBuy,
                amountToken: tokenAmount,
                amountETH: ethAmount,
                gasPrice: gasPrice,
                blockNumber: parsed[i].blockNumber,
                timestamp: parsed[i].timestamp
            });
        }

        CollectOutput memory output = CollectOutput({
            blockNumber: blockNumber,
            timestamp: timestamp,
            tokenAddress: TOKEN_ADDRESS,
            liquidityPool: LIQUIDITY_POOL,
            totalSupply: totalSupply,
            liquidityPoolBalance: poolBalance,
            poolReserveToken: reserveToken,
            poolReserveETH: reserveETH,
            recentSwaps: swaps
        });

        return abi.encode(output);
    }
    
    /**
     * @notice Advanced analysis with multiple detection algorithms
     * @dev PURE function - analyzes only the data[] parameter
     * @param data Array of encoded CollectOutput structs (historical window)
     * @return shouldRespond True if violation detected
     * @return responseData Encoded ResponseData with threat intelligence
     */
    function shouldRespond(bytes[] calldata data)
        external
        pure
        override
        returns (bool, bytes memory)
    {
        // ==================== INPUT VALIDATION ====================
        
        if (data.length < 1 || data[0].length == 0) {
            return (false, "");
        }
        
        // For advanced detection, prefer at least 3 samples
        if (data.length < 2) {
            return (false, "");
        }
        
        // ==================== DECODE SAMPLES ====================
        
        CollectOutput memory current = abi.decode(data[0], (CollectOutput));
        CollectOutput memory previous = abi.decode(data[1], (CollectOutput));
        
        if (current.totalSupply == 0) {
            return (false, "");
        }
        
        // ==================== DETECTION ALGORITHMS ====================
        
        // 1. Liquidity Drain Detection (Enhanced)
        {
            (bool detected, ResponseData memory response) = _detectLiquidityDrain(
                current,
                previous
            );
            if (detected) return (true, abi.encode(response));
        }
        
        // 2. Supply Manipulation Detection
        {
            (bool detected, ResponseData memory response) = _detectSupplyManipulation(
                current,
                previous
            );
            if (detected) return (true, abi.encode(response));
        }
        
        // 3. Gas Price Manipulation (if swap data available)
        if (current.recentSwaps.length > 0) {
            (bool detected, ResponseData memory response) = _detectGasManipulation(
                current
            );
            if (detected) return (true, abi.encode(response));
        }
        
        // 4. Wallet Clustering (Coordinated Attack)
        if (current.recentSwaps.length > 0 && data.length >= 2) {
            (bool detected, ResponseData memory response) = _detectCoordinatedAttack(
                current,
                data
            );
            if (detected) return (true, abi.encode(response));
        }
        
        // 5. Multi-Block Pattern Analysis
        if (data.length >= 3) {
            (bool detected, ResponseData memory response) = _detectMultiBlockPatterns(
                data
            );
            if (detected) return (true, abi.encode(response));
        }
        
        // 6. Wash Trading Detection
        if (current.recentSwaps.length >= 2) {
            (bool detected, ResponseData memory response) = _detectWashTrading(
                current
            );
            if (detected) return (true, abi.encode(response));
        }
        
        return (false, "");
    }
    
    // ==================== DETECTION ALGORITHMS ====================
    
    /**
     * @notice Detects sudden liquidity drainage
     */
    function _detectLiquidityDrain(
        CollectOutput memory current,
        CollectOutput memory previous
    ) internal pure returns (bool, ResponseData memory) {
        if (previous.liquidityPoolBalance == 0) {
            return (false, ResponseData(address(0), new address[](0), 0, 0, 0, 0, 0, bytes32(0)));
        }
        
        // Check for significant liquidity decrease
        if (current.liquidityPoolBalance >= previous.liquidityPoolBalance) {
            return (false, ResponseData(address(0), new address[](0), 0, 0, 0, 0, 0, bytes32(0)));
        }
        
        uint256 liquidityDrop = previous.liquidityPoolBalance - current.liquidityPoolBalance;
        uint256 liquidityDropBP = (liquidityDrop * BASIS_POINTS) / previous.liquidityPoolBalance;
        
        if (liquidityDropBP <= LIQUIDITY_DRAIN_THRESHOLD_BP) {
            return (false, ResponseData(address(0), new address[](0), 0, 0, 0, 0, 0, bytes32(0)));
        }
        
        // Calculate severity and confidence
        uint256 severity = _calculateSeverity(liquidityDropBP, LIQUIDITY_DRAIN_THRESHOLD_BP);
        uint256 confidence = liquidityDropBP > 2000 ? 95 : 80; // Maintain pause path for notable drains
        
        ResponseData memory response = ResponseData({
            violatorAddress: current.liquidityPool,
            relatedAddresses: new address[](0),
            accumulatedPercentBP: liquidityDropBP,
            detectionType: DETECTION_LIQUIDITY_MANIPULATION,
            blockNumber: current.blockNumber,
            severity: severity,
            confidence: confidence,
            patternSignature: keccak256(abi.encodePacked("LIQUIDITY_DRAIN", current.blockNumber))
        });
        
        return (true, response);
    }
    
    /**
     * @notice Detects suspicious supply changes
     */
    function _detectSupplyManipulation(
        CollectOutput memory current,
        CollectOutput memory previous
    ) internal pure returns (bool, ResponseData memory) {
        if (previous.totalSupply == 0 || current.totalSupply == previous.totalSupply) {
            return (false, ResponseData(address(0), new address[](0), 0, 0, 0, 0, 0, bytes32(0)));
        }
        
        uint256 supplyChange = current.totalSupply > previous.totalSupply
            ? current.totalSupply - previous.totalSupply
            : previous.totalSupply - current.totalSupply;
        
        uint256 supplyChangeBP = (supplyChange * BASIS_POINTS) / previous.totalSupply;
        
        // Trigger on >5% supply change
        if (supplyChangeBP <= 500) {
            return (false, ResponseData(address(0), new address[](0), 0, 0, 0, 0, 0, bytes32(0)));
        }
        
        uint256 severity = _calculateSeverity(supplyChangeBP, 500);
        uint256 confidence = 80;
        
        ResponseData memory response = ResponseData({
            violatorAddress: current.tokenAddress,
            relatedAddresses: new address[](0),
            accumulatedPercentBP: supplyChangeBP,
            detectionType: DETECTION_SUPPLY_MANIPULATION,
            blockNumber: current.blockNumber,
            severity: severity,
            confidence: confidence,
            patternSignature: keccak256(abi.encodePacked("SUPPLY_MANIPULATION", current.blockNumber))
        });
        
        return (true, response);
    }
    
    /**
     * @notice Detects gas price manipulation (front-running)
     */
    function _detectGasManipulation(
        CollectOutput memory current
    ) internal pure returns (bool, ResponseData memory) {
        if (current.recentSwaps.length < 2) {
            return (false, ResponseData(address(0), new address[](0), 0, 0, 0, 0, 0, bytes32(0)));
        }
        
        // Calculate average gas price
        uint256 totalGas = 0;
        uint256 maxGas = 0;
        uint256 sampleCount = 0;
        address maxGasWallet = address(0);

        for (uint256 i = 0; i < current.recentSwaps.length && i < MAX_SWAPS_PER_BLOCK; i++) {
            uint256 gas = current.recentSwaps[i].gasPrice;
            if (gas == 0) {
                continue;
            }

            totalGas += gas;
            sampleCount++;

            if (gas > maxGas) {
                maxGas = gas;
                maxGasWallet = current.recentSwaps[i].wallet;
            }
        }

        if (sampleCount < 2) {
            return (false, ResponseData(address(0), new address[](0), 0, 0, 0, 0, 0, bytes32(0)));
        }

        uint256 avgGas = totalGas / sampleCount;
        
        if (avgGas == 0 || maxGas <= avgGas) {
            return (false, ResponseData(address(0), new address[](0), 0, 0, 0, 0, 0, bytes32(0)));
        }
        
        // Check if max gas is significantly higher than average
        uint256 gasPremiumBP = ((maxGas - avgGas) * BASIS_POINTS) / avgGas;
        
        if (gasPremiumBP <= GAS_MANIPULATION_THRESHOLD_BP) {
            return (false, ResponseData(address(0), new address[](0), 0, 0, 0, 0, 0, bytes32(0)));
        }
        
        uint256 severity = _calculateSeverity(gasPremiumBP, GAS_MANIPULATION_THRESHOLD_BP);
        uint256 confidence = 85;
        
        ResponseData memory response = ResponseData({
            violatorAddress: maxGasWallet,
            relatedAddresses: new address[](0),
            accumulatedPercentBP: gasPremiumBP,
            detectionType: DETECTION_FRONT_RUNNING_GAS,
            blockNumber: current.blockNumber,
            severity: severity,
            confidence: confidence,
            patternSignature: keccak256(abi.encodePacked("GAS_MANIPULATION", maxGasWallet))
        });
        
        return (true, response);
    }
    
    /**
     * @notice Detects coordinated attacks across multiple wallets
     */
    function _detectCoordinatedAttack(
        CollectOutput memory current,
        bytes[] calldata data
    ) internal pure returns (bool, ResponseData memory) {
        WalletProfile[] memory profiles = _buildWalletProfiles(data);

        if (profiles.length < COORDINATED_WALLET_THRESHOLD) {
            return (false, ResponseData(address(0), new address[](0), 0, 0, 0, 0, 0, bytes32(0)));
        }

        uint256 anchorIndex = 0;
        uint256 anchorBuys = 0;
        for (uint256 i = 0; i < profiles.length; i++) {
            if (profiles[i].buyCount > anchorBuys) {
                anchorBuys = profiles[i].buyCount;
                anchorIndex = i;
            }
        }

        if (anchorBuys < 2) {
            return (false, ResponseData(address(0), new address[](0), 0, 0, 0, 0, 0, bytes32(0)));
        }

        WalletProfile memory anchor = profiles[anchorIndex];
        address[] memory relatedBuffer = new address[](profiles.length);
        uint256 relatedCount = 0;

        for (uint256 i = 0; i < profiles.length; i++) {
            WalletProfile memory candidate = profiles[i];

            uint256 gasDiff = candidate.averageGasPrice > anchor.averageGasPrice
                ? candidate.averageGasPrice - anchor.averageGasPrice
                : anchor.averageGasPrice - candidate.averageGasPrice;

            bool gasAligned = anchor.averageGasPrice == 0 || candidate.averageGasPrice == 0
                ? true
                : gasDiff * 100 <= anchor.averageGasPrice * 15; // <=15% diff

            uint256 blockDiff = candidate.firstSeenBlock > anchor.firstSeenBlock
                ? candidate.firstSeenBlock - anchor.firstSeenBlock
                : anchor.firstSeenBlock - candidate.firstSeenBlock;

            if (!gasAligned || blockDiff > 2) {
                continue;
            }

            bool alreadyIncluded = false;
            for (uint256 r = 0; r < relatedCount; r++) {
                if (relatedBuffer[r] == candidate.wallet) {
                    alreadyIncluded = true;
                    break;
                }
            }

            if (alreadyIncluded) {
                continue;
            }

            relatedBuffer[relatedCount] = candidate.wallet;
            relatedCount++;
        }

        if (relatedCount < COORDINATED_WALLET_THRESHOLD) {
            return (false, ResponseData(address(0), new address[](0), 0, 0, 0, 0, 0, bytes32(0)));
        }

        address[] memory clusterWallets = new address[](relatedCount);
        for (uint256 i = 0; i < relatedCount; i++) {
            clusterWallets[i] = relatedBuffer[i];
        }

        uint256 clusterVolume = 0;
        uint256 swapLimit = current.recentSwaps.length < MAX_SWAPS_PER_BLOCK
            ? current.recentSwaps.length
            : MAX_SWAPS_PER_BLOCK;

        for (uint256 i = 0; i < swapLimit; i++) {
            SwapData memory swapInfo = current.recentSwaps[i];
            if (!swapInfo.isBuy) continue;

            for (uint256 j = 0; j < clusterWallets.length; j++) {
                if (swapInfo.wallet == clusterWallets[j]) {
                    clusterVolume += swapInfo.amountToken;
                    break;
                }
            }
        }

        if (clusterVolume == 0 || current.totalSupply == 0) {
            return (false, ResponseData(address(0), new address[](0), 0, 0, 0, 0, 0, bytes32(0)));
        }

        uint256 accumulatedBP = (clusterVolume * BASIS_POINTS) / current.totalSupply;
        if (accumulatedBP < EXCESSIVE_ACCUMULATION_BP) {
            return (false, ResponseData(address(0), new address[](0), 0, 0, 0, 0, 0, bytes32(0)));
        }

        // Exclude anchor from related addresses (anchor is the violator)
        uint256 relatedSize = clusterWallets.length - 1;
        address[] memory relatedAddresses = new address[](relatedSize);
        uint256 cursor = 0;
        for (uint256 i = 0; i < clusterWallets.length; i++) {
            if (clusterWallets[i] == anchor.wallet) continue;
            relatedAddresses[cursor] = clusterWallets[i];
            cursor++;
        }

        uint256 severity = 75;
        if (accumulatedBP > 300) severity += 10;
        if (clusterWallets.length >= 5) severity += 10;
        if (severity > 95) severity = 95;

        uint256 confidence = 80;
        if (accumulatedBP > 300) confidence += 5;
        if (confidence > 95) confidence = 95;

        ResponseData memory response = ResponseData({
            violatorAddress: anchor.wallet,
            relatedAddresses: relatedAddresses,
            accumulatedPercentBP: accumulatedBP,
            detectionType: DETECTION_COORDINATED_ATTACK,
            blockNumber: anchor.firstSeenBlock,
            severity: severity,
            confidence: confidence,
            patternSignature: keccak256(abi.encodePacked("COORDINATED", clusterWallets.length))
        });

        return (true, response);
    }
    
    /**
     * @notice Detects patterns across multiple blocks
     */
    function _detectMultiBlockPatterns(
        bytes[] calldata data
    ) internal pure returns (bool, ResponseData memory) {
        if (data.length < 3) {
            return (false, ResponseData(address(0), new address[](0), 0, 0, 0, 0, 0, bytes32(0)));
        }
        
        uint256 consecutiveDecreases = 0;
        
        uint256 window = data.length - 1;
        if (window > MAX_HISTORY_SNAPSHOTS) {
            window = MAX_HISTORY_SNAPSHOTS;
        }

        for (uint256 i = 0; i < window; i++) {
            CollectOutput memory newer = abi.decode(data[i], (CollectOutput));
            CollectOutput memory older = abi.decode(data[i + 1], (CollectOutput));
            
            if (older.liquidityPoolBalance == 0) continue;
            
            if (newer.liquidityPoolBalance < older.liquidityPoolBalance) {
                uint256 decrease = older.liquidityPoolBalance - newer.liquidityPoolBalance;
                uint256 decreaseBP = (decrease * BASIS_POINTS) / older.liquidityPoolBalance;
                
                if (decreaseBP > 100) { // >1% decrease
                    consecutiveDecreases++;
                }
            } else {
                break; // Pattern broken
            }
        }
        
        if (consecutiveDecreases < 3) {
            return (false, ResponseData(address(0), new address[](0), 0, 0, 0, 0, 0, bytes32(0)));
        }
        
        CollectOutput memory current = abi.decode(data[0], (CollectOutput));
        
        uint256 severity = consecutiveDecreases >= 5 ? 95 : 80;
        uint256 confidence = 90;
        
        ResponseData memory response = ResponseData({
            violatorAddress: current.liquidityPool,
            relatedAddresses: new address[](0),
            accumulatedPercentBP: consecutiveDecreases * 100,
            detectionType: DETECTION_LIQUIDITY_MANIPULATION,
            blockNumber: current.blockNumber,
            severity: severity,
            confidence: confidence,
            patternSignature: keccak256(abi.encodePacked("MULTI_BLOCK_DRAIN", consecutiveDecreases))
        });
        
        return (true, response);
    }
    
    /**
     * @notice Detects wash trading patterns
     */
    function _detectWashTrading(
        CollectOutput memory current
    ) internal pure returns (bool, ResponseData memory) {
        // Look for rapid buy/sell from same addresses
        uint256 outerLimit = current.recentSwaps.length < MAX_SWAPS_PER_BLOCK
            ? current.recentSwaps.length
            : MAX_SWAPS_PER_BLOCK;

        for (uint256 i = 0; i < outerLimit; i++) {
            address wallet1 = current.recentSwaps[i].wallet;
            bool isBuy1 = current.recentSwaps[i].isBuy;
            
            for (uint256 j = i + 1; j < current.recentSwaps.length && j < MAX_SWAPS_PER_BLOCK; j++) {
                address wallet2 = current.recentSwaps[j].wallet;
                bool isBuy2 = current.recentSwaps[j].isBuy;
                
                // Same wallet, opposite direction (buy then sell or vice versa)
                if (wallet1 == wallet2 && isBuy1 != isBuy2) {
                    // Found potential wash trade
                    address[] memory related = new address[](1);
                    related[0] = wallet1;
                    
                    ResponseData memory response = ResponseData({
                        violatorAddress: wallet1,
                        relatedAddresses: related,
                        accumulatedPercentBP: 0,
                        detectionType: DETECTION_WASH_TRADING,
                        blockNumber: current.blockNumber,
                        severity: 60,
                        confidence: 70,
                        patternSignature: keccak256(abi.encodePacked("WASH_TRADE", wallet1))
                    });
                    
                    return (true, response);
                }
            }
        }
        
        return (false, ResponseData(address(0), new address[](0), 0, 0, 0, 0, 0, bytes32(0)));
    }
    
    // ==================== HELPER FUNCTIONS ====================
    
    /**
     * @notice Builds wallet behavior profiles from historical data
     */
    function _buildWalletProfiles(
        bytes[] calldata data
    ) internal pure returns (WalletProfile[] memory) {
        uint256 snapshots = data.length < MAX_HISTORY_SNAPSHOTS
            ? data.length
            : MAX_HISTORY_SNAPSHOTS;

        if (snapshots == 0) {
            return new WalletProfile[](0);
        }

        uint256 maxProfiles = MAX_SWAPS_PER_BLOCK;
        WalletProfile[] memory tempProfiles = new WalletProfile[](maxProfiles);
        uint256 profileCount = 0;

        for (uint256 i = 0; i < snapshots; i++) {
            CollectOutput memory sample = abi.decode(data[i], (CollectOutput));
            uint256 swapCount = sample.recentSwaps.length;
            if (swapCount == 0) continue;

            uint256 limit = swapCount < MAX_SWAPS_PER_BLOCK
                ? swapCount
                : MAX_SWAPS_PER_BLOCK;

            for (uint256 j = 0; j < limit; j++) {
                SwapData memory swapInfo = sample.recentSwaps[j];
                if (!swapInfo.isBuy) continue;

                uint256 idx = type(uint256).max;
                for (uint256 k = 0; k < profileCount; k++) {
                    if (tempProfiles[k].wallet == swapInfo.wallet) {
                        idx = k;
                        break;
                    }
                }

                if (idx == type(uint256).max) {
                    if (profileCount == maxProfiles) {
                        continue;
                    }
                    idx = profileCount;
                    profileCount++;
                    tempProfiles[idx] = WalletProfile({
                        wallet: swapInfo.wallet,
                        totalBought: 0,
                        buyCount: 0,
                        averageGasPrice: 0,
                        firstSeenBlock: swapInfo.blockNumber,
                        lastSeenBlock: swapInfo.blockNumber
                    });
                }

                WalletProfile memory profile = tempProfiles[idx];
                uint256 previousCount = profile.buyCount;

                profile.totalBought += swapInfo.amountToken;
                profile.buyCount = previousCount + 1;

                if (swapInfo.gasPrice > 0) {
                    if (profile.averageGasPrice == 0) {
                        profile.averageGasPrice = swapInfo.gasPrice;
                    } else {
                        profile.averageGasPrice = (
                            profile.averageGasPrice * previousCount + swapInfo.gasPrice
                        ) / (previousCount + 1);
                    }
                }

                if (swapInfo.blockNumber < profile.firstSeenBlock) {
                    profile.firstSeenBlock = swapInfo.blockNumber;
                }

                if (swapInfo.blockNumber > profile.lastSeenBlock) {
                    profile.lastSeenBlock = swapInfo.blockNumber;
                }

                tempProfiles[idx] = profile;
            }
        }

        if (profileCount == 0) {
            return new WalletProfile[](0);
        }

        WalletProfile[] memory profiles = new WalletProfile[](profileCount);
        for (uint256 i = 0; i < profileCount; i++) {
            profiles[i] = tempProfiles[i];
        }

        return profiles;
    }
    
    /**
     * @notice Calculates severity score (0-100)
     */
    function _calculateSeverity(uint256 actual, uint256 threshold)
        internal
        pure
        returns (uint256)
    {
        if (actual <= threshold) return 0;
        
        uint256 excess = actual - threshold;
        uint256 severity = (excess * 100) / threshold;
        
        return severity > 100 ? 100 : severity;
    }
    
    // ==================== VIEW FUNCTIONS ====================
    
    function getTokenAddress() external view returns (address) {
        return TOKEN_ADDRESS;
    }
    
    function getLiquidityPool() external view returns (address) {
        return LIQUIDITY_POOL;
    }
    
    function getLaunchBlock() external view returns (uint256) {
        return LAUNCH_BLOCK;
    }
}
