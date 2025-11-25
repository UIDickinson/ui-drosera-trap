/**
 * Network configurations for different blockchains
 * Includes RPC URLs, chain IDs, block explorers, etc.
 */

const networks = {
  // ==================== ETHEREUM ====================
  
  mainnet: {
    name: 'Ethereum Mainnet',
    chainId: 1,
    rpcUrl: process.env.MAINNET_RPC || 'https://eth-mainnet.g.alchemy.com/v2/YOUR_KEY',
    blockTime: 12, // seconds
    gasLimit: 500000,
    explorer: 'https://etherscan.io',
    currency: {
      name: 'Ether',
      symbol: 'ETH',
      decimals: 18
    },
    faucet: null // No faucet for mainnet
  },
  
  sepolia: {
    name: 'Ethereum Sepolia',
    chainId: 11155111,
    rpcUrl: process.env.SEPOLIA_RPC || 'https://ethereum-sepolia.publicnode.com',
    blockTime: 12,
    gasLimit: 500000,
    explorer: 'https://sepolia.etherscan.io',
    currency: {
      name: 'Sepolia Ether',
      symbol: 'ETH',
      decimals: 18
    },
    faucet: 'https://sepoliafaucet.com/'
  },
  
  hoodi: {
    name: 'Ethereum Hoodi',
    chainId: 17000,
    rpcUrl: process.env.HOODI_RPC || 'https://0xrpc.io/hoodi',
    blockTime: 12,
    gasLimit: 500000,
    explorer: 'https://hoodi.etherscan.io',
    currency: {
      name: 'Hoodi Ether',
      symbol: 'ETH',
      decimals: 18
    },
    faucet: 'https://0xrpc.io/hoodi'
  },
  
  // ==================== BASE (L2) ====================
  
  base: {
    name: 'Base',
    chainId: 8453,
    rpcUrl: process.env.BASE_RPC || 'https://mainnet.base.org',
    blockTime: 2,
    gasLimit: 300000,
    explorer: 'https://basescan.org',
    currency: {
      name: 'Ether',
      symbol: 'ETH',
      decimals: 18
    },
    faucet: null
  },
  
  baseSepolia: {
    name: 'Base Sepolia',
    chainId: 84532,
    rpcUrl: process.env.BASE_SEPOLIA_RPC || 'https://sepolia.base.org',
    blockTime: 2,
    gasLimit: 300000,
    explorer: 'https://sepolia.basescan.org',
    currency: {
      name: 'Sepolia Ether',
      symbol: 'ETH',
      decimals: 18
    },
    faucet: 'https://www.coinbase.com/faucets/base-ethereum-goerli-faucet'
  },
  
  // ==================== ARBITRUM ====================
  
  arbitrum: {
    name: 'Arbitrum One',
    chainId: 42161,
    rpcUrl: process.env.ARBITRUM_RPC || 'https://arb1.arbitrum.io/rpc',
    blockTime: 0.25,
    gasLimit: 300000,
    explorer: 'https://arbiscan.io',
    currency: {
      name: 'Ether',
      symbol: 'ETH',
      decimals: 18
    },
    faucet: null
  },
  
  arbitrumSepolia: {
    name: 'Arbitrum Sepolia',
    chainId: 421614,
    rpcUrl: process.env.ARBITRUM_SEPOLIA_RPC || 'https://sepolia-rollup.arbitrum.io/rpc',
    blockTime: 0.25,
    gasLimit: 300000,
    explorer: 'https://sepolia.arbiscan.io',
    currency: {
      name: 'Sepolia Ether',
      symbol: 'ETH',
      decimals: 18
    },
    faucet: 'https://faucet.quicknode.com/arbitrum/sepolia'
  },
  
  // ==================== POLYGON ====================
  
  polygon: {
    name: 'Polygon PoS',
    chainId: 137,
    rpcUrl: process.env.POLYGON_RPC || 'https://polygon-rpc.com',
    blockTime: 2,
    gasLimit: 300000,
    explorer: 'https://polygonscan.com',
    currency: {
      name: 'MATIC',
      symbol: 'MATIC',
      decimals: 18
    },
    faucet: null
  },
  
  polygonMumbai: {
    name: 'Polygon Mumbai',
    chainId: 80001,
    rpcUrl: process.env.POLYGON_MUMBAI_RPC || 'https://rpc-mumbai.maticvigil.com',
    blockTime: 2,
    gasLimit: 300000,
    explorer: 'https://mumbai.polygonscan.com',
    currency: {
      name: 'MATIC',
      symbol: 'MATIC',
      decimals: 18
    },
    faucet: 'https://faucet.polygon.technology/'
  },
  
  // ==================== BSC ====================
  
  bsc: {
    name: 'BNB Smart Chain',
    chainId: 56,
    rpcUrl: process.env.BSC_RPC || 'https://bsc-dataseed1.binance.org',
    blockTime: 3,
    gasLimit: 300000,
    explorer: 'https://bscscan.com',
    currency: {
      name: 'BNB',
      symbol: 'BNB',
      decimals: 18
    },
    faucet: null
  },
  
  bscTestnet: {
    name: 'BNB Smart Chain Testnet',
    chainId: 97,
    rpcUrl: process.env.BSC_TESTNET_RPC || 'https://data-seed-prebsc-1-s1.binance.org:8545',
    blockTime: 3,
    gasLimit: 300000,
    explorer: 'https://testnet.bscscan.com',
    currency: {
      name: 'BNB',
      symbol: 'BNB',
      decimals: 18
    },
    faucet: 'https://testnet.binance.org/faucet-smart'
  }
};

/**
 * Get network configuration by name
 */
function getNetwork(networkName) {
  const network = networks[networkName];
  if (!network) {
    throw new Error(`Network '${networkName}' not found. Available: ${Object.keys(networks).join(', ')}`);
  }
  return network;
}

/**
 * Get network configuration by chain ID
 */
function getNetworkByChainId(chainId) {
  const network = Object.values(networks).find(n => n.chainId === chainId);
  if (!network) {
    throw new Error(`No network found with chainId: ${chainId}`);
  }
  return network;
}

/**
 * Check if network is a testnet
 */
function isTestnet(networkName) {
  const testnets = ['sepolia', 'hoodi', 'baseSepolia', 'arbitrumSepolia', 'polygonMumbai', 'bscTestnet'];
  return testnets.includes(networkName);
}

/**
 * Get all available network names
 */
function getAvailableNetworks() {
  return Object.keys(networks);
}

module.exports = {
  networks,
  getNetwork,
  getNetworkByChainId,
  isTestnet,
  getAvailableNetworks
};