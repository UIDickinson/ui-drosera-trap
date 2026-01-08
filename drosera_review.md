# Comprehensive Drosera Project Review - Complete Supervisor Feedback

**Reviewer:** Bjorn Agnesi  
**Date:** December 5, 2025  
**Project:** Fair Launch Guardian Trap  
**Repository:** https://github.com/UIDickinson/ui-drosera-trap

---

## Important Note from Reviewer

> "Hi @AnonUI, I appears that I have missed your ticket. I could not find it in the archive. But here is your trap review:"

---

## Executive Summary

This is a **good product idea**, but as a Drosera trap it needs a complete rewrite around:
- **Stateless trap architecture**
- **Feeder contract pattern**
- **Separate responder contract**
- **Removal of constructor args**
- **Elimination of state mutation from the trap**

The current contract is an ambitious "launch guardian," but it won't work in Drosera because:

1. ❌ It doesn't implement the `ITrap` interface
2. ❌ It mutates state and "executes" responses inside `shouldRespond` (which must be deterministic/pure)
3. ❌ It relies on in-contract swap recording (`recordSwap`) that Drosera operators will not call
4. ❌ You duplicate the big contract twice and ship extra libs that aren't wired

**Required Action:** Split detection (trap) from action (responder), make the trap deterministic, and feed it data it can actually read at `collect()` time (e.g., via event log filters or simple ERC20 reads), then only return a payload to a responder.

---

## Critical Blocking Issues (Must Fix)

### 1. Wrong Interface + Wrong Mutability

**Drosera expects the exact ITrap interface:**

```solidity
interface ITrap {
    function collect() external view returns (bytes memory);
    function shouldRespond(bytes[] calldata) external pure returns (bool, bytes memory);
}
```

**Your contract issues:**
- ❌ Doesn't import `ITrap`
- ❌ Doesn't declare `is ITrap`
- ❌ Doesn't use `override` modifier
- ❌ `shouldRespond` is `external returns` (not `pure`)
- ❌ It reads/writes state via `_executeResponse`, mappings, arrays, etc.

**That alone makes it incompatible.**

**Fix Required:**
```solidity
contract FairLaunchGuardianTrap is ITrap {
    // Match exact function signatures with override
}
```

---

### 2. Stateful Logic Breaks Operator Determinism

**State variables you're maintaining:**
- `walletAccumulation`
- `buyCountPerAddress`
- `lastBuyBlock`
- `recentSwaps`
- `lastCollectedBlock`
- `detectionHistory`
- `isPaused`
- `blacklistedAddresses`

**Critical Problem:** In Drosera, traps are **deployed fresh on a shadow fork per sampled block**. Those writes don't persist the way you expect across samples, and different operators can observe different state depending on timing/call ordering → **consensus divergence risk**.

**Why This Breaks:**
- State mutations don't persist across operator calls
- Different operators see different states
- Leads to consensus failures
- Can result in operator penalties

**Fix Required:**
- Remove ALL state storage from trap
- Make trap completely stateless
- Derive all data from `bytes[] data` passed to `shouldRespond()`

---

### 3. Constructor Args Are Not Supported

**Your Issue:** Your constructor requires multiple parameters.

**Drosera Requirement:** Drosera deploys traps with **no constructor args**, so this won't even instantiate in the operator environment.

**Fix Required:**
- Remove all constructor parameters
- Use a stateless design that doesn't need initialization
- If configuration is needed, encode it in the feeder contract or pass via `collect()` data

---

### 4. collect() Depends on State That Never Updates

**The Problem:**
- `_getRecentSwapsForCollect()` filters by `lastCollectedBlock`
- But `lastCollectedBlock` is **never updated** in `collect()`
- Even if you tried to update it, `collect()` must be `view` and can't write

**Result:** In practice you'll either:
1. Always return "all swaps since deployment block" (on that shadow fork), OR
2. Always return empty depending on fork state

**Either way: it's not a stable sampling model.**

**Fix Options:**
- Delete the `lastCollectedBlock` filter entirely
- Make "since X" purely from timestamps inside the encoded samples
- Operators pass an array of prior `collect()` outputs for comparison

---

### 5. shouldRespond Executes Actions Inside the Trap (Disqualifying)

**Current Behavior:** `shouldRespond` calls `_executeResponse` which:
- Emits events
- Pauses contracts
- Blacklists addresses
- Mutates arrays

**This breaks determinism and can get operators penalized.**

**Drosera's Model:**
```
Trap detects → returns (true, payload) → Drosera calls responder
```

**Your trap is:**
- Mutating state internally
- Pausing/blacklisting inside the trap

**Drosera Requirement:**
- `shouldRespond` must NOT change state
- Should ideally be `pure`
- Should only compute `(trigger, payload)`

**Fix Required:**
- Move ALL actions (pause, blacklist, alerts) to a **separate responder contract** invoked by Drosera
- `shouldRespond` should only return an encoded `ResponseData` struct
- No state changes, no events, no external calls in `shouldRespond`

---

## Major Design Mismatch

### The Data Availability Problem

**What You're Building:**
Something that requires **live transaction-level data** (buys, gasPrice, patterns).

**How Drosera Works:**
A Drosera trap's `collect()` runs on a **shadow fork** and can read on-chain state, but it can't "see mempool swaps" unless you feed it via:

**Option A:** A **feeder contract** (off-chain bot writes metrics on-chain)

**Option B:** A **target protocol contract** that logs/records swap info on-chain

**Your Current Approach:**
You're halfway: `recordSwap()` is an on-chain feed, but it's:
- Permissioned to pool/token
- Assumes they call it
- That's fine, BUT then the trap must be **stateless** and just read feeder state in `collect()`

### Undeliverable Data Model

**Issue:** You depend on `recordSwap(...)` to populate:
- `recentSwaps`
- `walletAccumulation`
- Other state variables

**Problem:** Off-chain Drosera operators **won't call this**. Unless you actually integrate the token/DEX to call `recordSwap`, your trap will see **empty state everywhere**.

**Realistic Drosera Options:**

1. **Use Drosera's EventFilter** (from `drosera-contracts/Trap.sol`)
   - Read Uniswap `Swap` logs in `collect()`
   - All operations are deterministic
   - Eliminates the need for `recordSwap`

2. **Build a simpler trap** that samples readable on-chain state
   - ERC20 `balanceOf(pool)` deltas
   - `totalSupply`
   - Detect large deltas over `block_sample_size`
   - Already catches "launch rug" dynamics

3. **Off-chain data approach**
   - Move push-style data off-chain
   - Encode it into the planner's payload
   - `collect()` can be a stub in this case

---

## Additional Critical Issues

### 6. Non-Deterministic Inputs

**Issue:** `_estimateAverageGasPrice()` uses `tx.gasprice` inside a `view` `collect()`.

**Problems:**
- This is deterministic per transaction
- But it's NOT "average network gas"
- Depends on the caller transaction
- In off-chain view calls, this is often **zero/undefined**
- Results in **inconsistent values across operators**

**Fix Required:**
- **Remove `tx.gasprice` dependency entirely**
- If gas heuristics are needed:
  - Pass `gasPrice` with each recorded swap, OR
  - Compute average from `gasPrices[]` array in your encoded samples

---

### 7. Planner Safety Issues

**Issue:** `shouldRespond` only checks `data.length < 2`.

**Problem:** If `data[0].length == 0`, `abi.decode` can revert on malformed planner pipelines.

**Fix Required:**
```solidity
if (data.length < 1 || data[0].length == 0) return (false, "");
```

Apply similar checks for any indexed array reads.

**Additional Safety for Windowing:**
```solidity
if (data.length < 2 || data[0].length == 0 || data[1].length == 0) {
    return (false, "");
}
```

---

### 8. Array Loop Performance Issues

**Issue:** Looping through arrays of addresses in `shouldRespond` can be:
- Expensive
- Unpredictable if your feeder returns large arrays

**Impact:**
- Gas consumption varies wildly
- May hit block gas limits
- Causes operator consensus issues

**Fix Required:**
- Limit array sizes in feeder
- Add bounds checking
- Consider aggregated metrics instead of per-address loops

---

### 9. Missing Responder Contract & TOML Configuration

**Issue:** You emit events and set flags in the trap.

**Drosera Requirement:**
- Drosera will call a **responder function on another contract**
- You need:
  - A responder contract with handler function
  - A responder ABI
  - A TOML entry with `response_function` that matches your returned payload

**Fix Required:**
- Create separate responder contract
- Define responder ABI
- Configure TOML with proper `response_function` entry

---

### 10. Code Duplication & Unused Libraries

**Issues Found:**
- Two copies of the giant trap contract included
- Several libraries that aren't wired into live code paths:
  - `AddressValidator`
  - `BotDetection`
  - `LaunchMetrics`

**Fix Required:**
- Trim to **ONE trap implementation**
- Remove **ALL unused libraries and dependencies**
- Keep only what you actually use in the code

---

### 11. Inefficient Ring Buffer Implementation (O(n) Gas)

**Issue:** `_cleanOldSwaps()` shifts the entire array by `removeCount` on every write when size > 100.

**Problems:**
- O(n) gas complexity
- Expensive and unnecessary
- Storage writes inside a trap (not recommended in Drosera)

**Fix Options:**
1. Store a head index instead of shifting arrays
2. Use a fixed-size circular buffer in storage
3. **Best approach:** Remove local history storage entirely and compute from `bytes[] data` passed by Drosera

---

## What a "Drosera-Ready" Version Should Look Like

### Proper Architecture Split

Keep your architecture concept, but split it properly into three components:

#### A) Feeder Contract (On-Chain)

**Purpose:** Data aggregation and storage

**Responsibilities:**
- Receives `recordSwap` from pool/token OR from an off-chain indexer that submits summaries
- Stores per-block aggregated metrics:
  - `maxWalletBPSeen`
  - `maxGasPremiumBPSeen`
  - `numRapidBuys`
  - `suspectedCoordinated`
  - Other relevant metrics

**Key Point:** This is where state lives, NOT in the trap

---

#### B) Trap (Stateless)

**Purpose:** Detection logic only

**Responsibilities:**
- `collect()` reads the latest feeder snapshot and encodes it
- `shouldRespond()` is `pure` and only analyzes `bytes[] data` (window-based N samples)
- Returns `(true, payload)` when thresholds are crossed

**Key Characteristics:**
- **No state variables**
- **No constructor args**
- **No state mutations**
- **Purely computational**

---

#### C) Responder

**Purpose:** Execute actions

**Responsibilities:**
- Executes actions on your actual launch contracts:
  - Pause trading
  - Blacklist addresses
  - Tighten limits
  - Emit alerts

**Key Point:** All side effects happen here, not in the trap

---

## Reference Implementation

### Minimal Stateless Trap Contract

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ITrap} from "drosera-contracts/interfaces/ITrap.sol";

contract FairLaunchGuardianTrap is ITrap {
    uint256 public constant BASIS_POINTS = 10_000;
    uint256 public constant RAPID_BUY_THRESHOLD = 3;

    struct CollectOutput {
        uint256 blockNumber;
        address[] recentBuyers;
        uint256[] buyAmounts;
        uint256[] gasPrices;
        uint256 totalSupply;
        uint256 liquidityPoolBalance;
        uint256 averageGasPrice; // optional; can be computed off-chain
    }

    struct ResponseData {
        address violator;
        uint256 accumulatedPercentBP;
        uint8 detectionType; // map your enum to u8
        uint256 blockNumber;
        uint256 severity; // 0..100
    }

    // NOTE: Keep constructor args if you must, but do not depend on state in shouldRespond.
    // BEST PRACTICE: Remove constructor entirely for Drosera compatibility

    function collect() external view override returns (bytes memory) {
        // DO NOT use changing storage or lastCollectedBlock.
        // For now, return empty (operators can pass augmented data),
        // or, better, statically read ERC20 totals:
        return abi.encode(
            CollectOutput({
                blockNumber: block.number,
                recentBuyers: new address[](0),
                buyAmounts: new uint256[](0),
                gasPrices: new uint256[](0),
                totalSupply: 0,            // fill if you can read it
                liquidityPoolBalance: 0,   // fill if you can read it
                averageGasPrice: 0
            })
        );
    }

    function shouldRespond(bytes[] calldata data)
        external
        pure
        override
        returns (bool, bytes memory)
    {
        // CRITICAL: Always guard against empty data
        if (data.length == 0 || data[0].length == 0) return (false, "");

        // Latest sample
        CollectOutput memory cur = abi.decode(data[0], (CollectOutput));

        // Example: compute excessive-accumulation using ONLY cur
        // (or compare over a window in data[])
        if (cur.totalSupply == 0) return (false, "");

        // Example loop (accumulate per-buyer from cur only):
        for (uint256 i = 0; i < cur.recentBuyers.length; i++) {
            // Here you would compute wallet's cumulative share 
            // WITHIN THE WINDOW using data[].
            // For demo, we just threshold the single trade as % of supply:
            uint256 bp = (cur.buyAmounts[i] * BASIS_POINTS) / cur.totalSupply;
            
            if (bp > 100 /* e.g., >1% in one trade */) {
                ResponseData memory r = ResponseData({
                    violator: cur.recentBuyers[i],
                    accumulatedPercentBP: bp,
                    detectionType: 0, // EXCESSIVE_ACCUMULATION
                    blockNumber: cur.blockNumber,
                    severity: _severity(bp, 100) // actual vs limit
                });
                return (true, abi.encode(r));
            }
        }

        return (false, "");
    }

    function _severity(uint256 actual, uint256 limit) 
        private 
        pure 
        returns (uint256) 
    {
        if (actual <= limit) return 0;
        uint256 excess = actual - limit;
        uint256 s = (excess * 100) / limit;
        return s > 100 ? 100 : s;
    }
}
```

**Key Features of This Implementation:**
- ✅ Implements `ITrap` interface correctly
- ✅ `collect()` is `view` and reads only on-chain state
- ✅ `shouldRespond()` is `pure` and stateless
- ✅ No state mutations anywhere
- ✅ Proper input validation
- ✅ Returns encoded payload for responder

---

### Responder Contract

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

contract FairLaunchResponder {
    event LaunchGuardianIncident(
        address violator,
        uint8 detectionType,
        uint256 severity,
        uint256 blockNumber
    );

    // Must match response_function in TOML: "handle(bytes)"
    function handle(bytes calldata payload) external {
        (
            address violator,
            uint256 pctBP,
            uint8 dtype,
            uint256 blk,
            uint256 sev
        ) = abi.decode(payload, (address, uint256, uint8, uint256, uint256));

        emit LaunchGuardianIncident(violator, dtype, sev, blk);

        // OPTIONAL: call your token/guardian to pause/blacklist
        // try IGuardian(guardian).blacklist(violator) {} catch {}
    }
}
```

**Trap Payload Format:**
```solidity
abi.encode(violator, pctBP, dtype, blk, severity)
```

**Important:** The responder `handle()` function signature must match the `response_function` in your TOML configuration.

---

## Implementation Paths

### Path 1: EventLog Path (Recommended)

**Approach:**
1. Extend from `drosera-contracts/Trap.sol`
2. Implement `eventLogFilters()` for `UniswapV2Pair.Swap`
3. Parse logs inside `collect()` (all deterministic)
4. This eliminates the need for `recordSwap`

**Benefits:**
- ✅ Fully deterministic
- ✅ No dependency on external calls
- ✅ Works with Drosera's native event filtering
- ✅ Operators can verify independently
- ✅ No state storage needed

**Example Filter:**
```solidity
function eventLogFilters() external pure returns (EventLogFilter[] memory) {
    EventLogFilter[] memory filters = new EventLogFilter[](1);
    filters[0] = EventLogFilter({
        eventSignature: "Swap(address,uint256,uint256,uint256,uint256,address)",
        targetAddress: UNISWAP_PAIR_ADDRESS
    });
    return filters;
}
```

---

### Path 2: Lightweight Metric Path

**Approach:**
1. Start simple by reading `totalSupply()` and `balanceOf(pool)`
2. Detect large deltas over `block_sample_size`
3. This already catches "launch rug" dynamics

**Benefits:**
- ✅ Simpler implementation
- ✅ Easier to debug and test
- ✅ Good starting point for MVP
- ✅ Lower complexity
- ✅ Fewer dependencies

**Example Logic:**
```solidity
function collect() external view override returns (bytes memory) {
    uint256 poolBalance = IERC20(token).balanceOf(poolAddress);
    uint256 totalSupply = IERC20(token).totalSupply();
    
    return abi.encode(block.number, poolBalance, totalSupply);
}
```

---

## Implementation Guidelines

### Feed Real Data - Two Practical Paths

#### EventLog Path (Recommended):
- Extend from `drosera-contracts/Trap.sol`
- Implement `eventLogFilters()` for `UniswapV2Pair.Swap`
- Parse logs inside `collect()` (all deterministic)
- This eliminates the need for `recordSwap`

#### Lightweight Metric Path:
- Start simple by reading `totalSupply()` and `balanceOf(pool)`
- Detect large deltas over `block_sample_size`
- This already catches "launch rug" dynamics

---

### Planner Safety & Windowing

**Always guard against empty data blobs:**

```solidity
// For single-block analysis:
if (data.length < 1 || data[0].length == 0) return (false, "");

// For window-based analysis (comparing multiple blocks):
if (data.length < 2 || data[0].length == 0 || data[1].length == 0) {
    return (false, "");
}
```

**For Pattern Detection Over Multiple Blocks:**
- Compute patterns over multiple blocks
- Derive everything from the encoded samples (e.g., walk `data[i]`)
- **DO NOT use contract state**

**Example Multi-Block Analysis:**
```solidity
function shouldRespond(bytes[] calldata data)
    external
    pure
    override
    returns (bool, bytes memory)
{
    if (data.length < 3) return (false, ""); // Need at least 3 samples
    
    // Compare across time window
    for (uint256 i = 0; i < data.length; i++) {
        CollectOutput memory sample = abi.decode(data[i], (CollectOutput));
        // Analyze trends across samples...
    }
}
```

---

### Gas & Storage Optimization

**Remove from Trap:**
- ❌ `_cleanOldSwaps()` 
- ❌ Any dynamic storage history
- ❌ State arrays
- ❌ Mappings

**If History is Needed:**
- ✅ Compute it from `bytes[] data` that Drosera passes
- ✅ Let operators manage the history window
- ✅ Use `block_sample_size` in TOML to control window

**Key Principle:** The trap should be a pure function of its inputs (`bytes[] data`), with no persistent state.

---

## TOML Configuration

### Complete drosera.toml Example

```toml
# =========================
# Global Drosera config
# =========================
ethereum_rpc    = "https://ethereum-hoodi-rpc.publicnode.com"
drosera_rpc     = "https://relay.hoodi.drosera.io"
eth_chain_id    = 560048
drosera_address = "0x91cB447BaFc6e0EA0F4Fe056F5a9b1F14bb06e5D"

[traps]

# =========================
# Fair Launch Guardian Trap
# =========================
[traps.fair_launch_guardian]
# Path to the compiled artifact JSON (forge build output)
path = "out/FairLaunchGuardianTrap.sol/FairLaunchGuardianTrap.json"

# Responder contract deployed address
response_contract = "0xYOUR_RESPONDER_ADDRESS_HERE"

# If your trap returns (true, payloadBytes) where payload is bytes:
# responder should have: function handle(bytes calldata payload) external
response_function = "handle(bytes)"

# Sampling settings
# Use >=2 if you want rising-edge logic, window checks, or persistence detection.
# Recommendation: Start with 5-6 for pattern detection
block_sample_size = 5

# Cooldown to avoid spamming if conditions remain true
cooldown_period_blocks = 20

# Operator quorum
min_number_of_operators = 1
max_number_of_operators = 3

# Access control
private_trap = true
whitelist = [
  "0xYOUR_OPERATOR_ADDRESS_1",
  "0xYOUR_OPERATOR_ADDRESS_2"
]

# Optional: if you already deployed the trap and want to run it directly
# address = "0xYOUR_TRAP_ADDRESS_HERE"
```

### TOML Configuration Notes

**Required Fields:**
- `path` - Compiled artifact JSON from forge build
- `response_contract` - Deployed responder contract address
- `response_function` - Must match responder function signature

**Sampling Settings:**
- `block_sample_size` - Number of historical blocks to analyze
  - Use `5-6` for original review recommendations
  - Use `>=2` for rising-edge logic, window checks, or persistence detection
- `cooldown_period_blocks` - Prevents spam if conditions persist

**Operator Settings:**
- `min_number_of_operators` - Minimum for consensus
- `max_number_of_operators` - Maximum allowed operators
- `whitelist` - Approved operator addresses (if `private_trap = true`)

**Optional Fields:**
- `address` - Pre-deployed trap address (if not deploying fresh)

---

## Action Items Summary

### Immediate Priority (Critical Blockers)

- [ ] **1. Implement ITrap interface correctly**
  - Import `ITrap` from `drosera-contracts/interfaces/ITrap.sol`
  - Add `is ITrap` to contract declaration
  - Add `override` modifiers to interface functions

- [ ] **2. Remove all constructor parameters**
  - Drosera deploys with no constructor args
  - Use stateless design

- [ ] **3. Make shouldRespond pure and stateless**
  - Remove ALL state reads
  - Remove ALL state writes
  - Remove `_executeResponse` call
  - Change function to `pure`

- [ ] **4. Remove state variables from trap**
  - Delete: `walletAccumulation`, `buyCountPerAddress`, `lastBuyBlock`
  - Delete: `recentSwaps`, `lastCollectedBlock`
  - Delete: `detectionHistory`, `isPaused`, `blacklistedAddresses`

- [ ] **5. Create separate responder contract**
  - Move pause logic to responder
  - Move blacklist logic to responder
  - Move all event emissions to responder
  - Implement `handle(bytes)` function

- [ ] **6. Fix data availability issue**
  - Choose: EventLog path OR Lightweight Metric path
  - Implement chosen data feeding mechanism
  - Ensure deterministic data access

- [ ] **7. Add proper input validation**
  - Guard against empty `data` arrays
  - Guard against empty `data[0]`
  - Add bounds checking for all array accesses

- [ ] **8. Create TOML configuration file**
  - Set correct artifact path
  - Configure responder address
  - Match `response_function` signature
  - Set appropriate `block_sample_size`

---

### Code Quality & Cleanup

- [ ] **9. Remove duplicate trap implementations**
  - Keep only ONE trap contract
  - Delete all duplicates

- [ ] **10. Delete unused libraries**
  - Remove `AddressValidator` if not used
  - Remove `BotDetection` if not used
  - Remove `LaunchMetrics` if not used

- [ ] **11. Remove inefficient ring buffer**
  - Delete `_cleanOldSwaps()` function
  - Remove array shifting logic
  - Let Drosera manage history via `bytes[] data`

- [ ] **12. Eliminate non-deterministic inputs**
  - Remove `tx.gasprice` usage
  - Remove `_estimateAverageGasPrice()` function
  - If gas tracking needed, use historical data from samples

---

### Architecture & Design

- [ ] **13. Design stateless collect() implementation**
  - Read only on-chain state
  - Return encoded snapshot data
  - No state modifications

- [ ] **14. Ensure shouldRespond is pure computation**
  - Accept `bytes[] data` input only
  - Perform calculations on input data
  - Return `(bool, bytes)` with no side effects

- [ ] **15. Define clear data structures**
  - `CollectOutput` struct for `collect()` return
  - `ResponseData` struct for responder payload
  - Document encoding/decoding formats

- [ ] **16. Implement responder handler function**
  - Match TOML `response_function` signature
  - Execute all side effects here
  - Add error handling

- [ ] **17. Choose and implement data feeding strategy**
  - **Option A:** EventLog filtering (recommended)
  - **Option B:** Simple state reading
  - **Option C:** External feeder contract

---

### Testing & Validation

- [ ] **18. Test with Drosera operators**
  - Deploy to testnet
  - Verify operator consensus
  - Confirm deterministic behavior

- [ ] **19. Validate TOML configuration**
  - Test artifact path resolution
  - Verify responder contract integration
  - Confirm operator whitelist

- [ ] **20. Performance testing**
  - Measure gas costs
  - Test with large data sets
  - Verify no array length issues

---

## Critical Reminders

### Core Principles

1. **Stateless Traps:** Traps are deployed fresh on shadow forks per block. No persistent state.

2. **Determinism is Critical:** All operators must get identical results for consensus.

3. **Separation of Concerns:**
   - **Trap** = Detection logic only
   - **Responder** = Actions only
   - **Feeder** = Data aggregation only

4. **No Constructor Args:** Drosera deploys traps with zero-argument constructors.

5. **Pure Functions:** `shouldRespond` must be stateless and ideally `pure`.

---

### Shadow Fork Architecture

Understanding how Drosera works is crucial:

```
For each sampled block:
  1. Operator creates shadow fork at that block
  2. Deploys fresh trap instance (no constructor args)
  3. Calls collect() to gather data
  4. Calls shouldRespond() with historical data window
  5. If (true, payload) returned → sends to responder
```

**Key Insight:** Your trap is **not a long-lived contract**. It's deployed and destroyed many times. This is why state doesn't persist and why you must be stateless.

---

### Data Flow

```
On-Chain State / Event Logs
         ↓
    collect() [view]
         ↓
  Encoded Snapshot
         ↓
shouldRespond(bytes[]) [pure]
         ↓
  (true, payload) OR (false, "")
         ↓
   Responder.handle(payload)
         ↓
  Execute Actions (pause, blacklist, etc.)
```

---

## Common Pitfalls to Avoid

### ❌ DON'T:
- Store state in the trap
- Use constructor parameters
- Mutate state in `shouldRespond`
- Depend on `tx.gasprice` or other tx context
- Assume operators will call your custom functions
- Use O(n) operations on unbounded arrays
- Skip input validation
- Mix detection and response logic

### ✅ DO:
- Make trap completely stateless
- Use zero-argument constructor
- Keep `shouldRespond` pure
- Read deterministic on-chain state
- Design for operator consensus
- Validate all inputs
- Use bounded data structures
- Separate concerns cleanly

---

## Resources & References

### Drosera Documentation
- **ITrap Interface:** `drosera-contracts/interfaces/ITrap.sol`
- **Event Filtering:** `drosera-contracts/Trap.sol`
- **Base Trap Implementation:** `drosera-contracts/Trap.sol`

### Your Project
- **Repository:** https://github.com/UIDickinson/ui-drosera-trap
- **Current Implementation:** Needs complete refactor per this review

### Network Configuration
- **Ethereum RPC:** `https://ethereum-hoodi-rpc.publicnode.com`
- **Drosera RPC:** `https://relay.hoodi.drosera.io`
- **Chain ID:** `560048`
- **Drosera Address:** `0x91cB447BaFc6e0EA0F4Fe056F5a9b1F14bb06e5D`