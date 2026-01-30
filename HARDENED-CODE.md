# Hardened Code Reference

Battle-tested, audited contracts to use instead of custom implementations.

## OpenZeppelin Contracts
**Install:** `forge install OpenZeppelin/openzeppelin-contracts`
**Remapping:** `@openzeppelin/=lib/openzeppelin-contracts/`

### Access Control
```solidity
// Single owner
import "@openzeppelin/contracts/access/Ownable.sol";
contract MyContract is Ownable {
    constructor() Ownable(msg.sender) {}
}

// Role-based
import "@openzeppelin/contracts/access/AccessControl.sol";
contract MyContract is AccessControl {
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
}

// Two-step ownership (recommended)
import "@openzeppelin/contracts/access/Ownable2Step.sol";
```

### Security
```solidity
// Reentrancy protection
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
contract MyContract is ReentrancyGuard {
    function withdraw() external nonReentrant { }
}

// Pausable
import "@openzeppelin/contracts/utils/Pausable.sol";
contract MyContract is Pausable {
    function sensitiveAction() external whenNotPaused { }
}
```

### Tokens
```solidity
// ERC20
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

// Safe transfers (handles non-standard tokens like USDT)
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
using SafeERC20 for IERC20;
token.safeTransfer(to, amount);
token.safeTransferFrom(from, to, amount);

// ERC721
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";

// ERC1155
import "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
```

### Math
```solidity
// Safe multiplication with division (prevents overflow)
import "@openzeppelin/contracts/utils/math/Math.sol";
uint result = Math.mulDiv(a, b, c); // (a * b) / c without overflow

// Safe type casting
import "@openzeppelin/contracts/utils/math/SafeCast.sol";
using SafeCast for uint256;
uint128 small = bigNumber.toUint128(); // Reverts if overflow
```

### Upgrades
```solidity
// UUPS (recommended)
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

// Initializable
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
```

### Governance
```solidity
// ERC20 with voting
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Votes.sol";

// Governor
import "@openzeppelin/contracts/governance/Governor.sol";

// Timelock
import "@openzeppelin/contracts/governance/TimelockController.sol";
```

### Finance
```solidity
// Vesting
import "@openzeppelin/contracts/finance/VestingWallet.sol";

// Payment splitter
import "@openzeppelin/contracts/finance/PaymentSplitter.sol";
```

---

## Solmate (Gas-Optimized)
**Install:** `forge install transmissions11/solmate`
**Remapping:** `solmate/=lib/solmate/src/`

```solidity
// Gas-optimized ERC20
import "solmate/tokens/ERC20.sol";

// Gas-optimized ERC721
import "solmate/tokens/ERC721.sol";

// Gas-optimized ownership
import "solmate/auth/Owned.sol";

// Safe transfers
import "solmate/utils/SafeTransferLib.sol";
```

---

## Synthetix (Staking)
**Install:** `forge install Synthetixio/synthetix`

```solidity
// Battle-tested staking rewards
// DO NOT MODIFY - use as-is
import "synthetix/contracts/StakingRewards.sol";
```

### Staking Deployment Pattern
```solidity
// Deploy unmodified StakingRewards
StakingRewards staking = new StakingRewards(
    owner,           // Owner address
    rewardsDistributor, // Who can notify rewards
    rewardsToken,    // Token to distribute (WETH)
    stakingToken     // Token users stake
);
```

---

## Chainlink (Oracles & VRF)
**Install:** `forge install smartcontractkit/chainlink`

```solidity
// Price feeds
import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

function getPrice() public view returns (uint) {
    (, int price,, uint updatedAt,) = priceFeed.latestRoundData();
    require(block.timestamp - updatedAt < 3600, "Stale");
    return uint(price);
}

// VRF (secure randomness)
import "@chainlink/contracts/src/v0.8/vrf/VRFConsumerBaseV2.sol";
```

---

## Uniswap (DEX Integration)
**Install:** `forge install Uniswap/v3-periphery`

```solidity
// Swap router
import "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";

// TWAP oracle
import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
```

---

## EIP-7702 Compatibility (Smart Wallets)

EIP-7702 enables EOAs to delegate to smart contract code, enabling batching and account abstraction.

### ⚠️ Contract Compatibility Checklist
```solidity
// ❌ NEVER DO THIS - breaks smart wallets
require(tx.origin == msg.sender, "No contracts");

// ❌ ALSO BAD - same problem
if (tx.origin != msg.sender) revert NotEOA();

// ✅ DO THIS INSTEAD - use reentrancy guards
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
contract MyContract is ReentrancyGuard {
    function deposit() external nonReentrant { }
}
```

### Why tx.origin Checks Break
With EIP-7702, a user's EOA can delegate to smart contract code. When they use batching:
- `tx.origin` = user's address
- `msg.sender` = user's address (via delegation)
- But `tx.origin == msg.sender` check may still fail depending on implementation

**Bottom line:** Use `ReentrancyGuard` instead of `tx.origin` checks. It's more secure AND compatible with smart wallets.

---

## Approval Patterns (Frontend Security)

### ❌ NEVER: Infinite Approvals
```typescript
// DON'T DO THIS - exposes user to unlimited loss if contract exploited
const MAX_UINT256 = 2n ** 256n - 1n;
approve(spender, MAX_UINT256); // BAD!
```

### ✅ ALWAYS: Exact Approvals
```typescript
// Approve exactly what's needed for this transaction
const exactAmount = parseUnits('100', 6); // 100 USDC
approve(spender, exactAmount); // GOOD!
```

### EIP-7702 Batching (Best UX)
With smart wallets, you can batch approve + action into one user confirmation:

```typescript
// Check for batching support
const capabilities = await walletClient.request({
  method: 'wallet_getCapabilities',
  params: [address],
});
const supportsBatching = capabilities?.[chainId]?.atomicBatch?.supported;

if (supportsBatching) {
  // Single confirmation for approve + deposit
  await walletClient.request({
    method: 'wallet_sendCalls',
    params: [{
      version: '1.0',
      chainId: `0x${chainId.toString(16)}`,
      from: address,
      calls: [
        { to: tokenAddress, data: approveCalldata },
        { to: contractAddress, data: depositCalldata },
      ],
    }],
  });
} else {
  // Fallback: two separate transactions
  await approve(spender, exactAmount);
  await deposit(amount);
}
```

---

## DO NOT Implement Custom

| ❌ Don't Build | ✅ Use Instead |
|---------------|----------------|
| Custom ERC20 | OpenZeppelin ERC20 |
| Custom ERC721 | OpenZeppelin ERC721 |
| Custom ownership | Ownable/Ownable2Step |
| Custom reentrancy lock | ReentrancyGuard |
| Custom token transfers | SafeERC20 |
| Custom staking math | Synthetix StakingRewards |
| Custom governance | OpenZeppelin Governor |
| Custom randomness | Chainlink VRF |
| Custom price feeds | Chainlink Oracles |
| Custom vesting | VestingWallet |

---

*"Don't be clever. Be correct."* 🐉
