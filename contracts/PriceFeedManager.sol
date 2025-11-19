// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

interface IPyth {
    struct Price {
        int64 price;
        uint64 conf;
        int32 expo;
        uint256 publishTime;
    }
    
    function getPriceUnsafe(bytes32 id) external view returns (Price memory price);
    function getPrice(bytes32 id) external view returns (Price memory price);
}

/**
 * @title PriceFeedManager
 * @notice Price feed manager with Chainlink primary + Pyth Network fallback
 * @dev Manages price feeds from multiple oracle sources with automatic fallback mechanisms.
 *      Chainlink is used as the primary oracle with Pyth Network as a reliable fallback.
 * 
 * Key Features:
 * - Dual oracle system (Chainlink + Pyth)
 * - Automatic fallback when primary oracle fails
 * - Staleness checks for both oracle types
 * - USD value conversion utilities
 * - Timelock protection for critical functions
 * 
 * Security Features:
 * - Staleness threshold validation (1 hour)
 * - Price sanity checks (positive values)
 * - Round data validation for Chainlink
 * - Access control with timelock integration
 */
contract PriceFeedManager is Ownable {
    
    /// @notice Mapping of token addresses to their Chainlink price feeds
    mapping(address => AggregatorV3Interface) public priceFeeds;
    
    /// @notice Mapping of token addresses to their Pyth price IDs
    mapping(address => bytes32) public pythPriceIds;
    
    /// @notice Mapping of token addresses to their decimal places
    mapping(address => uint8) public tokenDecimals;
    
    /// @notice Timelock controller for critical operations
    address public timelock;
    
    /// @notice Pyth Network contract interface
    IPyth public pythContract;

    /// @notice Maximum age for Chainlink price data (1 hour)
    uint256 public constant CHAINLINK_STALENESS_THRESHOLD = 1 hours;
    
    /// @notice Maximum age for Pyth price data (20 seconds)  
    uint256 public constant PYTH_STALENESS_THRESHOLD = 20 seconds;

    /// @notice Thrown when token address is zero
    error InvalidTokenAddress();
    
    /// @notice Thrown when price feed address is zero (when not removing)
    error InvalidPriceFeedAddress();
    
    /// @notice Thrown when price ID is zero
    error InvalidPriceId();
    
    /// @notice Thrown when no price feed exists for token
    error PriceFeedNotFound();
    
    /// @notice Thrown when price is zero or negative
    error InvalidPrice();
    
    /// @notice Thrown when price data is too old
    error StalePrice();
    
    /// @notice Thrown when caller is not authorized
    error Unauthorized();

    /// @notice Emitted when a Chainlink price feed is updated
    event PriceFeedUpdated(address indexed token, address indexed priceFeed, uint8 decimals);
    
    /// @notice Emitted when a Pyth price ID is updated
    event PythPriceIdUpdated(address indexed token, bytes32 indexed priceId);

    /**
     * @notice Modifier to allow only owner or timelock to call critical functions
     */
    modifier onlyOwnerOrTimelock() {
        if (msg.sender != owner() && msg.sender != timelock) {
            revert Unauthorized();
        }
        _;
    }

    /**
     * @notice Initialize the PriceFeedManager
     * @param _timelock Address of the timelock controller
     * @param _pythContract Address of the Pyth Network contract
     */
    constructor(address _timelock, address _pythContract) Ownable(msg.sender) {
        if (_timelock == address(0)) revert InvalidTokenAddress();
        if (_pythContract == address(0)) revert InvalidPriceFeedAddress();
        
        timelock = _timelock;
        pythContract = IPyth(_pythContract);
    }

    /**
     * @notice Check if a token has any price feed configured
     * @param _token Token address to check
     * @return True if token has Chainlink or Pyth price feed
     */
    function hasPriceFeed(address _token) external view returns (bool) {
        return address(priceFeeds[_token]) != address(0) || pythPriceIds[_token] != bytes32(0);
    }

    /**
     * @notice Set or remove a Chainlink price feed for a token
     * @param _token Token address
     * @param _priceFeed Chainlink price feed address (zero to remove)
     * @param _decimals Token decimal places
     */
    function setPriceFeed(address _token, address _priceFeed, uint8 _decimals) external onlyOwnerOrTimelock {
        if (_token == address(0)) revert InvalidTokenAddress();
        
        if (_priceFeed == address(0)) {
            // Remove price feed
            delete priceFeeds[_token];
            delete tokenDecimals[_token];
        } else {
            priceFeeds[_token] = AggregatorV3Interface(_priceFeed);
            tokenDecimals[_token] = _decimals;
        }
        
        emit PriceFeedUpdated(_token, _priceFeed, _decimals);
    }

    /**
     * @notice Set a Pyth price ID for a token
     * @param _token Token address
     * @param _priceId Pyth price ID
     */
    function setPythPriceId(address _token, bytes32 _priceId) external onlyOwnerOrTimelock {
        if (_token == address(0)) revert InvalidTokenAddress();
        if (_priceId == bytes32(0)) revert InvalidPriceId();
        
        pythPriceIds[_token] = _priceId;
        emit PythPriceIdUpdated(_token, _priceId);
    }

    /**
     * @notice Get token price with automatic fallback
     * @param _token Token address
     * @return price Token price in USD with 8 decimals
     */
    function getTokenPrice(address _token) public view returns (uint256 price) {
        // Try Chainlink first
        try this.getChainlinkPrice(_token) returns (uint256 chainlinkPrice) {
            return chainlinkPrice;
        } catch {
            // Fallback to Pyth
            return getPythPrice(_token);
        }
    }

    /**
     * @notice Get price from Chainlink oracle
     * @param _token Token address
     * @return price Token price in USD with 8 decimals
     */
    function getChainlinkPrice(address _token) external view returns (uint256 price) {
        AggregatorV3Interface priceFeed = priceFeeds[_token];
        if (address(priceFeed) == address(0)) revert PriceFeedNotFound();

        (uint80 roundId, int256 answer, , uint256 updatedAt, uint80 answeredInRound) = priceFeed.latestRoundData();

        // Validate price data
        if (answer <= 0) revert InvalidPrice();
        if (answeredInRound < roundId) revert InvalidPrice();
        if (updatedAt == 0 || block.timestamp - updatedAt > CHAINLINK_STALENESS_THRESHOLD) {
            revert StalePrice();
        }

        return uint256(answer);
    }

    /**
     * @notice Get price from Pyth oracle
     * @param _token Token address
     * @return price Token price in USD with 8 decimals
     */
    function getPythPrice(address _token) public view returns (uint256 price) {
        bytes32 priceId = pythPriceIds[_token];
        if (priceId == bytes32(0)) revert PriceFeedNotFound();

        IPyth.Price memory pythPrice = pythContract.getPriceUnsafe(priceId);
        
        // Validate price data
        if (pythPrice.price <= 0) revert InvalidPrice();
        if (block.timestamp - pythPrice.publishTime > PYTH_STALENESS_THRESHOLD) {
            revert StalePrice();
        }

        // Convert Pyth price to Chainlink format (8 decimals)
        // Formula: (pythPrice * 10^expo) * 10^8
        
        uint256 basePrice = uint256(int256(pythPrice.price));
        int32 expo = pythPrice.expo;
        
        if (expo >= 0) {
            if (expo > 8) revert InvalidPrice();
            // Positive exponent: basePrice * 10^(expo + 8)
            return basePrice * (10 ** (uint32(expo) + 8));
        } else {
            uint32 absExpo = uint32(-expo);
            if (absExpo > 18) revert InvalidPrice();
            
            // Negative exponent: basePrice * 10^8 / 10^absExpo
            if (absExpo == 8) {
                return basePrice;
            } else if (absExpo > 8) {
                return basePrice / (10 ** (absExpo - 8));
            } else {
                return basePrice * (10 ** (8 - absExpo));
            }
        }
    }

    /**
     * @notice Convert token amount to USD value
     * @param _token Token address
     * @param _amount Token amount in token's native decimals
     * @return usdValue USD value with 18 decimals
     */
    function getTokenValueInUSD(address _token, uint256 _amount) external view returns (uint256 usdValue) {
        uint256 price = getTokenPrice(_token);
        uint8 decimals = tokenDecimals[_token];
        
        unchecked {
            usdValue = (_amount * price * 1e10) / (10 ** decimals);
        }
    }

    /**
     * @notice Convert USD value to token amount
     * @param _token Token address
     * @param _usdValue USD value with 18 decimals
     * @return tokenAmount Token amount in token's native decimals
     */
    function convertUsdToToken(address _token, uint256 _usdValue) external view returns (uint256 tokenAmount) {
        uint256 price = getTokenPrice(_token);
        uint8 decimals = tokenDecimals[_token];
        
        unchecked {
            tokenAmount = (_usdValue * (10 ** decimals)) / (price * 1e10);
        }
    }
}
