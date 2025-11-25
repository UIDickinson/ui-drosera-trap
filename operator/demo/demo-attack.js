// ============================================
// FILE: operator/demo/demo-attack.js
// ============================================

/**
 * Run specific attack scenarios for testing
 * Usage: node operator/demo/demo-attack.js <scenario>
 * 
 * Scenarios:
 * - sniper: Buy 10% of supply at once
 * - rapid: Multiple quick buys
 * - coordinated: Multiple wallets attacking
 * - frontrun: High gas price attack
 */

const { ethers } = require('ethers');
const logger = require('../utils/logger');
const { getSigner, parseEther, formatEther, waitForTx } = require('../utils/web3-helper');
const { dexAbi, tokenAbi, trapAbi } = require('../config/abis');
require('dotenv').config();

async function runAttack(scenario) {
    logger.header(`Attack Scenario: ${scenario.toUpperCase()}`);
    
    const DEX_ADDRESS = process.env.DEX_ADDRESS || process.env.LIQUIDITY_POOL;
    const TOKEN_ADDRESS = process.env.TOKEN_ADDRESS;
    const TRAP_ADDRESS = process.env.TRAP_ADDRESS;
    
    if (!DEX_ADDRESS || !TOKEN_ADDRESS || !TRAP_ADDRESS) {
        logger.error('Missing contract addresses in .env!');
        process.exit(1);
    }
    
    const signer = getSigner();
    const dex = new ethers.Contract(DEX_ADDRESS, dexAbi, signer);
    const token = new ethers.Contract(TOKEN_ADDRESS, tokenAbi, signer);
    const trap = new ethers.Contract(TRAP_ADDRESS, trapAbi, signer);
    
    logger.info('DEX:', DEX_ADDRESS);
    logger.info('Token:', TOKEN_ADDRESS);
    logger.info('Trap:', TRAP_ADDRESS);
    logger.separator();
    
    switch (scenario) {
        case 'sniper':
            await sniperAttack(dex, token, trap, signer);
            break;
        case 'rapid':
            await rapidAttack(dex, token, trap, signer);
            break;
        case 'coordinated':
            await coordinatedAttack(dex, token, trap, signer);
            break;
        case 'frontrun':
            await frontrunAttack(dex, token, trap, signer);
            break;
        default:
            logger.error('Unknown scenario:', scenario);
            logger.info('Available: sniper, rapid, coordinated, frontrun');
            process.exit(1);
    }
}

async function sniperAttack(dex, token, trap, signer) {
    logger.info('🎯 SNIPER ATTACK: Buying 10% of supply');
    logger.blank();
    
    const bot = ethers.Wallet.createRandom().connect(signer.provider);
    const buyAmount = parseEther('10'); // 10 ETH = ~10% of 1M supply
    
    logger.info('Bot address:', bot.address);
    logger.info('Buy amount:', formatEther(buyAmount), 'ETH');
    logger.blank();
    
    // Fund bot
    let tx = await signer.sendTransaction({
        to: bot.address,
        value: buyAmount.add(parseEther('0.01'))
    });
    await tx.wait();
    logger.success('Bot funded ✓');
    
    // Attack
    logger.info('Executing sniper attack...');
    try {
        const dexWithBot = dex.connect(bot);
        tx = await dexWithBot.swap({ value: buyAmount });
        await waitForTx(tx);
        
        // Check detection
        await sleep(2000);
        const isBlacklisted = await trap.isBlacklisted(bot.address);
        
        if (isBlacklisted) {
            logger.error('🚨 BOT BLACKLISTED!');
            logger.success('✓ Attack detected and blocked');
        } else {
            logger.warning('Bot not blacklisted yet');
        }
        
    } catch (error) {
        logger.error('Attack blocked:', error.message.split('\n')[0]);
    }
}

async function rapidAttack(dex, token, trap, signer) {
    logger.info('🎯 RAPID ATTACK: Multiple quick buys');
    logger.blank();
    
    const bot = ethers.Wallet.createRandom().connect(signer.provider);
    const buyAmount = parseEther('1'); // 1 ETH each
    const numBuys = 5;
    
    logger.info('Bot address:', bot.address);
    logger.info('Buys:', numBuys, 'x', formatEther(buyAmount), 'ETH');
    logger.blank();
    
    // Fund bot
    let tx = await signer.sendTransaction({
        to: bot.address,
        value: buyAmount.mul(numBuys).add(parseEther('0.1'))
    });
    await tx.wait();
    
    // Multiple rapid buys
    const dexWithBot = dex.connect(bot);
    
    for (let i = 0; i < numBuys; i++) {
        logger.info(`Buy ${i + 1}/${numBuys}...`);
        try {
            tx = await dexWithBot.swap({ value: buyAmount });
            await tx.wait();
            logger.success('  ✓ Success');
        } catch (error) {
            logger.error('  ✗ Blocked:', error.message.split('\n')[0]);
            break;
        }
        
        if (i < numBuys - 1) {
            await sleep(1000); // 1 second between buys
        }
    }
    
    const isBlacklisted = await trap.isBlacklisted(bot.address);
    logger.blank();
    if (isBlacklisted) {
        logger.error('🚨 BOT BLACKLISTED!');
        logger.success('✓ Rapid buying detected');
    }
}

async function coordinatedAttack(dex, token, trap, signer) {
    logger.info('🎯 COORDINATED ATTACK: 5 bots buying together');
    logger.blank();
    
    const numBots = 5;
    const buyAmount = parseEther('2'); // 2 ETH each = 10% total
    
    // Create bot wallets
    const bots = [];
    for (let i = 0; i < numBots; i++) {
        bots.push(ethers.Wallet.createRandom().connect(signer.provider));
    }
    
    logger.info('Created', numBots, 'bot wallets');
    logger.info('Each buying:', formatEther(buyAmount), 'ETH');
    logger.blank();
    
    // Fund all bots
    logger.info('Funding bots...');
    for (let i = 0; i < bots.length; i++) {
        const tx = await signer.sendTransaction({
            to: bots[i].address,
            value: buyAmount.add(parseEther('0.01'))
        });
        await tx.wait();
        logger.debug(`  Bot ${i + 1} funded`);
    }
    logger.success('All bots funded ✓');
    logger.blank();
    
    // Simultaneous attack
    logger.info('Executing coordinated attack...');
    const promises = bots.map(async (bot, i) => {
        const dexWithBot = dex.connect(bot);
        try {
            const tx = await dexWithBot.swap({ value: buyAmount });
            logger.debug(`  Bot ${i + 1} transaction sent`);
            return tx;
        } catch (error) {
            logger.error(`  Bot ${i + 1} failed`);
            return null;
        }
    });
    
    const txs = await Promise.all(promises);
    logger.info('Waiting for confirmations...');
    
    for (let tx of txs) {
        if (tx) await tx.wait();
    }
    
    logger.success('All transactions processed ✓');
    logger.blank();
    
    // Check how many are blacklisted
    let blacklistedCount = 0;
    for (let bot of bots) {
        if (await trap.isBlacklisted(bot.address)) {
            blacklistedCount++;
        }
    }
    
    if (blacklistedCount > 0) {
        logger.error(`🚨 ${blacklistedCount}/${numBots} BOTS BLACKLISTED!`);
        logger.success('✓ Coordinated attack detected');
    }
}

async function frontrunAttack(dex, token, trap, signer) {
    logger.info('🎯 FRONTRUN ATTACK: Using 5x gas price');
    logger.blank();
    
    const bot = ethers.Wallet.createRandom().connect(signer.provider);
    const buyAmount = parseEther('5'); // 5 ETH
    
    logger.info('Bot address:', bot.address);
    logger.info('Buy amount:', formatEther(buyAmount), 'ETH');
    logger.blank();
    
    // Fund bot
    let tx = await signer.sendTransaction({
        to: bot.address,
        value: buyAmount.add(parseEther('0.1'))
    });
    await tx.wait();
    
    // Get normal gas price
    const normalGas = await signer.provider.getGasPrice();
    const highGas = normalGas.mul(5); // 5x normal
    
    logger.info('Normal gas:', ethers.utils.formatUnits(normalGas, 'gwei'), 'gwei');
    logger.warning('Using gas:', ethers.utils.formatUnits(highGas, 'gwei'), 'gwei (5x!)');
    logger.blank();
    
    // Attack with high gas
    logger.info('Executing frontrun attack...');
    try {
        const dexWithBot = dex.connect(bot);
        tx = await dexWithBot.swap({ value: buyAmount, gasPrice: highGas });
        await waitForTx(tx);
        
        await sleep(2000);
        const isBlacklisted = await trap.isBlacklisted(bot.address);
        
        if (isBlacklisted) {
            logger.error('🚨 BOT BLACKLISTED!');
            logger.success('✓ High gas detected');
        }
        
    } catch (error) {
        logger.error('Attack blocked:', error.message.split('\n')[0]);
    }
}

function sleep(ms) {
    return new Promise(resolve => setTimeout(resolve, ms));
}

// Main
const scenario = process.argv[2] || 'sniper';

runAttack(scenario).then(() => {
    logger.blank();
    logger.success('Attack scenario complete!');
    logger.info('Check trap status with: npm run check-status');
    process.exit(0);
}).catch(error => {
    logger.error('Error:', error.message);
    process.exit(1);
});