/**
 * Monitor a token launch in real-time (for testing only!)
 * 
 * Note: In production, Drosera operators do this automatically.
 * This is just for local testing and understanding how monitoring works.
 * 
 * Usage: npm run monitor
 */

const { ethers } = require('ethers');
const { getProvider } = require('../utils/web3-helper');
const logger = require('../utils/logger');
const { trapAbi, tokenAbi, dexAbi } = require('../config/abis');
require('dotenv').config();

let isMonitoring = true;

async function monitorLaunch() {
  try {
    logger.header('Fair Launch Monitor (Testing Mode)');
    logger.warning('⚠️  This is for testing only!');
    logger.warning('⚠️  Drosera operators handle this automatically.');
    logger.separator();

    const network = process.env.NETWORK || 'hoodi';
    const trapAddress = process.env.TRAP_ADDRESS;
    const tokenAddress = process.env.TOKEN_ADDRESS;
    const dexAddress = process.env.LIQUIDITY_POOL;

    if (!trapAddress || !tokenAddress || !dexAddress) {
      logger.error('Missing environment variables');
      logger.info('Required: TRAP_ADDRESS, TOKEN_ADDRESS, LIQUIDITY_POOL');
      process.exit(1);
    }

    logger.info('Network:', network);
    logger.info('Trap:', trapAddress);
    logger.info('Token:', tokenAddress);
    logger.info('DEX:', dexAddress);
    logger.separator();

    // Connect to contracts
    const provider = getProvider(network);
    const trap = new ethers.Contract(trapAddress, trapAbi, provider);
    const token = new ethers.Contract(tokenAddress, tokenAbi, provider);
    const dex = new ethers.Contract(dexAddress, dexAbi, provider);

    // Get token info
    const tokenName = await token.name();
    const tokenSymbol = await token.symbol();
    
    logger.success('Connected to', tokenName, `(${tokenSymbol})`);
    logger.separator();

    // Check if monitoring is active
    const isActive = await trap.isMonitoringActive();
    if (!isActive) {
      logger.error('Trap monitoring is not active!');
      logger.info('Check launch configuration with: npm run check-status');
      process.exit(1);
    }

    logger.success('Monitoring is active!');
    logger.info('Press Ctrl+C to stop monitoring');
    logger.separator();

    // Listen for DEX swap events
    logger.info('Listening for swap events...\n');
    
    dex.on('Swap', async (buyer, ethAmount, tokenAmount, gasPrice, event) => {
      const block = event.blockNumber;
      const percent = tokenAmount.mul(10000).div(await token.totalSupply()).toNumber() / 100;
      
      logger.info(`\n🔔 Swap Detected (Block ${block})`);
      logger.info(`  Buyer: ${buyer}`);
      logger.info(`  Amount: ${ethers.utils.formatEther(tokenAmount)} tokens (${percent.toFixed(2)}%)`);
      logger.info(`  Gas: ${ethers.utils.formatUnits(gasPrice, 'gwei')} gwei`);
      
      // Check if suspicious
      if (percent > 5) {
        logger.warning(`  ⚠️  SUSPICIOUS: > 5% of supply!`);
      }
      
      if (gasPrice.gt(ethers.utils.parseUnits('100', 'gwei'))) {
        logger.warning(`  ⚠️  SUSPICIOUS: High gas price!`);
      }
    });

    // Listen for trap events
    trap.on('SuspiciousActivityDetected', (launchId, address, detectionType, amount, block) => {
      logger.warning(`\n🚨 DETECTION at block ${block}`);
      logger.warning(`  Type: ${getDetectionTypeName(detectionType)}`);
      logger.warning(`  Address: ${address}`);
      logger.warning(`  Amount: ${ethers.utils.formatEther(amount)}`);
    });

    trap.on('AddressBlacklisted', (launchId, address, reason) => {
      logger.error(`\n❌ ADDRESS BLACKLISTED`);
      logger.error(`  Address: ${address}`);
      logger.error(`  Reason: ${getDetectionTypeName(reason)}`);
    });

    trap.on('TradingPaused', (launchId, block, reason) => {
      logger.error(`\n⛔ TRADING PAUSED at block ${block}`);
      logger.error(`  Reason: ${reason}`);
    });

    // Monitor new blocks
    provider.on('block', async (blockNumber) => {
      if (!isMonitoring) return;
      
      try {
        // Call collect() each block
        const data = await trap.collect();
        
        if (data.length > 2) {
          // Try to decode
          const collectOutputType = ethers.utils.ParamType.from(
            'tuple(uint256 blockNumber, address[] recentBuyers, uint256[] buyAmounts, uint256[] gasPrices, uint256 totalSupply, uint256 liquidityPoolBalance, uint256 averageGasPrice)'
          );
          
          const decoded = ethers.utils.defaultAbiCoder.decode([collectOutputType], data);
          const output = decoded[0];
          
          if (output.recentBuyers.length > 0) {
            logger.info(`\n📊 Block ${blockNumber}: ${output.recentBuyers.length} buyers`);
          } else {
            logger.debug(`Block ${blockNumber}: No activity`);
          }
        }
        
      } catch (error) {
        if (!error.message.includes('monitoring')) {
          logger.debug('Block', blockNumber, 'error:', error.message);
        }
      }
    });

    // Handle Ctrl+C
    process.on('SIGINT', () => {
      logger.info('\n\nStopping monitor...');
      isMonitoring = false;
      process.exit(0);
    });

    // Keep process alive
    await new Promise(() => {});

  } catch (error) {
    logger.error('Monitoring error:', error.message);
    if (process.env.DEBUG === 'true') {
      console.error(error);
    }
    process.exit(1);
  }
}

function getDetectionTypeName(type) {
  const types = {
    0: 'EXCESSIVE_ACCUMULATION',
    1: 'FRONT_RUNNING_GAS',
    2: 'RAPID_BUYING_PATTERN',
    3: 'COORDINATED_ATTACK',
    4: 'WHALE_DUMP'
  };
  return types[type] || 'UNKNOWN';
}

// Run if called directly
if (require.main === module) {
  monitorLaunch();
}

module.exports = monitorLaunch;