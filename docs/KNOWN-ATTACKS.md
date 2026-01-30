# Known Attacks Reference 🛡️

A comprehensive guide to smart contract vulnerabilities based on [ConsenSys Best Practices](https://consensysdiligence.github.io/smart-contract-best-practices/).

---

## Table of Contents
- [Reentrancy](#reentrancy)
- [Oracle Manipulation](#oracle-manipulation)
- [Frontrunning](#frontrunning)
- [Denial of Service](#denial-of-service)
- [Force Feeding](#force-feeding)
- [Timestamp Dependence](#timestamp-dependence)
- [Griefing](#griefing)
- [Insecure Arithmetic](#insecure-arithmetic)

---

## Reentrancy

**SWC-107** | **Severity: Critical**

Reentrancy occurs when an external call allows the callee to re-enter the calling function before state changes are complete.

### Single-Function Reentrancy

```solidity
// ❌ VULNERABLE
mapping(address => uint) public balances;

function withdraw() public {
    uint amount = balances[msg.sender];
    (bool success, ) = msg.sender.call{value: amount}("");
    require(success);
    balances[msg.sender] = 0; // State change AFTER external call
}
```

**Attack:** Attacker's fallback calls `withdraw()` again before balance is zeroed.

```solidity
// ✅ SAFE: Checks-Effects-Interactions
function withdraw() public {
    uint amount = balances[msg.sender];
    balances[msg.sender] = 0; // State change BEFORE external call
    (bool success, ) = msg.sender.call{value: amount}("");
    require(success);
}
```

### Cross-Function Reentrancy

```solidity
// ❌ VULNERABLE
function transfer(address to, uint amount) public {
    if (balances[msg.sender] >= amount) {
        balances[to] += amount;
        balances[msg.sender] -= amount;
    }
}

function withdraw() public {
    uint amount = balances[msg.sender];
    (bool success, ) = msg.sender.call{value: amount}("");
    require(success);
    balances[msg.sender] = 0;
}
```

**Attack:** During `withdraw()`, attacker calls `transfer()` to move funds before balance zeroed.

### Cross-Contract Reentrancy

When Contract A calls Contract B, which calls back into Contract A or a related Contract C that shares state.

### Read-Only Reentrancy

```solidity
// ❌ VULNERABLE: Price oracle reads during reentrancy
contract Vault {
    function getSharePrice() external view returns (uint) {
        return totalAssets / totalShares; // Can be manipulated mid-tx
    }
}
```

**Attack:** Attacker manipulates state, reads stale price during callback, completes attack.

### Mitigations

1. **Checks-Effects-Interactions Pattern** - Always update state before external calls
2. **ReentrancyGuard** - Use OpenZeppelin's `nonReentrant` modifier
3. **Pull Payments** - Let users withdraw instead of pushing funds

```solidity
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract Safe is ReentrancyGuard {
    function withdraw() external nonReentrant {
        // Safe from reentrancy
    }
}
```

---

## Oracle Manipulation

**Severity: Critical**

Manipulation of external price feeds to exploit DeFi protocols.

### Flash Loan Price Manipulation

```solidity
// ❌ VULNERABLE: Single-source spot price
function getPrice() public view returns (uint) {
    (uint reserve0, uint reserve1, ) = uniswapPair.getReserves();
    return reserve1 * 1e18 / reserve0; // Spot price
}
```

**Attack:**
1. Take flash loan of Token A
2. Dump into Uniswap pool, crashing price
3. Exploit protocol using manipulated price
4. Repay flash loan

### Mitigations

1. **Use Chainlink/Decentralized Oracles**
```solidity
import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

function getPrice() public view returns (uint) {
    (, int price, , uint updatedAt, ) = priceFeed.latestRoundData();
    require(block.timestamp - updatedAt < STALENESS_THRESHOLD, "Stale");
    require(price > 0, "Invalid");
    return uint(price);
}
```

2. **Time-Weighted Average Price (TWAP)**
```solidity
// Use cumulative prices over time window (e.g., 30 min)
// See Uniswap TWAP oracle examples
```

3. **Multiple Oracle Sources** - Median of 3+ sources

---

## Frontrunning

**SWC-114** | **Severity: High**

Attackers observe pending transactions and insert their own with higher gas.

### Displacement Attack
Attacker's tx replaces victim's entirely (e.g., domain registration).

### Insertion Attack (Sandwich)
```
1. Victim submits buy order for Token X
2. Attacker frontruns: buys Token X (price rises)
3. Victim's order executes at higher price
4. Attacker backruns: sells Token X for profit
```

### Suppression Attack (Block Stuffing)
Attacker fills blocks with high-gas transactions to prevent victim's tx.

### Mitigations

1. **Commit-Reveal Scheme**
```solidity
// Phase 1: Commit
mapping(address => bytes32) public commits;

function commit(bytes32 hash) external {
    commits[msg.sender] = hash;
}

// Phase 2: Reveal (after delay)
function reveal(bytes32 secret) external {
    require(keccak256(abi.encodePacked(secret, msg.sender)) == commits[msg.sender]);
    // Execute action
}
```

2. **Slippage Protection**
```solidity
function swap(uint amountIn, uint minAmountOut) external {
    uint amountOut = _swap(amountIn);
    require(amountOut >= minAmountOut, "Slippage");
}
```

3. **Batch Auctions** - Execute all orders at same price

4. **Private Mempools** - Flashbots Protect, MEV Blocker

---

## Denial of Service

**SWC-113, SWC-128** | **Severity: High**

### DoS via Unexpected Revert

```solidity
// ❌ VULNERABLE: One failure blocks all
function distributeRewards(address[] calldata users) external {
    for (uint i = 0; i < users.length; i++) {
        (bool success, ) = users[i].call{value: rewards[i]}("");
        require(success); // Reverts entire batch if one fails
    }
}
```

### DoS via Block Gas Limit

```solidity
// ❌ VULNERABLE: Unbounded loop
address[] public users;

function processAll() external {
    for (uint i = 0; i < users.length; i++) { // Can exceed gas limit
        _process(users[i]);
    }
}
```

### Mitigations

1. **Pull Over Push**
```solidity
// ✅ SAFE: Users withdraw themselves
mapping(address => uint) public pendingWithdrawals;

function withdraw() external {
    uint amount = pendingWithdrawals[msg.sender];
    pendingWithdrawals[msg.sender] = 0;
    (bool success, ) = msg.sender.call{value: amount}("");
    require(success);
}
```

2. **Bounded Arrays**
```solidity
uint256 public constant MAX_USERS = 100;

function addUser(address user) external {
    require(users.length < MAX_USERS, "Max reached");
    users.push(user);
}
```

3. **Pagination**
```solidity
function processUsers(uint start, uint count) external {
    uint end = start + count;
    if (end > users.length) end = users.length;
    
    for (uint i = start; i < end; i++) {
        _process(users[i]);
    }
}
```

---

## Force Feeding

**Severity: Medium**

ETH can be forcibly sent to contracts via:
- `selfdestruct(target)` - Deprecated but still works
- Coinbase rewards
- Pre-calculated contract address

```solidity
// ❌ VULNERABLE: Assumes balance == deposits
function invariantCheck() external view {
    require(address(this).balance == totalDeposits); // Can fail
}

// ✅ SAFE: Track deposits separately
function invariantCheck() external view {
    require(trackedBalance >= totalDeposits); // Use internal accounting
}
```

---

## Timestamp Dependence

**SWC-116** | **Severity: Low-Medium**

Miners can manipulate `block.timestamp` by ~15 seconds.

```solidity
// ❌ VULNERABLE: Timestamp for randomness
function random() external view returns (uint) {
    return uint(keccak256(abi.encodePacked(block.timestamp)));
}

// ❌ VULNERABLE: Exact time checks
require(block.timestamp == deadline); // Miner can skip

// ✅ SAFER: Range checks
require(block.timestamp >= deadline); // Harder to manipulate
```

**Mitigation:** Use Chainlink VRF for randomness, allow time ranges not exact matches.

---

## Griefing

**Severity: Medium**

Malicious actors causing harm without direct profit.

### Examples
- Spamming with dust amounts to bloat storage
- Repeatedly failing transactions to waste others' gas
- Locking funds by refusing to participate

### Mitigations
- Minimum transaction amounts
- Timeout mechanisms for multi-party operations
- Economic penalties for bad actors

---

## Insecure Arithmetic

**SWC-101** | **Severity: Critical (pre-0.8.0)**

```solidity
// ❌ VULNERABLE (Solidity < 0.8.0)
uint8 x = 255;
x++; // Overflows to 0!

// ✅ SAFE (Solidity >= 0.8.0)
// Built-in overflow checks
uint8 x = 255;
x++; // Reverts with panic

// For unchecked math (gas optimization):
unchecked {
    x++; // No overflow check
}
```

---

## Quick Reference

| Attack | SWC | Mitigation |
|--------|-----|------------|
| Reentrancy | 107 | CEI pattern, ReentrancyGuard |
| Oracle Manipulation | - | Chainlink, TWAP, multiple sources |
| Frontrunning | 114 | Commit-reveal, slippage, private mempool |
| DoS (Revert) | 113 | Pull payments |
| DoS (Gas Limit) | 128 | Bounded loops, pagination |
| Force Feeding | - | Internal accounting |
| Timestamp | 116 | Ranges, Chainlink VRF |
| Overflow | 101 | Solidity 0.8+, SafeMath |

---

## Resources

- [SWC Registry](https://swcregistry.io/)
- [ConsenSys Best Practices](https://consensysdiligence.github.io/smart-contract-best-practices/)
- [Smart Contract Security Field Guide](https://scsfg.io/)
- [Damn Vulnerable DeFi](https://www.damnvulnerabledefi.xyz/)
