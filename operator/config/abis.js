/**
 * Contract ABIs for Fair Launch Guardian
 * All ABIs needed for interacting with contracts
 */

// Fair Launch Guardian Trap ABI
const trapAbi = [
  // View functions
  'function collect() external view returns (bytes memory)',
  'function getConfig() external view returns (tuple(address tokenAddress, address liquidityPool, uint256 launchBlock, uint256 monitoringDuration, uint256 maxWalletBasisPoints, uint256 maxGasPremiumBasisPoints, bool isActive))',
  'function isMonitoringActive() external view returns (bool)',
  'function walletAccumulation(address) external view returns (uint256)',
  'function buyCountPerAddress(address) external view returns (uint256)',
  
  // State-changing functions
  'function shouldRespond(bytes[] calldata data) external returns (bool, bytes memory)',
  'function deactivate() external',
  
  // Events
  'event SuspiciousActivityDetected(bytes32 indexed launchId, address indexed suspiciousAddress, uint8 detectionType, uint256 amount, uint256 blockNumber)',
  'event AddressBlacklisted(bytes32 indexed launchId, address indexed blacklistedAddress, uint8 reason)',
  'event TradingPaused(bytes32 indexed launchId, uint256 blockNumber, string reason)',
  'event ResponseExecuted(bytes32 indexed launchId, uint8 action, address targetAddress)'
];

// ERC20 Token ABI (standard functions)
const tokenAbi = [
  'function name() external view returns (string)',
  'function symbol() external view returns (string)',
  'function decimals() external view returns (uint8)',
  'function totalSupply() external view returns (uint256)',
  'function balanceOf(address account) external view returns (uint256)',
  'function transfer(address to, uint256 amount) external returns (bool)',
  'function allowance(address owner, address spender) external view returns (uint256)',
  'function approve(address spender, uint256 amount) external returns (bool)',
  'function transferFrom(address from, address to, uint256 amount) external returns (bool)',
  
  'event Transfer(address indexed from, address indexed to, uint256 value)',
  'event Approval(address indexed owner, address indexed spender, uint256 value)'
];

// Mock DEX ABI (for testing)
const dexAbi = [
  'function swap() external payable',
  'function getReserve() external view returns (uint256)',
  'function getPrice() external pure returns (uint256)',
  'function addLiquidity(uint256 amount) external',
  
  'event Swap(address indexed buyer, uint256 ethAmount, uint256 tokenAmount, uint256 gasPrice)'
];

// Uniswap V2 Pair ABI (for production DEX monitoring)
const uniswapV2PairAbi = [
  'function token0() external view returns (address)',
  'function token1() external view returns (address)',
  'function getReserves() external view returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast)',
  'function price0CumulativeLast() external view returns (uint256)',
  'function price1CumulativeLast() external view returns (uint256)',
  'function kLast() external view returns (uint256)',
  'function totalSupply() external view returns (uint256)',
  
  'event Mint(address indexed sender, uint amount0, uint amount1)',
  'event Burn(address indexed sender, uint amount0, uint amount1, address indexed to)',
  'event Swap(address indexed sender, uint amount0In, uint amount1In, uint amount0Out, uint amount1Out, address indexed to)',
  'event Sync(uint112 reserve0, uint112 reserve1)'
];

// Uniswap V2 Router ABI (for swap monitoring)
const uniswapV2RouterAbi = [
  'function factory() external pure returns (address)',
  'function WETH() external pure returns (address)',
  'function swapExactETHForTokens(uint amountOutMin, address[] calldata path, address to, uint deadline) external payable returns (uint[] memory amounts)',
  'function swapExactTokensForETH(uint amountIn, uint amountOutMin, address[] calldata path, address to, uint deadline) external returns (uint[] memory amounts)'
];

// Drosera Callback ABI (if using callback contract)
const droseraCallbackAbi = [
  'function onTrapResponse(address trapAddress, bytes calldata responseData) external',
  'function supportsCallback() external pure returns (bool)',
  
  'event TrapResponseReceived(address indexed trapAddress, bytes responseData, uint256 timestamp)'
];

module.exports = {
  trapAbi,
  tokenAbi,
  dexAbi,
  uniswapV2PairAbi,
  uniswapV2RouterAbi,
  droseraCallbackAbi
};