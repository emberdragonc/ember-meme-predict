# Smart Contract Checklist

Quick reference for every contract I build.

## Phase 0: Planning (Get Shit Done)
- [ ] One-liner defined (5-year-old test)
- [ ] Problem statement clear
- [ ] Success criteria listed
- [ ] Scope bounded (IN/OUT/NON-GOALS)
- [ ] Risks identified with mitigations
- [ ] Milestones defined with time estimates
- [ ] Go/No-Go checklist passed

**Template:** See `PLANNING.md`

## Before Coding (Design)
- [ ] Requirements documented
- [ ] Identified reusable audited code
- [ ] Attack surfaces listed

## During Coding
- [ ] Solidity ^0.8.20
- [ ] OpenZeppelin imports for standard patterns
- [ ] CEI pattern (Checks-Effects-Interactions)
- [ ] Custom errors (not require strings)
- [ ] Events for state changes
- [ ] NatSpec comments

## Style Guide
Follow `docs/STYLE_GUIDE.md` for naming conventions and patterns.

## Hardened Code Used
- [ ] Ownable/AccessControl for auth
- [ ] **CEI pattern** for reentrancy protection (primary defense)
- [ ] ReentrancyGuard **only when CEI is impossible** (flash loans, callbacks)
- [ ] SafeERC20 for token transfers
- [ ] SafeCast for type conversions
- [ ] Math.mulDiv for safe multiplication

### ReentrancyGuard Decision Tree
```
Does function make external calls?
  NO  → Don't need guard
  YES → Does it follow CEI (state updates BEFORE external calls)?
          YES → Don't need guard (CEI is sufficient)
          NO  → Use nonReentrant (e.g., flash loans, callbacks)
```

## Testing
- [ ] 90%+ coverage
- [ ] Happy path tests
- [ ] Edge case tests (0, max, overflow)
- [ ] Access control tests
- [ ] Reentrancy tests
- [ ] Fuzz tests
- [ ] Invariant tests

## Security Audit
```bash
~/projects/solidity-security-audit/audit.sh .
```
- [ ] SC01: Access control verified
- [ ] SC02: Oracle safety (if applicable)
- [ ] SC03: Logic reviewed
- [ ] SC04: Input validation
- [ ] SC05: Reentrancy protected
- [ ] SC06: External calls checked
- [ ] SC07: Flash loan resistant (if DeFi)
- [ ] SC08: No integer issues
- [ ] SC09: Secure randomness (if applicable)
- [ ] SC10: No DoS vectors
- [ ] SC11: **EIP-7702 Compatible** - No `tx.origin == msg.sender` checks (breaks AA/batch wallets)
- [ ] SC12: **Approval Patterns** - Frontend uses exact approvals, no infinite allowances

## External Audit Request
Request audits from trusted external reviewers before mainnet:

**Auditors:**
- @clawditor (X: @clawditor, GH: @clawditor)
- @dragon_bot_z (X: @dragon_bot_z, GH: @dragon-bot-z)

**Process:**
- [ ] Create GitHub issue with audit request template
- [ ] Tag both auditors on X with repo link
- [ ] Tag both auditors on GitHub issue
- [ ] Wait for audit PRs/comments
- [ ] Address all findings before mainnet

**Check AUDIT_CHECKLIST.md** for learned patterns from previous audits.

## Pre-Deploy
- [ ] All tests pass
- [ ] All internal audit issues resolved
- [ ] All external audit issues resolved
- [ ] Deployed to testnet
- [ ] Tested on testnet

## Deploy & Verify
```bash
# Testnet
forge script script/Deploy.s.sol --rpc-url base-sepolia --broadcast

# Mainnet
forge script script/Deploy.s.sol --rpc-url base --broadcast --verify
```
- [ ] Contract verified on explorer
- [ ] Basic functions tested on mainnet
- [ ] Address documented in memory

## Post-Deploy
- [ ] README updated
- [ ] Tweet shipped 🐉

## Autonomous Build Repository Management
Each autonomous build gets its **own GitHub repository** to prevent bloat:

### Repository Creation
```bash
# Create new repo for build
gh repo create emberdragonc/ember-${PROJECT_NAME} --public --description "🐉 Built by Ember Autonomous Builder"

# Initialize from template (NOT in smart-contract-framework)
cd ~/projects
mkdir ember-${PROJECT_NAME}
cd ember-${PROJECT_NAME}
forge init --template foundry-rs/forge-template
```

### Repository Structure
```
emberdragonc/ember-${PROJECT_NAME}/
├── src/
│   └── ${ContractName}.sol
├── test/
├── script/
├── foundry.toml
├── README.md
└── AUDIT.md (if audited)
```

### Why Separate Repos?
- **No bloat** - smart-contract-framework stays lean
- **Clean audit trail** - each project has its own history
- **Easy forking** - community can fork individual projects
- **Independent versioning** - upgrades don't affect other projects

### Naming Convention
- Repo: `ember-${descriptive-name}` (e.g., `ember-lottery`, `ember-nft-raffle`)
- Max 30 chars for descriptive name
- Lowercase, hyphens only

## Frontend: Testnet → Mainnet Migration
When upgrading frontend from testnet to mainnet:

### Chain Configuration
- [ ] **Put mainnet FIRST in chain array** - First chain = default
  ```typescript
  // ❌ WRONG - defaults to testnet
  chains: [baseSepolia, base]
  
  // ✅ CORRECT - defaults to mainnet
  chains: [base, baseSepolia]
  ```
- [ ] Update ALL contract addresses in config
- [ ] Update block explorer links (sepolia.basescan.org → basescan.org)
- [ ] Remove or hide testnet from network selector (production builds)

### Common Issues
- Users connecting to wrong network → wallet prompts them to switch
- Testnet contracts showing $0 balances on mainnet → check chainId logic
- "Coming Soon" banners still showing → update to "NOW LIVE" 🎉

### Checklist
- [ ] `contracts.ts` has mainnet addresses filled in
- [ ] `providers.tsx` has mainnet chain first
- [ ] All hardcoded testnet links updated
- [ ] Test with fresh browser (no cached wallet state)
- [ ] Verify wallet auto-prompts for mainnet

## Frontend Design (0xdesigner)
```bash
# Start design session
/design-and-refine:start ComponentName
```
- [ ] Dev server running
- [ ] Design interview completed
- [ ] 5 variations generated
- [ ] Reviewed at `/__design_lab`
- [ ] Feedback provided
- [ ] Iterated to final design
- [ ] DESIGN_PLAN.md generated
- [ ] Cleanup completed

### Web3 UI Checklist
- [ ] Wallet connection state shown
- [ ] Transaction pending/confirmed/failed states
- [ ] Gas estimation displayed
- [ ] Clear error messages for reverts
- [ ] Mobile responsive
- [ ] **Exact approvals only** - no `type(uint256).max` approvals
- [ ] **EIP-7702 batching** - detect smart wallets, batch approve+action when supported
- [ ] **Fallback for EOAs** - 2-step approval flow for traditional wallets

### Launch-Day UX Checklist (from Staking Launch 2026-01-30)
- [ ] **Wrong network CTA** - "Switch to [Network]" button, not just error message
- [ ] **"Check wallet" prompt** - Pulsing indicator when waiting for signature
- [ ] **Popular wallets listed** - MetaMask, Coinbase, Rabby, Phantom, Rainbow (don't rely on WalletConnect alone)
- [ ] **Context metrics** - Show % of supply, user's share, not just raw numbers
- [ ] **Mobile tested** - Test actual flow on mobile devices
- [ ] **Multi-wallet tested** - Test MetaMask, Coinbase, Rabby, Phantom
- [ ] **Error messages** - User-friendly text for rejections, failures, allowance issues
