/**
 * Test the collect() function of your trap
 * 
 * Usage: npm run test-collect
 */

const { ethers } = require('ethers');
const { getProvider } = require('../utils/web3-helper');
const logger = require('../utils/logger');
const { trapAbi } = require('../config/abis');
require('dotenv').config();

async function testCollect() {
  try {
    logger.header('Testing collect() Function');

    const network = process.env.NETWORK || 'hoodi';
    const trapAddress = process.env.TRAP_ADDRESS;

    if (!trapAddress) {
      logger.error('TRAP_ADDRESS not set in .env');
      process.exit(1);
    }

    logger.info('Network:', network);
    logger.info('Trap:', trapAddress);
    logger.separator();

    // Connect to trap
    const provider = getProvider(network);
    const trap = new ethers.Contract(trapAddress, trapAbi, provider);

    // Get current block
    const currentBlock = await provider.getBlockNumber();
    logger.info('Current Block:', currentBlock);
    logger.separator();

    // Call collect()
    logger.info('Calling collect()...');
    
    try {
      const data = await trap.collect();
      
      logger.success('collect() executed successfully!');
      logger.info('Data length:', data.length, 'bytes');
      
      if (data.length > 2) {
        logger.separator();
        logger.info('Attempting to decode data...');
        
        try {
          // Define the CollectOutput struct
          const collectOutputType = ethers.utils.ParamType.from(
            'tuple(uint256 blockNumber, address[] recentBuyers, uint256[] buyAmounts, uint256[] gasPrices, uint256 totalSupply, uint256 liquidityPoolBalance, uint256 averageGasPrice)'
          );
          
          const decoded = ethers.utils.defaultAbiCoder.decode([collectOutputType], data);
          const output = decoded[0];
          
          logger.success('Data decoded successfully!');
          logger.separator();
          
          const decodedData = {
            'Block Number': output.blockNumber.toString(),
            'Recent Buyers': output.recentBuyers.length,
            'Buy Amounts': output.buyAmounts.length,
            'Gas Prices': output.gasPrices.length,
            'Total Supply': ethers.utils.formatEther(output.totalSupply),
            'Pool Balance': ethers.utils.formatEther(output.liquidityPoolBalance),
            'Avg Gas Price': ethers.utils.formatUnits(output.averageGasPrice, 'gwei') + ' gwei'
          };
          
          logger.table(decodedData);
          
          // Show buyers if any
          if (output.recentBuyers.length > 0) {
            logger.separator();
            logger.info('Recent Buyers:');
            output.recentBuyers.forEach((buyer, index) => {
              const amount = ethers.utils.formatEther(output.buyAmounts[index]);
              const gas = ethers.utils.formatUnits(output.gasPrices[index], 'gwei');
              logger.info(`  ${index + 1}. ${buyer}`);
              logger.info(`     Amount: ${amount} tokens`);
              logger.info(`     Gas: ${gas} gwei`);
            });
          } else {
            logger.info('No recent buyers in this block');
          }
          
        } catch (decodeError) {
          logger.warning('Could not decode data:', decodeError.message);
          logger.debug('Raw data:', data);
        }
      } else {
        logger.info('No data collected (monitoring may not be active)');
      }
      
    } catch (error) {
      logger.error('collect() failed:', error.message);
      
      if (error.message.includes('monitoring')) {
        logger.info('');
        logger.info('Possible reasons:');
        logger.info('• Monitoring period has not started yet');
        logger.info('• Monitoring period has ended');
        logger.info('• Trap has been deactivated');
      }
    }

    logger.separator();
    logger.success('Test complete!');

  } catch (error) {
    logger.error('Error testing collect():', error.message);
    if (process.env.DEBUG === 'true') {
      console.error(error);
    }
    process.exit(1);
  }
}

// Run if called directly
if (require.main === module) {
  testCollect();
}

module.exports = testCollect;