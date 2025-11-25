// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title DemoToken
 * @notice ERC20 token that integrates with FairLaunchGuardianTrap
 * @dev This token checks the trap before allowing transfers
 */
contract DemoToken {
    
    string public name;
    string public symbol;
    uint8 public constant decimals = 18;
    uint256 public totalSupply;
    
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;
    
    address public fairLaunchTrap;
    address public liquidityPool;
    bool public launchProtectionEnabled;
    
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
    event TrapIntegrated(address indexed trap);
    event LaunchProtectionToggled(bool enabled);
    
    constructor(
        string memory _name,
        string memory _symbol,
        uint256 _totalSupply
    ) {
        name = _name;
        symbol = _symbol;
        totalSupply = _totalSupply;
        balanceOf[msg.sender] = _totalSupply;
        launchProtectionEnabled = false;
        
        emit Transfer(address(0), msg.sender, _totalSupply);
    }
    
    /**
     * @notice Integrate with Fair Launch Guardian Trap
     * @param _trap Address of the trap contract
     * @param _pool Address of the liquidity pool to protect
     */
    function integrateTrap(address _trap, address _pool) external {
        require(fairLaunchTrap == address(0), "Trap already integrated");
        require(_trap != address(0), "Invalid trap address");
        
        fairLaunchTrap = _trap;
        liquidityPool = _pool;
        launchProtectionEnabled = true;
        
        emit TrapIntegrated(_trap);
        emit LaunchProtectionToggled(true);
    }
    
    /**
     * @notice Enable/disable launch protection
     */
    function setLaunchProtection(bool _enabled) external {
        launchProtectionEnabled = _enabled;
        emit LaunchProtectionToggled(_enabled);
    }
    
    /**
     * @notice Standard ERC20 transfer with trap integration
     */
    function transfer(address to, uint256 amount) external returns (bool) {
        return _transfer(msg.sender, to, amount);
    }
    
    /**
     * @notice Standard ERC20 transferFrom with trap integration
     */
    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        require(allowance[from][msg.sender] >= amount, "Insufficient allowance");
        allowance[from][msg.sender] -= amount;
        return _transfer(from, to, amount);
    }
    
    /**
     * @notice Internal transfer with trap checks
     */
    function _transfer(address from, address to, uint256 amount) internal returns (bool) {
        require(balanceOf[from] >= amount, "Insufficient balance");
        
        // If launch protection is enabled and this is a buy from pool
        if (launchProtectionEnabled && from == liquidityPool && fairLaunchTrap != address(0)) {
            // Check if buyer is blacklisted
            (bool success, bytes memory data) = fairLaunchTrap.staticcall(
                abi.encodeWithSignature("isBlacklisted(address)", to)
            );
            
            if (success && data.length >= 32) {
                bool isBlacklisted = abi.decode(data, (bool));
                require(!isBlacklisted, "Address is blacklisted by Fair Launch Guardian");
            }
            
            // Check if trading is paused
            (success, data) = fairLaunchTrap.staticcall(
                abi.encodeWithSignature("isPaused()")
            );
            
            if (success && data.length >= 32) {
                bool isPaused = abi.decode(data, (bool));
                require(!isPaused, "Trading paused by Fair Launch Guardian");
            }
            
            // Record the swap in the trap
            (success, ) = fairLaunchTrap.call(
                abi.encodeWithSignature("recordSwap(address,uint256,uint256)", to, amount, tx.gasprice)
            );
            // Continue even if recording fails (trap might be inactive)
        }
        
        // Execute transfer
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        
        emit Transfer(from, to, amount);
        return true;
    }
    
    /**
     * @notice Standard ERC20 approve
     */
    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }
    
    /**
     * @notice Mint new tokens (for testing)
     */
    function mint(address to, uint256 amount) external {
        totalSupply += amount;
        balanceOf[to] += amount;
        emit Transfer(address(0), to, amount);
    }
}