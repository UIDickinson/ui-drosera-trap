# Fair Launch Guardian Trap V2 - Drosera Compatible

## Overview

This is a **complete rewrite** of the Fair Launch Guardian Trap to be fully compatible with Drosera's stateless trap architecture. The V2 implementation follows all recommendations from the Drosera review.

## Architecture

### Three-Contract System

```
┌─────────────────────────────────────────────────────────────┐
│                      DROSERA FLOW                           │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  1. Drosera calls collect() on shadow fork                  │
│     └─> FairLaunchGuardianTrap.collect()                   │
│         └─> Reads on-chain state (ERC20, pool)             │
│         └─> Returns encoded snapshot                        │
│                                                             │
│  2. Drosera calls shouldRespond() with history window       │
│     └─> FairLaunchGuardianTrap.shouldRespond(data[])      │
│         └─> Pure function - analyzes data[] only            │
│         └─> Returns (true, payload) if violation detected   │
│                                                             │
│  3. If violation detected, Drosera calls responder          │
│     └─> FairLaunchResponder.handle(payload)               │
│         └─> Executes actions (pause, blacklist, alerts)    │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

### Contracts

#### 1. **FairLaunchGuardianTrap.sol** (Detection)
- **Role:** Pure detection logic
- **Functions:**
  - `collect()` - VIEW function that reads on-chain state
  - `shouldRespond()` - PURE function that analyzes data
- **Features:**
  - ✅ Stateless (no storage variables except immutables)
  - ✅ No constructor args dependency (uses immutables for config)
  - ✅ Deterministic across all operators
  - ✅ Implements ITrap interface correctly
  - ✅ Pure shouldRespond() with no state mutations
  - ✅ Proper input validation

#### 2. **FairLaunchResponder.sol** (Actions)
- **Role:** Execute responses when violations detected
- **Functions:**
  - `handle(bytes)` - Called by Drosera with encoded payload
- **Actions:**
  - Emergency pause on token/pool
  - Blacklist violators
  - Emit alerts
  - Log incident history
- **Features:**
  - ✅ All side effects isolated here
  - ✅ Admin controls for false positives
  - ✅ Incident tracking and history

#### 3. **LaunchDataFeeder.sol** (Optional)
- **Role:** Aggregate swap data on-chain
- **Usage:** Alternative to EventLog filtering
- **Functions:**
  - `recordSwap()` - Called by pool/token or bot
  - `getBlockMetrics()` - Read by trap's collect()
- **Features:**
  - Per-block aggregated metrics
  - Wallet accumulation tracking
  - Gas price monitoring

## Key Improvements from V1

### ❌ V1 Problems
- State variables in trap (breaks consensus)
- Constructor args (Drosera can't deploy)
- `shouldRespond()` mutates state
- Mixed detection + action logic
- Non-deterministic inputs (tx.gasprice)
- No ITrap interface implementation

### ✅ V2 Solutions
- Completely stateless trap
- Immutable config only
- Pure `shouldRespond()` function
- Separated trap/responder contracts
- Deterministic data sources
- Proper ITrap implementation

## Detection Capabilities

### Current Detections

1. **Liquidity Drain Detection**
   - Monitors pool balance changes
   - Triggers on >10% single-block drain
   - Severity based on drain magnitude

2. **Supply Manipulation Detection**
   - Monitors total supply changes
   - Triggers on >5% single-block change
   - Detects coordinated minting/burning

3. **Multi-Block Pattern Detection**
   - Analyzes trends over time window
   - Detects consistent liquidity drainage
   - Requires 3+ consecutive suspicious blocks

### Detection Types

```solidity
0 = EXCESSIVE_ACCUMULATION      // Single wallet accumulates too much
1 = FRONT_RUNNING_GAS           // Suspicious gas price patterns
2 = RAPID_BUYING                // Rapid consecutive buys
3 = COORDINATED_ATTACK          // Multiple wallets acting in sync
4 = LIQUIDITY_MANIPULATION      // Pool liquidity being drained
```

## Deployment Guide

### Prerequisites

```bash
# Install Foundry
curl -L https://foundry.paradigm.xyz | bash
foundryup

# Install Drosera CLI
# (Follow Drosera documentation)
```

### Step 1: Deploy Responder

```bash
# Deploy responder first
forge create src/v2/FairLaunchResponder.sol:FairLaunchResponder \
  --constructor-args \
    <DROSERA_ADDRESS> \
    <TOKEN_ADDRESS> \
    <POOL_ADDRESS> \
  --rpc-url $RPC_URL \
  --private-key $PRIVATE_KEY
```

Save the deployed responder address.

### Step 2: Deploy Trap (Optional - Drosera can deploy)

```bash
# If you want to pre-deploy the trap
forge create src/v2/FairLaunchGuardianTrap.sol:FairLaunchGuardianTrap \
  --constructor-args \
    <TOKEN_ADDRESS> \
    <POOL_ADDRESS> \
  --rpc-url $RPC_URL \
  --private-key $PRIVATE_KEY
```

**Note:** Drosera can deploy the trap for you. The constructor args are a temporary compromise - see "Production Notes" below.

### Step 3: Configure TOML

Edit `drosera.toml`:

```toml
[traps.fair_launch_guardian_v2]
path = "out/FairLaunchGuardianTrap.sol/FairLaunchGuardianTrap.json"
response_contract = "<YOUR_DEPLOYED_RESPONDER_ADDRESS>"
response_function = "handle(bytes)"
block_sample_size = 5
cooldown_period_blocks = 20
```

### Step 4: Build and Deploy

```bash
# Build contracts
forge build

# Deploy via Drosera CLI
drosera-cli deploy drosera.toml
```

## Configuration

### Tuning block_sample_size

- **1 block** - Single block analysis only (fast, less context)
- **2 blocks** - Can compare current vs previous
- **3-5 blocks** - Pattern detection over time (recommended)
- **6+ blocks** - Deep historical analysis (slower)

**Recommendation:** Start with 5 for good balance.

### Tuning cooldown_period_blocks

- **Short (5-10)** - More responsive, may spam on persistent issues
- **Medium (20-50)** - Balanced (recommended)
- **Long (100+)** - Conservative, may miss rapid attacks

**Recommendation:** 20 blocks (~5 minutes on most chains)

## Testing

### Local Testing

```bash
# Run tests
forge test -vvv

# Test specific contract
forge test --match-contract FairLaunchGuardianTrapTest -vvv
```

### Testnet Deployment

1. Deploy to testnet first (e.g., Sepolia, Goerli)
2. Monitor for 24-48 hours
3. Verify operator consensus
4. Check for false positives
5. Tune thresholds if needed

## Production Notes

### Constructor Args Issue

The current implementation has constructor args for `TOKEN_ADDRESS` and `LIQUIDITY_POOL`. This is a **temporary compromise** for development.

**For production Drosera compatibility:**

**Option A:** Hardcode addresses in the contract
```solidity
address public constant TOKEN_ADDRESS = 0x...;
address public constant LIQUIDITY_POOL = 0x...;
```

**Option B:** Pass via collect() encoded data
```solidity
// Encode config in collect() return
return abi.encode(config, snapshot);
```

**Option C:** Use factory pattern with CREATE2
- Deploy different trap instances per token
- Use CREATE2 for deterministic addresses

### Data Feeding Strategy

You have three options:

#### Option 1: EventLog Filtering (Recommended)
- Most deterministic
- No external dependencies
- Drosera provides native support
- See review for implementation

#### Option 2: Simple State Reading (Current)
- Read ERC20 balanceOf() and totalSupply()
- Works with any token
- No integration needed
- Limited detection capabilities

#### Option 3: Feeder Contract
- Most flexible
- Requires integration with token/pool
- Can track detailed metrics
- Centralization risk

## Security Considerations

### Trap Security
- ✅ No reentrancy risk (pure/view only)
- ✅ No state mutation exploits
- ✅ Input validation on all data
- ✅ Deterministic across operators

### Responder Security
- ⚠️ Only Drosera can call handler
- ⚠️ Owner can override (for false positives)
- ⚠️ Pause/blacklist are powerful - test thoroughly
- ⚠️ Consider timelock for admin functions

### Operational Security
- Monitor responder events closely
- Have incident response plan
- Test false positive recovery
- Document emergency procedures

## Monitoring

### Key Events to Monitor

```solidity
// From Responder
event LaunchGuardianIncident(...)  // Violation detected
event EmergencyPauseTriggered(...) // Pause activated
event AddressBlacklisted(...)      // Address blacklisted
```

### Metrics to Track

- Total incidents triggered
- False positive rate
- Response time (detection → action)
- Severity distribution
- Cooldown effectiveness

## Troubleshooting

### Trap Not Triggering
1. Check `collect()` returns valid data
2. Verify `shouldRespond()` thresholds
3. Increase block_sample_size for more data
4. Check operator logs

### False Positives
1. Review incident details via `getIncident()`
2. Adjust detection thresholds in trap
3. Increase cooldown period
4. Use responder's `unpause()` or `removeFromBlacklist()`

### Operator Consensus Issues
1. Ensure trap is truly stateless
2. Check for non-deterministic inputs
3. Verify all operators see same on-chain state
4. Review Drosera operator logs

## Roadmap

### Phase 2 Enhancements
- [ ] Implement EventLog filtering
- [ ] Add more detection patterns
- [ ] Wallet clustering analysis
- [ ] Gas price manipulation detection

### Phase 3 Features
- [ ] Multi-pool monitoring
- [ ] Cross-chain support
- [ ] ML-based anomaly detection
- [ ] Automated threshold tuning

## Resources

- [Drosera Documentation](https://docs.drosera.io)
- [Review Document](../drosera_review.md)
- [ITrap Interface Spec](../contracts/src/interfaces/ITrap.sol)

## License

MIT

## Support

For issues or questions:
1. Review the [drosera_review.md](../drosera_review.md) document
2. Check Drosera documentation
3. Open GitHub issue with trap logs
