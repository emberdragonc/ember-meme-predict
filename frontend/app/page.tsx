'use client';

import { useState, useEffect } from 'react';
import { ConnectButton } from '@rainbow-me/rainbowkit';
import { useAccount, useReadContract, useWriteContract, useWaitForTransactionReceipt, usePublicClient, useWalletClient } from 'wagmi';
import { parseEther, formatEther, parseUnits, erc20Abi, type Address, encodeFunctionData } from 'viem';
import { track } from '@vercel/analytics';

// Contract ABI (minimal for Example contract)
const CONTRACT_ABI = [
  {
    name: 'deposit',
    type: 'function',
    stateMutability: 'payable',
    inputs: [],
    outputs: [],
  },
  {
    name: 'withdraw',
    type: 'function',
    stateMutability: 'nonpayable',
    inputs: [{ name: 'amount', type: 'uint256' }],
    outputs: [],
  },
  {
    name: 'balances',
    type: 'function',
    stateMutability: 'view',
    inputs: [{ name: '', type: 'address' }],
    outputs: [{ type: 'uint256' }],
  },
  {
    name: 'totalDeposits',
    type: 'function',
    stateMutability: 'view',
    inputs: [],
    outputs: [{ type: 'uint256' }],
  },
  {
    name: 'depositToken',
    type: 'function',
    stateMutability: 'nonpayable',
    inputs: [
      { name: 'token', type: 'address' },
      { name: 'amount', type: 'uint256' }
    ],
    outputs: [],
  },
] as const;

const CONTRACT_ADDRESS = process.env.NEXT_PUBLIC_CONTRACT_ADDRESS as `0x${string}`;

// =============================================================================
// EIP-7702 BATCHING UTILITIES
// =============================================================================

/**
 * Check if the wallet supports EIP-7702 batching (wallet_sendCalls)
 * Smart wallets (Coinbase, Ambire, etc.) support this, EOAs don't
 */
async function supportsEIP7702(walletClient: any): Promise<boolean> {
  if (!walletClient) return false;
  
  try {
    // Check if wallet supports wallet_getCapabilities (EIP-5792)
    const capabilities = await walletClient.request({
      method: 'wallet_getCapabilities',
      params: [walletClient.account.address],
    });
    
    // Check for atomicBatch capability on the current chain
    const chainId = await walletClient.getChainId();
    return capabilities?.[chainId]?.atomicBatch?.supported === true;
  } catch {
    // wallet_getCapabilities not supported = no batching
    return false;
  }
}

/**
 * Execute batched calls using EIP-7702 (wallet_sendCalls)
 * This allows approve + action in a single user confirmation
 */
async function sendBatchedCalls(
  walletClient: any,
  calls: Array<{ to: Address; data: `0x${string}`; value?: bigint }>
): Promise<`0x${string}`> {
  const result = await walletClient.request({
    method: 'wallet_sendCalls',
    params: [{
      version: '1.0',
      chainId: `0x${walletClient.chain.id.toString(16)}`,
      from: walletClient.account.address,
      calls: calls.map(call => ({
        to: call.to,
        data: call.data,
        value: call.value ? `0x${call.value.toString(16)}` : '0x0',
      })),
    }],
  });
  
  return result as `0x${string}`;
}

// =============================================================================
// EXACT APPROVAL PATTERN
// =============================================================================

/**
 * SECURITY BEST PRACTICE: Exact Approvals Only
 * 
 * ❌ NEVER use infinite approvals (type(uint256).max)
 *    - If contract is compromised, attacker drains ALL your tokens
 *    - Unnecessary trust assumption
 * 
 * ✅ ALWAYS approve exact amounts
 *    - User approves only what's needed for this transaction
 *    - Minimizes exposure if contract is exploited
 *    - Better UX with EIP-7702 batching (approve + action in one tx)
 */

interface ApproveAndExecuteParams {
  tokenAddress: Address;
  spenderAddress: Address;
  amount: bigint;
  executeCall: {
    to: Address;
    data: `0x${string}`;
    value?: bigint;
  };
}

export default function Home() {
  const { address, isConnected } = useAccount();
  const publicClient = usePublicClient();
  const { data: walletClient } = useWalletClient();
  
  const [depositAmount, setDepositAmount] = useState('0.01');
  const [withdrawAmount, setWithdrawAmount] = useState('0.01');
  const [tokenDepositAmount, setTokenDepositAmount] = useState('100');
  const [selectedToken, setSelectedToken] = useState<Address>('0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913'); // USDC on Base
  
  // EIP-7702 support detection
  const [supports7702, setSupports7702] = useState(false);
  const [isCheckingCapabilities, setIsCheckingCapabilities] = useState(true);
  
  // Check for EIP-7702 support on wallet connect
  useEffect(() => {
    async function checkCapabilities() {
      if (walletClient) {
        setIsCheckingCapabilities(true);
        const supported = await supportsEIP7702(walletClient);
        setSupports7702(supported);
        setIsCheckingCapabilities(false);
      }
    }
    checkCapabilities();
  }, [walletClient]);

  // Read user balance
  const { data: userBalance, refetch: refetchBalance } = useReadContract({
    address: CONTRACT_ADDRESS,
    abi: CONTRACT_ABI,
    functionName: 'balances',
    args: address ? [address] : undefined,
  });

  // Read total deposits
  const { data: totalDeposits } = useReadContract({
    address: CONTRACT_ADDRESS,
    abi: CONTRACT_ABI,
    functionName: 'totalDeposits',
  });
  
  // Read current token allowance
  const { data: currentAllowance, refetch: refetchAllowance } = useReadContract({
    address: selectedToken,
    abi: erc20Abi,
    functionName: 'allowance',
    args: address ? [address, CONTRACT_ADDRESS] : undefined,
  });

  // Deposit ETH
  const { writeContract: deposit, data: depositHash, isPending: isDepositing } = useWriteContract();
  const { isLoading: isDepositConfirming, isSuccess: isDepositSuccess } = useWaitForTransactionReceipt({
    hash: depositHash,
  });

  // Withdraw
  const { writeContract: withdraw, data: withdrawHash, isPending: isWithdrawing } = useWriteContract();
  const { isLoading: isWithdrawConfirming, isSuccess: isWithdrawSuccess } = useWaitForTransactionReceipt({
    hash: withdrawHash,
  });
  
  // Approve token (for fallback path)
  const { writeContract: approve, data: approveHash, isPending: isApproving } = useWriteContract();
  const { isLoading: isApproveConfirming, isSuccess: isApproveSuccess } = useWaitForTransactionReceipt({
    hash: approveHash,
  });
  
  // Token deposit (for fallback path)
  const { writeContract: depositToken, data: tokenDepositHash, isPending: isTokenDepositing } = useWriteContract();
  const { isLoading: isTokenDepositConfirming, isSuccess: isTokenDepositSuccess } = useWaitForTransactionReceipt({
    hash: tokenDepositHash,
  });
  
  // Batched operation state
  const [batchTxId, setBatchTxId] = useState<string | null>(null);
  const [isBatching, setIsBatching] = useState(false);

  const handleDeposit = () => {
    track('deposit_initiated', { amount: depositAmount });
    
    deposit({
      address: CONTRACT_ADDRESS,
      abi: CONTRACT_ABI,
      functionName: 'deposit',
      value: parseEther(depositAmount),
    });
  };

  const handleWithdraw = () => {
    track('withdraw_initiated', { amount: withdrawAmount });
    
    withdraw({
      address: CONTRACT_ADDRESS,
      abi: CONTRACT_ABI,
      functionName: 'withdraw',
      args: [parseEther(withdrawAmount)],
    });
  };
  
  /**
   * Token deposit with EXACT approval pattern
   * Uses EIP-7702 batching if available, falls back to 2-tx flow
   */
  const handleTokenDeposit = async () => {
    if (!walletClient || !address) return;
    
    // EXACT AMOUNT - never approve more than needed
    const exactAmount = parseUnits(tokenDepositAmount, 6); // USDC has 6 decimals
    
    track('token_deposit_initiated', { 
      amount: tokenDepositAmount, 
      token: selectedToken,
      method: supports7702 ? 'batched' : 'sequential'
    });
    
    // Encode the calls
    const approveData = encodeFunctionData({
      abi: erc20Abi,
      functionName: 'approve',
      args: [CONTRACT_ADDRESS, exactAmount], // EXACT amount, not infinite!
    });
    
    const depositData = encodeFunctionData({
      abi: CONTRACT_ABI,
      functionName: 'depositToken',
      args: [selectedToken, exactAmount],
    });
    
    if (supports7702) {
      // =======================================================================
      // EIP-7702 PATH: Single transaction for approve + deposit
      // Best UX - user confirms once, both operations execute atomically
      // =======================================================================
      try {
        setIsBatching(true);
        
        const txId = await sendBatchedCalls(walletClient, [
          { to: selectedToken, data: approveData },
          { to: CONTRACT_ADDRESS, data: depositData },
        ]);
        
        setBatchTxId(txId);
        track('token_deposit_batched', { txId });
        
      } catch (error) {
        console.error('Batched call failed:', error);
        track('token_deposit_batch_failed', { error: String(error) });
      } finally {
        setIsBatching(false);
      }
      
    } else {
      // =======================================================================
      // FALLBACK PATH: Two separate transactions (traditional EOA flow)
      // Less ideal UX but still uses exact approvals
      // =======================================================================
      
      // Check if we need to approve
      const needsApproval = !currentAllowance || currentAllowance < exactAmount;
      
      if (needsApproval) {
        // Step 1: Approve EXACT amount
        approve({
          address: selectedToken,
          abi: erc20Abi,
          functionName: 'approve',
          args: [CONTRACT_ADDRESS, exactAmount], // EXACT, not infinite!
        });
        // User will need to call deposit after approval confirms
        // In a real app, you'd handle this with state machine
      } else {
        // Already approved enough, proceed to deposit
        depositToken({
          address: CONTRACT_ADDRESS,
          abi: CONTRACT_ABI,
          functionName: 'depositToken',
          args: [selectedToken, exactAmount],
        });
      }
    }
  };

  // Refetch on success
  useEffect(() => {
    if (isDepositSuccess || isWithdrawSuccess || isTokenDepositSuccess) {
      refetchBalance();
      refetchAllowance();
    }
  }, [isDepositSuccess, isWithdrawSuccess, isTokenDepositSuccess, refetchBalance, refetchAllowance]);

  return (
    <main className="min-h-screen bg-gray-900 text-white p-8">
      <div className="max-w-2xl mx-auto">
        <div className="flex justify-between items-center mb-8">
          <h1 className="text-3xl font-bold">🐉 Smart Contract Frontend</h1>
          <ConnectButton />
        </div>

        {/* Wallet Capabilities Badge */}
        {isConnected && !isCheckingCapabilities && (
          <div className="mb-4">
            {supports7702 ? (
              <span className="bg-green-600/20 text-green-400 px-3 py-1 rounded-full text-sm">
                ✓ Smart Wallet (EIP-7702 batching enabled)
              </span>
            ) : (
              <span className="bg-yellow-600/20 text-yellow-400 px-3 py-1 rounded-full text-sm">
                ⚠ EOA Wallet (2-step approvals required)
              </span>
            )}
          </div>
        )}

        {/* Stats */}
        <div className="grid grid-cols-2 gap-4 mb-8">
          <div className="bg-gray-800 rounded-lg p-4">
            <div className="text-gray-400 text-sm">Your Balance</div>
            <div className="text-2xl font-bold">
              {userBalance ? formatEther(userBalance) : '0'} ETH
            </div>
          </div>
          <div className="bg-gray-800 rounded-lg p-4">
            <div className="text-gray-400 text-sm">Total Deposits</div>
            <div className="text-2xl font-bold">
              {totalDeposits ? formatEther(totalDeposits) : '0'} ETH
            </div>
          </div>
        </div>

        {isConnected ? (
          <div className="space-y-6">
            {/* ETH Deposit */}
            <div className="bg-gray-800 rounded-lg p-6">
              <h2 className="text-xl font-semibold mb-4">Deposit ETH</h2>
              <div className="flex gap-4">
                <input
                  type="number"
                  value={depositAmount}
                  onChange={(e) => setDepositAmount(e.target.value)}
                  className="flex-1 bg-gray-700 rounded px-4 py-2"
                  placeholder="Amount in ETH"
                  step="0.01"
                />
                <button
                  onClick={handleDeposit}
                  disabled={isDepositing || isDepositConfirming}
                  className="bg-blue-600 hover:bg-blue-700 disabled:bg-gray-600 px-6 py-2 rounded font-semibold"
                >
                  {isDepositing ? 'Confirming...' : isDepositConfirming ? 'Processing...' : 'Deposit'}
                </button>
              </div>
              {isDepositSuccess && (
                <p className="text-green-400 mt-2">✓ Deposit successful!</p>
              )}
            </div>

            {/* Token Deposit with Exact Approval */}
            <div className="bg-gray-800 rounded-lg p-6">
              <h2 className="text-xl font-semibold mb-2">Deposit Token</h2>
              <p className="text-gray-400 text-sm mb-4">
                {supports7702 
                  ? '🔥 Approve & deposit in one transaction!' 
                  : 'Approve exact amount, then deposit'}
              </p>
              <div className="flex gap-4">
                <input
                  type="number"
                  value={tokenDepositAmount}
                  onChange={(e) => setTokenDepositAmount(e.target.value)}
                  className="flex-1 bg-gray-700 rounded px-4 py-2"
                  placeholder="Amount (USDC)"
                  step="1"
                />
                <button
                  onClick={handleTokenDeposit}
                  disabled={isApproving || isApproveConfirming || isTokenDepositing || isTokenDepositConfirming || isBatching}
                  className="bg-green-600 hover:bg-green-700 disabled:bg-gray-600 px-6 py-2 rounded font-semibold"
                >
                  {isBatching 
                    ? 'Batching...' 
                    : isApproving || isApproveConfirming 
                      ? 'Approving...' 
                      : isTokenDepositing || isTokenDepositConfirming 
                        ? 'Depositing...' 
                        : supports7702 
                          ? 'Approve & Deposit' 
                          : currentAllowance && currentAllowance >= parseUnits(tokenDepositAmount || '0', 6)
                            ? 'Deposit'
                            : 'Approve'}
                </button>
              </div>
              {currentAllowance !== undefined && (
                <p className="text-gray-500 text-sm mt-2">
                  Current allowance: {(Number(currentAllowance) / 1e6).toFixed(2)} USDC
                </p>
              )}
              {(isApproveSuccess || isTokenDepositSuccess) && (
                <p className="text-green-400 mt-2">✓ Success!</p>
              )}
              {batchTxId && (
                <p className="text-blue-400 mt-2">Batch TX: {batchTxId.slice(0, 10)}...</p>
              )}
              
              {/* Security Notice */}
              <div className="mt-4 p-3 bg-gray-700/50 rounded border border-gray-600">
                <p className="text-sm text-gray-300">
                  🔒 <strong>Security:</strong> This dApp uses <em>exact approvals</em> only.
                  You approve exactly {tokenDepositAmount} USDC, not unlimited.
                </p>
              </div>
            </div>

            {/* Withdraw */}
            <div className="bg-gray-800 rounded-lg p-6">
              <h2 className="text-xl font-semibold mb-4">Withdraw</h2>
              <div className="flex gap-4">
                <input
                  type="number"
                  value={withdrawAmount}
                  onChange={(e) => setWithdrawAmount(e.target.value)}
                  className="flex-1 bg-gray-700 rounded px-4 py-2"
                  placeholder="Amount in ETH"
                  step="0.01"
                />
                <button
                  onClick={handleWithdraw}
                  disabled={isWithdrawing || isWithdrawConfirming}
                  className="bg-purple-600 hover:bg-purple-700 disabled:bg-gray-600 px-6 py-2 rounded font-semibold"
                >
                  {isWithdrawing ? 'Confirming...' : isWithdrawConfirming ? 'Processing...' : 'Withdraw'}
                </button>
              </div>
              {isWithdrawSuccess && (
                <p className="text-green-400 mt-2">✓ Withdrawal successful!</p>
              )}
            </div>
          </div>
        ) : (
          <div className="bg-gray-800 rounded-lg p-8 text-center">
            <p className="text-gray-400 mb-4">Connect your wallet to get started</p>
          </div>
        )}

        <div className="mt-8 text-center text-gray-500 text-sm">
          <p>Contract: {CONTRACT_ADDRESS}</p>
          <p>Built by Ember 🐉 • Audited by Clawditor 🦞</p>
        </div>
      </div>
    </main>
  );
}
