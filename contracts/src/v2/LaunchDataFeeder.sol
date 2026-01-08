// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title LaunchDataFeeder
 * @notice OPTIONAL feeder contract for aggregating swap data on-chain
 * @dev ⚠️  NOTE: This is OPTIONAL and NOT RECOMMENDED for most use cases
 * 
 * Recommended Approach: Use EventLog filtering instead (see FairLaunchGuardianTrapEventLog)
 * 
 * Use this feeder ONLY if:
 * - You need custom metrics not available in standard events
 * - You have control over the token/pool contracts
 * - You understand the centralization tradeoffs
 * 
 * This contract can be called by token/pool contracts or off-chain bots
 * to record trading data. The trap reads this aggregated data instead of
 * processing individual swaps.
 * 
 * Architecture:
 * - Pool/Token calls recordSwap() on each transaction
 * - Feeder aggregates data per block
 * - Trap's collect() reads feeder's latest block metrics
 * - No state in trap = deterministic operator consensus
 * 
 * Usage:
 * Option A: Integrate recordSwap() call into token transfer logic
 * Option B: Off-chain bot monitors events and calls recordSwap()
 * Option C: Use EventLog filtering (RECOMMENDED - see review)
 */
contract LaunchDataFeeder {
    
    // ==================== STRUCTS ====================
    
    /**
     * @notice Aggregated metrics for a single block
     */
    struct BlockMetrics {
        uint256 blockNumber;
        uint256 timestamp;
        uint256 totalBuyVolume;
        uint256 totalSellVolume;
        uint256 uniqueBuyers;
        uint256 uniqueSellers;
        uint256 maxSingleBuyBP; // Largest buy as % of supply
        uint256 maxWalletAccumulationBP; // Largest wallet % after this block
        uint256 averageGasPrice;
        uint256 maxGasPrice;
        bool suspiciousActivity; // Flag set by bot/guardian
    }
    
    /**
     * @notice Individual swap record (optional detailed tracking)
     */
    struct SwapRecord {
        uint256 blockNumber;
        uint256 timestamp;
        address wallet;
        bool isBuy;
        uint256 amount;
        uint256 gasPrice;
    }
    
    // ==================== STATE ====================
    
    address public owner;
    address public authorizedRecorder; // Pool or bot allowed to record
    
    // Per-block aggregated metrics
    mapping(uint256 => BlockMetrics) public blockMetrics;
    
    // Latest recorded block (for sequential validation)
    uint256 public latestBlock;
    
    // Optional: Track per-wallet accumulation
    mapping(address => uint256) public walletAccumulation;
    
    // Config
    address public immutable TOKEN_ADDRESS;
    uint256 public immutable TOTAL_SUPPLY;
    
    // ==================== EVENTS ====================
    
    event SwapRecorded(
        uint256 indexed blockNumber,
        address indexed wallet,
        bool isBuy,
        uint256 amount,
        uint256 gasPrice
    );
    
    event BlockMetricsUpdated(
        uint256 indexed blockNumber,
        uint256 totalBuyVolume,
        uint256 maxSingleBuyBP,
        uint256 uniqueBuyers
    );
    
    event SuspiciousActivityFlagged(
        uint256 indexed blockNumber,
        string reason
    );
    
    // ==================== MODIFIERS ====================
    
    modifier onlyAuthorized() {
        require(
            msg.sender == authorizedRecorder || msg.sender == owner,
            "Not authorized"
        );
        _;
    }
    
    modifier onlyOwner() {
        require(msg.sender == owner, "Only owner");
        _;
    }
    
    // ==================== CONSTRUCTOR ====================
    
    constructor(
        address _tokenAddress,
        uint256 _totalSupply,
        address _authorizedRecorder
    ) {
        owner = msg.sender;
        TOKEN_ADDRESS = _tokenAddress;
        TOTAL_SUPPLY = _totalSupply;
        authorizedRecorder = _authorizedRecorder;
    }
    
    // ==================== RECORDING FUNCTIONS ====================
    
    /**
     * @notice Record a swap transaction
     * @dev Called by pool/token contract or authorized bot
     * @param wallet The wallet making the swap
     * @param isBuy True if buying token, false if selling
     * @param amount Amount of tokens involved
     */
    function recordSwap(
        address wallet,
        bool isBuy,
        uint256 amount
    ) external onlyAuthorized {
        _recordSwapInternal(wallet, isBuy, amount);
    }
    
    /**
     * @notice Batch record multiple swaps (gas efficient for bot submissions)
     * @param wallets Array of wallet addresses
     * @param isBuys Array of buy/sell flags
     * @param amounts Array of amounts
     */
    function recordSwapBatch(
        address[] calldata wallets,
        bool[] calldata isBuys,
        uint256[] calldata amounts
    ) external onlyAuthorized {
        require(
            wallets.length == isBuys.length && isBuys.length == amounts.length,
            "Array length mismatch"
        );
        
        for (uint256 i = 0; i < wallets.length; i++) {
            _recordSwapInternal(wallets[i], isBuys[i], amounts[i]);
        }
    }
    
    /**
     * @notice Internal function to record a single swap
     * @dev Used by both recordSwap and recordSwapBatch to avoid code duplication
     */
    function _recordSwapInternal(
        address wallet,
        bool isBuy,
        uint256 amount
    ) internal {
        uint256 currentBlock = block.number;
        
        // Initialize block metrics if first swap in this block
        if (blockMetrics[currentBlock].blockNumber == 0) {
            blockMetrics[currentBlock].blockNumber = currentBlock;
            blockMetrics[currentBlock].timestamp = block.timestamp;
            latestBlock = currentBlock;
        }
        
        BlockMetrics storage metrics = blockMetrics[currentBlock];
        
        // Update volume
        if (isBuy) {
            metrics.totalBuyVolume += amount;
            metrics.uniqueBuyers++; // Simplified - should track unique addresses
        } else {
            metrics.totalSellVolume += amount;
            metrics.uniqueSellers++;
        }
        
        // Update wallet accumulation
        if (isBuy) {
            walletAccumulation[wallet] += amount;
            
            // Calculate as basis points of total supply
            uint256 walletBP = (walletAccumulation[wallet] * 10_000) / TOTAL_SUPPLY;
            
            // Update max if this wallet now has more
            if (walletBP > metrics.maxWalletAccumulationBP) {
                metrics.maxWalletAccumulationBP = walletBP;
            }
        } else {
            if (walletAccumulation[wallet] >= amount) {
                walletAccumulation[wallet] -= amount;
            } else {
                walletAccumulation[wallet] = 0;
            }
        }
        
        // Track single largest buy
        if (isBuy) {
            uint256 buyBP = (amount * 10_000) / TOTAL_SUPPLY;
            if (buyBP > metrics.maxSingleBuyBP) {
                metrics.maxSingleBuyBP = buyBP;
            }
        }
        
        // Update gas price tracking
        uint256 gasPrice = tx.gasprice;
        if (gasPrice > metrics.maxGasPrice) {
            metrics.maxGasPrice = gasPrice;
        }
        
        // Update average gas (simplified - should use proper averaging)
        if (metrics.averageGasPrice == 0) {
            metrics.averageGasPrice = gasPrice;
        } else {
            metrics.averageGasPrice = (metrics.averageGasPrice + gasPrice) / 2;
        }
        
        emit SwapRecorded(currentBlock, wallet, isBuy, amount, gasPrice);
    }
    
    /**
     * @notice Flag current block as suspicious (called by monitoring bot)
     * @param reason Human-readable reason for flagging
     */
    function flagSuspiciousActivity(string calldata reason) external onlyAuthorized {
        uint256 currentBlock = block.number;
        
        if (blockMetrics[currentBlock].blockNumber == 0) {
            blockMetrics[currentBlock].blockNumber = currentBlock;
            blockMetrics[currentBlock].timestamp = block.timestamp;
        }
        
        blockMetrics[currentBlock].suspiciousActivity = true;
        
        emit SuspiciousActivityFlagged(currentBlock, reason);
    }
    
    // ==================== VIEW FUNCTIONS ====================
    
    /**
     * @notice Get metrics for a specific block
     * @param blockNumber The block to query
     * @return Block metrics struct
     */
    function getBlockMetrics(uint256 blockNumber)
        external
        view
        returns (BlockMetrics memory)
    {
        return blockMetrics[blockNumber];
    }
    
    /**
     * @notice Get metrics for latest recorded block
     * @return Block metrics struct
     */
    function getLatestMetrics() external view returns (BlockMetrics memory) {
        return blockMetrics[latestBlock];
    }
    
    /**
     * @notice Get metrics for multiple blocks (for trap collect())
     * @param startBlock Starting block number
     * @param count Number of blocks to retrieve
     * @return Array of block metrics
     */
    function getBlockMetricsBatch(uint256 startBlock, uint256 count)
        external
        view
        returns (BlockMetrics[] memory)
    {
        BlockMetrics[] memory results = new BlockMetrics[](count);
        
        for (uint256 i = 0; i < count; i++) {
            results[i] = blockMetrics[startBlock + i];
        }
        
        return results;
    }
    
    /**
     * @notice Get wallet accumulation as basis points
     * @param wallet Address to check
     * @return Wallet holdings as basis points of total supply
     */
    function getWalletAccumulationBP(address wallet)
        external
        view
        returns (uint256)
    {
        if (TOTAL_SUPPLY == 0) return 0;
        return (walletAccumulation[wallet] * 10_000) / TOTAL_SUPPLY;
    }
    
    /**
     * @notice Get current total supply configuration
     */
    function getTotalSupply() external view returns (uint256) {
        return TOTAL_SUPPLY;
    }
    
    // ==================== ADMIN FUNCTIONS ====================
    
    /**
     * @notice Update authorized recorder
     * @param newRecorder New authorized address
     */
    function updateAuthorizedRecorder(address newRecorder) external onlyOwner {
        require(newRecorder != address(0), "Invalid address");
        authorizedRecorder = newRecorder;
    }
    
    /**
     * @notice Transfer ownership
     * @param newOwner New owner address
     */
    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "Invalid address");
        owner = newOwner;
    }
    
    /**
     * @notice Emergency: Reset wallet accumulation (if data corruption)
     * @param wallet Address to reset
     */
    function resetWalletAccumulation(address wallet) external onlyOwner {
        walletAccumulation[wallet] = 0;
    }
}
