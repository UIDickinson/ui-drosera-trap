/**
 * Web3 helper utilities for blockchain interactions
 */

const { ethers } = require('ethers');
const { getNetwork } = require('../config/networks');
require('dotenv').config();

/**
 * Get provider for specified network
 */
function getProvider(networkName = 'hoodi') {
  const network = getNetwork(networkName);
  
  if (!network.rpcUrl) {
    throw new Error(`No RPC URL configured for network: ${networkName}`);
  }

  return new ethers.providers.JsonRpcProvider(network.rpcUrl);
}

/**
 * Get signer from private key
 */
function getSigner(networkName = 'hoodi') {
  const provider = getProvider(networkName);
  const privateKey = process.env.PRIVATE_KEY;

  if (!privateKey) {
    throw new Error('PRIVATE_KEY not set in .env file');
  }

  // Ensure private key starts with 0x
  const formattedKey = privateKey.startsWith('0x') ? privateKey : `0x${privateKey}`;
  
  return new ethers.Wallet(formattedKey, provider);
}

/**
 * Format large numbers with commas
 */
function formatNumber(num) {
  return num.toString().replace(/\B(?=(\d{3})+(?!\d))/g, ',');
}

/**
 * Format Wei to Ether
 */
function formatEther(wei) {
  return ethers.utils.formatEther(wei);
}

/**
 * Parse Ether to Wei
 */
function parseEther(ether) {
  return ethers.utils.parseEther(ether.toString());
}

/**
 * Format address (shortened)
 */
function formatAddress(address) {
  if (!address) return 'N/A';
  if (address.length < 10) return address;
  return `${address.slice(0, 6)}...${address.slice(-4)}`;
}

/**
 * Wait for transaction confirmation
 */
async function waitForTx(tx, confirmations = 1) {
  console.log(`Transaction sent: ${tx.hash}`);
  console.log('Waiting for confirmation...');
  
  const receipt = await tx.wait(confirmations);
  
  console.log(`✓ Confirmed in block: ${receipt.blockNumber}`);
  console.log(`  Gas used: ${formatNumber(receipt.gasUsed.toString())}`);
  
  return receipt;
}

/**
 * Get current gas price
 */
async function getGasPrice(provider) {
  const gasPrice = await provider.getGasPrice();
  return gasPrice;
}

/**
 * Format gas price in gwei
 */
function formatGasPrice(gasPrice) {
  return ethers.utils.formatUnits(gasPrice, 'gwei') + ' gwei';
}

/**
 * Get current block number
 */
async function getCurrentBlock(provider) {
  return await provider.getBlockNumber();
}

/**
 * Get block by number
 */
async function getBlock(provider, blockNumber) {
  return await provider.getBlock(blockNumber);
}

/**
 * Get transaction receipt
 */
async function getTxReceipt(provider, txHash) {
  return await provider.getTransactionReceipt(txHash);
}

/**
 * Check if address is valid
 */
function isValidAddress(address) {
  return ethers.utils.isAddress(address);
}

/**
 * Get balance in ETH
 */
async function getBalance(provider, address) {
  const balance = await provider.getBalance(address);
  return formatEther(balance);
}

/**
 * Estimate gas for transaction
 */
async function estimateGas(contract, functionName, ...args) {
  try {
    const gasEstimate = await contract.estimateGas[functionName](...args);
    return gasEstimate;
  } catch (error) {
    throw new Error(`Gas estimation failed: ${error.message}`);
  }
}

/**
 * Create contract instance
 */
function getContract(address, abi, signerOrProvider) {
  return new ethers.Contract(address, abi, signerOrProvider);
}

/**
 * Sleep utility
 */
function sleep(ms) {
  return new Promise(resolve => setTimeout(resolve, ms));
}

/**
 * Retry with exponential backoff
 */
async function retry(fn, maxAttempts = 3, delay = 1000) {
  for (let attempt = 1; attempt <= maxAttempts; attempt++) {
    try {
      return await fn();
    } catch (error) {
      if (attempt === maxAttempts) {
        throw error;
      }
      console.log(`Attempt ${attempt} failed, retrying in ${delay}ms...`);
      await sleep(delay);
      delay *= 2; // Exponential backoff
    }
  }
}

module.exports = {
  getProvider,
  getSigner,
  formatNumber,
  formatEther,
  parseEther,
  formatAddress,
  waitForTx,
  getGasPrice,
  formatGasPrice,
  getCurrentBlock,
  getBlock,
  getTxReceipt,
  isValidAddress,
  getBalance,
  estimateGas,
  getContract,
  sleep,
  retry
};