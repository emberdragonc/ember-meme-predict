# Security Philosophy 🔐

Core principles for secure smart contract development, based on [ConsenSys Diligence Best Practices](https://consensysdiligence.github.io/smart-contract-best-practices/).

---

## The Smart Contract Security Mindset

Smart contract programming requires a **different engineering mindset**. Unlike web or mobile development:

- **Cost of failure is high** - Bugs can drain millions instantly
- **Change is difficult** - Contracts are immutable once deployed  
- **Everything is public** - Code, transactions, and state are visible to attackers
- **Execution is adversarial** - Assume all inputs are malicious

> "It is not enough to defend against known vulnerabilities. You must learn a new philosophy of development."

---

## Core Principles

### 1. 🔴 Prepare for Failure

**Contracts WILL have bugs.** Design for graceful degradation.

#### Circuit Breakers (Pause Functionality)
```solidity
import "@openzeppelin/contracts/security/Pausable.sol";

contract MyContract is Pausable {
    function criticalFunction() external whenNotPaused {
        // Can be paused in emergency
    }
    
    function pause() external onlyOwner {
        _pause();
    }
}
```

#### Rate Limiting
```solidity
mapping(address => uint256) public lastAction;
uint256 public constant COOLDOWN = 1 hours;

modifier rateLimited() {
    require(block.timestamp >= lastAction[msg.sender] + COOLDOWN);
    lastAction[msg.sender] = block.timestamp;
    _;
}
```

#### Withdrawal Limits
```solidity
uint256 public constant MAX_DAILY_WITHDRAWAL = 100 ether;
mapping(address => uint256) public dailyWithdrawn;
mapping(address => uint256) public lastWithdrawalDay;

function withdraw(uint256 amount) external {
    uint256 today = block.timestamp / 1 days;
    if (lastWithdrawalDay[msg.sender] < today) {
        dailyWithdrawn[msg.sender] = 0;
        lastWithdrawalDay[msg.sender] = today;
    }
    require(dailyWithdrawn[msg.sender] + amount <= MAX_DAILY_WITHDRAWAL);
    dailyWithdrawn[msg.sender] += amount;
    // ... transfer
}
```

---

### 2. 🟡 Rollout Carefully

#### Testing Progression
1. **Unit tests** - Test individual functions
2. **Integration tests** - Test contract interactions
3. **Fork tests** - Test against mainnet state
4. **Testnet deployment** - Real network conditions
5. **Mainnet with limits** - Gradual rollout

#### Phased Deployment
```solidity
uint256 public depositCap = 10 ether; // Start small

function setDepositCap(uint256 newCap) external onlyOwner {
    require(newCap >= depositCap, "Can only increase");
    depositCap = newCap;
}
```

#### Bug Bounty Program
- Launch bounty before mainnet
- Reward proportional to severity
- Clear scope and rules
- Platforms: Immunefi, Code4rena, Sherlock

#### Timelock for Admin Actions
```solidity
import "@openzeppelin/contracts/governance/TimelockController.sol";

// Critical changes require 48h delay
// Users can exit if they disagree
```

---

### 3. 🟢 Keep Contracts Simple

> "Complexity is the enemy of security."

#### Do's
- ✅ Single responsibility per contract
- ✅ Minimal state variables
- ✅ Short, focused functions
- ✅ Clear, readable code over clever optimizations
- ✅ Reuse audited libraries (OpenZeppelin, Solady)

#### Don'ts
- ❌ Premature gas optimization
- ❌ Complex inheritance hierarchies
- ❌ Multiple responsibilities in one contract
- ❌ Reinventing standard patterns

#### Modular Design
```
├── Token.sol          # ERC20 only
├── Staking.sol        # Staking logic only
├── Rewards.sol        # Reward distribution only
└── Governance.sol     # Voting only
```

---

### 4. 🔵 Stay Up to Date

#### Monitor Security Feeds
- [@samczsun](https://twitter.com/samczsun) - Researcher
- [@BlockSecTeam](https://twitter.com/BlockSecTeam) - Exploit alerts
- [Rekt News](https://rekt.news/) - Post-mortems
- [DeFi Hacks](https://defillama.com/hacks) - Database

#### Update Dependencies
```bash
# Check for updates
forge update

# Update specific dependency
forge install OpenZeppelin/openzeppelin-contracts@v5.0.0
```

#### Track CVEs
- [SWC Registry](https://swcregistry.io/) - Smart Contract Weakness Classification
- Solidity release notes for compiler bugs

---

### 5. ⚫ Know Blockchain Properties

#### Transactions Are Public
- All tx data visible in mempool before execution
- Attackers can frontrun, sandwich, extract MEV
- **Mitigation:** Commit-reveal, private mempools, slippage protection

#### Execution Order Not Guaranteed
- Miners/validators control tx ordering
- Higher gas = higher priority (usually)
- **Mitigation:** Design to be order-independent when possible

#### Timestamps Can Be Manipulated
- Miners can adjust ~15 seconds
- **Mitigation:** Use ranges, not exact times; use block numbers for precision

#### Randomness Is Hard
- `block.timestamp`, `block.difficulty` are manipulable
- **Mitigation:** Use Chainlink VRF or commit-reveal

#### External Calls Are Dangerous
- Called contract controls execution
- Can reenter, consume gas, revert
- **Mitigation:** CEI pattern, ReentrancyGuard, gas limits

---

## Security Checklist Mindset

Before each deployment, ask:

1. **What can go wrong?** - Enumerate failure modes
2. **What's the worst case?** - Quantify maximum loss
3. **How do we recover?** - Plan incident response
4. **Who can we call?** - Security partners on standby
5. **What's the exit plan?** - How do users get funds out?

---

## Defense in Depth

Layer multiple protections:

```
┌─────────────────────────────────────┐
│         1. Code Quality             │  ← Audited code, tests
├─────────────────────────────────────┤
│       2. Static Analysis            │  ← Slither, Mythril
├─────────────────────────────────────┤
│        3. Access Control            │  ← Ownable, roles
├─────────────────────────────────────┤
│       4. Rate Limiting              │  ← Caps, cooldowns
├─────────────────────────────────────┤
│       5. Circuit Breakers           │  ← Pause functionality
├─────────────────────────────────────┤
│         6. Monitoring               │  ← Alerts, dashboards
├─────────────────────────────────────┤
│       7. Incident Response          │  ← Runbooks, contacts
└─────────────────────────────────────┘
```

---

## Remember

> **"Security is a process, not a product."** - Bruce Schneier

- There is no "secure" - only "secure enough for now"
- New attacks are discovered constantly
- The threat landscape evolves
- Stay humble, stay vigilant

---

## Resources

- [ConsenSys Best Practices](https://consensysdiligence.github.io/smart-contract-best-practices/)
- [Trail of Bits Guidelines](https://github.com/crytic/building-secure-contracts)
- [Solidity Security Considerations](https://docs.soliditylang.org/en/latest/security-considerations.html)
