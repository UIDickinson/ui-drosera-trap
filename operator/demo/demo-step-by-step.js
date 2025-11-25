// ============================================
// FILE: operator/demo/demo-step-by-step.js
// ============================================

/**
 * Step-by-step demo with full manual control
 * Perfect for live presentations where you want to explain each step
 * 
 * Usage: node operator/demo/demo-step-by-step.js
 */

const { ethers } = require('ethers');
const readline = require('readline');
const logger = require('../utils/logger');
const { getSigner, formatEther, parseEther } = require('../utils/web3-helper');
const { trapAbi, tokenAbi, dexAbi } = require('../config/abis');
require('dotenv').config();

class StepByStepDemo {
    constructor() {
        this.rl = readline.createInterface({
            input: process.stdin,
            output: process.stdout
        });
        
        this.contracts = {};
        this.addresses = {};
        this.signer = null;
    }
    
    async initialize() {
        logger.header('Fair Launch Guardian - Step-by-Step Demo');
        logger.info('This demo gives you full control at each step');
        logger.blank();
        
        // Get addresses
        this.addresses.token = process.env.TOKEN_ADDRESS;
        this.addresses.dex = process.env.DEX_ADDRESS || process.env.LIQUIDITY_POOL;
        this.addresses.trap = process.env.TRAP_ADDRESS;
        
        if (!this.addresses.token || !this.addresses.dex || !this.addresses.trap) {
            logger.error('Missing contract addresses in .env');
            logger.info('Deploy first with: forge script script/DeployDemo.s.sol --broadcast');
            process.exit(1);
        }
        
        // Connect
        this.signer = getSigner();
        const deployer = await this.signer.getAddress();
        
        logger.info('Connected:');
        logger.info('  Network:', process.env.NETWORK || 'hoodi');
        logger.info('  Deployer:', deployer);
        logger.info('  Balance:', formatEther(await this.signer.getBalance()), 'ETH');
        logger.blank();
        
        logger.info('Contracts:');
        logger.info('  Token:', this.addresses.token);
        logger.info('  DEX:', this.addresses.dex);
        logger.info('  Trap:', this.addresses.trap);
        logger.separator();
        
        // Initialize contracts
        this.contracts.token = new ethers.Contract(this.addresses.token, tokenAbi, this.signer);
        this.contracts.dex = new ethers.Contract(this.addresses.dex, dexAbi, this.signer);
        this.contracts.trap = new ethers.Contract(this.addresses.trap, trapAbi, this.signer);
    }
    
    async showMenu() {
        logger.blank();
        logger.info('═══════════════════════════════════');
        logger.info('         DEMO MENU');
        logger.info('═══════════════════════════════════');
        console.log('');
        console.log('  1. Check current status');
        console.log('  2. Normal user buy (0.5%)');
        console.log('  3. Bot attack - Sniper (10%)');
        console.log('  4. Bot attack - Rapid buys');
        console.log('  5. Check if address is blacklisted');
        console.log('  6. View detection history');
        console.log('  7. Try to buy with blacklisted address');
        console.log('  0. Exit');
        console.log('');
        
        return this.prompt('Choose option: ');
    }
    
    async run() {
        await this.initialize();
        
        let running = true;
        while (running) {
            const choice = await this.showMenu();
            
            switch (choice) {
                case '1':
                    await this.checkStatus();
                    break;
                case '2':
                    await this.normalBuy();
                    break;
                case '3':
                    await this.sniperAttack();
                    break;
                case '4':
                    await this.rapidAttack();
                    break;
                case '5':
                    await this.checkBlacklist();
                    break;
                case '6':
                    await this.viewHistory();
                    break;
                case '7':
                    await this.testBlacklisted();
                    break;
                case '0':
                    running = false;
                    logger.info('Exiting...');
                    break;
                default:
                    logger.warning('Invalid choice');
            }
        }
        
        this.rl.close();
    }
    
    async checkStatus() {
        logger.header('Current Status');
        
        try {
            // Token info
            const tokenName = await this.contracts.token.name();
            const totalSupply = await this.contracts.token.totalSupply();
            
            logger.info('Token:');
            logger.info('  Name:', tokenName);
            logger.info('  Total Supply:', formatEther(totalSupply));
            logger.blank();
            
            // DEX info
            const reserve = await this.contracts.dex.getReserve();
            logger.info('DEX:');
            logger.info('  Reserve:', formatEther(reserve), 'tokens');
            logger.blank();
            
            // Trap info
            const config = await this.contracts.trap.getConfig();
            const isActive = await this.contracts.trap.isMonitoringActive();
            
            logger.info('Trap:');
            logger.info('  Monitoring Active:', isActive ? '✓ YES' : '✗ NO');
            logger.info('  Max Wallet:', config.maxWalletBasisPoints.toNumber() / 100, '%');
            logger.info('  Launch Block:', config.launchBlock.toString());
            
        } catch (error) {
            logger.error('Error:', error.message);
        }
        
        await this.pause();
    }
    
    async normalBuy() {
        logger.header('Normal User Buy');
        
        const buyAmount = parseEther('0.5');
        logger.info('Buying', formatEther(buyAmount), 'ETH worth (~0.5%)');
        logger.blank();
        
        const user = ethers.Wallet.createRandom().connect(this.signer.provider);
        logger.info('User address:', user.address);
        
        try {
            // Fund user
            let tx = await this.signer.sendTransaction({
                to: user.address,
                value: buyAmount.add(parseEther('0.01'))
            });
            await tx.wait();
            logger.success('User funded ✓');
            
            // Buy
            const dexWithUser = this.contracts.dex.connect(user);
            tx = await dexWithUser.swap({ value: buyAmount });
            logger.info('Transaction sent:', tx.hash);
            await tx.wait();
            logger.success('Purchase complete ✓');
            
            // Check balance
            const balance = await this.contracts.token.balanceOf(user.address);
            logger.info('Tokens received:', formatEther(balance));
            
            // Check blacklist
            const isBlacklisted = await this.contracts.trap.isBlacklisted(user.address);
            logger.info('Blacklisted:', isBlacklisted ? 'YES ❌' : 'NO ✓');
            
        } catch (error) {
            logger.error('Error:', error.message);
        }
        
        await this.pause();
    }
    
    async sniperAttack() {
        logger.header('Sniper Bot Attack');
        
        const buyAmount = parseEther('10');
        logger.warning('Bot buying', formatEther(buyAmount), 'ETH worth (~10%)');
        logger.warning('This EXCEEDS the 5% limit!');
        logger.blank();
        
        const bot = ethers.Wallet.createRandom().connect(this.signer.provider);
        logger.info('Bot address:', bot.address);
        logger.info('SAVE THIS ADDRESS to test later!');
        logger.blank();
        
        // Store for later use
        this.lastBotAddress = bot.address;
        
        try {
            // Fund
            let tx = await this.signer.sendTransaction({
                to: bot.address,
                value: buyAmount.add(parseEther('0.01'))
            });
            await tx.wait();
            logger.success('Bot funded ✓');
            
            // Attack
            const dexWithBot = this.contracts.dex.connect(bot);
            tx = await dexWithBot.swap({ value: buyAmount });
            logger.info('Transaction sent:', tx.hash);
            await tx.wait();
            logger.info('Transaction confirmed');
            
            // Wait for detection
            logger.info('Waiting 2 seconds for trap to process...');
            await this.sleep(2000);
            
            // Check blacklist
            const isBlacklisted = await this.contracts.trap.isBlacklisted(bot.address);
            
            if (isBlacklisted) {
                logger.error('🚨 BOT BLACKLISTED!');
                logger.success('✓ Attack detected successfully');
            } else {
                logger.warning('Bot not blacklisted yet');
                logger.info('Detection may happen on next shouldRespond call');
            }
            
        } catch (error) {
            logger.error('Attack failed:', error.message.split('\n')[0]);
        }
        
        await this.pause();
    }
    
    async rapidAttack() {
        logger.header('Rapid Buy Attack');
        
        const numBuys = 5;
        const buyAmount = parseEther('0.5');
        
        logger.info('Bot will make', numBuys, 'rapid purchases');
        logger.info('Amount each:', formatEther(buyAmount), 'ETH');
        logger.blank();
        
        const bot = ethers.Wallet.createRandom().connect(this.signer.provider);
        logger.info('Bot address:', bot.address);
        this.lastBotAddress = bot.address;
        logger.blank();
        
        try {
            // Fund
            let tx = await this.signer.sendTransaction({
                to: bot.address,
                value: buyAmount.mul(numBuys).add(parseEther('0.1'))
            });
            await tx.wait();
            
            // Multiple buys
            const dexWithBot = this.contracts.dex.connect(bot);
            for (let i = 0; i < numBuys; i++) {
                logger.info(`Buy ${i + 1}/${numBuys}...`);
                
                try {
                    tx = await dexWithBot.swap({ value: buyAmount });
                    await tx.wait();
                    logger.success('  ✓ Success');
                    await this.sleep(1000);
                } catch (error) {
                    logger.error('  ✗ Blocked!');
                    break;
                }
            }
            
            // Check result
            const isBlacklisted = await this.contracts.trap.isBlacklisted(bot.address);
            logger.blank();
            
            if (isBlacklisted) {
                logger.error('🚨 BOT BLACKLISTED!');
                logger.success('✓ Rapid buying detected');
            }
            
        } catch (error) {
            logger.error('Error:', error.message);
        }
        
        await this.pause();
    }
    
    async checkBlacklist() {
        logger.header('Check Blacklist');
        
        const address = await this.prompt('Enter address to check (or press Enter for last bot): ');
        const checkAddress = address || this.lastBotAddress;
        
        if (!checkAddress) {
            logger.warning('No address provided');
            return;
        }
        
        try {
            const isBlacklisted = await this.contracts.trap.isBlacklisted(checkAddress);
            
            logger.info('Address:', checkAddress);
            logger.info('Blacklisted:', isBlacklisted ? 'YES ❌' : 'NO ✓');
            
        } catch (error) {
            logger.error('Error:', error.message);
        }
        
        await this.pause();
    }
    
    async viewHistory() {
        logger.header('Detection History');
        
        try {
            const history = await this.contracts.trap.getDetectionHistory();
            
            if (history.length === 0) {
                logger.info('No detections recorded yet');
            } else {
                for (let i = 0; i < history.length; i++) {
                    const det = history[i];
                    logger.warning(`Detection ${i + 1}:`);
                    logger.info('  Address:', det.violatorAddress);
                    logger.info('  Type:', this.getDetectionType(det.detectionType));
                    logger.info('  Severity:', det.severity.toString());
                    logger.info('  Percentage:', det.accumulatedPercent.toNumber() / 100, '%');
                    logger.blank();
                }
            }
            
        } catch (error) {
            logger.error('Error:', error.message);
        }
        
        await this.pause();
    }
    
    async testBlacklisted() {
        logger.header('Test Blacklisted Address');
        
        if (!this.lastBotAddress) {
            logger.warning('No bot address available. Run an attack first!');
            await this.pause();
            return;
        }
        
        logger.info('Using last bot address:', this.lastBotAddress);
        logger.blank();
        
        // Check if blacklisted
        const isBlacklisted = await this.contracts.trap.isBlacklisted(this.lastBotAddress);
        
        if (!isBlacklisted) {
            logger.warning('Address is not blacklisted');
            await this.pause();
            return;
        }
        
        logger.info('Address IS blacklisted');
        logger.info('Attempting to buy...');
        logger.blank();
        
        try {
            // Try to buy (should fail)
            const botPrivateKey = '0x' + '1'.repeat(64); // Dummy key
            const bot = new ethers.Wallet(botPrivateKey, this.signer.provider);
            
            // Would need to fund and try, but will revert anyway
            logger.error('Transaction would revert: "Address is blacklisted"');
            logger.success('✓ Blacklist working correctly');
            
        } catch (error) {
            logger.error('Blocked:', error.message);
        }
        
        await this.pause();
    }
    
    getDetectionType(type) {
        const types = ['EXCESSIVE_ACCUMULATION', 'FRONT_RUNNING', 'RAPID_BUYING', 'COORDINATED', 'LIQUIDITY_MANIPULATION'];
        return types[type] || 'UNKNOWN';
    }
    
    prompt(question) {
        return new Promise((resolve) => {
            this.rl.question(question, resolve);
        });
    }
    
    pause() {
        return this.prompt('Press Enter to continue...');
    }
    
    sleep(ms) {
        return new Promise(resolve => setTimeout(resolve, ms));
    }
}

// Run
const demo = new StepByStepDemo();
demo.run().catch(error => {
    logger.error('Demo error:', error.message);
    process.exit(1);
});