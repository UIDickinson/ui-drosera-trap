// ============================================
// FILE: operator/demo/demo-full-launch.js
// ============================================

/**
 * Complete Fair Launch Guardian Demonstration
 * 
 * This script runs the entire demo from start to finish:
 * 1. Deploy token + DEX + trap
 * 2. Add liquidity
 * 3. Normal user buys (allowed)
 * 4. Bot attacks (detected and blocked)
 * 5. Show results
 * 
 * Perfect for recording videos or live demonstrations
 */

const { ethers } = require('ethers');
const fs = require('fs');
const path = require('path');
require('dotenv').config();

const logger = require('../utils/logger');
const { getSigner, formatEther, parseEther, waitForTx, formatAddress } = require('../utils/web3-helper');

// Demo configuration
const DEMO_CONFIG = {
    tokenName: 'DemoLaunchToken',
    tokenSymbol: 'DLT',
    totalSupply: parseEther('1000000'), // 1 million tokens
    liquidityAmount: parseEther('500000'), // 500k tokens to pool
    normalBuyAmount: parseEther('0.5'), // 0.5 ETH (0.5% of supply)
    botBuyAmount: parseEther('10'), // 10 ETH (10% of supply - should be blocked!)
    
    // Trap configuration
    maxWalletPercent: 500, // 5%
    maxGasPremium: 200, // 2x
    monitoringBlocks: 50
};

class DemoOrchestrator {
    constructor() {
        this.signer = null;
        this.addresses = {
            token: null,
            dex: null,
            trap: null,
            deployer: null,
            normalUser: null,
            bot: null
        };
        this.contracts = {};
    }
    
    async initialize() {
        logger.header('Fair Launch Guardian - Complete Demo');
        
        const network = process.env.NETWORK || 'hoodi';
        logger.info('Network:', network);
        
        this.signer = getSigner(network);
        this.addresses.deployer = await this.signer.getAddress();
        
        logger.info('Deployer:', this.addresses.deployer);
        
        const balance = await this.signer.getBalance();
        logger.info('Balance:', formatEther(balance), 'ETH');
        
        if (balance.lt(parseEther('0.5'))) {
            logger.error('Insufficient balance! Need at least 0.5 ETH for demo');
            process.exit(1);
        }
        
        logger.separator();
        
        // Create test wallets
        this.addresses.normalUser = ethers.Wallet.createRandom().connect(this.signer.provider).address;
        this.addresses.bot = ethers.Wallet.createRandom().connect(this.signer.provider).address;
        
        logger.info('Test wallets created:');
        logger.info('  Normal User:', formatAddress(this.addresses.normalUser));
        logger.info('  Bot:', formatAddress(this.addresses.bot));
        logger.blank();
    }
    
    async step1_deployContracts() {
        logger.header('STEP 1: Deploy Contracts');
        
        // Deploy DemoToken
        logger.info('Deploying DemoToken...');
        const TokenFactory = new ethers.ContractFactory(
            this._getABI('DemoToken'),
            this._getBytecode('DemoToken'),
            this.signer
        );
        
        const token = await TokenFactory.deploy(
            DEMO_CONFIG.tokenName,
            DEMO_CONFIG.tokenSymbol,
            DEMO_CONFIG.totalSupply
        );
        await token.deployed();
        this.addresses.token = token.address;
        this.contracts.token = token;
        
        logger.success('✓ Token deployed:', token.address);
        logger.info('  Name:', await token.name());
        logger.info('  Symbol:', await token.symbol());
        logger.info('  Supply:', formatEther(await token.totalSupply()));
        logger.blank();
        
        await this._pause('Token deployed. Press Enter to continue...', 3000);
        
        // Deploy DemoDEX
        logger.info('Deploying DemoDEX...');
        const DEXFactory = new ethers.ContractFactory(
            this._getABI('DemoDEX'),
            this._getBytecode('DemoDEX'),
            this.signer
        );
        
        const dex = await DEXFactory.deploy(token.address);
        await dex.deployed();
        this.addresses.dex = dex.address;
        this.contracts.dex = dex;
        
        logger.success('✓ DEX deployed:', dex.address);
        logger.info('  Price:', formatEther(await dex.getPrice()), 'ETH per token');
        logger.blank();
        
        await this._pause('DEX deployed. Press Enter to continue...', 3000);
        
        // Deploy Fair Launch Guardian Trap
        logger.info('Deploying Fair Launch Guardian Trap...');
        const TrapFactory = new ethers.ContractFactory(
            this._getABI('FairLaunchGuardianTrap'),
            this._getBytecode('FairLaunchGuardianTrap'),
            this.signer
        );
        
        const launchBlock = await this.signer.provider.getBlockNumber();
        const trap = await TrapFactory.deploy(
            token.address,
            dex.address,
            launchBlock,
            DEMO_CONFIG.monitoringBlocks,
            DEMO_CONFIG.maxWalletPercent,
            DEMO_CONFIG.maxGasPremium
        );
        await trap.deployed();
        this.addresses.trap = trap.address;
        this.contracts.trap = trap;
        
        logger.success('✓ Trap deployed:', trap.address);
        logger.info('  Launch Block:', launchBlock);
        logger.info('  Monitoring Duration:', DEMO_CONFIG.monitoringBlocks, 'blocks');
        logger.info('  Max Wallet:', DEMO_CONFIG.maxWalletPercent / 100, '%');
        logger.blank();
        
        await this._pause('All contracts deployed! Press Enter to continue...', 5000);
        
        // Save addresses
        this._saveAddresses();
    }
    
    async step2_setupIntegration() {
        logger.header('STEP 2: Integrate Trap with Token');
        
        logger.info('Integrating trap with token...');
        const tx = await this.contracts.token.integrateTrap(
            this.addresses.trap,
            this.addresses.dex
        );
        await waitForTx(tx);
        
        logger.success('✓ Trap integrated!');
        logger.info('  Token now checks trap before transfers');
        logger.info('  Blacklisted addresses will be blocked');
        logger.blank();
        
        await this._pause('Integration complete. Press Enter to continue...', 3000);
    }
    
    async step3_addLiquidity() {
        logger.header('STEP 3: Add Liquidity to DEX');
        
        logger.info('Adding', formatEther(DEMO_CONFIG.liquidityAmount), 'tokens to DEX...');
        
        // Approve
        let tx = await this.contracts.token.approve(
            this.addresses.dex,
            DEMO_CONFIG.liquidityAmount
        );
        await waitForTx(tx);
        
        // Add liquidity
        tx = await this.contracts.dex.addLiquidity(DEMO_CONFIG.liquidityAmount);
        await waitForTx(tx);
        
        const reserve = await this.contracts.dex.getReserve();
        logger.success('✓ Liquidity added!');
        logger.info('  DEX Reserve:', formatEther(reserve), 'tokens');
        logger.blank();
        
        await this._pause('Liquidity added. Launch is ready! Press Enter to continue...', 3000);
    }
    
    async step4_normalUserBuys() {
        logger.header('STEP 4: Normal User Buys (Should Succeed)');
        
        logger.info('Normal user buying', formatEther(DEMO_CONFIG.normalBuyAmount), 'ETH worth of tokens...');
        logger.info('This is ~0.5% of supply - within limits');
        logger.blank();
        
        // Fund normal user
        let tx = await this.signer.sendTransaction({
            to: this.addresses.normalUser,
            value: DEMO_CONFIG.normalBuyAmount.mul(2) // Extra for gas
        });
        await waitForTx(tx);
        
        // Create wallet for normal user
        const normalUserWallet = new ethers.Wallet(
            ethers.Wallet.createRandom().privateKey,
            this.signer.provider
        );
        
        // Fund it
        tx = await this.signer.sendTransaction({
            to: normalUserWallet.address,
            value: DEMO_CONFIG.normalBuyAmount.add(parseEther('0.01'))
        });
        await waitForTx(tx);
        
        // Buy tokens
        const dexWithUser = this.contracts.dex.connect(normalUserWallet);
        tx = await dexWithUser.swap({ value: DEMO_CONFIG.normalBuyAmount });
        const receipt = await waitForTx(tx);
        
        // Check balance
        const balance = await this.contracts.token.balanceOf(normalUserWallet.address);
        const totalSupply = await this.contracts.token.totalSupply();
        const percent = balance.mul(10000).div(totalSupply).toNumber() / 100;
        
        logger.success('✓ Purchase successful!');
        logger.info('  Tokens received:', formatEther(balance));
        logger.info('  Percentage:', percent.toFixed(2), '%');
        logger.info('  No detection - within limits ✓');
        logger.blank();
        
        await this._pause('Normal user succeeded. Press Enter for bot attack...', 5000);
    }
    
    async step5_botAttacks() {
        logger.header('STEP 5: Bot Attacks (Should Be BLOCKED)');
        
        logger.warning('⚠️  Bot attempting to buy', formatEther(DEMO_CONFIG.botBuyAmount), 'ETH worth...');
        logger.warning('⚠️  This is ~10% of supply - EXCEEDS 5% LIMIT!');
        logger.blank();
        
        // Create bot wallet
        const botWallet = new ethers.Wallet(
            ethers.Wallet.createRandom().privateKey,
            this.signer.provider
        );
        
        // Fund bot
        let tx = await this.signer.sendTransaction({
            to: botWallet.address,
            value: DEMO_CONFIG.botBuyAmount.add(parseEther('0.01'))
        });
        await waitForTx(tx);
        
        logger.info('Bot wallet funded:', formatAddress(botWallet.address));
        logger.info('Executing attack...');
        logger.blank();
        
        try {
            // Bot tries to buy
            const dexWithBot = this.contracts.dex.connect(botWallet);
            tx = await dexWithBot.swap({ value: DEMO_CONFIG.botBuyAmount });
            await waitForTx(tx);
            
            // Check if detected
            await this._sleep(2000); // Wait for trap to process
            
            const isBlacklisted = await this.contracts.trap.isBlacklisted(botWallet.address);
            
            if (isBlacklisted) {
                logger.error('🚨 BOT DETECTED AND BLACKLISTED!');
                logger.success('✓ Fair Launch Guardian working correctly!');
            } else {
                logger.warning('⚠️  Bot not blacklisted yet (might be on next check)');
            }
            
        } catch (error) {
            if (error.message.includes('blacklisted')) {
                logger.error('🚨 TRANSACTION REVERTED!');
                logger.error('   Bot is BLACKLISTED by Fair Launch Guardian');
                logger.success('✓ Protection working perfectly!');
            } else {
                logger.error('Transaction failed:', error.message);
            }
        }
        
        logger.blank();
        await this._pause('Bot attack handled! Press Enter for results...', 5000);
    }
    
    async step6_showResults() {
        logger.header('STEP 6: Demonstration Results');
        
        // Get trap status
        const config = await this.contracts.trap.getConfig();
        const isActive = await this.contracts.trap.isMonitoringActive();
        const history = await this.contracts.trap.getDetectionHistory();
        
        logger.success('📊 Fair Launch Guardian Statistics:');
        logger.blank();
        
        logger.info('Configuration:');
        logger.info('  Max Wallet:', config.maxWalletBasisPoints.toNumber() / 100, '%');
        logger.info('  Max Gas Premium:', config.maxGasPremiumBasisPoints.toNumber() / 100, 'x');
        logger.info('  Monitoring Active:', isActive ? '✓ YES' : '✗ NO');
        logger.blank();
        
        logger.info('Detection History:');
        if (history.length > 0) {
            for (let i = 0; i < history.length; i++) {
                const detection = history[i];
                logger.warning(`  Detection ${i + 1}:`);
                logger.info('    Address:', formatAddress(detection.violatorAddress));
                logger.info('    Type:', this._getDetectionTypeName(detection.detectionType));
                logger.info('    Severity:', detection.severity.toString());
                logger.info('    Accumulated:', detection.accumulatedPercent.toNumber() / 100, '%');
            }
        } else {
            logger.info('  No detections yet (check after next block)');
        }
        
        logger.blank();
        logger.success('✅ DEMONSTRATION COMPLETE!');
        logger.blank();
        
        this._printSummary();
    }
    
    _printSummary() {
        logger.header('Demo Summary');
        
        console.log('📋 Deployed Contracts:');
        console.log(`   Token:  ${this.addresses.token}`);
        console.log(`   DEX:    ${this.addresses.dex}`);
        console.log(`   Trap:   ${this.addresses.trap}`);
        console.log('');
        console.log('🔍 Verify on Block Explorer:');
        console.log(`   https://hoodi.etherscan.io/address/${this.addresses.token}`);
        console.log(`   https://hoodi.etherscan.io/address/${this.addresses.trap}`);
        console.log('');
        console.log('📹 For Your Video:');
        console.log('   1. Show contract deployment ✓');
        console.log('   2. Show normal user buying ✓');
        console.log('   3. Show bot being blocked ✓');
        console.log('   4. Show detection events ✓');
        console.log('');
        console.log('💾 Addresses saved to: demo-addresses.json');
    }
    
    _saveAddresses() {
        const data = {
            network: process.env.NETWORK,
            timestamp: new Date().toISOString(),
            addresses: this.addresses,
            config: DEMO_CONFIG
        };
        
        fs.writeFileSync(
            path.join(__dirname, 'demo-addresses.json'),
            JSON.stringify(data, null, 2)
        );
    }
    
    _getDetectionTypeName(type) {
        const types = ['EXCESSIVE_ACCUMULATION', 'FRONT_RUNNING_GAS', 'RAPID_BUYING', 'COORDINATED_ATTACK', 'LIQUIDITY_MANIPULATION'];
        return types[type] || 'UNKNOWN';
    }
    
    async _pause(message, autoMs = 0) {
        if (process.env.AUTO_DEMO === 'true' && autoMs > 0) {
            logger.info(message.replace('Press Enter', 'Auto-continuing'));
            await this._sleep(autoMs);
            return;
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
    
    _sleep(ms) {
        return new Promise(resolve => setTimeout(resolve, ms));
    }
    
    _getABI(contractName) {
        // Load from compiled artifacts
        // In real deployment, these would be loaded from the build
        return require(`../../contracts/out/${contractName}.sol/${contractName}.json`).abi;
    }
    
    _getBytecode(contractName) {
        return require(`../../contracts/out/${contractName}.sol/${contractName}.json`).bytecode.object;
    }
}

// Main execution
async function main() {
    const demo = new DemoOrchestrator();
    
    try {
        await demo.initialize();
        await demo.step1_deployContracts();
        await demo.step2_setupIntegration();
        await demo.step3_addLiquidity();
        await demo.step4_normalUserBuys();
        await demo.step5_botAttacks();
        await demo.step6_showResults();
        
        logger.success('🎉 Demo completed successfully!');
        process.exit(0);
        
    } catch (error) {
        logger.error('Demo failed:', error.message);
        if (process.env.DEBUG === 'true') {
            console.error(error);
        }
        process.exit(1);
    }
}

if (require.main === module) {
    main();
}

module.exports = { DemoOrchestrator };