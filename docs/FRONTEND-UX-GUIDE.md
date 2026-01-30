# Frontend UX Guide for Web3 Apps

Guidelines for building production-ready Web3 frontends. Based on real launch-day issues from Ember Staking (2026-01-30).

---

## Network Handling

### Wrong Network State
**Never** just show an error message. Always provide an actionable button.

```tsx
// ❌ Bad
if (chainId !== targetChainId) {
  return <p>Please switch to Base</p>;
}

// ✅ Good
import { useSwitchChain } from 'wagmi';

const { switchChain } = useSwitchChain();

if (chainId !== targetChainId) {
  return (
    <div>
      <p>Wrong network detected</p>
      <button onClick={() => switchChain({ chainId: base.id })}>
        Switch to Base
      </button>
    </div>
  );
}
```

### Chain Order Matters
First chain in array = default network. Always put mainnet first for production.

```tsx
// ❌ Bad - testnet becomes default
chains: [baseSepolia, base]

// ✅ Good - mainnet is default
chains: [base, baseSepolia]
```

---

## Wallet Connection

### List Popular Wallets Explicitly
Don't rely on WalletConnect fallback. Users expect to see their wallet listed.

```tsx
import { 
  metaMaskWallet, 
  coinbaseWallet,
  rabbyWallet,
  phantomWallet,
  rainbowWallet,
  walletConnectWallet,
} from '@rainbow-me/rainbowkit/wallets';

const connectors = connectorsForWallets([
  {
    groupName: 'Popular',
    wallets: [
      metaMaskWallet,
      coinbaseWallet,
      rabbyWallet,
      phantomWallet,  // Don't forget Phantom!
      rainbowWallet,
      walletConnectWallet,  // Fallback for others
    ],
  },
], { appName: 'My App', projectId });
```

---

## Token Approvals

### Use Exact Amounts
Infinite approvals scare users and trigger wallet warnings.

```tsx
// ❌ Bad - scary for users
const MAX_UINT256 = 2n ** 256n - 1n;
approve(spender, MAX_UINT256);

// ✅ Good - exact amount
const stakeAmount = parseEther(userInput);
approve(spender, stakeAmount);
```

### EIP-7702 Batching for Smart Wallets
Smart wallets (Coinbase, Ambire) support batching approve+action into one tx.

```tsx
import { useWalletClient } from 'wagmi';
import { encodeFunctionData } from 'viem';

const { data: walletClient } = useWalletClient();
const [supportsBatching, setSupportsBatching] = useState(false);

// Detect batching support
useEffect(() => {
  async function check() {
    if (!walletClient) return;
    try {
      const caps = await walletClient.request({
        method: 'wallet_getCapabilities',
        params: [address],
      });
      const chainCaps = caps?.[`0x${chainId.toString(16)}`];
      setSupportsBatching(chainCaps?.atomicBatch?.supported === true);
    } catch {
      setSupportsBatching(false); // EOA wallet
    }
  }
  check();
}, [walletClient, chainId, address]);

// Batch approve + action
async function handleBatchedAction() {
  const approveData = encodeFunctionData({
    abi: ERC20_ABI,
    functionName: 'approve',
    args: [contractAddress, amount],
  });
  
  const actionData = encodeFunctionData({
    abi: CONTRACT_ABI,
    functionName: 'stake',
    args: [amount],
  });
  
  await walletClient.request({
    method: 'wallet_sendCalls',
    params: [{
      version: '1.0',
      chainId: `0x${chainId.toString(16)}`,
      from: address,
      calls: [
        { to: tokenAddress, data: approveData },
        { to: contractAddress, data: actionData },
      ],
    }],
  });
}
```

---

## Transaction Feedback

### Always Show Pending State
Users need to know when to check their wallet.

```tsx
// ✅ Good
{isPending && (
  <div className="animate-pulse">
    👛 Please confirm in your wallet...
  </div>
)}
```

### User-Friendly Error Messages
Don't show raw error messages. Translate them.

```tsx
onError: (err) => {
  if (err.message?.includes('rejected') || err.message?.includes('denied')) {
    setError('Transaction rejected by user');
  } else if (err.message?.includes('insufficient')) {
    setError('Insufficient token balance');
  } else if (err.message?.includes('allowance')) {
    setError('Approval needed first');
  } else {
    setError('Transaction failed. Please try again.');
  }
}
```

---

## Stats & Metrics

### Show Context, Not Just Numbers
Raw numbers are meaningless without context.

```tsx
// ❌ Bad
<p>Total Staked: 50,000,000</p>

// ✅ Good
<p>Total Staked: 50,000,000 EMBER</p>
<p>Supply Staked: 5.00%</p>  {/* Shows adoption context */}
<p>Your Share: 2.50%</p>     {/* Shows user's position */}
```

---

## Pre-Launch Checklist

### Network & Wallet
- [ ] Mainnet FIRST in chain array
- [ ] "Switch Network" button (not just error message)
- [ ] Popular wallets explicitly listed
- [ ] WalletConnect as fallback

### Transactions
- [ ] Exact approvals (not infinite)
- [ ] EIP-7702 batching for smart wallets
- [ ] 2-step fallback for EOA wallets
- [ ] "Check wallet" prompt during pending
- [ ] User-friendly error messages
- [ ] Loading states for all async ops

### Stats & Display
- [ ] Context metrics (%, shares)
- [ ] Number formatting with locale
- [ ] Token symbols shown

### Testing
- [ ] Mobile browser (iOS Safari, Android Chrome)
- [ ] MetaMask (most popular EOA)
- [ ] Coinbase Wallet (smart wallet batching)
- [ ] Rabby (popular among DeFi users)
- [ ] Phantom (if targeting Solana crossover)
- [ ] Wrong network → switch flow
- [ ] Rejection → error message
- [ ] Insufficient balance → error message

---

## Common Pitfalls

| Pitfall | Impact | Solution |
|---------|--------|----------|
| Testnet first in chains | Users default to wrong network | Mainnet first |
| Infinite approvals | Scares users, security risk | Exact amounts |
| No network switch button | Users stuck | useSwitchChain + button |
| Missing wallet in list | Users think not supported | List top 5+ explicitly |
| No pending indicator | Users confused | "Check wallet" banner |
| Raw error messages | Users confused | Translate to friendly text |
| Just raw numbers | No context | Add %, shares, symbols |

---

*Last updated: 2026-01-30 after Ember Staking launch*
