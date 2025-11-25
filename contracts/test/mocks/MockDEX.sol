// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./MockToken.sol";

/**
 * @title MockDEX
 * @notice Simple DEX simulator for testing
 */
contract MockDEX {
    address public token;
    uint256 public constant PRICE = 1e15; // 0.001 ETH per token
    
    event Swap(
        address indexed buyer,
        uint256 ethAmount,
        uint256 tokenAmount,
        uint256 gasPrice
    );
    
    constructor(address _token) {
        token = _token;
    }
    
    /**
     * @notice Swap ETH for tokens
     */
    function swap() external payable {
        require(msg.value > 0, "Send ETH to swap");
        
        // Calculate token amount based on fixed price
        uint256 tokenAmount = (msg.value * 1e18) / PRICE;
        
        // Transfer tokens to buyer
        require(
            MockToken(token).balanceOf(address(this)) >= tokenAmount,
            "Insufficient liquidity"
        );
        
        bool success = MockToken(token).transfer(msg.sender, tokenAmount);
        require(success, "Transfer failed");
        
        emit Swap(msg.sender, msg.value, tokenAmount, tx.gasprice);
    }
    
    /**
     * @notice Get token reserve in pool
     */
    function getReserve() external view returns (uint256) {
        return MockToken(token).balanceOf(address(this));
    }
    
    /**
     * @notice Add liquidity (for testing)
     */
    function addLiquidity(uint256 amount) external {
        bool success = MockToken(token).transferFrom(msg.sender, address(this), amount);
        require(success, "TransferFrom failed");
    }
    
    /**
     * @notice Get current price
     */
    function getPrice() external pure returns (uint256) {
        return PRICE;
    }
}