// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title MemePrediction
 * @author Ember Autonomous Builder
 * @notice Memecoin Prediction Market - Wager on which memecoin pumps hardest
 * @dev Built for @VavityV's idea. Follows CEI pattern, no ReentrancyGuard needed.
 *
 * How it works:
 * 1. Admin creates a round with N memecoins (by symbol)
 * 2. Admin commits to winner hash BEFORE betting closes (commit-reveal)
 * 3. Users place wagers on their pick during betting window
 * 4. After deadline, admin reveals the winning coin (must match commitment)
 * 5. Winners split the pot proportionally, minus platform fee
 * 6. If admin fails to resolve within timeout, users can claim refunds
 *
 * Fee: 5% (50% to idea contributor, 50% to EMBER stakers via FeeSplitter)
 */
contract MemePrediction is Ownable {
    // ============================================
    // Constants
    // ============================================
    
    uint256 public constant FEE_BPS = 500; // 5% fee
    uint256 public constant BPS = 10_000;
    uint256 public constant MIN_DURATION = 1 hours;
    uint256 public constant REFUND_TIMEOUT = 7 days;
    uint256 public constant MAX_COINS = 20;
    uint256 public constant MIN_WAGER = 0.001 ether;

    // ============================================
    // Errors
    // ============================================
    
    error RoundNotActive();
    error RoundNotResolved();
    error RoundAlreadyResolved();
    error BettingClosed();
    error InvalidCoinIndex();
    error InsufficientWager();
    error AlreadyClaimed();
    error NoWinnings();
    error TransferFailed();
    error ZeroAddress();
    error DurationTooShort();
    error NeedAtLeastTwoCoins();
    error RefundTooEarly();
    error AlreadyRefunded();
    error NoCommitment();
    error CommitmentMismatch();
    error AlreadyCommitted();
    error BettingStillOpen();
    error TooManyCoins();
    error NoWinnersExist();
    error RoundIsCancelled();

    // ============================================
    // Events
    // ============================================
    
    event RoundCreated(uint256 indexed roundId, string[] coins, uint256 deadline);
    event WagerPlaced(uint256 indexed roundId, address indexed user, uint256 coinIndex, uint256 amount);
    event WinnerCommitted(uint256 indexed roundId, bytes32 commitmentHash);
    event RoundResolved(uint256 indexed roundId, uint256 winningCoinIndex, string winningCoin);
    event WinningsClaimed(uint256 indexed roundId, address indexed user, uint256 amount);
    event EmergencyRefund(uint256 indexed roundId, address indexed user, uint256 amount);
    event FeesCollected(uint256 amount);
    event FeeRecipientUpdated(address indexed oldRecipient, address indexed newRecipient);
    event RoundCancelled(uint256 indexed roundId);

    // ============================================
    // Types
    // ============================================
    
    struct Round {
        string[] coins;           // List of coin symbols/names
        uint256 deadline;         // Betting closes at this timestamp
        uint256 totalPot;         // Total ETH wagered
        uint256 winningCoinIndex; // Index of winning coin (set on resolve)
        bytes32 commitment;       // Hash commitment of winner (for commit-reveal)
        bool resolved;            // Has the round been resolved?
        bool exists;              // Does this round exist?
        bool cancelled;           // Has the round been cancelled?
    }

    struct Wager {
        uint256 coinIndex;  // Which coin they bet on
        uint256 amount;     // How much they wagered
        bool claimed;       // Have they claimed winnings?
        bool refunded;      // Have they claimed emergency refund?
    }

    // ============================================
    // State Variables
    // ============================================
    
    uint256 public nextRoundId = 1;
    address public feeRecipient;

    mapping(uint256 roundId => Round) public rounds;
    mapping(uint256 roundId => mapping(address user => Wager)) public wagers;
    mapping(uint256 roundId => mapping(uint256 coinIndex => uint256 total)) public coinTotals;
    mapping(uint256 roundId => uint256 total) public winningPool;

    // ============================================
    // Constructor
    // ============================================
    
    constructor(address _feeRecipient) Ownable(msg.sender) {
        if (_feeRecipient == address(0)) revert ZeroAddress();
        feeRecipient = _feeRecipient;
    }

    // ============================================
    // Admin Functions
    // ============================================

    /// @notice Create a new prediction round
    /// @param _coins Array of coin symbols (e.g., ["PEPE", "DOGE", "SHIB"])
    /// @param _duration How long the betting window stays open (in seconds)
    /// @return roundId The ID of the created round
    function createRound(string[] memory _coins, uint256 _duration) external onlyOwner returns (uint256 roundId) {
        // CHECKS
        if (_duration < MIN_DURATION) revert DurationTooShort();
        if (_coins.length < 2) revert NeedAtLeastTwoCoins();
        if (_coins.length > MAX_COINS) revert TooManyCoins();
        
        roundId = nextRoundId++;
        
        Round storage r = rounds[roundId];
        r.coins = _coins;
        r.deadline = block.timestamp + _duration;
        r.exists = true;

        emit RoundCreated(roundId, _coins, r.deadline);
    }

    /// @notice Commit to a winner before betting closes (commit-reveal scheme)
    /// @dev Hash = keccak256(abi.encodePacked(roundId, winningCoinIndex, salt))
    /// @param _roundId The round to commit for
    /// @param _commitmentHash The hash of (roundId, winningCoinIndex, salt)
    function commitWinner(uint256 _roundId, bytes32 _commitmentHash) external onlyOwner {
        Round storage r = rounds[_roundId];
        
        // CHECKS
        if (!r.exists) revert RoundNotActive();
        if (r.cancelled) revert RoundIsCancelled();
        if (r.commitment != bytes32(0)) revert AlreadyCommitted();
        if (block.timestamp >= r.deadline) revert BettingClosed();
        
        // EFFECTS
        r.commitment = _commitmentHash;
        
        emit WinnerCommitted(_roundId, _commitmentHash);
    }

    /// @notice Resolve a round by revealing the committed winner
    /// @param _roundId The round to resolve
    /// @param _winningCoinIndex Index of the winning coin (must match commitment)
    /// @param _salt The salt used in the commitment hash
    function resolveRound(uint256 _roundId, uint256 _winningCoinIndex, bytes32 _salt) external onlyOwner {
        Round storage r = rounds[_roundId];
        
        // CHECKS
        if (!r.exists) revert RoundNotActive();
        if (r.cancelled) revert RoundIsCancelled();
        if (r.resolved) revert RoundAlreadyResolved();
        if (block.timestamp < r.deadline) revert BettingStillOpen();
        if (_winningCoinIndex >= r.coins.length) revert InvalidCoinIndex();
        if (r.commitment == bytes32(0)) revert NoCommitment();
        
        // Verify commitment matches reveal
        bytes32 expectedHash_ = keccak256(abi.encodePacked(_roundId, _winningCoinIndex, _salt));
        if (expectedHash_ != r.commitment) revert CommitmentMismatch();
        
        // Ensure at least one person bet on the winning coin
        if (coinTotals[_roundId][_winningCoinIndex] == 0) revert NoWinnersExist();

        // EFFECTS
        r.winningCoinIndex = _winningCoinIndex;
        r.resolved = true;
        winningPool[_roundId] = coinTotals[_roundId][_winningCoinIndex];

        uint256 fee_ = (r.totalPot * FEE_BPS) / BPS;

        // INTERACTIONS
        if (fee_ > 0) {
            (bool success_,) = feeRecipient.call{ value: fee_ }("");
            if (!success_) revert TransferFailed();
            emit FeesCollected(fee_);
        }

        emit RoundResolved(_roundId, _winningCoinIndex, r.coins[_winningCoinIndex]);
    }

    /// @notice Update the fee recipient
    /// @param _feeRecipient New fee recipient address
    function setFeeRecipient(address _feeRecipient) external onlyOwner {
        if (_feeRecipient == address(0)) revert ZeroAddress();
        address old_ = feeRecipient;
        feeRecipient = _feeRecipient;
        emit FeeRecipientUpdated(old_, _feeRecipient);
    }

    /// @notice Cancel a round (users can immediately claim refunds)
    /// @param _roundId The round to cancel
    function cancelRound(uint256 _roundId) external onlyOwner {
        Round storage r = rounds[_roundId];
        
        // CHECKS
        if (!r.exists) revert RoundNotActive();
        if (r.resolved) revert RoundAlreadyResolved();
        if (r.cancelled) revert RoundIsCancelled();
        
        // EFFECTS
        r.cancelled = true;
        
        emit RoundCancelled(_roundId);
    }

    // ============================================
    // User Functions
    // ============================================

    /// @notice Place a wager on a coin
    /// @param _roundId The round to bet on
    /// @param _coinIndex Index of the coin to bet on
    function placeWager(uint256 _roundId, uint256 _coinIndex) external payable {
        Round storage r = rounds[_roundId];
        
        // CHECKS
        if (!r.exists) revert RoundNotActive();
        if (r.cancelled) revert RoundIsCancelled();
        if (block.timestamp >= r.deadline) revert BettingClosed();
        if (_coinIndex >= r.coins.length) revert InvalidCoinIndex();
        if (msg.value < MIN_WAGER) revert InsufficientWager();

        Wager storage w = wagers[_roundId][msg.sender];
        
        // Users can only bet on one coin per round, but can add more to existing bet
        if (w.amount > 0 && w.coinIndex != _coinIndex) revert InvalidCoinIndex();

        // EFFECTS (all state updates before any external calls - CEI)
        if (w.amount == 0) {
            w.coinIndex = _coinIndex;
        }
        w.amount += msg.value;
        r.totalPot += msg.value;
        coinTotals[_roundId][_coinIndex] += msg.value;

        // No INTERACTIONS needed here

        emit WagerPlaced(_roundId, msg.sender, _coinIndex, msg.value);
    }

    /// @notice Claim winnings from a resolved round
    /// @param _roundId The round to claim from
    function claimWinnings(uint256 _roundId) external {
        Round storage r = rounds[_roundId];
        Wager storage w = wagers[_roundId][msg.sender];
        
        // CHECKS
        if (!r.resolved) revert RoundNotResolved();
        if (w.claimed) revert AlreadyClaimed();
        if (w.refunded) revert AlreadyRefunded(); // Prevent double withdrawal
        if (w.coinIndex != r.winningCoinIndex) revert NoWinnings();
        if (w.amount == 0) revert NoWinnings();

        // Calculate winnings: proportional share of pot after fees
        uint256 potAfterFees_ = r.totalPot - ((r.totalPot * FEE_BPS) / BPS);
        uint256 userShare_ = (w.amount * potAfterFees_) / winningPool[_roundId];

        // EFFECTS (state update before external call - CEI)
        w.claimed = true;

        // INTERACTIONS
        (bool success_,) = msg.sender.call{ value: userShare_ }("");
        if (!success_) revert TransferFailed();

        emit WinningsClaimed(_roundId, msg.sender, userShare_);
    }

    /// @notice Emergency refund if admin fails to resolve within timeout
    /// @param _roundId The round to claim refund from
    function emergencyRefund(uint256 _roundId) external {
        Round storage r = rounds[_roundId];
        Wager storage w = wagers[_roundId][msg.sender];
        
        // CHECKS
        if (!r.exists) revert RoundNotActive();
        if (r.resolved) revert RoundAlreadyResolved(); // Can't refund if already resolved
        // Allow immediate refund if cancelled, otherwise wait for timeout
        if (!r.cancelled && block.timestamp < r.deadline + REFUND_TIMEOUT) revert RefundTooEarly();
        if (w.refunded) revert AlreadyRefunded();
        if (w.amount == 0) revert NoWinnings();
        
        uint256 refundAmount_ = w.amount;
        
        // EFFECTS
        w.refunded = true;
        
        // INTERACTIONS
        (bool success_,) = msg.sender.call{ value: refundAmount_ }("");
        if (!success_) revert TransferFailed();
        
        emit EmergencyRefund(_roundId, msg.sender, refundAmount_);
    }

    // ============================================
    // View Functions
    // ============================================

    /// @notice Get round details
    function getRound(uint256 _roundId)
        external
        view
        returns (
            string[] memory coins_,
            uint256 deadline_,
            uint256 totalPot_,
            uint256 winningCoinIndex_,
            bytes32 commitment_,
            bool resolved_,
            bool cancelled_
        )
    {
        Round storage r = rounds[_roundId];
        return (r.coins, r.deadline, r.totalPot, r.winningCoinIndex, r.commitment, r.resolved, r.cancelled);
    }

    /// @notice Get user's wager for a round
    function getWager(uint256 _roundId, address _user)
        external
        view
        returns (uint256 coinIndex_, uint256 amount_, bool claimed_, bool refunded_)
    {
        Wager storage w = wagers[_roundId][_user];
        return (w.coinIndex, w.amount, w.claimed, w.refunded);
    }

    /// @notice Get total wagered on a specific coin in a round
    function getCoinTotal(uint256 _roundId, uint256 _coinIndex) external view returns (uint256) {
        return coinTotals[_roundId][_coinIndex];
    }

    /// @notice Check if betting is still open
    function isBettingOpen(uint256 _roundId) external view returns (bool) {
        Round storage r = rounds[_roundId];
        return r.exists && !r.resolved && !r.cancelled && block.timestamp < r.deadline;
    }

    /// @notice Check if emergency refund is available for a round
    function isRefundAvailable(uint256 _roundId) external view returns (bool) {
        Round storage r = rounds[_roundId];
        return r.exists && !r.resolved && (r.cancelled || block.timestamp >= r.deadline + REFUND_TIMEOUT);
    }

    /// @notice Helper to compute commitment hash (use off-chain, save the salt!)
    function computeCommitment(uint256 _roundId, uint256 _winningCoinIndex, bytes32 _salt) 
        external 
        pure 
        returns (bytes32) 
    {
        return keccak256(abi.encodePacked(_roundId, _winningCoinIndex, _salt));
    }
}
