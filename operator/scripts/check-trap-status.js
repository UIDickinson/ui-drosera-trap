// ============================================
// FILE: operator/scripts/check-trap-status.js
// ============================================
/**
 * Check the status of your deployed Fair Launch Guardian Trap
 * 
 * Usage: npm run check-status
 */

const { ethers } = require('ethers');
const { getProvider, formatAddress, formatNumber } = require('../utils/web3-helper');
const logger = require('../utils/logger');
const { trapAbi, tokenAbi } = require('../config/abis');
require('dotenv').config();

async function checkTrapStatus() {
  try {
    logger.header('Fair Launch Guardian - Status Check');

    // Get configuration
    const network = process.env.NETWORK || 'hoodi';
    const trapAddress = process.env.TRAP_ADDRESS;

    if (!trapAddress) {
      logger.error('TRAP_ADDRESS not set in .env file');
      process.exit(1);
    }

    logger.info('Network:', network);
    logger.info('Trap Address:', trapAddress);
    logger.separator();

    // Connect to provider
    const provider = getProvider(network);
    const trap = new ethers.Contract(trapAddress, trapAbi, provider);

    // Get current block
    const currentBlock = await provider.getBlockNumber();
    logger.info('Current Block:', formatNumber(currentBlock));
    logger.separator();

    // Get trap configuration
    logger.info('Fetching configuration...');
    const config = await trap.getConfig();
    
    const configData = {
      'Token Address': config[0],
      'Liquidity Pool': config[1],
      'Launch Block': formatNumber(config[2].toString()),
      'Monitoring Duration': config[3].toString() + ' blocks',
      'Max Wallet %': (config[4].toNumber() / 100).toFixed(2) + '%',
      'Max Gas Premium': (config[5].toNumber() / 100) + 'x',
      'Is Active': config[6] ? '✓ Yes' : '✗ No'
    };

    logger.table(configData);

    // Get token info
    logger.separator();
    logger.info('Fetching token information...');
    try {
      const token = new ethers.Contract(config[0], tokenAbi, provider);
      const tokenName = await token.name();
      const tokenSymbol = await token.symbol();
      const totalSupply = await token.totalSupply();

      const tokenData = {
        'Name': tokenName,
        'Symbol': tokenSymbol,
        'Total Supply': formatNumber(ethers.utils.formatEther(totalSupply))
      };

      logger.table(tokenData);
    } catch (error) {
      logger.warning('Could not fetch token info:', error.message);
    }

    // Check monitoring status
    logger.separator();
    logger.info('Checking monitoring status...');
    
    const isMonitoring = await trap.isMonitoringActive();
    const launchBlock = config[2].toNumber();
    const monitoringDuration = config[3].toNumber();
    const blocksSinceLaunch = currentBlock - launchBlock;
    const blocksRemaining = Math.max(0, monitoringDuration - blocksSinceLaunch);
    
    const statusData = {
      'Monitoring Active': isMonitoring ? '✓ YES' : '✗ NO',
      'Launch Block': formatNumber(launchBlock),
      'Current Block': formatNumber(currentBlock),
      'Blocks Since Launch': formatNumber(blocksSinceLaunch),
      'Blocks Remaining': formatNumber(blocksRemaining)
    };

    logger.table(statusData);

    if (blocksSinceLaunch < 0) {
      logger.info('Launch has not started yet');
      logger.info('Launch will begin in', formatNumber(-blocksSinceLaunch), 'blocks');
    } else if (blocksRemaining > 0) {
      logger.success('Monitoring is active!');
      const estimatedMinutes = blocksRemaining * 12 / 60; // Assuming 12 sec blocks
      logger.info(`Approximately ${estimatedMinutes.toFixed(1)} minutes remaining`);
    } else {
      logger.warning('Monitoring period has ended');
    }

    // Test collect() function
    logger.separator();
    logger.info('Testing collect() function...');
    
    try {
      const collectData = await trap.collect();
      logger.success('collect() working correctly');
      logger.info('Returned', collectData.length, 'bytes of data');
      
      // Try to decode (this will work if there's actual data)
      if (collectData.length > 2) {
        logger.debug('Raw data:', collectData);
      }
    } catch (error) {
      logger.error('collect() failed:', error.message);
    }

    logger.separator();
    logger.success('Status check complete!');
    logger.info('');
    logger.info('Next steps:');
    logger.info('1. If not registered: Visit https://app.drosera.io');
    logger.info('2. Test with simulation: npm run simulate-sniper');
    logger.info('3. Monitor launch: npm run monitor');

  } catch (error) {
    logger.error('Error checking trap status:', error.message);
    if (process.env.DEBUG === 'true') {
      console.error(error);
    }
    process.exit(1);
  }
}

// Run if called directly
if (require.main === module) {
  checkTrapStatus();
}

module.exports = checkTrapStatus;
