# Pre-Deployment Checklist ✅

Complete this checklist before any mainnet deployment.

---

## 1. Code Review

### General
- [ ] All TODO/FIXME comments resolved
- [ ] No console.log or debug code
- [ ] No hardcoded test addresses/values
- [ ] License headers on all files
- [ ] NatSpec documentation complete

### Security Patterns
- [ ] CEI pattern followed (Checks-Effects-Interactions)
- [ ] ReentrancyGuard on all state-changing external calls
- [ ] Access control on admin functions
- [ ] Events emitted for all state changes
- [ ] Custom errors used (not require strings)

### External Interactions
- [ ] All external calls identified and reviewed
- [ ] External calls use .call() not .transfer()/.send()
- [ ] Return values checked on all external calls
- [ ] SafeERC20 used for token transfers
- [ ] Untrusted contracts marked in naming

### Input Validation
- [ ] All inputs validated (zero address, zero amount, bounds)
- [ ] Array lengths checked
- [ ] Overflow protection (Solidity 0.8+ or SafeMath)

---

## 2. Testing

### Coverage
- [ ] Unit test coverage > 90%
- [ ] All public/external functions tested
- [ ] Edge cases covered
- [ ] Revert conditions tested

### Fuzz Testing
- [ ] Fuzz tests for math operations
- [ ] Fuzz tests for user inputs
- [ ] At least 1000 fuzz runs per test

### Integration/Fork Tests
- [ ] Fork tests against mainnet state
- [ ] External protocol interactions tested
- [ ] Gas costs within acceptable limits

### Invariant Tests
- [ ] Key protocol invariants defined
- [ ] Invariant tests pass with 256+ runs

---

## 3. Security Analysis

### Static Analysis
- [ ] Slither passes with no high/medium issues
- [ ] All Slither warnings reviewed and documented
- [ ] Aderyn scan completed (if applicable)

### Manual Review
- [ ] Known attack vectors checklist reviewed
- [ ] All findings from AUDIT_CHECKLIST.md addressed
- [ ] Admin key security reviewed
- [ ] Upgrade mechanism reviewed (if applicable)

### External Audit
- [ ] Code frozen for audit
- [ ] Audit report received
- [ ] All critical/high findings fixed
- [ ] Medium findings addressed or accepted with rationale

---

## 4. Documentation

### Technical
- [ ] README updated with deployment instructions
- [ ] Architecture diagram current
- [ ] All external dependencies documented
- [ ] Upgrade process documented (if applicable)

### User-Facing
- [ ] Function documentation complete
- [ ] Integration guide for developers
- [ ] Known limitations documented

### Internal
- [ ] Admin runbook created
- [ ] Incident response plan documented
- [ ] Emergency contact list current

---

## 5. Pre-Deployment Setup

### Keys & Access
- [ ] Deployer wallet funded
- [ ] Multisig setup (if applicable)
- [ ] Hardware wallet tested
- [ ] Admin keys secured (not hot wallet)

### Infrastructure
- [ ] RPC endpoints tested
- [ ] Etherscan API key ready
- [ ] Monitoring/alerting configured
- [ ] Subgraph deployed (if applicable)

### Contingency
- [ ] Pause mechanism tested
- [ ] Emergency withdrawal tested
- [ ] Rollback plan documented

---

## 6. Deployment

### Pre-Flight
- [ ] Gas prices acceptable
- [ ] No network congestion
- [ ] Team available for monitoring

### Deployment Steps
- [ ] Constructor arguments double-checked
- [ ] Initial state values verified
- [ ] Deployment script tested on testnet

### Post-Deployment
- [ ] Contract addresses recorded
- [ ] Etherscan verification successful
- [ ] Initial state verified on-chain
- [ ] Monitoring alerts confirmed working

---

## 7. Post-Deployment

### Immediate (0-24h)
- [ ] All contract functions tested on mainnet
- [ ] Monitoring dashboards checked
- [ ] Initial users onboarded successfully

### Short-term (1-7 days)
- [ ] No unexpected behavior observed
- [ ] Gas costs as expected
- [ ] User feedback addressed

### Ongoing
- [ ] Bug bounty program live
- [ ] Security monitoring active
- [ ] Regular security reviews scheduled

---

## Emergency Contacts

| Role | Contact | Availability |
|------|---------|--------------|
| Lead Dev | @handle | 24/7 |
| Security | @handle | 24/7 |
| Ops | @handle | Business hours |

---

## Sign-off

| Role | Name | Date | Signature |
|------|------|------|-----------|
| Dev Lead | | | |
| Security | | | |
| Product | | | |

---

## Quick Commands

```bash
# Final test run
forge test -vvv

# Coverage check
forge coverage

# Slither scan
slither . --filter-paths "lib|test"

# Gas report
forge test --gas-report > gas-report.txt

# Deploy (example)
forge script script/Deploy.s.sol --rpc-url $RPC_URL --broadcast --verify
```
