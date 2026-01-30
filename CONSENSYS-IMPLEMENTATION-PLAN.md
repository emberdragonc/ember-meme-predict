# ConsenSys Best Practices Implementation Plan 🐉

Based on: https://consensysdiligence.github.io/smart-contract-best-practices/

## Executive Summary

This plan integrates ConsenSys Diligence's smart contract security best practices into our framework. The guide covers:
1. **General Philosophy** - Security mindset
2. **Development Recommendations** - Code patterns
3. **Known Attacks** - Vulnerability categories
4. **Security Tools** - Automated analysis

---

## Phase 1: Documentation & Checklists 📋

### 1.1 Create KNOWN-ATTACKS.md
**Priority: HIGH | Effort: Medium**

Document all attack vectors with examples:

```markdown
# Known Attacks Reference

## Reentrancy
- Single-function reentrancy
- Cross-function reentrancy
- Cross-contract reentrancy
- Read-only reentrancy

## Oracle Manipulation
- Single source manipulation
- Flash loan price manipulation
- TWAP manipulation

## Frontrunning
- Displacement attacks
- Insertion attacks (sandwich)
- Suppression attacks (block stuffing)

## Denial of Service
- Unexpected revert DoS
- Block gas limit DoS
- Unbounded array DoS

## Other
- Timestamp dependence
- Insecure arithmetic (pre-0.8)
- Force feeding ETH
- Griefing attacks
```

**Action Items:**
- [ ] Create `docs/KNOWN-ATTACKS.md` with code examples
- [ ] Add SWC Registry references (SWC-107, SWC-113, etc.)
- [ ] Link mitigations to each attack type

### 1.2 Create SECURITY-PHILOSOPHY.md
**Priority: HIGH | Effort: Low**

Core principles from ConsenSys:

```markdown
# Security Philosophy

## 1. Prepare for Failure
- Contracts WILL have bugs
- Design for graceful degradation
- Include circuit breakers (pause functionality)

## 2. Rollout Carefully
- Test extensively on testnets
- Time-locked deployments
- Bug bounty programs
- Phased rollouts with limits

## 3. Keep Contracts Simple
- Complexity is the enemy of security
- Modular design
- Reuse audited code (OZ, Solady)

## 4. Stay Up to Date
- Monitor for new vulnerabilities
- Subscribe to security feeds
- Update dependencies regularly

## 5. Be Aware of Blockchain Properties
- Transactions are public (frontrunning)
- Execution order not guaranteed
- Timestamps can be manipulated
- Randomness is hard
```

**Action Items:**
- [ ] Create `docs/SECURITY-PHILOSOPHY.md`
- [ ] Add to onboarding documentation

---

## Phase 2: Code Pattern Library 🔧

### 2.1 Create PATTERNS.md - Development Recommendations

**Priority: HIGH | Effort: High**

#### External Calls Patterns

```solidity
// ❌ BAD: State change after external call
function withdraw() external {
    (bool success, ) = msg.sender.call{value: balance}("");
    require(success);
    balances[msg.sender] = 0; // State change AFTER call
}

// ✅ GOOD: Checks-Effects-Interactions
function withdraw() external {
    uint256 amount = balances[msg.sender];
    balances[msg.sender] = 0; // State change BEFORE call
    (bool success, ) = msg.sender.call{value: amount}("");
    require(success, "Transfer failed");
}
```

#### Pull Over Push Pattern

```solidity
// ❌ BAD: Push payments (can DoS)
function distributeRewards(address[] calldata users) external {
    for (uint i = 0; i < users.length; i++) {
        payable(users[i]).transfer(rewards[users[i]]); // One failure blocks all
    }
}

// ✅ GOOD: Pull payments
mapping(address => uint256) public pendingWithdrawals;

function claimReward() external {
    uint256 amount = pendingWithdrawals[msg.sender];
    pendingWithdrawals[msg.sender] = 0;
    (bool success, ) = msg.sender.call{value: amount}("");
    require(success);
}
```

#### Don't Use transfer() or send()

```solidity
// ❌ BAD: Only forwards 2300 gas (breaks after EIP-1884)
msg.sender.transfer(amount);

// ✅ GOOD: Forward all gas, check return
(bool success, ) = msg.sender.call{value: amount}("");
require(success, "Transfer failed");
```

**Action Items:**
- [ ] Create `contracts/patterns/` directory
- [ ] Add `ChecksEffectsInteractions.sol` example
- [ ] Add `PullPayment.sol` example
- [ ] Add `SafeExternalCall.sol` example
- [ ] Create `PATTERNS.md` documentation

### 2.2 Update HARDENED-CODE.md

Add ConsenSys-recommended patterns:

```markdown
## Assert vs Require vs Revert

| Function | Use Case | Gas on Failure |
|----------|----------|----------------|
| `require()` | Input validation, access control | Refunds remaining gas |
| `assert()` | Invariant checking, internal errors | Consumes all gas |
| `revert()` | Complex conditions with custom errors | Refunds remaining gas |

## Invariant Example
```solidity
function deposit() public payable {
    balances[msg.sender] += msg.value;
    totalDeposits += msg.value;
    assert(address(this).balance >= totalDeposits); // Invariant
}
```

**Action Items:**
- [ ] Add assert/require/revert guidance
- [ ] Add invariant checking examples
- [ ] Document when to use each

---

## Phase 3: Security Tooling Integration 🛠️

### 3.1 Add Slither to CI Pipeline
**Priority: HIGH | Effort: Medium**

Update `.github/workflows/ci.yml`:

```yaml
slither:
  runs-on: ubuntu-latest
  steps:
    - uses: actions/checkout@v4
    - name: Run Slither
      uses: crytic/slither-action@v0.3.0
      with:
        sarif: results.sarif
        fail-on: medium
    - name: Upload SARIF
      uses: github/codeql-action/upload-sarif@v2
      with:
        sarif_file: results.sarif
```

**Action Items:**
- [ ] Add Slither GitHub Action
- [ ] Configure `slither.config.json` for project
- [ ] Add Slither badge to README

### 3.2 Add Echidna Fuzzing
**Priority: MEDIUM | Effort: High**

```yaml
# .github/workflows/fuzz.yml
fuzz:
  runs-on: ubuntu-latest
  steps:
    - uses: actions/checkout@v4
    - name: Run Echidna
      uses: crytic/echidna-action@v2
      with:
        files: .
        contract: MyContractTest
        config: echidna.config.yaml
```

Create `echidna.config.yaml`:
```yaml
testMode: assertion
testLimit: 50000
shrinkLimit: 5000
seqLen: 100
```

**Action Items:**
- [ ] Create `test/invariants/` directory for Echidna tests
- [ ] Write property tests for critical invariants
- [ ] Add Echidna to CI (optional, slow)
- [ ] Document fuzzing best practices

### 3.3 Security Tools Reference

Add to README or separate doc:

| Tool | Purpose | Integration |
|------|---------|-------------|
| **Slither** | Static analysis | CI (required) |
| **Mythril** | Symbolic execution | Local/CI |
| **Echidna** | Fuzzing | Local/CI |
| **Manticore** | Dynamic analysis | Local |
| **Foundry Fuzz** | Built-in fuzzing | CI (required) |
| **Certora** | Formal verification | Enterprise |

**Action Items:**
- [ ] Create `docs/SECURITY-TOOLS.md`
- [ ] Add installation instructions for each tool
- [ ] Create local analysis scripts

---

## Phase 4: Attack-Specific Mitigations ⚔️

### 4.1 Reentrancy Protection

Already have ReentrancyGuard, but add:

```solidity
// contracts/security/ReentrancyAware.sol

/// @notice Base contract that marks functions as potentially reentrant
abstract contract ReentrancyAware {
    /// @dev Mark functions that make external calls
    /// Use with: `untrustedExternalCall(target).doSomething()`
    modifier untrusted() {
        // Just a marker for code review
        _;
    }
}
```

**Action Items:**
- [ ] Add cross-function reentrancy examples
- [ ] Document read-only reentrancy risks
- [ ] Add to AUDIT_CHECKLIST.md

### 4.2 Oracle Security

```solidity
// contracts/security/OracleConsumer.sol

abstract contract OracleConsumer {
    uint256 public constant PRICE_STALENESS_THRESHOLD = 1 hours;
    
    error StalePrice();
    error InvalidPrice();
    
    function _validatePrice(
        uint256 price,
        uint256 updatedAt
    ) internal view {
        if (price == 0) revert InvalidPrice();
        if (block.timestamp - updatedAt > PRICE_STALENESS_THRESHOLD) {
            revert StalePrice();
        }
    }
    
    /// @dev Use TWAP instead of spot price
    /// @dev Use multiple oracle sources
    /// @dev Add circuit breakers for extreme price movements
}
```

**Action Items:**
- [ ] Create oracle integration guide
- [ ] Add Chainlink integration example
- [ ] Document TWAP usage
- [ ] Add oracle checklist items

### 4.3 Frontrunning Protection

```solidity
// contracts/security/CommitReveal.sol

abstract contract CommitReveal {
    mapping(address => bytes32) public commits;
    mapping(address => uint256) public commitTimestamps;
    
    uint256 public constant MIN_REVEAL_DELAY = 1 minutes;
    
    function commit(bytes32 hash) external {
        commits[msg.sender] = hash;
        commitTimestamps[msg.sender] = block.timestamp;
    }
    
    modifier revealed(bytes32 secret) {
        require(
            block.timestamp >= commitTimestamps[msg.sender] + MIN_REVEAL_DELAY,
            "Too early"
        );
        require(
            commits[msg.sender] == keccak256(abi.encodePacked(secret, msg.sender)),
            "Invalid reveal"
        );
        delete commits[msg.sender];
        _;
    }
}
```

**Action Items:**
- [ ] Create `contracts/security/CommitReveal.sol`
- [ ] Add batch auction pattern example
- [ ] Document slippage protection patterns

### 4.4 DoS Prevention

Add to AUDIT_CHECKLIST.md:

```markdown
## DoS Prevention Checklist
- [ ] No unbounded loops over user-controlled arrays
- [ ] Pull over push for payments
- [ ] Array length caps with MAX constants
- [ ] Paginated operations for large datasets
- [ ] No single point of failure in withdrawals
```

**Action Items:**
- [ ] Add DoS patterns to AUDIT_CHECKLIST.md
- [ ] Create bounded array example
- [ ] Document gas limit considerations

---

## Phase 5: Process & Governance 📜

### 5.1 Pre-Deployment Checklist

Create `DEPLOYMENT-CHECKLIST.md`:

```markdown
# Pre-Deployment Checklist

## Code Review
- [ ] All external calls identified and marked
- [ ] Reentrancy guards on all state-changing functions
- [ ] Access control verified
- [ ] Events emitted for all state changes

## Testing
- [ ] Unit test coverage > 90%
- [ ] Fuzz tests for math operations
- [ ] Fork tests against mainnet state
- [ ] Gas benchmarks recorded

## Security
- [ ] Slither passes with no high/medium
- [ ] Manual review of all external interactions
- [ ] Known attack vectors addressed
- [ ] Emergency pause mechanism tested

## Documentation
- [ ] NatSpec on all public functions
- [ ] Architecture diagram updated
- [ ] Admin functions documented
- [ ] Upgrade path documented (if applicable)

## Deployment
- [ ] Deployer keys secured
- [ ] Constructor args verified
- [ ] Etherscan verification ready
- [ ] Monitoring/alerts configured
```

### 5.2 Update Existing Checklists

Merge ConsenSys patterns into:
- `CHECKLIST.md` - General development
- `AUDIT_CHECKLIST.md` - Security findings

---

## Implementation Timeline 📅

### Week 1: Documentation
- [ ] KNOWN-ATTACKS.md
- [ ] SECURITY-PHILOSOPHY.md
- [ ] DEPLOYMENT-CHECKLIST.md

### Week 2: Code Patterns
- [ ] PATTERNS.md with examples
- [ ] Update HARDENED-CODE.md
- [ ] Create contracts/security/ directory

### Week 3: Tooling
- [ ] Slither CI integration
- [ ] Local analysis scripts
- [ ] SECURITY-TOOLS.md

### Week 4: Attack Mitigations
- [ ] CommitReveal.sol
- [ ] OracleConsumer.sol
- [ ] Update AUDIT_CHECKLIST.md

---

## Quick Wins (Do Now) 🚀

1. **Add Slither to CI** - Catches 80% of common issues
2. **Create KNOWN-ATTACKS.md** - Reference for all devs
3. **Update AUDIT_CHECKLIST.md** - Add ConsenSys patterns
4. **Add CEI pattern to PATTERNS.md** - Most important pattern

---

## References

- [ConsenSys Best Practices](https://consensysdiligence.github.io/smart-contract-best-practices/)
- [Smart Contract Security Field Guide](https://scsfg.io/)
- [SWC Registry](https://swcregistry.io/)
- [Slither](https://github.com/crytic/slither)
- [Echidna](https://github.com/crytic/echidna)

---

*Generated by Ember 🐉 | 2026-01-29*
