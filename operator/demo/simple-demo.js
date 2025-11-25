/**
 * Simple demo script using deployed contracts
 * Run AFTER deploying with Foundry script
 * 
 * Usage:
 * 1. Deploy: forge script script/DeployDemo.s.sol --broadcast
 * 2. Save addresses to .env
 * 3. Run: node operator/demo/simple-demo.js
 */

const { ethers } = require('ethers');
const logger = require('../utils/logger');
const { getSigner, formatEther, parseEther, waitForTx } = require('../utils/web3-helper');
const { trapAbi, tokenAbi, dexAbi } = require('../config/abis');
require('dotenv').config();

async function runDemo() {
    try {
        logger.header('Fair Launch Guardian - Live Demo');
        
        // Get addresses from env
        const TOKEN_ADDRESS = process.env.TOKEN_ADDRESS;
        const DEX_ADDRESS = process.env.DEX_ADDRESS || process.env.LIQUIDITY_POOL;
        const TRAP_ADDRESS = process.env.TRAP_ADDRESS;
        
        if (!TOKEN_ADDRESS || !DEX_ADDRESS || !TRAP_ADDRESS) {
            logger.error('Missing contract addresses!');
            logger.info('Please set in .env:');
            logger.info('  TOKEN_ADDRESS=0x...');
            logger.info('  DEX_ADDRESS=0x...');
            logger.info('  TRAP_ADDRESS=0x...');
            logger.info('');
            logger.info('Deploy first with:');
            logger.info('  cd contracts');
            logger.info('  forge script script/DeployDemo.s.sol --broadcast --rpc-url $HOODI_RPC');
            process.exit(1);
        }
        
        const network = process.env.NETWORK || 'hoodi';
        logger.info('Network:', network);
        logger.info('Token:', TOKEN_ADDRESS);
        logger.info('DEX:', DEX_ADDRESS);
        logger.info('Trap:', TRAP_ADDRESS);
        logger.separator();
        
        // Connect to contracts
        const signer = getSigner(network);
        const deployer = await signer.getAddress();
        logger.info('Deployer:', deployer);
        
        const token = new ethers.Contract(TOKEN_ADDRESS, tokenAbi, signer);
        const dex = new ethers.Contract(DEX_ADDRESS, dexAbi, signer);
        const trap = new ethers.Contract(TRAP_ADDRESS, trapAbi, signer);
        
        logger.blank();
        
        // STEP 1: Check setup
        await checkSetup(token, dex, trap);
        
        // STEP 2: Normal user buy
        await normalUserBuy(dex, token, trap, signer);
        
        // STEP 3: Bot attack
        await botAttack(dex, token, trap, signer);
        
        // STEP 4: Show results
        await showResults(trap);
        
        logger.success('🎉 Demo complete!');
        
    } catch (error) {
        logger.error('Demo failed:', error.message);
        if (process.env.DEBUG === 'true') {
            console.error(error);
        }
        process.exit(1);
    }
}

async function checkSetup(token, dex, trap) {
    logger.header('STEP 1: Verify Setup');
    
    const tokenName = await token.name();
    const totalSupply = await token.totalSupply();
    const reserve = await dex.getReserve();
    const isActive = await trap.isMonitoringActive();
    
    logger.info('Token:', tokenName);
    logger.info('  Total Supply:', formatEther(totalSupply));
    logger.info('');
    logger.info('DEX:');
    logger.info('  Reserve:', formatEther(reserve), 'tokens');
    logger.info('');
    logger.info('Trap:');
    logger.info('  Monitoring Active:', isActive ? '✓ YES' : '✗ NO');
    
    if (!isActive) {
        logger.warning('⚠️  Monitoring not active! Check configuration');
    }
    
    logger.blank();
    await pause('Setup verified. Press Enter to continue...');
}

async function normalUserBuy(dex, token, trap, signer) {
    logger.header('STEP 2: Normal User Buy');
    
    const buyAmount = parseEther('0.5'); // 0.5 ETH
    
    logger.info('Buying', formatEther(buyAmount), 'ETH worth of tokens...');
    logger.info('This is ~0.5% of supply - within 5% limit');
    logger.blank();
    
    // Create normal user wallet
    const normalUser = ethers.Wallet.createRandom().connect(signer.provider);
    logger.info('Normal User:', normalUser.address);
    
    // Fund normal user
    let tx = await signer.sendTransaction({
        to: normalUser.address,
        value: buyAmount.add(parseEther('0.01')) // Extra for gas
    });
    await tx.wait();
    logger.info('User funded ✓');
    
    // Buy tokens
    const dexWithUser = dex.connect(normalUser);
    tx = await dexWithUser.swap({ value: buyAmount });
    const receipt = await waitForTx(tx);
    
    // Check balance
    const balance = await token.balanceOf(normalUser.address);
    const totalSupply = await token.totalSupply();
    const percent = balance.mul(10000).div(totalSupply).toNumber() / 100;
    
    logger.success('✓ Purchase successful!');
    logger.info('  Tokens received:', formatEther(balance));
    logger.info('  Percentage:', percent.toFixed(2), '%');
    logger.info('  Transaction:', receipt.transactionHash);
    
    // Check if blacklisted
    const isBlacklisted = await trap.isBlacklisted(normalUser.address);
    logger.info('  Blacklisted:', isBlacklisted ? '✗ YES' : '✓ NO');
    
    if (!isBlacklisted) {
        logger.success('✓ Normal user can trade freely!');
    }
    
    logger.blank();
    await pause('Normal buy complete. Press Enter for bot attack...');
}

async function botAttack(dex, token, trap, signer) {
    logger.header('STEP 3: Bot Attack');
    
    const botAmount = parseEther('10'); // 10 ETH = ~10% of supply
    
    logger.warning('⚠️  Bot attempting to buy', formatEther(botAmount), 'ETH worth');
    logger.warning('⚠️  This is ~10% of supply - EXCEEDS 5% LIMIT!');
    logger.blank();
    
    // Create bot wallet
    const bot = ethers.Wallet.createRandom().connect(signer.provider);
    logger.info('Bot Address:', bot.address);
    
    // Fund bot
    let tx = await signer.sendTransaction({
        to: bot.address,
        value: botAmount.add(parseEther('0.01'))
    });
    await tx.wait();
    logger.info('Bot funded ✓');
    logger.blank();
    
    logger.info('Executing attack...');
    
    try {
        // Bot attempts to buy
        const dexWithBot = dex.connect(bot);
        tx = await dexWithBot.swap({ value: botAmount });
        const receipt = await tx.wait();
        
        logger.info('Transaction completed:', receipt.transactionHash);
        
        // Wait a moment for trap to process
        logger.info('Waiting for trap detection...');
        await sleep(3000);
        
        // Check if blacklisted
        const isBlacklisted = await trap.isBlacklisted(bot.address);
        
        if (isBlacklisted) {
            logger.error('🚨 BOT DETECTED AND BLACKLISTED!');
            logger.success('✓ Fair Launch Guardian working correctly!');
            logger.info('  Bot address:', bot.address);
            logger.info('  Status: BLACKLISTED');
            
            // Try to buy again (should fail)
            logger.blank();
            logger.info('Testing if bot can buy again...');
            
            try {
                tx = await dexWithBot.swap({ value: parseEther('0.1') });
                await tx.wait();
                logger.warning('⚠️  Bot could still buy (unexpected)');
            } catch (error) {
                if (error.message.includes('blacklisted')) {
                    logger.error('✓ Bot transaction REVERTED!');
                    logger.success('✓ Bot is permanently blocked!');
                } else {
                    logger.info('Transaction failed:', error.message);
                }
            }
            
        } else {
            logger.warning('⚠️  Bot not blacklisted yet');
            logger.info('Trap may detect on next shouldRespond call');
        }
        
    } catch (error) {
        if (error.message.includes('blacklisted') || error.message.includes('paused')) {
            logger.error('🚨 TRANSACTION BLOCKED BY TRAP!');
            logger.success('✓ Protection working perfectly!');
        } else {
            logger.error('Transaction failed:', error.message.split('\n')[0]);
        }
    }
    
    logger.blank();
    await pause('Bot attack handled! Press Enter for results...');
}

async function showResults(trap) {
    logger.header('STEP 4: Results');
    
    try {
        const config = await trap.getConfig();
        const isActive = await trap.isMonitoringActive();
        
        logger.info('📊 Fair Launch Guardian Status:');
        logger.blank();
        
        logger.info('Configuration:');
        logger.info('  Max Wallet:', config.maxWalletBasisPoints.toNumber() / 100, '%');
        logger.info('  Max Gas Premium:', config.maxGasPremiumBasisPoints.toNumber() / 100, 'x');
        logger.info('  Launch Block:', config.launchBlock.toString());
        logger.info('  Monitoring Duration:', config.monitoringDuration.toString(), 'blocks');
        logger.info('  Active:', isActive ? '✓ YES' : '✗ NO');
        logger.blank();
        
        // Try to get detection history
        try {
            const history = await trap.getDetectionHistory();
            
            logger.info('Detection History:');
            if (history.length > 0) {
                for (let i = 0; i < history.length; i++) {
                    const detection = history[i];
                    logger.warning(`  Detection ${i + 1}:`);
                    logger.info('    Violator:', detection.violatorAddress);
                    logger.info('    Type:', getDetectionTypeName(detection.detectionType));
                    logger.info('    Severity:', detection.severity.toString());
                    logger.info('    Accumulated:', detection.accumulatedPercent.toNumber() / 100, '%');
                }
            } else {
                logger.info('  No detections recorded yet');
                logger.info('  (Detection may happen on next Drosera operator call)');
            }
        } catch (error) {
            logger.info('  Could not fetch detection history');
        }
        
        logger.blank();
        logger.success('✅ DEMONSTRATION COMPLETE!');
        
        logger.blank();
        logger.info('🔍 View on Block Explorer:');
        logger.info(`  https://hoodi.etherscan.io/address/${trap.address}`);
        
    } catch (error) {
        logger.error('Error fetching results:', error.message);
    }
}

function getDetectionTypeName(type) {
    const types = [
        'EXCESSIVE_ACCUMULATION',
        'FRONT_RUNNING_GAS',
        'RAPID_BUYING_PATTERN',
        'COORDINATED_ATTACK',
        'LIQUIDITY_MANIPULATION'
    ];
    return types[type] || 'UNKNOWN';
}

function sleep(ms) {
    return new Promise(resolve => setTimeout(resolve, ms));
}

function pause(message) {
    if (process.env.AUTO_DEMO === 'true') {
        logger.info(message.replace('Press Enter', 'Auto-continuing'));
        return sleep(2000);
    }
    
    return new Promise((resolve) => {
        const readline = require('readline').createInterface({
            input: process.stdin,
            output: process.stdout
        });
        
        readline.question(message, () => {
            readline.close();
            resolve();
        });
    });
}

if (require.main === module) {
    runDemo();
}

module.exports = { runDemo };