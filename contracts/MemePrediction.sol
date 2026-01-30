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
 * 2. Users place wagers on their pick during betting window
 * 3. After deadline, admin resolves with the winning coin
 * 4. Winners split the pot proportionally, minus platform fee
 *
 * Fee: 5% (50% to idea contributor, 50% to EMBER stakers via FeeSplitter)
 */
contract MemePrediction is Ownable {
    // ============================================
    // Constants
    // ============================================
    
    uint256 public constant FEE_BPS = 500; // 5% fee
    uint256 public constant BPS = 10_000;

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

    // ============================================
    // Events
    // ============================================
    
    event RoundCreated(uint256 indexed roundId, string[] coins, uint256 deadline);
    event WagerPlaced(uint256 indexed roundId, address indexed user, uint256 coinIndex, uint256 amount);
    event RoundResolved(uint256 indexed roundId, uint256 winningCoinIndex, string winningCoin);
    event WinningsClaimed(uint256 indexed roundId, address indexed user, uint256 amount);
    event FeesCollected(uint256 amount);
    event FeeRecipientUpdated(address indexed oldRecipient, address indexed newRecipient);

    // ============================================
    // Types
    // ============================================
    
    struct Round {
        string[] coins;           // List of coin symbols/names
        uint256 deadline;         // Betting closes at this timestamp
        uint256 totalPot;         // Total ETH wagered
        uint256 winningCoinIndex; // Index of winning coin (set on resolve)
        bool resolved;            // Has the round been resolved?
        bool exists;              // Does this round exist?
    }

    struct Wager {
        uint256 coinIndex;  // Which coin they bet on
        uint256 amount;     // How much they wagered
        bool claimed;       // Have they claimed winnings?
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
        roundId = nextRoundId++;
        
        Round storage r = rounds[roundId];
        r.coins = _coins;
        r.deadline = block.timestamp + _duration;
        r.exists = true;

        emit RoundCreated(roundId, _coins, r.deadline);
    }

    /// @notice Resolve a round with the winning coin
    /// @param _roundId The round to resolve
    /// @param _winningCoinIndex Index of the winning coin
    function resolveRound(uint256 _roundId, uint256 _winningCoinIndex) external onlyOwner {
        Round storage r = rounds[_roundId];
        
        // CHECKS
        if (!r.exists) revert RoundNotActive();
        if (r.resolved) revert RoundAlreadyResolved();
        if (_winningCoinIndex >= r.coins.length) revert InvalidCoinIndex();

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
        address old_ = feeRecipient;
        feeRecipient = _feeRecipient;
        emit FeeRecipientUpdated(old_, _feeRecipient);
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
        if (block.timestamp >= r.deadline) revert BettingClosed();
        if (_coinIndex >= r.coins.length) revert InvalidCoinIndex();
        if (msg.value == 0) revert InsufficientWager();

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

    // ============================================
    // View Functions
    // ============================================

    /// @notice Get round details
    function getRound(uint256 _roundId)
        external
        view
        returns (string[] memory coins_, uint256 deadline_, uint256 totalPot_, uint256 winningCoinIndex_, bool resolved_)
    {
        Round storage r = rounds[_roundId];
        return (r.coins, r.deadline, r.totalPot, r.winningCoinIndex, r.resolved);
    }

    /// @notice Get user's wager for a round
    function getWager(uint256 _roundId, address _user)
        external
        view
        returns (uint256 coinIndex_, uint256 amount_, bool claimed_)
    {
        Wager storage w = wagers[_roundId][_user];
        return (w.coinIndex, w.amount, w.claimed);
    }

    /// @notice Get total wagered on a specific coin in a round
    function getCoinTotal(uint256 _roundId, uint256 _coinIndex) external view returns (uint256) {
        return coinTotals[_roundId][_coinIndex];
    }

    /// @notice Check if betting is still open
    function isBettingOpen(uint256 _roundId) external view returns (bool) {
        Round storage r = rounds[_roundId];
        return r.exists && !r.resolved && block.timestamp < r.deadline;
    }
}
