// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title AddressValidator
 * @notice Library for validating and checking addresses
 */
library AddressValidator {
    /**
     * @notice Check if address is a contract
     * @param account Address to check
     * @return True if address is a contract
     */
    function isContract(address account) internal view returns (bool) {
        uint256 size;
        assembly {
            size := extcodesize(account)
        }
        return size > 0;
    }
    
    /**
     * @notice Check if address is likely a bot (contract wallet)
     * @param account Address to check
     * @return True if likely a bot
     */
    function isLikelyBot(address account) internal view returns (bool) {
        // Check if it's a contract
        if (isContract(account)) {
            return true;
        }
        
        // Additional heuristics can be added here
        // For example: checking if address follows known bot patterns
        
        return false;
    }
    
    /**
     * @notice Calculate account "age" in blocks
     * @param account Address to check
     * @param currentBlock Current block number
     * @return Age in blocks (0 if very new)
     */
    function getAccountAge(address account, uint256 currentBlock) internal view returns (uint256) {
        // Note: This is a simplified version
        // In production, you'd need to track first transaction block
        // or use an oracle/indexer
        
        // For now, return 0 if contract (new), otherwise assume old
        if (isContract(account)) {
            return 0;
        }
        
        return currentBlock; // Placeholder
    }
    
    /**
     * @notice Validate address is not zero and not a known system address
     * @param account Address to validate
     * @return True if valid
     */
    function isValidBuyer(address account) internal pure returns (bool) {
        // Check not zero address
        if (account == address(0)) return false;
        
        // Check not burn address
        if (account == address(0xdead) || account == address(0x000000000000000000000000000000000000dEaD)) {
            return false;
        }
        
        return true;
    }
}