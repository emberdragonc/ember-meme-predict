# Secure Code Patterns 🔧

Battle-tested patterns for secure smart contract development.

---

## Table of Contents
- [Checks-Effects-Interactions (CEI)](#checks-effects-interactions-cei)
- [Pull Over Push Payments](#pull-over-push-payments)
- [Safe External Calls](#safe-external-calls)
- [Commit-Reveal](#commit-reveal)
- [Oracle Security](#oracle-security)
- [Bounded Operations](#bounded-operations)
- [Access Control](#access-control)

---

## Checks-Effects-Interactions (CEI)

**The most important pattern for preventing reentrancy.**

### Pattern
1. **Checks** - Validate all inputs and conditions
2. **Effects** - Update contract state
3. **Interactions** - Make external calls LAST

```solidity
// ❌ BAD: Interaction before Effects
function withdraw(uint256 amount) external {
    require(balances[msg.sender] >= amount, "Insufficient");
    
    // INTERACTION: External call first
    (bool success, ) = msg.sender.call{value: amount}("");
    require(success);
    
    // EFFECT: State change after (VULNERABLE!)
    balances[msg.sender] -= amount;
}

// ✅ GOOD: CEI Pattern
function withdraw(uint256 amount) external {
    // CHECKS
    require(balances[msg.sender] >= amount, "Insufficient");
    
    // EFFECTS: State change first
    balances[msg.sender] -= amount;
    
    // INTERACTIONS: External call last
    (bool success, ) = msg.sender.call{value: amount}("");
    require(success);
}
```

### With ReentrancyGuard (Belt + Suspenders)
```solidity
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract Vault is ReentrancyGuard {
    function withdraw(uint256 amount) external nonReentrant {
        require(balances[msg.sender] >= amount, "Insufficient");
        balances[msg.sender] -= amount;
        (bool success, ) = msg.sender.call{value: amount}("");
        require(success);
    }
}
```

---

## Pull Over Push Payments

**Let users withdraw funds instead of pushing to them.**

### Why Push Is Dangerous
```solidity
// ❌ BAD: Push payment - one failure blocks all
function distributeRewards(address[] calldata users, uint256[] calldata amounts) external {
    for (uint256 i = 0; i < users.length; i++) {
        // If ANY transfer fails, everything reverts
        (bool success, ) = users[i].call{value: amounts[i]}("");
        require(success, "Transfer failed");
    }
}
```

### Pull Pattern
```solidity
// ✅ GOOD: Pull payment - users withdraw themselves
mapping(address => uint256) public pendingWithdrawals;

function allocateReward(address user, uint256 amount) internal {
    pendingWithdrawals[user] += amount;
    emit RewardAllocated(user, amount);
}

function withdrawReward() external nonReentrant {
    uint256 amount = pendingWithdrawals[msg.sender];
    require(amount > 0, "Nothing to withdraw");
    
    pendingWithdrawals[msg.sender] = 0;
    
    (bool success, ) = msg.sender.call{value: amount}("");
    require(success, "Transfer failed");
    
    emit Withdrawn(msg.sender, amount);
}
```

### Benefits
- ✅ One user's failure doesn't affect others
- ✅ Users pay their own gas
- ✅ Prevents DoS via griefing contracts
- ✅ Clearer accounting

---

## Safe External Calls

### Don't Use transfer() or send()

```solidity
// ❌ BAD: Only forwards 2300 gas
// Breaks after EIP-1884 (Istanbul hard fork)
msg.sender.transfer(amount);
payable(user).send(amount);

// ✅ GOOD: Forward all gas, check return value
(bool success, ) = msg.sender.call{value: amount}("");
require(success, "Transfer failed");
```

### Handle Return Values
```solidity
// ❌ BAD: Ignoring return value
someAddress.call{value: amount}("");

// ❌ BAD: Only checking success, ignoring data
(bool success, ) = someAddress.call(data);
require(success);

// ✅ GOOD: Check both success and handle data
(bool success, bytes memory data) = someAddress.call(data);
require(success, "Call failed");
// Process data if needed
```

### Mark Untrusted Contracts
```solidity
// ✅ GOOD: Naming makes risk clear
UntrustedExternalContract.withdraw(amount); // Obviously risky
TrustedBank.withdraw(amount); // Vetted contract

function makeUntrustedWithdrawal(uint256 amount) internal {
    // Function name signals danger
}
```

### Use SafeERC20 for Tokens
```solidity
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract Vault {
    using SafeERC20 for IERC20;
    
    function deposit(IERC20 token, uint256 amount) external {
        // Handles non-standard return values (USDT, etc.)
        token.safeTransferFrom(msg.sender, address(this), amount);
    }
}
```

---

## Commit-Reveal

**Prevent frontrunning by hiding intentions until reveal.**

### Pattern
```solidity
// contracts/security/CommitReveal.sol

abstract contract CommitReveal {
    mapping(address => bytes32) public commits;
    mapping(address => uint256) public commitTimestamps;
    
    uint256 public constant MIN_REVEAL_DELAY = 1 minutes;
    uint256 public constant MAX_REVEAL_WINDOW = 24 hours;
    
    error NoCommit();
    error TooEarly();
    error TooLate();
    error InvalidReveal();
    
    function commit(bytes32 hash) external {
        commits[msg.sender] = hash;
        commitTimestamps[msg.sender] = block.timestamp;
        emit Committed(msg.sender, hash);
    }
    
    modifier onlyRevealed(bytes32 secret) {
        if (commits[msg.sender] == bytes32(0)) revert NoCommit();
        
        uint256 elapsed = block.timestamp - commitTimestamps[msg.sender];
        if (elapsed < MIN_REVEAL_DELAY) revert TooEarly();
        if (elapsed > MAX_REVEAL_WINDOW) revert TooLate();
        
        bytes32 expected = keccak256(abi.encodePacked(secret, msg.sender));
        if (commits[msg.sender] != expected) revert InvalidReveal();
        
        delete commits[msg.sender];
        _;
    }
    
    event Committed(address indexed user, bytes32 hash);
}
```

### Usage Example
```solidity
contract SecretBid is CommitReveal {
    function placeBid(bytes32 secret, uint256 bidAmount) 
        external 
        payable 
        onlyRevealed(secret) 
    {
        require(msg.value == bidAmount, "Wrong amount");
        // Process bid
    }
}

// User flow:
// 1. User computes: hash = keccak256(abi.encodePacked(secret, userAddress))
// 2. User calls: commit(hash)
// 3. Wait MIN_REVEAL_DELAY
// 4. User calls: placeBid(secret, amount)
```

---

## Oracle Security

### Validate Oracle Data
```solidity
// ❌ BAD: No validation
function getPrice() public view returns (uint256) {
    (, int256 price, , , ) = priceFeed.latestRoundData();
    return uint256(price);
}

// ✅ GOOD: Full validation
uint256 public constant STALENESS_THRESHOLD = 1 hours;
uint256 public constant MIN_PRICE = 1; // Adjust per asset
uint256 public constant MAX_PRICE = 1e12; // Adjust per asset

error StalePrice();
error InvalidPrice();
error PriceOutOfBounds();

function getPrice() public view returns (uint256) {
    (
        uint80 roundId,
        int256 price,
        ,
        uint256 updatedAt,
        uint80 answeredInRound
    ) = priceFeed.latestRoundData();
    
    // Check for stale data
    if (block.timestamp - updatedAt > STALENESS_THRESHOLD) revert StalePrice();
    
    // Check for valid round
    if (answeredInRound < roundId) revert StalePrice();
    
    // Check for valid price
    if (price <= 0) revert InvalidPrice();
    
    uint256 uPrice = uint256(price);
    if (uPrice < MIN_PRICE || uPrice > MAX_PRICE) revert PriceOutOfBounds();
    
    return uPrice;
}
```

### Use Multiple Sources
```solidity
function getMedianPrice() public view returns (uint256) {
    uint256 priceA = _getChainlinkPrice();
    uint256 priceB = _getUniswapTWAP();
    uint256 priceC = _getBandPrice();
    
    // Return median
    return _median(priceA, priceB, priceC);
}
```

---

## Bounded Operations

### Cap Array Sizes
```solidity
// ❌ BAD: Unbounded array
address[] public users;

function addUser(address user) external {
    users.push(user); // Can grow forever
}

// ✅ GOOD: Bounded array
uint256 public constant MAX_USERS = 1000;

function addUser(address user) external {
    require(users.length < MAX_USERS, "Max users reached");
    users.push(user);
}
```

### Paginate Large Operations
```solidity
// ❌ BAD: Process all in one tx
function processAll() external {
    for (uint256 i = 0; i < users.length; i++) {
        _process(users[i]); // May exceed gas limit
    }
}

// ✅ GOOD: Paginated processing
uint256 public lastProcessedIndex;

function processBatch(uint256 batchSize) external {
    uint256 end = lastProcessedIndex + batchSize;
    if (end > users.length) end = users.length;
    
    for (uint256 i = lastProcessedIndex; i < end; i++) {
        _process(users[i]);
    }
    
    lastProcessedIndex = end;
}
```

### Gas-Aware Loops
```solidity
function processBatchGasAware() external {
    uint256 i = lastProcessedIndex;
    
    while (i < users.length && gasleft() > 50000) {
        _process(users[i]);
        i++;
    }
    
    lastProcessedIndex = i;
}
```

---

## Access Control

### Simple: Ownable
```solidity
import "@openzeppelin/contracts/access/Ownable.sol";

contract MyContract is Ownable {
    function adminOnly() external onlyOwner {
        // Only owner can call
    }
}
```

### Advanced: Role-Based
```solidity
import "@openzeppelin/contracts/access/AccessControl.sol";

contract MyContract is AccessControl {
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");
    
    constructor() {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(ADMIN_ROLE, msg.sender);
    }
    
    function adminFunction() external onlyRole(ADMIN_ROLE) {
        // Only admins
    }
    
    function operatorFunction() external onlyRole(OPERATOR_ROLE) {
        // Only operators
    }
}
```

### Two-Step Ownership Transfer
```solidity
import "@openzeppelin/contracts/access/Ownable2Step.sol";

contract MyContract is Ownable2Step {
    // Requires new owner to accept, preventing accidental transfers
}
```

---

## Quick Reference

| Pattern | Use Case |
|---------|----------|
| CEI | All functions with external calls |
| Pull Payments | Distributing funds to multiple users |
| Safe Calls | Any ETH transfer |
| SafeERC20 | Any token transfer |
| Commit-Reveal | Auctions, voting, games |
| Oracle Validation | Any external price data |
| Bounded Arrays | User lists, reward tokens |
| Pagination | Processing large datasets |
| ReentrancyGuard | State-changing + external calls |
| Ownable2Step | Admin ownership |
