# Solidity Style Guide 🐉

Ember's opinionated style guide for consistent, gas-efficient smart contracts.

## Contract Layout

Order your contract sections consistently:

```solidity
// 1. Type declarations (structs, enums)
// 2. State variables (constants, immutables, then regular)
// 3. Events
// 4. Custom errors
// 5. Modifiers
// 6. Constructor
// 7. External functions
// 8. External view functions
// 9. Public functions
// 10. Public view functions
// 11. Internal functions
// 12. Internal view functions
// 13. Private functions
// 14. Private view functions
```

## Imports

Sort imports: external dependencies first, then local. Use named imports.

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

// External (alphabetical)
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

// Local
import { IMyContract } from "./interfaces/IMyContract.sol";
```

## Naming Conventions

### Constants
All caps with underscores:
```solidity
uint256 public constant MAX_SUPPLY = 1_000_000;
uint256 private constant FEE_BPS = 300;
```

### State Variables
mixedCase, no underscores:
```solidity
address public treasury;
mapping(address user => uint256 balance) public balances;
```

### Function Parameters
Underscore prefix:
```solidity
function deposit(address _token, uint256 _amount) external {
```

### Local Variables
Underscore suffix:
```solidity
function calculate() internal view returns (uint256 result_) {
    uint256 temp_ = balances[msg.sender];
    result_ = temp_ * 2;
}
```

### Events
CapWords, past tense for actions:
```solidity
event Deposited(address indexed user, uint256 amount);
event FeeUpdated(uint256 oldFee, uint256 newFee);
```

### Custom Errors
CapWords, descriptive:
```solidity
error InsufficientBalance();
error InvalidRecipient();
error UnauthorizedCaller();
```

### Modifiers
mixedCase:
```solidity
modifier onlyAdmin() { }
modifier whenNotPaused() { }
```

## CEI Pattern (Checks-Effects-Interactions)

**Always follow CEI.** This is your primary reentrancy defense.

```solidity
function withdraw(uint256 _amount) external {
    // 1. CHECKS - Validate inputs and state
    if (_amount == 0) revert ZeroAmount();
    if (balances[msg.sender] < _amount) revert InsufficientBalance();
    
    // 2. EFFECTS - Update state BEFORE external calls
    balances[msg.sender] -= _amount;
    
    // 3. INTERACTIONS - External calls last
    (bool success,) = msg.sender.call{ value: _amount }("");
    if (!success) revert TransferFailed();
}
```

## When to Use ReentrancyGuard

**Only use `nonReentrant` when CEI is impossible.** Adding it unnecessarily wastes gas.

### ❌ DON'T use when CEI is followed:
```solidity
// BAD - CEI already prevents reentrancy, guard is wasted gas
function withdraw(uint256 _amount) external nonReentrant {
    if (balances[msg.sender] < _amount) revert InsufficientBalance();
    balances[msg.sender] -= _amount;  // Effect before interaction
    (bool success,) = msg.sender.call{ value: _amount }("");
    if (!success) revert TransferFailed();
}
```

### ✅ DO use when CEI cannot be followed:
```solidity
// GOOD - External call must happen before state update
function flashLoan(uint256 _amount) external nonReentrant {
    uint256 balanceBefore_ = address(this).balance;
    
    // Interaction happens BEFORE we can check the effect
    (bool success,) = msg.sender.call{ value: _amount }("");
    if (!success) revert TransferFailed();
    
    // Check happens AFTER interaction - CEI violated, guard needed
    if (address(this).balance < balanceBefore_) revert LoanNotRepaid();
}
```

### When ReentrancyGuard IS needed:
- Flash loans (must send before checking repayment)
- Callbacks that read state (ERC721 `onERC721Received`, etc.)
- Cross-function reentrancy (multiple functions share state)
- Complex DeFi integrations with untrusted external contracts

### When ReentrancyGuard is NOT needed:
- Simple transfers following CEI
- Pure/view functions
- Functions with no external calls
- Functions where state updates complete before any external call

## Number Formatting

Use underscores for large numbers:
```solidity
uint256 constant TOTAL_SUPPLY = 1_000_000_000e18;
uint256 constant MAX_BPS = 10_000;
```

## NatSpec Comments

Always document public/external functions:
```solidity
/// @notice Deposits tokens into the vault
/// @param _token The token address to deposit
/// @param _amount The amount to deposit
/// @return shares_ The shares minted
function deposit(address _token, uint256 _amount) external returns (uint256 shares_) {
```

## Gas Optimization Tips

1. **Cache storage reads** - Read once, use many times
2. **Use custom errors** - Cheaper than require strings
3. **Pack structs** - Order by size (uint256, uint128, address, uint96, etc.)
4. **Use unchecked** - When overflow is impossible
5. **Skip ReentrancyGuard** - When CEI is sufficient

## File Naming

- Contracts: `PascalCase.sol` (e.g., `EmberStaking.sol`)
- Interfaces: `IPascalCase.sol` (e.g., `IEmberStaking.sol`)
- Libraries: `PascalCaseLib.sol` (e.g., `MathLib.sol`)
- Tests: `PascalCase.t.sol` (e.g., `EmberStaking.t.sol`)

---

*Based on industry best practices and the MetaMask Delegation Framework style guide.*
