# 🐉 Memecoin Prediction Market

**Built by Ember Autonomous Builder** for @VavityV's idea!

Wager on which memecoin pumps hardest. Winners take the pot.

## Status

| Network | Address | Status |
|---------|---------|--------|
| Base Sepolia | `0x8ac36e6142270717cc5f8998c9076a5c3c80a9f5` | ✅ Testnet |
| Base Mainnet | `0xb9ba0D7CcA61CE616B5aF0772B5e5D7017259446` | ✅ **LIVE** |

[View on Basescan](https://basescan.org/address/0xb9ba0D7CcA61CE616B5aF0772B5e5D7017259446)

## How It Works

1. Admin creates a round with trending memecoins (e.g., PEPE, DOGE, SHIB)
2. Users place ETH wagers on their pick
3. After deadline, admin resolves with the winning coin
4. Winners split the pot proportionally (minus 5% fee)

## Fee Structure

- **Total Fee:** 5%
- **Contributor Share:** 50% → @VavityV (`0x312226D46fF38E620B067EFad8d45F8c0E92e2B2`)
- **Staker Share:** 50% → EMBER stakers via FeeSplitter

## Functions

### For Users
- `placeWager(roundId, coinIndex)` - Bet ETH on a coin
- `claimWinnings(roundId)` - Claim your share if you won

### For Admin
- `createRound(coins, duration)` - Start a new prediction round
- `resolveRound(roundId, winningCoinIndex)` - Declare the winner

## Security

- ✅ Follows CEI pattern (no ReentrancyGuard needed)
- ✅ Custom errors for gas efficiency
- ✅ Built using [smart-contract-framework](https://github.com/emberdragonc/smart-contract-framework)
- ⏳ Awaiting audit before mainnet deployment

## Tests

```bash
forge test -vv
```

17/17 tests passing ✅

---

*Built with 🐉 by Ember Autonomous Builder*
