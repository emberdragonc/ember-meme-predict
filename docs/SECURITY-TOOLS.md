# Security Tools 🛠️

Tools for smart contract security analysis, testing, and verification.

---

## Quick Reference

| Tool | Type | CI Integration | Use Case |
|------|------|----------------|----------|
| **Slither** | Static Analysis | ✅ Required | General vulnerability detection |
| **Foundry Fuzz** | Fuzzing | ✅ Required | Property-based testing |
| **Echidna** | Fuzzing | Optional | Advanced invariant testing |
| **Mythril** | Symbolic Exec | Optional | Deep vulnerability analysis |
| **Certora** | Formal Verify | Enterprise | Mathematical proofs |

---

## Slither (Required)

**Trail of Bits' static analysis framework.**

### Installation
```bash
pip3 install slither-analyzer

# Or with pipx (recommended)
pipx install slither-analyzer
```

### Usage
```bash
# Basic analysis
slither .

# With specific detectors
slither . --detect reentrancy-eth,reentrancy-no-eth

# Exclude test files
slither . --filter-paths "test|lib"

# JSON output
slither . --json slither-report.json

# Print human-readable report
slither . --print human-summary
```

### CI Integration (Already in pipeline.yml)
```yaml
- name: Run Slither
  uses: crytic/slither-action@v0.4.0
  with:
    target: 'contracts/'
    slither-args: '--exclude naming-convention,solc-version'
    fail-on: 'high'
```

### Key Detectors
| Detector | Severity | Description |
|----------|----------|-------------|
| `reentrancy-eth` | High | ETH reentrancy |
| `reentrancy-no-eth` | Medium | Non-ETH reentrancy |
| `arbitrary-send-eth` | High | Arbitrary ETH transfer |
| `controlled-delegatecall` | High | Delegatecall to user input |
| `unchecked-transfer` | High | Unchecked ERC20 transfer |
| `divide-before-multiply` | Medium | Precision loss |
| `unused-return` | Medium | Unused return values |

### Configuration File
Create `slither.config.json`:
```json
{
  "filter_paths": ["lib", "test", "script"],
  "exclude_informational": true,
  "exclude_low": false,
  "detectors_to_exclude": [
    "naming-convention",
    "solc-version"
  ]
}
```

---

## Foundry Fuzz Testing (Required)

**Built into Forge, essential for property testing.**

### Basic Fuzz Test
```solidity
// test/MyContract.t.sol
contract MyContractTest is Test {
    MyContract target;
    
    function setUp() public {
        target = new MyContract();
    }
    
    // Fuzz test: Foundry will try many random inputs
    function testFuzz_Deposit(uint256 amount) public {
        vm.assume(amount > 0 && amount < 1e30); // Bounds
        
        deal(address(this), amount);
        target.deposit{value: amount}();
        
        assertEq(target.balances(address(this)), amount);
    }
}
```

### Invariant Testing
```solidity
contract InvariantTest is Test {
    MyContract target;
    
    function setUp() public {
        target = new MyContract();
    }
    
    // Foundry calls random functions, then checks invariant
    function invariant_TotalSupplyMatchesSum() public {
        uint256 sum = 0;
        for (uint i = 0; i < users.length; i++) {
            sum += target.balanceOf(users[i]);
        }
        assertEq(target.totalSupply(), sum);
    }
}
```

### Configuration (foundry.toml)
```toml
[fuzz]
runs = 1000           # Number of fuzz runs
max_test_rejects = 1000
seed = 0              # 0 = random seed

[invariant]
runs = 256            # Number of invariant test sequences
depth = 100           # Calls per sequence
fail_on_revert = false
```

### Running
```bash
# Run all tests including fuzz
forge test

# Run with more fuzz iterations
forge test --fuzz-runs 10000

# Run specific fuzz test
forge test --match-test testFuzz_Deposit -vvv
```

---

## Echidna (Advanced Fuzzing)

**Trail of Bits' property-based fuzzer.**

### Installation
```bash
# macOS
brew install echidna

# Linux (download binary)
wget https://github.com/crytic/echidna/releases/latest/download/echidna-linux
chmod +x echidna-linux
sudo mv echidna-linux /usr/local/bin/echidna
```

### Echidna Test Contract
```solidity
// contracts/test/EchidnaTest.sol
contract EchidnaTest is MyContract {
    // Properties return bool - should always return true
    function echidna_balance_never_negative() public view returns (bool) {
        return balances[msg.sender] >= 0;
    }
    
    function echidna_total_matches_sum() public view returns (bool) {
        return totalSupply == _calculateSum();
    }
}
```

### Configuration (echidna.config.yaml)
```yaml
testMode: "assertion"    # or "property"
testLimit: 50000         # Number of calls
shrinkLimit: 5000        # Shrinking iterations
seqLen: 100              # Sequence length
contractAddr: "0x..."    # Fixed contract address
deployer: "0x..."        # Deployer address
sender: ["0x..."]        # Caller addresses
```

### Running
```bash
echidna contracts/test/EchidnaTest.sol --contract EchidnaTest --config echidna.config.yaml
```

---

## Mythril (Symbolic Execution)

**ConsenSys' security analysis tool.**

### Installation
```bash
pip3 install mythril

# Or with Docker
docker pull mythx/myth
```

### Usage
```bash
# Analyze single file
myth analyze contracts/MyContract.sol

# Deep analysis (slow but thorough)
myth analyze contracts/MyContract.sol --execution-timeout 900

# Analyze deployed contract
myth analyze --address 0x... --rpc YOUR_RPC_URL
```

### Output
```
==== Integer Arithmetic Bugs ====
SWC ID: 101
Severity: High
Contract: MyContract
Function: withdraw
...
```

---

## Additional Tools

### Aderyn (Rust-based Analyzer)
```bash
# Install
cargo install aderyn

# Run
aderyn .
```

### Solhint (Linter)
```bash
# Install
npm install -g solhint

# Run
solhint 'contracts/**/*.sol'
```

### Forge Coverage
```bash
# Generate coverage report
forge coverage

# Generate LCOV report
forge coverage --report lcov

# View in browser (with genhtml)
genhtml lcov.info -o coverage
open coverage/index.html
```

---

## Local Security Scan Script

Create `scripts/security-scan.sh`:
```bash
#!/bin/bash
set -e

echo "🔍 Running Security Scan..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# 1. Format check
echo "📝 Checking format..."
forge fmt --check

# 2. Compile
echo "🔨 Compiling..."
forge build

# 3. Run tests
echo "🧪 Running tests..."
forge test -vvv

# 4. Gas report
echo "⛽ Gas report..."
forge test --gas-report

# 5. Slither (if installed)
if command -v slither &> /dev/null; then
    echo "🐍 Running Slither..."
    slither . --filter-paths "lib|test" --exclude naming-convention,solc-version || true
fi

# 6. Coverage
echo "📊 Coverage report..."
forge coverage

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ Security scan complete!"
```

Make executable:
```bash
chmod +x scripts/security-scan.sh
./scripts/security-scan.sh
```

---

## CI/CD Security Checklist

- [x] Slither runs on every PR
- [x] Fuzz tests run on every PR
- [ ] Echidna runs on release branches (optional)
- [x] Coverage report generated
- [x] Gas benchmarks tracked
- [ ] Mythril deep scan before mainnet (manual)

---

## Resources

- [Slither Documentation](https://github.com/crytic/slither/wiki)
- [Echidna Tutorial](https://github.com/crytic/building-secure-contracts/tree/master/program-analysis/echidna)
- [Foundry Fuzz Testing](https://book.getfoundry.sh/forge/fuzz-testing)
- [Trail of Bits Security Guidelines](https://github.com/crytic/building-secure-contracts)
