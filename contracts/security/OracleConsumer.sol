// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title OracleConsumer
/// @author Ember 🐉
/// @notice Abstract contract for secure oracle price consumption
/// @dev Inherit and implement _getPriceFromOracle for your specific oracle
abstract contract OracleConsumer {
    // ============ Errors ============
    error StalePrice();
    error InvalidPrice();
    error PriceOutOfBounds();
    error OracleNotSet();

    // ============ Events ============
    event OracleUpdated(address indexed oldOracle, address indexed newOracle);
    event StalenessThresholdUpdated(uint256 oldThreshold, uint256 newThreshold);

    // ============ Constants ============
    /// @notice Default staleness threshold (1 hour)
    uint256 public constant DEFAULT_STALENESS_THRESHOLD = 1 hours;

    /// @notice Minimum acceptable price (prevents zero/negative)
    uint256 public constant MIN_VALID_PRICE = 1;

    /// @notice Maximum price deviation from last known (50% = 5000 bps)
    uint256 public constant MAX_PRICE_DEVIATION_BPS = 5000;

    uint256 internal constant BPS_DENOMINATOR = 10000;

    // ============ Storage ============
    /// @notice Staleness threshold in seconds
    uint256 public stalenessThreshold;

    /// @notice Last validated price for deviation checks
    uint256 public lastValidPrice;

    /// @notice Timestamp of last valid price
    uint256 public lastPriceTimestamp;

    // ============ Constructor ============
    constructor() {
        stalenessThreshold = DEFAULT_STALENESS_THRESHOLD;
    }

    // ============ Internal Functions ============

    /// @notice Validate a price from an oracle
    /// @param price The raw price from oracle
    /// @param updatedAt When the price was last updated
    /// @return validatedPrice The validated price
    function _validatePrice(uint256 price, uint256 updatedAt) internal view returns (uint256 validatedPrice) {
        // Check for stale data
        if (block.timestamp - updatedAt > stalenessThreshold) {
            revert StalePrice();
        }

        // Check for invalid price
        if (price < MIN_VALID_PRICE) {
            revert InvalidPrice();
        }

        // Check for extreme deviation (circuit breaker)
        if (lastValidPrice > 0) {
            uint256 deviation = _calculateDeviation(price, lastValidPrice);
            if (deviation > MAX_PRICE_DEVIATION_BPS) {
                revert PriceOutOfBounds();
            }
        }

        return price;
    }

    /// @notice Update the last known valid price
    /// @param price The new valid price
    function _updateLastPrice(uint256 price) internal {
        lastValidPrice = price;
        lastPriceTimestamp = block.timestamp;
    }

    /// @notice Calculate deviation between two prices in basis points
    /// @param newPrice The new price
    /// @param oldPrice The reference price
    /// @return deviation The deviation in basis points
    function _calculateDeviation(uint256 newPrice, uint256 oldPrice) internal pure returns (uint256 deviation) {
        if (newPrice >= oldPrice) {
            deviation = ((newPrice - oldPrice) * BPS_DENOMINATOR) / oldPrice;
        } else {
            deviation = ((oldPrice - newPrice) * BPS_DENOMINATOR) / oldPrice;
        }
    }

    /// @notice Get and validate price with all checks
    /// @return price The validated price
    /// @dev Override _fetchOracleData in implementing contract
    function _getValidatedPrice() internal virtual returns (uint256 price) {
        (uint256 rawPrice, uint256 updatedAt) = _fetchOracleData();
        price = _validatePrice(rawPrice, updatedAt);
        _updateLastPrice(price);
    }

    /// @notice Fetch raw data from oracle - must be implemented
    /// @return price The raw price
    /// @return updatedAt When the price was updated
    function _fetchOracleData() internal view virtual returns (uint256 price, uint256 updatedAt);

    // ============ Admin Functions ============

    /// @notice Update staleness threshold
    /// @param newThreshold New threshold in seconds
    function _setStalenessThreshold(uint256 newThreshold) internal {
        emit StalenessThresholdUpdated(stalenessThreshold, newThreshold);
        stalenessThreshold = newThreshold;
    }
}

/// @notice Chainlink Aggregator interface
interface AggregatorV3Interface {
    function latestRoundData()
        external
        view
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound);
    function decimals() external view returns (uint8);
}

/// @title ChainlinkConsumer
/// @notice Example implementation for Chainlink price feeds
/// @dev Demonstrates how to implement OracleConsumer for Chainlink
abstract contract ChainlinkConsumer is OracleConsumer {
    // ============ Errors ============
    error InvalidRound();
    error NegativePrice();

    // ============ Storage ============
    AggregatorV3Interface public priceFeed;

    // ============ Constructor ============
    constructor(address _priceFeed) {
        if (_priceFeed == address(0)) revert OracleNotSet();
        priceFeed = AggregatorV3Interface(_priceFeed);
    }

    // ============ Implementation ============

    function _fetchOracleData() internal view override returns (uint256 price, uint256 updatedAt) {
        (uint80 roundId, int256 answer,, uint256 _updatedAt, uint80 answeredInRound) = priceFeed.latestRoundData();

        // Validate round
        if (answeredInRound < roundId) revert InvalidRound();

        // Validate price is positive
        if (answer <= 0) revert NegativePrice();

        price = uint256(answer);
        updatedAt = _updatedAt;
    }

    /// @notice Get price with specified decimals
    /// @param targetDecimals Desired decimal precision
    /// @return price Normalized price
    function getPriceNormalized(uint8 targetDecimals) external returns (uint256 price) {
        uint256 rawPrice = _getValidatedPrice();
        uint8 feedDecimals = priceFeed.decimals();

        if (targetDecimals >= feedDecimals) {
            price = rawPrice * (10 ** (targetDecimals - feedDecimals));
        } else {
            price = rawPrice / (10 ** (feedDecimals - targetDecimals));
        }
    }
}
