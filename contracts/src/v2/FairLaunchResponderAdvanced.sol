// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title FairLaunchResponderAdvanced
 * @notice Enhanced responder contract with threat intelligence and coordinated response
 * @dev Handles advanced ResponseData from FairLaunchGuardianTrapAdvanced
 * 
 * Enhancements:
 * - Confidence-based thresholds
 * - Coordinated wallet handling (batch blacklist)
 * - Pattern-based response strategies
 * - Threat intelligence tracking
 * - Rate limiting for false positive mitigation
 */
contract FairLaunchResponderAdvanced {
    
    // ==================== STRUCTS ====================
    
    /**
     * @notice Enhanced response data from advanced trap
     */
    struct ResponseData {
        address violatorAddress;
        address[] relatedAddresses;
        uint256 accumulatedPercentBP;
        uint8 detectionType;
        uint256 blockNumber;
        uint256 severity; // 0-100
        uint256 confidence; // 0-100
        bytes32 patternSignature;
    }
    
    /**
     * @notice Threat intelligence entry
     */
    struct ThreatIntel {
        bytes32 patternSignature;
        uint256 firstSeen;
        uint256 lastSeen;
        uint256 occurrences;
        uint8 detectionType;
        bool resolved;
    }
    
    // ==================== EVENTS ====================
    
    event LaunchGuardianIncident(
        address indexed violator,
        uint8 indexed detectionType,
        uint256 severity,
        uint256 confidence,
        uint256 blockNumber,
        bytes32 patternSignature,
        uint256 timestamp
    );
    
    event CoordinatedAttackDetected(
        address indexed primaryViolator,
        address[] relatedAddresses,
        uint256 severity,
        uint256 timestamp
    );
    
    event EmergencyPauseTriggered(
        address indexed target,
        uint8 reason,
        uint256 blockNumber,
        uint256 timestamp
    );
    
    event AddressBlacklisted(
        address indexed violator,
        uint8 reason,
        uint256 confidence,
        uint256 timestamp
    );
    
    event ThreatIntelUpdated(
        bytes32 indexed patternSignature,
        uint8 detectionType,
        uint256 occurrences
    );
    
    event ResponderCalled(
        uint256 timestamp,
        uint256 severity,
        uint256 confidence,
        bytes payload
    );
    
    // ==================== STATE ====================
    
    address public owner;
    address public droseraAddress;
    
    address public guardedToken;
    address public guardedPool;
    
    // Blacklist with metadata
    mapping(address => bool) public blacklisted;
    mapping(address => uint256) public blacklistTimestamp;
    mapping(address => uint8) public blacklistReason;
    mapping(address => uint256) public blacklistConfidence;
    
    // Pause state
    bool public isPaused;
    uint256 public pauseTimestamp;
    uint8 public pauseReason;
    
    // Response history
    uint256 public totalIncidents;
    mapping(uint256 => ResponseData) public incidentHistory;
    
    // Threat intelligence
    mapping(bytes32 => ThreatIntel) public threatIntelligence;
    bytes32[] public knownPatterns;
    
    // Rate limiting
    uint256 public lastResponseBlock;
    uint256 public minBlocksBetweenResponses = 5; // Cooldown
    
    // Confidence thresholds
    uint256 public minConfidenceForPause = 80; // 80%
    uint256 public minConfidenceForBlacklist = 70; // 70%
    uint256 public minConfidenceForAlert = 50; // 50%
    
    // ==================== MODIFIERS ====================
    
    modifier onlyDrosera() {
        require(msg.sender == droseraAddress, "Only Drosera can call");
        _;
    }
    
    modifier onlyOwner() {
        require(msg.sender == owner, "Only owner can call");
        _;
    }
    
    modifier respectCooldown() {
        require(
            block.number >= lastResponseBlock + minBlocksBetweenResponses,
            "Cooldown period active"
        );
        _;
        lastResponseBlock = block.number;
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
     * @notice Enhanced handler with confidence-based response
     * @param payload Encoded ResponseData from advanced trap
     */
    function handle(bytes calldata payload) external onlyDrosera respectCooldown {
        ResponseData memory response = abi.decode(payload, (ResponseData));
        
        emit ResponderCalled(
            block.timestamp,
            response.severity,
            response.confidence,
            payload
        );
        
        // Store incident
        incidentHistory[totalIncidents] = response;
        totalIncidents++;
        
        // Update threat intelligence
        _updateThreatIntel(response);
        
        // Emit incident event
        emit LaunchGuardianIncident(
            response.violatorAddress,
            response.detectionType,
            response.severity,
            response.confidence,
            response.blockNumber,
            response.patternSignature,
            block.timestamp
        );
        
        // Handle coordinated attacks specially
        if (response.relatedAddresses.length > 0) {
            emit CoordinatedAttackDetected(
                response.violatorAddress,
                response.relatedAddresses,
                response.severity,
                block.timestamp
            );
        }
        
        // Execute confidence-based response
        _executeConfidenceBasedResponse(response);
    }
    
    // ==================== INTERNAL RESPONSE LOGIC ====================
    
    /**
     * @notice Execute response based on confidence and severity
     */
    function _executeConfidenceBasedResponse(ResponseData memory response) internal {
        // Only act if confidence meets minimum thresholds
        if (response.confidence < minConfidenceForAlert) {
            return; // Too low confidence, only log
        }
        
        // High confidence + high severity = immediate pause
        if (
            response.confidence >= minConfidenceForPause &&
            response.severity >= 75
        ) {
            _emergencyPause(response.detectionType);
        }
        
        // Medium-high confidence = blacklist
        if (response.confidence >= minConfidenceForBlacklist) {
            _blacklistAddress(
                response.violatorAddress,
                response.detectionType,
                response.confidence
            );
            
            // Blacklist related addresses in coordinated attacks
            if (response.relatedAddresses.length > 0) {
                _blacklistCoordinatedAddresses(
                    response.relatedAddresses,
                    response.detectionType,
                    response.confidence
                );
            }
        }
        
        // Type-specific responses
        if (response.detectionType == 4) { // LIQUIDITY_MANIPULATION
            _handleLiquidityManipulation(response);
        }
    }
    
    /**
     * @notice Triggers emergency pause
     */
    function _emergencyPause(uint8 reason) internal {
        if (!isPaused) {
            isPaused = true;
            pauseTimestamp = block.timestamp;
            pauseReason = reason;
            
            emit EmergencyPauseTriggered(guardedToken, reason, block.number, block.timestamp);
            
            // In production: call actual pause functions
            // IGuardedToken(guardedToken).pause();
            // IGuardedPool(guardedPool).pause();
        }
    }
    
    /**
     * @notice Blacklist single address with metadata
     */
    function _blacklistAddress(address violator, uint8 reason, uint256 confidence) internal {
        if (!blacklisted[violator]) {
            blacklisted[violator] = true;
            blacklistTimestamp[violator] = block.timestamp;
            blacklistReason[violator] = reason;
            blacklistConfidence[violator] = confidence;
            
            emit AddressBlacklisted(violator, reason, confidence, block.timestamp);
            
            // In production: call actual blacklist function
            // IGuardedToken(guardedToken).blacklist(violator);
        }
    }
    
    /**
     * @notice Batch blacklist coordinated addresses
     */
    function _blacklistCoordinatedAddresses(
        address[] memory addresses,
        uint8 reason,
        uint256 confidence
    ) internal {
        for (uint256 i = 0; i < addresses.length && i < 50; i++) {
            _blacklistAddress(addresses[i], reason, confidence);
        }
    }
    
    /**
     * @notice Handle liquidity manipulation specifically
     */
    function _handleLiquidityManipulation(ResponseData memory response) internal {
        // Could implement pool-specific measures
        // For high-severity liquidity drains, might want to freeze pool
        
        if (response.severity >= 90) {
            // Critical liquidity drain - consider additional measures
            // IGuardedPool(guardedPool).emergencyFreeze();
        }
    }
    
    /**
     * @notice Update threat intelligence database
     */
    function _updateThreatIntel(ResponseData memory response) internal {
        bytes32 sig = response.patternSignature;
        
        if (threatIntelligence[sig].firstSeen == 0) {
            // New pattern
            threatIntelligence[sig] = ThreatIntel({
                patternSignature: sig,
                firstSeen: block.timestamp,
                lastSeen: block.timestamp,
                occurrences: 1,
                detectionType: response.detectionType,
                resolved: false
            });
            knownPatterns.push(sig);
        } else {
            // Existing pattern
            threatIntelligence[sig].lastSeen = block.timestamp;
            threatIntelligence[sig].occurrences++;
        }
        
        emit ThreatIntelUpdated(
            sig,
            response.detectionType,
            threatIntelligence[sig].occurrences
        );
    }
    
    // ==================== ADMIN FUNCTIONS ====================
    
    /**
     * @notice Update confidence thresholds
     */
    function setConfidenceThresholds(
        uint256 _pauseThreshold,
        uint256 _blacklistThreshold,
        uint256 _alertThreshold
    ) external onlyOwner {
        require(_pauseThreshold <= 100 && _blacklistThreshold <= 100 && _alertThreshold <= 100, "Invalid threshold");
        require(_pauseThreshold >= _blacklistThreshold && _blacklistThreshold >= _alertThreshold, "Invalid ordering");
        
        minConfidenceForPause = _pauseThreshold;
        minConfidenceForBlacklist = _blacklistThreshold;
        minConfidenceForAlert = _alertThreshold;
    }
    
    /**
     * @notice Update cooldown period
     */
    function setMinBlocksBetweenResponses(uint256 _blocks) external onlyOwner {
        minBlocksBetweenResponses = _blocks;
    }
    
    /**
     * @notice Manually unpause
     */
    function unpause() external onlyOwner {
        isPaused = false;
        pauseTimestamp = 0;
        pauseReason = 0;
    }
    
    /**
     * @notice Remove from blacklist
     */
    function removeFromBlacklist(address account) external onlyOwner {
        blacklisted[account] = false;
        blacklistTimestamp[account] = 0;
        blacklistReason[account] = 0;
        blacklistConfidence[account] = 0;
    }
    
    /**
     * @notice Mark threat pattern as resolved
     */
    function resolveThreatPattern(bytes32 patternSignature) external onlyOwner {
        require(threatIntelligence[patternSignature].firstSeen > 0, "Pattern not found");
        threatIntelligence[patternSignature].resolved = true;
    }
    
    /**
     * @notice Update Drosera address
     */
    function updateDroseraAddress(address newDroseraAddress) external onlyOwner {
        require(newDroseraAddress != address(0), "Invalid address");
        droseraAddress = newDroseraAddress;
    }
    
    /**
     * @notice Update protected contracts
     */
    function updateProtectedContracts(address newToken, address newPool) external onlyOwner {
        guardedToken = newToken;
        guardedPool = newPool;
    }
    
    /**
     * @notice Transfer ownership
     */
    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "Invalid address");
        owner = newOwner;
    }
    
    // ==================== VIEW FUNCTIONS ====================
    
    function isBlacklisted(address account) external view returns (bool) {
        return blacklisted[account];
    }
    
    function getBlacklistInfo(address account)
        external
        view
        returns (bool blacklistedStatus, uint256 timestamp, uint8 reason, uint256 confidence)
    {
        return (
            blacklisted[account],
            blacklistTimestamp[account],
            blacklistReason[account],
            blacklistConfidence[account]
        );
    }
    
    function getIncident(uint256 index) external view returns (ResponseData memory) {
        require(index < totalIncidents, "Index out of bounds");
        return incidentHistory[index];
    }
    
    function getThreatIntel(bytes32 patternSignature)
        external
        view
        returns (ThreatIntel memory)
    {
        return threatIntelligence[patternSignature];
    }
    
    function getKnownPatternsCount() external view returns (uint256) {
        return knownPatterns.length;
    }
    
    function getPauseStatus()
        external
        view
        returns (bool paused, uint256 timestamp, uint8 reason)
    {
        return (isPaused, pauseTimestamp, pauseReason);
    }
    
    function getConfidenceThresholds()
        external
        view
        returns (uint256 pause, uint256 blacklist, uint256 alert)
    {
        return (minConfidenceForPause, minConfidenceForBlacklist, minConfidenceForAlert);
    }
}
