// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title FairLaunchResponder
 * @notice Responder contract that executes actions when trap detects violations
 * @dev This is called by Drosera after the trap returns (true, payload)
 * 
 * Separation of Concerns:
 * - Trap = Detection only (pure logic)
 * - Responder = Actions only (state changes, external calls)
 * 
 * This contract receives encoded ResponseData from the trap and executes:
 * - Emergency pause on token/pool
 * - Blacklist violators
 * - Emit alerts
 * - Notify administrators
 */
contract FairLaunchResponder {
    
    // ==================== STRUCTS ====================
    
    /**
     * @notice Response data decoded from trap payload
     * @dev Must match the ResponseData struct in FairLaunchGuardianTrap
     */
    struct ResponseData {
        address violatorAddress;
        uint256 accumulatedPercentBP;
        uint8 detectionType;
        uint256 blockNumber;
        uint256 severity;
    }
    
    // ==================== EVENTS ====================
    
    /**
     * @notice Emitted when a violation is detected and handled
     */
    event LaunchGuardianIncident(
        address indexed violator,
        uint8 indexed detectionType,
        uint256 severity,
        uint256 blockNumber,
        uint256 accumulatedPercentBP,
        uint256 timestamp
    );
    
    /**
     * @notice Emitted when emergency pause is triggered
     */
    event EmergencyPauseTriggered(
        address indexed target,
        uint256 blockNumber,
        uint256 timestamp
    );
    
    /**
     * @notice Emitted when an address is blacklisted
     */
    event AddressBlacklisted(
        address indexed violator,
        uint8 reason,
        uint256 timestamp
    );
    
    /**
     * @notice Emitted when responder is called
     */
    event ResponderCalled(
        uint256 timestamp,
        bytes payload
    );
    
    // ==================== STATE ====================
    
    address public owner;
    address public droseraAddress;
    
    // Protected contracts that this responder can control
    address public guardedToken;
    address public guardedPool;
    
    // Blacklist storage
    mapping(address => bool) public blacklisted;
    mapping(address => uint256) public blacklistTimestamp;
    
    // Pause state
    bool public isPaused;
    uint256 public pauseTimestamp;
    
    // Response history (for tracking and analytics)
    uint256 public totalIncidents;
    mapping(uint256 => ResponseData) public incidentHistory;
    
    // ==================== MODIFIERS ====================
    
    modifier onlyDrosera() {
        require(msg.sender == droseraAddress, "Only Drosera can call");
        _;
    }
    
    modifier onlyOwner() {
        require(msg.sender == owner, "Only owner can call");
        _;
    }
    
    // ==================== CONSTRUCTOR ====================
    
    constructor(
        address _droseraAddress,
        address _guardedToken,
        address _guardedPool
    ) {
        owner = msg.sender;
        droseraAddress = _droseraAddress;
        guardedToken = _guardedToken;
        guardedPool = _guardedPool;
    }
    
    // ==================== MAIN RESPONDER FUNCTION ====================
    
    /**
     * @notice Main handler function called by Drosera
     * @dev Function signature MUST match drosera.toml response_function
     *      Format: "handle(bytes)"
     * 
     * @param payload Encoded ResponseData struct from trap
     */
    function handle(bytes calldata payload) external onlyDrosera {
        emit ResponderCalled(block.timestamp, payload);
        
        // Decode the response data from trap
        ResponseData memory response = abi.decode(payload, (ResponseData));
        
        // Store incident in history
        incidentHistory[totalIncidents] = response;
        totalIncidents++;
        
        // Emit incident event
        emit LaunchGuardianIncident(
            response.violatorAddress,
            response.detectionType,
            response.severity,
            response.blockNumber,
            response.accumulatedPercentBP,
            block.timestamp
        );
        
        // Execute actions based on severity
        _executeResponse(response);
    }
    
    // ==================== INTERNAL FUNCTIONS ====================
    
    /**
     * @notice Executes appropriate response based on detection type and severity
     * @param response The decoded response data
     */
    function _executeResponse(ResponseData memory response) internal {
        // High severity (>75) = Immediate pause + blacklist
        if (response.severity > 75) {
            _emergencyPause();
            _blacklistAddress(response.violatorAddress, response.detectionType);
        }
        // Medium severity (50-75) = Blacklist only
        else if (response.severity > 50) {
            _blacklistAddress(response.violatorAddress, response.detectionType);
        }
        // Low severity (<50) = Log only (already emitted event)
        
        // Type-specific actions
        if (response.detectionType == 4) { // LIQUIDITY_MANIPULATION
            // Could trigger additional pool-specific protections
            _handleLiquidityManipulation(response);
        }
    }
    
    /**
     * @notice Triggers emergency pause on protected contracts
     */
    function _emergencyPause() internal {
        if (!isPaused) {
            isPaused = true;
            pauseTimestamp = block.timestamp;
            
            emit EmergencyPauseTriggered(guardedToken, block.number, block.timestamp);
            
            // In production, this would call pause() on actual contracts:
            // IGuardedToken(guardedToken).pause();
            // IGuardedPool(guardedPool).pause();
        }
    }
    
    /**
     * @notice Blacklists an address
     * @param violator Address to blacklist
     * @param reason Detection type code
     */
    function _blacklistAddress(address violator, uint8 reason) internal {
        if (!blacklisted[violator]) {
            blacklisted[violator] = true;
            blacklistTimestamp[violator] = block.timestamp;
            
            emit AddressBlacklisted(violator, reason, block.timestamp);
            
            // In production, this would call blacklist() on actual contracts:
            // IGuardedToken(guardedToken).blacklist(violator);
        }
    }
    
    /**
     * @notice Handles liquidity manipulation specifically
     * @param response The response data
     */
    function _handleLiquidityManipulation(ResponseData memory response) internal {
        // Could implement pool-specific emergency measures
        // For example: freeze pool, disable swaps, alert liquidity providers
        
        // This is a placeholder for production implementation
        // IGuardedPool(guardedPool).emergencyFreeze();
    }
    
    // ==================== ADMIN FUNCTIONS ====================
    
    /**
     * @notice Manually unpause if it was a false positive
     */
    function unpause() external onlyOwner {
        isPaused = false;
        pauseTimestamp = 0;
    }
    
    /**
     * @notice Remove address from blacklist
     * @param account Address to unblacklist
     */
    function removeFromBlacklist(address account) external onlyOwner {
        blacklisted[account] = false;
        blacklistTimestamp[account] = 0;
    }
    
    /**
     * @notice Update Drosera address (in case of migration)
     * @param newDroseraAddress New Drosera contract address
     */
    function updateDroseraAddress(address newDroseraAddress) external onlyOwner {
        require(newDroseraAddress != address(0), "Invalid address");
        droseraAddress = newDroseraAddress;
    }
    
    /**
     * @notice Update protected contracts
     * @param newToken New token address to guard
     * @param newPool New pool address to guard
     */
    function updateProtectedContracts(address newToken, address newPool) external onlyOwner {
        guardedToken = newToken;
        guardedPool = newPool;
    }
    
    /**
     * @notice Transfer ownership
     * @param newOwner New owner address
     */
    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "Invalid address");
        owner = newOwner;
    }
    
    // ==================== VIEW FUNCTIONS ====================
    
    /**
     * @notice Check if an address is blacklisted
     */
    function isBlacklisted(address account) external view returns (bool) {
        return blacklisted[account];
    }
    
    /**
     * @notice Get incident details by index
     */
    function getIncident(uint256 index) external view returns (ResponseData memory) {
        require(index < totalIncidents, "Index out of bounds");
        return incidentHistory[index];
    }
    
    /**
     * @notice Get current pause status
     */
    function getPauseStatus() external view returns (bool paused, uint256 timestamp) {
        return (isPaused, pauseTimestamp);
    }
}
