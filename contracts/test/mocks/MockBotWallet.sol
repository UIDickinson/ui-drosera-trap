// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title MockBotWallet
 * @notice Simulates bot behavior for testing
 */
contract MockBotWallet {
    address public owner;
    address public dex;
    
    event BuyExecuted(uint256 amount, uint256 gasPrice);
    
    constructor(address _dex) {
        owner = msg.sender;
        dex = _dex;
    }
    
    /**
     * @notice Execute a buy with custom gas price
     */
    function executeBuy(uint256 gasPrice) external payable {
        require(msg.sender == owner, "Only owner");
        
        // Call swap with custom gas
        (bool success, ) = dex.call{value: msg.value, gas: gasleft()}(
            abi.encodeWithSignature("swap()")
        );
        
        require(success, "Swap failed");
        emit BuyExecuted(msg.value, gasPrice);
    }
    
    /**
     * @notice Execute multiple rapid buys
     */
    function executeRapidBuys(uint256 count, uint256 amountEach) external payable {
        require(msg.sender == owner, "Only owner");
        require(msg.value >= amountEach * count, "Insufficient ETH");
        
        for (uint256 i = 0; i < count; i++) {
            (bool success, ) = dex.call{value: amountEach}(
                abi.encodeWithSignature("swap()")
            );
            require(success, "Swap failed");
        }
    }
    
    /**
     * @notice Withdraw tokens
     */
    function withdrawTokens(address token, uint256 amount) external {
        require(msg.sender == owner, "Only owner");
        (bool success, ) = token.call(
            abi.encodeWithSignature("transfer(address,uint256)", owner, amount)
        );
        require(success, "Transfer failed");
    }
    
    /**
     * @notice Withdraw ETH
     */
    function withdrawETH() external {
        require(msg.sender == owner, "Only owner");
        payable(owner).transfer(address(this).balance);
    }
    
    receive() external payable {}
}