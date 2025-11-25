// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IDemoToken {
    function transfer(address to, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
}

/**
 * @title DemoDEX
 * @notice Simple DEX for demonstration that works with trap
 * @dev Simulates Uniswap-style swaps with fixed pricing
 */
contract DemoDEX {
    
    address public token;
    uint256 public constant PRICE = 1e15; // 0.001 ETH per token
    
    event Swap(
        address indexed buyer,
        uint256 ethAmount,
        uint256 tokenAmount,
        uint256 gasPrice,
        uint256 timestamp
    );
    
    event LiquidityAdded(
        address indexed provider,
        uint256 amount
    );
    
    constructor(address _token) {
        require(_token != address(0), "Invalid token address");
        token = _token;
    }
    
    /**
     * @notice Swap ETH for tokens
     * @dev This is what users/bots call to buy tokens
     */
    function swap() external payable returns (uint256) {
        require(msg.value > 0, "Must send ETH");
        
        // Calculate token amount based on fixed price
        uint256 tokenAmount = (msg.value * 1e18) / PRICE;
        
        // Check liquidity
        uint256 reserve = IDemoToken(token).balanceOf(address(this));
        require(reserve >= tokenAmount, "Insufficient liquidity");
        
        // Transfer tokens to buyer
        // This will trigger the trap integration in DemoToken
        require(
            IDemoToken(token).transfer(msg.sender, tokenAmount),
            "Token transfer failed"
        );
        
        emit Swap(
            msg.sender,
            msg.value,
            tokenAmount,
            tx.gasprice,
            block.timestamp
        );
        
        return tokenAmount;
    }
    
    /**
     * @notice Add liquidity to the DEX
     */
    function addLiquidity(uint256 amount) external {
        require(
            IDemoToken(token).transferFrom(msg.sender, address(this), amount),
            "Transfer failed"
        );
        
        emit LiquidityAdded(msg.sender, amount);
    }
    
    /**
     * @notice Get current liquidity reserve
     */
    function getReserve() external view returns (uint256) {
        return IDemoToken(token).balanceOf(address(this));
    }
    
    /**
     * @notice Get current price
     */
    function getPrice() external pure returns (uint256) {
        return PRICE;
    }
    
    /**
     * @notice Calculate output amount for given ETH input
     */
    function calculateOutput(uint256 ethAmount) external pure returns (uint256) {
        return (ethAmount * 1e18) / PRICE;
    }
    
    /**
     * @notice Withdraw ETH (for testing)
     */
    function withdrawETH() external {
        payable(msg.sender).transfer(address(this).balance);
    }
    
    receive() external payable {
        // Allow receiving ETH
    }
}