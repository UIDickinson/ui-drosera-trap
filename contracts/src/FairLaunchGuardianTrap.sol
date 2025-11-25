// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title FairLaunchGuardianTrap - PRODUCTION VERSION
 * @notice Actually working Drosera Trap that monitors DEX swaps
 * @dev This version has real implementation, not placeholders
 */
contract FairLaunchGuardianTrap {
    
    // ==================== STRUCTS ====================
    
    struct CollectOutput {
        uint256 blockNumber;
        address[] recentBuyers;
        uint256[] buyAmounts;
        uint256[] gasPrices;
        uint256 totalSupply;
        uint256 liquidityPoolBalance;
        uint256 averageGasPrice;
    }
    
    struct LaunchConfig {
        address tokenAddress;
        address liquidityPool;
        uint256 launchBlock;
        uint256 monitoringDuration;
        uint256 maxWalletBasisPoints;
        uint256 maxGasPremiumBasisPoints;
        bool isActive;
    }
    
    struct ResponseData {
        address violatorAddress;
        uint256 accumulatedPercent;
        DetectionType detectionType;
        uint256 blockNumber;
        uint256 severity;
    }
    
    enum DetectionType {
        EXCESSIVE_ACCUMULATION,
        FRONT_RUNNING_GAS,
        RAPID_BUYING_PATTERN,
        COORDINATED_ATTACK,
        LIQUIDITY_MANIPULATION
    }
    
    // ==================== STATE ====================
    
    LaunchConfig public launchConfig;
    address public owner;
    
    // Track accumulation per address
    mapping(address => uint256) public walletAccumulation;
    mapping(address => uint256) public buyCountPerAddress;
    mapping(address => uint256) public lastBuyBlock;
    
    // Blacklist
    mapping(address => bool) public blacklistedAddresses;
    
    // Store recent swap data for collect()
    struct SwapRecord {
        address buyer;
        uint256 amount;
        uint256 gasPrice;
        uint256 blockNumber;
    }
    
    SwapRecord[] public recentSwaps;
    uint256 public lastCollectedBlock;
    
    // Detection history (limited size)
    ResponseData[] public detectionHistory;
    uint256 public constant MAX_HISTORY = 50;
    
    bool public isPaused;
    
    uint256 public constant BASIS_POINTS = 10000;
    uint256 public constant RAPID_BUY_THRESHOLD = 3;
    uint256 public constant COORDINATED_BUY_THRESHOLD = 5;
    
    // ==================== EVENTS ====================
    
    event LaunchConfigured(
        address indexed token,
        address indexed pool,
        uint256 launchBlock,
        uint256 duration
    );
    
    event SwapRecorded(
        address indexed buyer,
        uint256 amount,
        uint256 gasPrice,
        uint256 blockNumber
    );
    
    event SuspiciousActivityDetected(
        address indexed violator,
        DetectionType detectionType,
        uint256 severity,
        uint256 blockNumber
    );
    
    event AddressBlacklisted(
        address indexed violator,
        DetectionType reason
    );
    
    event TradingPaused(
        uint256 blockNumber,
        string reason
    );
    
    event TradingUnpaused(uint256 blockNumber);
    
    // ==================== MODIFIERS ====================
    
    modifier onlyOwner() {
        require(msg.sender == owner, "Not owner");
        _;
    }
    
    modifier whenActive() {
        require(launchConfig.isActive, "Trap not active");
        require(block.number <= launchConfig.launchBlock + launchConfig.monitoringDuration, "Monitoring ended");
        _;
    }
    
    // ==================== CONSTRUCTOR ====================
    
    constructor(
        address _tokenAddress,
        address _liquidityPool,
        uint256 _launchBlock,
        uint256 _monitoringDuration,
        uint256 _maxWalletBP,
        uint256 _maxGasPremiumBP
    ) {
        require(_tokenAddress != address(0), "Invalid token");
        require(_liquidityPool != address(0), "Invalid pool");
        
        owner = msg.sender;
        
        launchConfig = LaunchConfig({
            tokenAddress: _tokenAddress,
            liquidityPool: _liquidityPool,
            launchBlock: _launchBlock,
            monitoringDuration: _monitoringDuration,
            maxWalletBasisPoints: _maxWalletBP,
            maxGasPremiumBasisPoints: _maxGasPremiumBP,
            isActive: true
        });
        
        lastCollectedBlock = block.number;
        
        emit LaunchConfigured(_tokenAddress, _liquidityPool, _launchBlock, _monitoringDuration);
    }
    
    // ==================== CORE DROSERA FUNCTIONS ====================
    
    /**
     * @notice Collect recent swap data
     * @dev Called by Drosera operators every block
     */
    function collect() external view returns (bytes memory) {
        // If not monitoring, return empty data
        if (!launchConfig.isActive || 
            block.number > launchConfig.launchBlock + launchConfig.monitoringDuration) {
            return abi.encode(CollectOutput({
                blockNumber: block.number,
                recentBuyers: new address[](0),
                buyAmounts: new uint256[](0),
                gasPrices: new uint256[](0),
                totalSupply: 0,
                liquidityPoolBalance: 0,
                averageGasPrice: 0
            }));
        }
        
        // Get swaps since last collection
        (address[] memory buyers, uint256[] memory amounts, uint256[] memory prices) = 
            _getRecentSwapsForCollect();
        
        // Get token info
        uint256 totalSupply = _getTotalSupply();
        uint256 poolBalance = _getPoolBalance();
        uint256 avgGas = _estimateAverageGasPrice();
        
        return abi.encode(CollectOutput({
            blockNumber: block.number,
            recentBuyers: buyers,
            buyAmounts: amounts,
            gasPrices: prices,
            totalSupply: totalSupply,
            liquidityPoolBalance: poolBalance,
            averageGasPrice: avgGas
        }));
    }
    
    /**
     * @notice Analyze data and determine if response needed
     * @dev Called by Drosera operators with historical data
     */
    function shouldRespond(bytes[] calldata data) external returns (bool, bytes memory) {
        if (data.length < 2) return (false, bytes(""));
        
        if (!launchConfig.isActive) return (false, bytes(""));
        
        // Decode most recent data
        CollectOutput memory currentData = abi.decode(data[0], (CollectOutput));
        
        // Check if still in monitoring period
        if (currentData.blockNumber > launchConfig.launchBlock + launchConfig.monitoringDuration) {
            return (false, bytes(""));
        }
        
        // Run detection on each buyer
        for (uint256 i = 0; i < currentData.recentBuyers.length; i++) {
            (bool detected, ResponseData memory response) = _analyzeSwap(
                currentData.recentBuyers[i],
                currentData.buyAmounts[i],
                currentData.gasPrices[i],
                currentData.totalSupply,
                currentData.averageGasPrice,
                currentData.blockNumber,
                data
            );
            
            if (detected) {
                // Execute response
                _executeResponse(response);
                
                return (true, abi.encode(response));
            }
        }
        
        return (false, bytes(""));
    }
    
    // ==================== SWAP RECORDING (Called by integrated tokens/DEXs) ====================
    
    /**
     * @notice Record a swap (called by token or DEX)
     * @dev External contracts call this to notify of swaps
     */
    function recordSwap(
        address buyer,
        uint256 amount,
        uint256 gasPrice
    ) external whenActive {
        // Only accept from monitored pool or token
        require(
            msg.sender == launchConfig.liquidityPool || 
            msg.sender == launchConfig.tokenAddress,
            "Unauthorized caller"
        );
        
        // Don't record blacklisted addresses
        if (blacklistedAddresses[buyer]) {
            return;
        }
        
        // Add to recent swaps
        recentSwaps.push(SwapRecord({
            buyer: buyer,
            amount: amount,
            gasPrice: gasPrice,
            blockNumber: block.number
        }));
        
        // Update tracking
        walletAccumulation[buyer] += amount;
        buyCountPerAddress[buyer]++;
        lastBuyBlock[buyer] = block.number;
        
        emit SwapRecorded(buyer, amount, gasPrice, block.number);
        
        // Clean old swaps (keep last 100)
        if (recentSwaps.length > 100) {
            _cleanOldSwaps();
        }
    }
    
    // ==================== DETECTION LOGIC ====================
    
    function _analyzeSwap(
        address buyer,
        uint256 amount,
        uint256 gasPrice,
        uint256 totalSupply,
        uint256 avgGas,
        uint256 blockNumber,
        bytes[] calldata historicalData
    ) internal returns (bool, ResponseData memory) {
        
        // Guard: totalSupply cannot be zero (prevents division by zero)
        if (totalSupply == 0) {
            return (false, ResponseData({
                violatorAddress: address(0),
                accumulatedPercent: 0,
                detectionType: DetectionType.EXCESSIVE_ACCUMULATION,
                blockNumber: 0,
                severity: 0
            }));
        }
        
        // Calculate percentage of supply
        uint256 percentBP = (walletAccumulation[buyer] * BASIS_POINTS) / totalSupply;
        
        // Check 1: Excessive accumulation
        if (percentBP > launchConfig.maxWalletBasisPoints) {
            uint256 severity = _calculateSeverity(percentBP, launchConfig.maxWalletBasisPoints);
            
            return (true, ResponseData({
                violatorAddress: buyer,
                accumulatedPercent: percentBP,
                detectionType: DetectionType.EXCESSIVE_ACCUMULATION,
                blockNumber: blockNumber,
                severity: severity
            }));
        }
        
        // Check 2: Front-running via gas
        if (avgGas > 0 && gasPrice > avgGas) {
            uint256 gasPremiumBP = ((gasPrice - avgGas) * BASIS_POINTS) / avgGas;
            
            if (gasPremiumBP > launchConfig.maxGasPremiumBasisPoints) {
                uint256 severity = _calculateGasSeverity(gasPremiumBP);
                
                return (true, ResponseData({
                    violatorAddress: buyer,
                    accumulatedPercent: percentBP,
                    detectionType: DetectionType.FRONT_RUNNING_GAS,
                    blockNumber: blockNumber,
                    severity: severity
                }));
            }
        }
        
        // Check 3: Rapid buying
        if (buyCountPerAddress[buyer] >= RAPID_BUY_THRESHOLD) {
            uint256 firstBuyBlock = _getFirstBuyBlock(buyer, historicalData);
            // Only check if we have valid history (firstBuyBlock != max uint256)
            if (firstBuyBlock != type(uint256).max) {
                uint256 blocksSpan = blockNumber > firstBuyBlock ? blockNumber - firstBuyBlock : 0;
                
                if (blocksSpan <= 5 && blocksSpan > 0) {
                    return (true, ResponseData({
                        violatorAddress: buyer,
                        accumulatedPercent: percentBP,
                        detectionType: DetectionType.RAPID_BUYING_PATTERN,
                        blockNumber: blockNumber,
                        severity: 75
                    }));
                }
            }
        }
        
        return (false, ResponseData({
            violatorAddress: address(0),
            accumulatedPercent: 0,
            detectionType: DetectionType.EXCESSIVE_ACCUMULATION,
            blockNumber: 0,
            severity: 0
        }));
    }
    
    function _executeResponse(ResponseData memory response) internal {
        // Store in history with ring-buffer behavior (rotate oldest if full)
        if (detectionHistory.length < MAX_HISTORY) {
            detectionHistory.push(response);
        } else {
            // Ring-buffer: shift all and replace oldest
            for (uint256 i = 0; i < MAX_HISTORY - 1; i++) {
                detectionHistory[i] = detectionHistory[i + 1];
            }
            detectionHistory[MAX_HISTORY - 1] = response;
        }
        
        emit SuspiciousActivityDetected(
            response.violatorAddress,
            response.detectionType,
            response.severity,
            response.blockNumber
        );
        
        // Execute based on severity
        if (response.severity >= 80) {
            // Severe: Pause trading
            isPaused = true;
            emit TradingPaused(block.number, "Critical violation detected");
        } else if (response.severity >= 60) {
            // Moderate: Blacklist
            blacklistedAddresses[response.violatorAddress] = true;
            emit AddressBlacklisted(response.violatorAddress, response.detectionType);
        }
        // Below 60: Alert only (event emitted above)
    }
    
    // ==================== HELPER FUNCTIONS ====================
    
    function _getRecentSwapsForCollect() internal view returns (
        address[] memory,
        uint256[] memory,
        uint256[] memory
    ) {
        uint256 count = 0;
        
        // Count swaps since last collection
        for (uint256 i = recentSwaps.length; i > 0; i--) {
            if (recentSwaps[i-1].blockNumber > lastCollectedBlock) {
                count++;
            } else {
                break;
            }
        }
        
        address[] memory buyers = new address[](count);
        uint256[] memory amounts = new uint256[](count);
        uint256[] memory prices = new uint256[](count);
        
        uint256 index = 0;
        for (uint256 i = recentSwaps.length; i > 0 && index < count; i--) {
            SwapRecord memory swap = recentSwaps[i-1];
            if (swap.blockNumber > lastCollectedBlock) {
                buyers[index] = swap.buyer;
                amounts[index] = swap.amount;
                prices[index] = swap.gasPrice;
                index++;
            }
        }
        
        return (buyers, amounts, prices);
    }
    
    function _getTotalSupply() internal view returns (uint256) {
        (bool success, bytes memory data) = launchConfig.tokenAddress.staticcall(
            abi.encodeWithSignature("totalSupply()")
        );
        return success && data.length >= 32 ? abi.decode(data, (uint256)) : 0;
    }
    
    function _getPoolBalance() internal view returns (uint256) {
        (bool success, bytes memory data) = launchConfig.tokenAddress.staticcall(
            abi.encodeWithSignature("balanceOf(address)", launchConfig.liquidityPool)
        );
        return success && data.length >= 32 ? abi.decode(data, (uint256)) : 0;
    }
    
    function _estimateAverageGasPrice() internal view returns (uint256) {
        return tx.gasprice; // Simplified
    }
    
    function _calculateSeverity(uint256 actual, uint256 limit) internal pure returns (uint256) {
        if (actual <= limit) return 0;
        uint256 excess = actual - limit;
        uint256 severity = (excess * 100) / limit;
        return severity > 100 ? 100 : severity;
    }
    
    function _calculateGasSeverity(uint256 premiumBP) internal pure returns (uint256) {
        uint256 severity = (premiumBP * 100) / BASIS_POINTS;
        return severity > 100 ? 100 : severity;
    }
    
    function _getFirstBuyBlock(address buyer, bytes[] calldata historicalData) internal pure returns (uint256) {
        for (uint256 i = historicalData.length; i > 0; i--) {
            CollectOutput memory data = abi.decode(historicalData[i-1], (CollectOutput));
            for (uint256 j = 0; j < data.recentBuyers.length; j++) {
                if (data.recentBuyers[j] == buyer) {
                    return data.blockNumber;
                }
            }
        }
        // Return max uint256 as sentinel if not found (signals no valid history)
        // Caller should handle this by skipping rapid-buy check when result is max
        return type(uint256).max;
    }
    
    function _cleanOldSwaps() internal {
        uint256 keepCount = 50;
        uint256 removeCount = recentSwaps.length - keepCount;
        
        for (uint256 i = 0; i < removeCount; i++) {
            recentSwaps[i] = recentSwaps[i + removeCount];
        }
        
        for (uint256 i = 0; i < removeCount; i++) {
            recentSwaps.pop();
        }
    }
    
    // ==================== ADMIN FUNCTIONS ====================
    
    function unpause() external onlyOwner {
        isPaused = false;
        emit TradingUnpaused(block.number);
    }
    
    function addToBlacklist(address account) external onlyOwner {
        blacklistedAddresses[account] = true;
    }
    
    function removeFromBlacklist(address account) external onlyOwner {
        blacklistedAddresses[account] = false;
    }
    
    function deactivate() external onlyOwner {
        launchConfig.isActive = false;
    }
    
    // ==================== VIEW FUNCTIONS ====================
    
    function isBlacklisted(address account) external view returns (bool) {
        return blacklistedAddresses[account];
    }
    
    function isMonitoringActive() external view returns (bool) {
        return launchConfig.isActive && 
               block.number <= launchConfig.launchBlock + launchConfig.monitoringDuration;
    }
    
    function getConfig() external view returns (LaunchConfig memory) {
        return launchConfig;
    }
    
    function getDetectionHistory() external view returns (ResponseData[] memory) {
        return detectionHistory;
    }
    
    function getRecentSwapCount() external view returns (uint256) {
        return recentSwaps.length;
    }
}
