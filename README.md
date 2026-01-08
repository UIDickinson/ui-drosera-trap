# Fair Launch Guardian V2 - Drosera Trap

[![Tests](https://img.shields.io/badge/tests-36%2F36%20passing-brightgreen)](contracts/test)
[![Bjorn Review](https://img.shields.io/badge/%20Review-Compliant%20✓-blue)](drosera_review.md)
[![Deployed](https://img.shields.io/badge/Hoodi%20Testnet-Deployed-orange)](DEPLOYMENT_SUMMARY.md)
[![Solidity](https://img.shields.io/badge/Solidity-0.8.20-363636)](contracts/foundry.toml)

**Standard Drosera trap protecting token launches from sniper bots, MEV attacks, and unfair distribution.**

> **Review Compliant** - Complete V2 rewrite meeting all Drosera architecture requirements

---

## Function

| Launch Type | Protection |
|-------------|------------|
| **DEX Fair Launches** | Detects excessive accumulation by single wallets |
| **Memecoin Launches** | Identifies coordinated bot swarms |
| **ICO/Token Sales** | Prevents whale dominance patterns |
| **Stealth Launches** | Monitors suspicious trading patterns |

---

## Contents

- [Architecture Overview](#architecture-overview)
- [Strategy Comparison](#strategy-comparison)
- [Quick Start](#quick-start)
- [Prerequisites](#prerequisites)
- [Installation](#installation)
- [Configuration](#configuration)
- [Building & Testing](#building--testing)
- [Deployment](#deployment)
- [Registration with Drosera](#registration-with-drosera)
- [Troubleshooting](#troubleshooting)
- [Deployed Contracts](#deployed-contracts)
- [Contributing](#contributing)
- [Support & Documentation](#support--documentation)

---

## Architecture Overview

**V2 Architecture: Stateless Traps + Separate Responder**


### Key Architectural Changes (V1 → V2)

| Aspect | V1 (Deprecated) | V2 (Current) |
|--------|-----------------|--------------|
| **State** | Stateful (mappings, arrays) | Stateless (compile-time constants) |
| **Constructor** | Required parameters | No parameters |
| **Detection** | In trap + execution | Detection only |
| **Actions** | Internal to trap | Separate responder |
| **shouldRespond** | Impure (state changes) | Pure (no side effects) |
| **ITrap** | Not implemented | Fully compliant |

---

## Strategy Comparison


Choose the trap strategy that fits your needs:

| Feature | **Simple** | **EventLog** (recommended) | **Advanced** |
|---------|-----------|--------------|-------------|
| **Complexity** | Low | Medium | High |
| **Gas Cost** | Lowest | Medium | Highest |
| **Detection** | Basic drain | Swap patterns | Comprehensive |
| **Integration** | None | None | None |
| **Recommended For** | Testing | Production | High-value launches |
| **Tests Passing** | 8/8 | 2/2 | 2/2 |

### Strategy Details

#### 1 **Simple** - Basic State Reading
- Easiest to deploy
- No integration required  
- Monitors `totalSupply()` and `balanceOf(pool)`
- Limited detection (liquidity drains only)
- **Use Case:** Quick testing, basic protection

#### 2 **EventLog**  **(Recommended)**
- **Used recommended path as per corrections meted out**
- Most deterministic
- No integration required
- Detailed trade analysis via Swap events
- Detects accumulation + coordinated attacks
- **Use Case:** Production deployments

#### 3 **Advanced** - Comprehensive Detection
- Maximum detection capabilities
- Threat intelligence tracking
- Coordinated attack detection
- Confidence-based response thresholds
- Higher complexity
- Higher gas costs
- **Use Case:** High-value launches requiring maximum protection

---

## Quick Start

```bash
# 1. Clone repository
git clone https://github.com/UIDickinson/ui-drosera-trap.git
cd ui-drosera-trap

# 2. Install dependencies
cd contracts && forge install

# 3. Set up environment
cp ../env.example ../.env
# Edit .env with your PRIVATE_KEY

# 4. Build contracts
forge build

# 5. Run tests
forge test
# Expected: 36/36 tests passing ✅

# 6. Deploy (if needed)
export PRIVATE_KEY=0x...
forge script script/DeployEventLogTrap.s.sol:DeployEventLogTrap \
  --rpc-url https://ethereum-hoodi-rpc.publicnode.com \
  --broadcast

# 7. Register with Drosera
# See "Registration with Drosera" section below
```

---

## Prerequisites

### Required Tools

- **Foundry** (Forge + Cast) - v0.2.0+
  ```bash
  curl -L https://foundry.paradigm.xyz | bash
  foundryup
  forge --version
  ```

- **Git**
  ```bash
  git --version
  ```

### Accounts & Keys

- **Hoodi Testnet Account** with test ETH
  - Get testnet ETH: https://cloud.google.com/application/web3/faucet/ethereum/hoodi
  - Private key for deployment (keep secure!)

### Network Information

- **Hoodi Testnet (Chain ID: 560048)**
  - RPC: `https://ethereum-hoodi-rpc.publicnode.com`
  - Alternative: `https://relay.hoodi.drosera.io`
  - Drosera Address: `0x91cB447BaFc6e0EA0F4Fe056F5a9b1F14bb06e5D`

---

## Installation

### 1. Clone the Repository

```bash
git clone https://github.com/UIDickinson/ui-drosera-trap.git
cd ui-drosera-trap
```

### 2. Install Foundry Dependencies

```bash
cd contracts
forge install
```

This installs:
- `forge-std` - Foundry standard library

**Verify installation:**
```bash
forge --version
ls lib/forge-std  # Should show forge-std files
```

---

## Configuration

### Understanding V2 Configuration

**V2 traps use compile-time constants** (not environment variables):

```solidity
// In trap source code:
address public constant TOKEN_ADDRESS = 0xBE820752AE8E48010888E89862cbb97aF506d183;
address public constant LIQUIDITY_POOL = 0xE225187b6f9F107d558B9585D5F5D94Aae6F4F71;
```

This is **required by Drosera** - traps must have no constructor arguments.

### Step 1: Choose Your Strategy

1. **Simple**: `contracts/src/v2/FairLaunchGuardianTrapSimple.sol`
2. **EventLog**: `contracts/src/v2/FairLaunchGuardianTrapEventLog.sol`
3. **Advanced**: `contracts/src/v2/FairLaunchGuardianTrapAdvanced.sol`

### Step 2: Update Trap Addresses (If Deploying New)

If you want to monitor a different token/pool, edit the trap file:

```solidity
// Replace these addresses in your chosen trap file:
address public constant TOKEN_ADDRESS = 0xYourTokenAddress;
address public constant LIQUIDITY_POOL = 0xYourPoolAddress;
```

### Step 3: Set Up Environment (For Deployment Only)

```bash
cp env.example .env
```

Edit `.env`:
```bash
PRIVATE_KEY=0x...  # Your private key (NEVER commit this!)
```

**Security:** The `.env` file is already in `.gitignore`. Keep your private key secure!

---

## Building & Testing

### Build Contracts

```bash
cd contracts
forge build
```

**Expected output:**
```
Compiler run successful with warnings:
...
```

Minor warnings about function mutability are normal and safe.

### Run All Tests

```bash
forge test
```

**Expected Results:**
```
Test result: ok. 36 passed; 0 failed ✅
```

### Run Tests with Details

```bash
forge test -vv  # Detailed output
forge test -vvvv  # Very detailed (traces)
```

### Test Coverage

```bash
forge coverage
```

### Run Specific Test Suite

```bash
# Test specific strategy
forge test --match-path test/v2/FairLaunchGuardianTrapEventLog.t.sol

# Test responder
forge test --match-path test/v2/FairLaunchResponder.t.sol

# Integration tests
forge test --match-path test/v2/Integration.t.sol
```

---

## Deployment

### Option 1: Use Already Deployed Contracts (Recommended)

We've already deployed a complete demo environment on Hoodi testnet:

```bash
# See full details
cat DEPLOYMENT_SUMMARY.md
```

**Deployed Addresses:**
- **EventLog Trap**: `0x53663707d165458B534eADCb6715BC0EEfA1f212`
- **Responder**: `0xFAb32eC4e0B41fBc9Ec4E3f4BA2D73aF12e18794`
- **DemoToken**: `0xBE820752AE8E48010888E89862cbb97aF506d183`
- **DemoDEX**: `0xE225187b6f9F107d558B9585D5F5D94Aae6F4F71`

**Skip to:** [Registration with Drosera](#registration-with-drosera)

### Option 2: Deploy Your Own Demo Environment

Deploy test token, DEX, responder, and trap:

```bash
cd contracts
export PRIVATE_KEY=0x...

forge script script/DeployDemo.s.sol:DeployDemo \
  --rpc-url https://ethereum-hoodi-rpc.publicnode.com \
  --broadcast \
  -vv
```

This deploys:
1. `DemoToken` - Test ERC20 (1M supply)
2. `DemoDEX` - Simple liquidity pool
3. `FairLaunchResponder` - Action executor
4. `SimpleTrap` - Basic monitoring trap

**After deployment**, update trap addresses in source code (see Configuration section).

### Option 3: Deploy EventLog Trap Only

If you have an existing token/pool and responder:

```bash
cd contracts

# 1. Update addresses in src/v2/FairLaunchGuardianTrapEventLog.sol
# Edit TOKEN_ADDRESS and LIQUIDITY_POOL constants

# 2. Rebuild
forge build

# 3. Deploy
export PRIVATE_KEY=0x...
forge script script/DeployEventLogTrap.s.sol:DeployEventLogTrap \
  --rpc-url https://ethereum-hoodi-rpc.publicnode.com \
  --broadcast \
  -vv
```

### Verify Deployment

Check that contracts are configured correctly:

```bash
# Check trap configuration
cast call <TRAP_ADDRESS> "getConfig()(address,address,bool)" \
  --rpc-url https://ethereum-hoodi-rpc.publicnode.com

# Check token supply
cast call <TOKEN_ADDRESS> "totalSupply()(uint256)" \
  --rpc-url https://ethereum-hoodi-rpc.publicnode.com

# Check pool balance
cast call <TOKEN_ADDRESS> "balanceOf(address)(uint256)" <POOL_ADDRESS> \
  --rpc-url https://ethereum-hoodi-rpc.publicnode.com
```

---

## Registration with Drosera

After deployment, register your trap with Drosera to activate monitoring.

### Option 1: Drosera CLI (Recommended)

```bash
# Install CLI (if not installed)
curl -sSL https://get.drosera.io | sh

# Register trap
drosera register 0x53663707d165458B534eADCb6715BC0EEfA1f212 \
  --config drosera.toml \
  --network hoodi
```

### Option 2: Drosera Web Interface

1. Visit: https://app.drosera.io
2. Connect your wallet
3. Click "Register Trap"
4. Enter trap address: `0x53663707d165458B534eADCb6715BC0EEfA1f212`
5. Set responder: `0xFAb32eC4e0B41fBc9Ec4E3f4BA2D73aF12e18794`
6. Configure parameters from `drosera.toml`:
   - `block_sample_size`: 5
   - `cooldown_period_blocks`: 20
   - `min_number_of_operators`: 1
   - `max_number_of_operators`: 3

### Configuration File

The `drosera.toml` file is pre-configured with all three strategies. Choose your preferred trap:

```toml
# Option 1: Simple (testing)
[traps.fair_launch_simple]

# Option 2: EventLog (recommended)
[traps.fair_launch_eventlog]

# Option 3: Advanced (comprehensive)
[traps.fair_launch_advanced]
```

---

## Troubleshooting

### Build Errors

#### Error: `forge-std not found`

**Solution:**
```bash
cd contracts
forge install foundry-rs/forge-std
```

#### Error: Stack too deep

**Solution:** This is already configured in `foundry.toml`:
```toml
via_ir = true  # Enables IR optimization
```

If you still get the error, try:
```bash
forge clean
forge build
```

#### Error: Solc version mismatch

**Solution:**
```bash
forge build --force  # Force recompilation
```

---

### Test Failures

#### Tests fail with "Cooldown period active"

**Cause:** Tests need block progression between calls.

**Solution:** Already fixed in V2 - tests add `vm.roll(block.number + 10)` between operations.

#### Can't reproduce coordinated attack detection

**Cause:** Test data must include wallets with multiple buys.

**Solution:** Already fixed - tests now provide 2+ buys per wallet to meet detection threshold.

---

### Deployment Issues

#### Transaction reverts: "Insufficient balance"

**Solution:**
1. Get testnet ETH from faucet: https://cloud.google.com/application/web3/faucet/ethereum/hoodi
2. Check balance: `cast balance <YOUR_ADDRESS> --rpc-url https://ethereum-hoodi-rpc.publicnode.com`

#### Error: "No constructor args allowed"

**Explanation:** This is correct for V2! Traps have no constructor parameters.

**Solution:** Use compile-time constants in source code instead.

---

### Runtime Issues

#### Trap doesn't detect attacks

**Check:**
1. Is trap registered with Drosera? (Check Drosera dashboard)
2. Are operators running? (Requires Drosera network)
3. Is `block_sample_size` sufficient? (Need history window)
4. Check trap configuration: `cast call <TRAP> "getConfig()"`

#### Responder not executing actions

**Check:**
1. Trap configured with correct responder address in `drosera.toml`
2. Drosera has permission to call responder
3. Check responder owner: `cast call <RESPONDER> "owner()"`
4. Review incident history: `cast call <RESPONDER> "getIncident(uint256)"`

---

### Configuration Issues

#### Wrong addresses in trap

**Solution:** Update compile-time constants and rebuild:
```bash
# Edit src/v2/FairLaunchGuardianTrapEventLog.sol
# Change TOKEN_ADDRESS and LIQUIDITY_POOL

forge clean
forge build
```

#### Need to test different thresholds

**Solution:** Responder thresholds can be adjusted by owner:
```solidity
// In responder contract
responder.setConfidenceThresholds(90, 80, 60);
```

---

## Deployed Contracts

### Hoodi Testnet (Chain ID: 560048)

| Contract | Address | Purpose |
|----------|---------|---------|
| **EventLog Trap** | `0x53663707d165458B534eADCb6715BC0EEfA1f212` | Recommended production trap |
| **Simple Trap** | `0xC25C47e7CE52302Ef2c85620c1dfd8d7BcE4096C` | Basic testing trap |
| **Responder** | `0xFAb32eC4e0B41fBc9Ec4E3f4BA2D73aF12e18794` | Action executor |
| **DemoToken** | `0xBE820752AE8E48010888E89862cbb97aF506d183` | Test ERC20 |
| **DemoDEX** | `0xE225187b6f9F107d558B9585D5F5D94Aae6F4F71` | Test liquidity pool |

**Full deployment details:** [DEPLOYMENT_SUMMARY.md](DEPLOYMENT_SUMMARY.md)

**Transaction hashes available in:** `contracts/broadcast/`

---

## Contributing

### For Project Launchers

Protect your token launch from:
- Sniper bots (first-block accumulation)
- Whale accumulation (excessive holdings)
- Front-running attacks (MEV bots)
- Coordinated bot swarms (Sybil attacks)

### For Developers

**Ways to Contribute:**

1. **New Detection Patterns**
   - Study emerging bot behaviors
   - Implement new detection algorithms
   - Add comprehensive tests
   - Submit PR with documentation

2. **Strategy Improvements**
   - Optimize gas usage
   - Enhance detection accuracy
   - Improve false positive rates
   - Add new trap strategies

3. **Documentation**
   - Improve setup guides
   - Add deployment examples
   - Create video tutorials
   - Translate to other languages

4. **Testing & QA**
   - Find edge cases
   - Report bugs with reproducible examples
   - Suggest threshold improvements
   - Test on different networks

### For Researchers

Study and analyze:
- Bot detection accuracy metrics
- Gas cost optimization
- Pattern effectiveness across launch types
- DeFi security automation trade-offs

**Share your findings:** Open issues or discussions on GitHub

---

## Review Compliance

This V2 architecture fully addresses all requirements from [Bjorn Agnesi's professional review](drosera_review.md):

| Requirement | Status |
|-------------|--------|
| ITrap interface implementation | Implemented |
| Stateless architecture (no state storage) | Complete |
| No constructor arguments | Removed |
| Pure `shouldRespond()` function | Implemented |
| Separate responder contract | Deployed |
| EventLog filtering support | Recommended strategy |
| Deterministic logic | Verified |
| No state mutations in trap | Confirmed |

**Review Date:** December 5, 2025  
**Compliance Date:** January 8, 2026  
**All 36 tests passing**

---

## Project Roadmap

### Phase 1: V2 Architecture (Complete)
- Stateless trap implementation
- Three strategy options
- Separate responder contracts
- Review compliance
- 36/36 tests passing
- Hoodi testnet deployment

### Phase 2: Production Hardening (In Progress)
- [ ] Security audit
- [ ] Mainnet deployment
- [ ] Operator dashboard
- [ ] Real-world testing

### Phase 3: Ecosystem Integration
- [ ] Integration with launch platforms (Pinksale, etc.)
- [ ] Multi-chain support (Arbitrum, Base, etc.)
- [ ] Enhanced analytics dashboard
- [ ] Automated alert system

### Future Enhancements
- [ ] Machine learning pattern detection
- [ ] Cross-DEX monitoring
- [ ] Mobile app for alerts
- [ ] Governance features

---

## Support & Documentation

### Official Resources
- **Drosera Network**: https://drosera.io
- **Drosera Docs**: https://dev.drosera.io
- **Drosera Examples**: https://github.com/drosera-network/examples
- **Discord Community**: https://discord.gg/drosera

### Development Tools
- **Foundry Book**: https://book.getfoundry.sh
- **Solidity Docs**: https://docs.soliditylang.org
- **Hoodi Testnet**: https://ethereum-hoodi-rpc.publicnode.com

### Project Resources
- **GitHub Issues**: Report bugs and request features
- **Discussions**: Ask questions and share ideas
- **Pull Requests**: Contribute improvements

---

## Acknowledgments

- **Bjorn Agnesi** - Professional review and architecture guidance
- **Drosera Network** - Trap infrastructure and operator network
- **Foundry Team** - Development tooling
- **Community Contributors** - Testing and feedback

---

**Version:** 2.0.0  
**Last Updated:** January 8, 2026  
**Status:** Deployed on Hoodi Testnet
**Test Coverage:** 36/36 passing
**Bjorn Review:** Compliant
