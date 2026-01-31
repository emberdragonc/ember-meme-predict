// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { IPyth } from "@pythnetwork/pyth-sdk-solidity/IPyth.sol";
import { PythStructs } from "@pythnetwork/pyth-sdk-solidity/PythStructs.sol";

/**
 * @title MemePredictionTrustless
 * @author Ember Autonomous Builder 🐉
 * @notice Fully trustless memecoin prediction market using Pyth Network oracles
 * @dev No admin picks winners - 100% determined by on-chain oracle price data
 *
 * How it works:
 * 1. Admin creates a round with N memecoins (symbol + Pyth price feed ID)
 * 2. Users place wagers on their pick during betting window
 * 3. At round start, starting prices are snapshotted from Pyth
 * 4. After deadline, ANYONE can call resolveRound() with price update data
 * 5. Contract computes % change for each coin, winner = highest gain (or smallest loss)
 * 6. Winners split the pot proportionally, minus platform fee
 * 7. If oracle data unavailable for 7 days, users can claim refunds
 *
 * Key constraint: Admin NEVER picks winners - purely oracle-determined
 */
contract MemePredictionTrustless is Ownable {
    // ============================================
    // Constants
    // ============================================
    
    uint256 public constant FEE_BPS = 500; // 5% fee
    uint256 public constant BPS = 10_000;
    uint256 public constant MIN_DURATION = 1 hours;
    uint256 public constant REFUND_TIMEOUT = 7 days;
    uint256 public constant MAX_COINS = 10;
    uint256 public constant MIN_WAGER = 0.001 ether;
    uint256 public constant PRICE_STALENESS = 1 hours; // Max age for price data
    int64 public constant PRICE_PRECISION = 1e18; // Normalize all prices to 18 decimals

    // ============================================
    // Errors
    // ============================================
    
    error RoundNotActive();
    error RoundNotResolved();
    error RoundAlreadyResolved();
    error BettingClosed();
    error BettingStillOpen();
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
    error TooManyCoins();
    error RoundIsCancelled();
    error PriceStale();
    error InvalidPrice();
    error PriceNotSnapshotted();
    error ArrayLengthMismatch();
    error InsufficientPythFee();
    error NoBettors();

    // ============================================
    // Events
    // ============================================
    
    event RoundCreated(uint256 indexed roundId, string[] coins, bytes32[] priceFeeds, uint256 deadline);
    event PricesSnapshotted(uint256 indexed roundId, int64[] startPrices);
    event WagerPlaced(uint256 indexed roundId, address indexed user, uint256 coinIndex, uint256 amount);
    event RoundResolved(uint256 indexed roundId, uint256 winningCoinIndex, string winningCoin, int256 percentGain);
    event WinningsClaimed(uint256 indexed roundId, address indexed user, uint256 amount);
    event EmergencyRefund(uint256 indexed roundId, address indexed user, uint256 amount);
    event FeesCollected(uint256 amount);
    event FeeRecipientUpdated(address indexed oldRecipient, address indexed newRecipient);
    event RoundCancelled(uint256 indexed roundId);

    // ============================================
    // Types
    // ============================================
    
    struct Coin {
        string symbol;           // Coin symbol (e.g., "PEPE")
        bytes32 priceFeedId;     // Pyth price feed ID
        int64 startPrice;        // Price at round start (normalized to 18 decimals)
        int64 endPrice;          // Price at resolution (normalized to 18 decimals)
    }

    struct Round {
        Coin[] coins;             // List of coins with their price feeds
        uint256 deadline;         // Betting closes at this timestamp
        uint256 totalPot;         // Total ETH wagered
        uint256 winningCoinIndex; // Index of winning coin (set on resolve)
        bool pricesSnapshotted;   // Have starting prices been recorded?
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
    
    IPyth public immutable pyth;
    uint256 public nextRoundId = 1;
    address public feeRecipient;

    mapping(uint256 roundId => Round) internal _rounds;
    mapping(uint256 roundId => mapping(address user => Wager)) public wagers;
    mapping(uint256 roundId => mapping(uint256 coinIndex => uint256 total)) public coinTotals;
    mapping(uint256 roundId => uint256 total) public winningPool;

    // ============================================
    // Constructor
    // ============================================
    
    /// @param _pyth Address of Pyth contract on this chain
    /// @param _feeRecipient Address to receive platform fees
    constructor(address _pyth, address _feeRecipient) Ownable(msg.sender) {
        if (_pyth == address(0)) revert ZeroAddress();
        if (_feeRecipient == address(0)) revert ZeroAddress();
        pyth = IPyth(_pyth);
        feeRecipient = _feeRecipient;
    }

    // ============================================
    // Admin Functions
    // ============================================

    /// @notice Create a new prediction round with oracle-backed coins
    /// @param _symbols Array of coin symbols (e.g., ["PEPE", "DOGE", "SHIB"])
    /// @param _priceFeeds Array of Pyth price feed IDs for each coin
    /// @param _duration How long the betting window stays open (in seconds)
    /// @return roundId The ID of the created round
    function createRound(
        string[] memory _symbols, 
        bytes32[] memory _priceFeeds, 
        uint256 _duration
    ) external onlyOwner returns (uint256 roundId) {
        // CHECKS
        if (_duration < MIN_DURATION) revert DurationTooShort();
        if (_symbols.length < 2) revert NeedAtLeastTwoCoins();
        if (_symbols.length > MAX_COINS) revert TooManyCoins();
        if (_symbols.length != _priceFeeds.length) revert ArrayLengthMismatch();
        
        roundId = nextRoundId++;
        
        Round storage r = _rounds[roundId];
        r.deadline = block.timestamp + _duration;
        r.exists = true;

        // Add each coin with its price feed
        for (uint256 i = 0; i < _symbols.length; i++) {
            r.coins.push(Coin({
                symbol: _symbols[i],
                priceFeedId: _priceFeeds[i],
                startPrice: 0,
                endPrice: 0
            }));
        }

        emit RoundCreated(roundId, _symbols, _priceFeeds, r.deadline);
    }

    /// @notice Snapshot starting prices for a round (can be called by anyone)
    /// @dev Should be called close to round creation. Uses Pyth updatePriceFeeds
    /// @param _roundId The round to snapshot prices for
    /// @param _priceUpdateData Pyth price update data from Hermes
    function snapshotStartPrices(uint256 _roundId, bytes[] calldata _priceUpdateData) external payable {
        Round storage r = _rounds[_roundId];
        
        // CHECKS
        if (!r.exists) revert RoundNotActive();
        if (r.cancelled) revert RoundIsCancelled();
        if (r.pricesSnapshotted) revert PriceNotSnapshotted(); // Already snapshotted
        if (block.timestamp >= r.deadline) revert BettingClosed();
        
        // Update Pyth prices
        uint256 fee = pyth.getUpdateFee(_priceUpdateData);
        if (msg.value < fee) revert InsufficientPythFee();
        pyth.updatePriceFeeds{value: fee}(_priceUpdateData);
        
        // Snapshot each coin's starting price
        int64[] memory startPrices = new int64[](r.coins.length);
        for (uint256 i = 0; i < r.coins.length; i++) {
            PythStructs.Price memory price = pyth.getPriceNoOlderThan(r.coins[i].priceFeedId, PRICE_STALENESS);
            if (price.price <= 0) revert InvalidPrice();
            
            // Normalize to 18 decimals
            r.coins[i].startPrice = _normalizePrice(price.price, price.expo);
            startPrices[i] = r.coins[i].startPrice;
        }
        
        r.pricesSnapshotted = true;
        
        // Refund excess ETH
        if (msg.value > fee) {
            (bool success,) = msg.sender.call{value: msg.value - fee}("");
            if (!success) revert TransferFailed();
        }
        
        emit PricesSnapshotted(_roundId, startPrices);
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
        Round storage r = _rounds[_roundId];
        
        // CHECKS
        if (!r.exists) revert RoundNotActive();
        if (r.resolved) revert RoundAlreadyResolved();
        if (r.cancelled) revert RoundIsCancelled();
        
        // EFFECTS
        r.cancelled = true;
        
        emit RoundCancelled(_roundId);
    }

    // Override Ownable to prevent zero-address admin
    function transferOwnership(address newOwner) public override onlyOwner {
        if (newOwner == address(0)) revert ZeroAddress();
        super.transferOwnership(newOwner);
    }

    function renounceOwnership() public pure override {
        revert ZeroAddress();
    }

    // ============================================
    // Trustless Resolution (ANYONE can call)
    // ============================================

    /// @notice Resolve a round using oracle prices - ANYONE can call this!
    /// @dev Winner is determined purely by on-chain oracle data - no admin involvement
    /// @param _roundId The round to resolve
    /// @param _priceUpdateData Pyth price update data from Hermes
    function resolveRound(uint256 _roundId, bytes[] calldata _priceUpdateData) external payable {
        Round storage r = _rounds[_roundId];
        
        // CHECKS
        if (!r.exists) revert RoundNotActive();
        if (r.cancelled) revert RoundIsCancelled();
        if (r.resolved) revert RoundAlreadyResolved();
        if (block.timestamp < r.deadline) revert BettingStillOpen();
        if (!r.pricesSnapshotted) revert PriceNotSnapshotted();
        if (r.totalPot == 0) revert NoBettors();
        
        // Update Pyth prices
        uint256 fee = pyth.getUpdateFee(_priceUpdateData);
        if (msg.value < fee) revert InsufficientPythFee();
        pyth.updatePriceFeeds{value: fee}(_priceUpdateData);
        
        // Get end prices and calculate winner
        int256 highestGain = type(int256).min;
        uint256 winnerIndex = 0;
        
        for (uint256 i = 0; i < r.coins.length; i++) {
            PythStructs.Price memory price = pyth.getPriceNoOlderThan(r.coins[i].priceFeedId, PRICE_STALENESS);
            if (price.price <= 0) revert InvalidPrice();
            
            // Normalize to 18 decimals
            int64 endPrice = _normalizePrice(price.price, price.expo);
            r.coins[i].endPrice = endPrice;
            
            // Calculate percentage gain: ((end - start) * 10000) / start
            // Using BPS precision for % calculation
            int256 percentGain = ((int256(endPrice) - int256(r.coins[i].startPrice)) * int256(BPS)) 
                                  / int256(r.coins[i].startPrice);
            
            if (percentGain > highestGain) {
                highestGain = percentGain;
                winnerIndex = i;
            }
        }
        
        // Check if winning coin has any bettors
        if (coinTotals[_roundId][winnerIndex] == 0) {
            // Find next best coin with bettors
            int256 nextBestGain = type(int256).min;
            uint256 nextWinner = 0;
            bool foundWinner = false;
            
            for (uint256 i = 0; i < r.coins.length; i++) {
                if (coinTotals[_roundId][i] > 0) {
                    int256 percentGain = ((int256(r.coins[i].endPrice) - int256(r.coins[i].startPrice)) * int256(BPS)) 
                                          / int256(r.coins[i].startPrice);
                    if (percentGain > nextBestGain) {
                        nextBestGain = percentGain;
                        nextWinner = i;
                        foundWinner = true;
                    }
                }
            }
            
            if (!foundWinner) {
                // No one bet on any coin with positive/least-negative gain - cancel round
                r.cancelled = true;
                emit RoundCancelled(_roundId);
                _refundExcessPythFee(fee);
                return;
            }
            
            winnerIndex = nextWinner;
            highestGain = nextBestGain;
        }

        // EFFECTS
        r.winningCoinIndex = winnerIndex;
        r.resolved = true;
        winningPool[_roundId] = coinTotals[_roundId][winnerIndex];

        uint256 platformFee = (r.totalPot * FEE_BPS) / BPS;

        // INTERACTIONS
        if (platformFee > 0) {
            (bool success,) = feeRecipient.call{value: platformFee}("");
            if (!success) revert TransferFailed();
            emit FeesCollected(platformFee);
        }

        _refundExcessPythFee(fee);

        emit RoundResolved(_roundId, winnerIndex, r.coins[winnerIndex].symbol, highestGain);
    }

    // ============================================
    // User Functions
    // ============================================

    /// @notice Place a wager on a coin
    /// @param _roundId The round to bet on
    /// @param _coinIndex Index of the coin to bet on
    function placeWager(uint256 _roundId, uint256 _coinIndex) external payable {
        Round storage r = _rounds[_roundId];
        
        // CHECKS
        if (!r.exists) revert RoundNotActive();
        if (r.cancelled) revert RoundIsCancelled();
        if (block.timestamp >= r.deadline) revert BettingClosed();
        if (_coinIndex >= r.coins.length) revert InvalidCoinIndex();
        if (msg.value < MIN_WAGER) revert InsufficientWager();

        Wager storage w = wagers[_roundId][msg.sender];
        
        // Users can only bet on one coin per round, but can add more to existing bet
        if (w.amount > 0 && w.coinIndex != _coinIndex) revert InvalidCoinIndex();

        // EFFECTS
        if (w.amount == 0) {
            w.coinIndex = _coinIndex;
        }
        w.amount += msg.value;
        r.totalPot += msg.value;
        coinTotals[_roundId][_coinIndex] += msg.value;

        emit WagerPlaced(_roundId, msg.sender, _coinIndex, msg.value);
    }

    /// @notice Claim winnings from a resolved round
    /// @param _roundId The round to claim from
    function claimWinnings(uint256 _roundId) external {
        Round storage r = _rounds[_roundId];
        Wager storage w = wagers[_roundId][msg.sender];
        
        // CHECKS
        if (!r.resolved) revert RoundNotResolved();
        if (w.claimed) revert AlreadyClaimed();
        if (w.refunded) revert AlreadyRefunded();
        if (w.coinIndex != r.winningCoinIndex) revert NoWinnings();
        if (w.amount == 0) revert NoWinnings();

        // Calculate winnings: proportional share of pot after fees
        uint256 potAfterFees = r.totalPot - ((r.totalPot * FEE_BPS) / BPS);
        uint256 userShare = (w.amount * potAfterFees) / winningPool[_roundId];

        // EFFECTS
        w.claimed = true;

        // INTERACTIONS
        (bool success,) = msg.sender.call{value: userShare}("");
        if (!success) revert TransferFailed();

        emit WinningsClaimed(_roundId, msg.sender, userShare);
    }

    /// @notice Emergency refund if round cannot be resolved within timeout
    /// @param _roundId The round to claim refund from
    function emergencyRefund(uint256 _roundId) external {
        Round storage r = _rounds[_roundId];
        Wager storage w = wagers[_roundId][msg.sender];
        
        // CHECKS
        if (!r.exists) revert RoundNotActive();
        if (r.resolved) revert RoundAlreadyResolved();
        if (!r.cancelled && block.timestamp < r.deadline + REFUND_TIMEOUT) revert RefundTooEarly();
        if (w.refunded) revert AlreadyRefunded();
        if (w.amount == 0) revert NoWinnings();
        
        uint256 refundAmount = w.amount;
        
        // EFFECTS
        w.refunded = true;
        
        // INTERACTIONS
        (bool success,) = msg.sender.call{value: refundAmount}("");
        if (!success) revert TransferFailed();
        
        emit EmergencyRefund(_roundId, msg.sender, refundAmount);
    }

    // ============================================
    // View Functions
    // ============================================

    /// @notice Get round details
    function getRound(uint256 _roundId)
        external
        view
        returns (
            string[] memory symbols,
            bytes32[] memory priceFeeds,
            int64[] memory startPrices,
            int64[] memory endPrices,
            uint256 deadline,
            uint256 totalPot,
            uint256 winningCoinIndex,
            bool pricesSnapshotted,
            bool resolved,
            bool cancelled
        )
    {
        Round storage r = _rounds[_roundId];
        uint256 len = r.coins.length;
        
        symbols = new string[](len);
        priceFeeds = new bytes32[](len);
        startPrices = new int64[](len);
        endPrices = new int64[](len);
        
        for (uint256 i = 0; i < len; i++) {
            symbols[i] = r.coins[i].symbol;
            priceFeeds[i] = r.coins[i].priceFeedId;
            startPrices[i] = r.coins[i].startPrice;
            endPrices[i] = r.coins[i].endPrice;
        }
        
        return (
            symbols,
            priceFeeds,
            startPrices,
            endPrices,
            r.deadline,
            r.totalPot,
            r.winningCoinIndex,
            r.pricesSnapshotted,
            r.resolved,
            r.cancelled
        );
    }

    /// @notice Get user's wager for a round
    function getWager(uint256 _roundId, address _user)
        external
        view
        returns (uint256 coinIndex, uint256 amount, bool claimed, bool refunded)
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
        Round storage r = _rounds[_roundId];
        return r.exists && !r.resolved && !r.cancelled && block.timestamp < r.deadline;
    }

    /// @notice Check if emergency refund is available for a round
    function isRefundAvailable(uint256 _roundId) external view returns (bool) {
        Round storage r = _rounds[_roundId];
        return r.exists && !r.resolved && (r.cancelled || block.timestamp >= r.deadline + REFUND_TIMEOUT);
    }

    /// @notice Get the required fee for Pyth price updates
    /// @param _priceUpdateData The price update data
    function getUpdateFee(bytes[] calldata _priceUpdateData) external view returns (uint256) {
        return pyth.getUpdateFee(_priceUpdateData);
    }

    /// @notice Get number of coins in a round
    function getCoinsCount(uint256 _roundId) external view returns (uint256) {
        return _rounds[_roundId].coins.length;
    }

    // ============================================
    // Internal Functions
    // ============================================

    /// @notice Normalize price to 18 decimals
    /// @param _price Raw price from Pyth
    /// @param _expo Exponent from Pyth (negative)
    function _normalizePrice(int64 _price, int32 _expo) internal pure returns (int64) {
        // Pyth prices come with variable exponents (usually negative)
        // We normalize to 18 decimals for consistent comparison
        if (_expo >= 0) {
            // Price is already >= 1e0, scale up
            return _price * int64(int256(10 ** (18 + uint32(_expo))));
        } else {
            // Price has negative exponent
            int32 absExpo = -_expo;
            if (absExpo <= 18) {
                // Scale up to 18 decimals
                return _price * int64(int256(10 ** uint32(18 - uint32(absExpo))));
            } else {
                // Very small price, scale down
                return _price / int64(int256(10 ** uint32(uint32(absExpo) - 18)));
            }
        }
    }

    /// @notice Refund excess ETH sent for Pyth fee
    function _refundExcessPythFee(uint256 _fee) internal {
        if (msg.value > _fee) {
            (bool success,) = msg.sender.call{value: msg.value - _fee}("");
            if (!success) revert TransferFailed();
        }
    }

    /// @notice Receive function to accept ETH
    receive() external payable {}
}
