// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { Test } from "forge-std/Test.sol";
import "../contracts/PriceFeedManager.sol";

// Mock Chainlink Aggregator
contract MockChainlinkAggregator {
    int256 public price;
    uint256 public updatedAt;
    uint80 public roundId;
    uint80 public answeredInRound;
    
    constructor(int256 _price) {
        price = _price;
        updatedAt = block.timestamp;
        roundId = 1;
        answeredInRound = 1;
    }
    
    function latestRoundData() external view returns (
        uint80 _roundId,
        int256 answer,
        uint256 startedAt,
        uint256 _updatedAt,
        uint80 _answeredInRound
    ) {
        return (roundId, price, block.timestamp, updatedAt, answeredInRound);
    }
    
    function updatePrice(int256 _price, uint256 _updatedAt) external {
        price = _price;
        updatedAt = _updatedAt;
    }
    
    function updateRoundData(uint80 _roundId, uint80 _answeredInRound) external {
        roundId = _roundId;
        answeredInRound = _answeredInRound;
    }
}

// Mock Pyth Contract
contract MockPyth {
    mapping(bytes32 => IPyth.Price) public prices;
    
    function updatePrice(bytes32 id, int64 price, int32 expo, uint256 publishTime) external {
        prices[id] = IPyth.Price({
            price: price,
            conf: 0,
            expo: expo,
            publishTime: publishTime
        });
    }
    
    function getPriceUnsafe(bytes32 id) external view returns (IPyth.Price memory) {
        return prices[id];
    }
    
    function getPrice(bytes32 id) external view returns (IPyth.Price memory) {
        return prices[id];
    }
}

contract PriceFeedManagerTest is Test {
    PriceFeedManager public priceFeedManager;
    MockChainlinkAggregator public mockChainlink;
    MockPyth public mockPyth;
    
    address public owner;
    address public timelock;
    address public unauthorized;
    address public token;
    
    bytes32 constant PYTH_PRICE_ID = 0x1234567890123456789012345678901234567890123456789012345678901234;
    
    event PriceFeedUpdated(address indexed token, address indexed priceFeed, uint8 decimals);
    event PythPriceIdUpdated(address indexed token, bytes32 indexed priceId);
    
    function setUp() public {
        owner = address(this);
        timelock = makeAddr("timelock");
        unauthorized = makeAddr("unauthorized");
        token = makeAddr("token");
        
        // Deploy mocks
        mockChainlink = new MockChainlinkAggregator(200000000000); // $2000 with 8 decimals
        mockPyth = new MockPyth();
        
        // Deploy PriceFeedManager
        priceFeedManager = new PriceFeedManager(timelock, address(mockPyth));
        
        // Set up Pyth price data (ETH price: $2000)
        // Use expo=0 for simplicity: 2000 * 10^0 = $2000
        mockPyth.updatePrice(PYTH_PRICE_ID, 2000, 0, block.timestamp);
    }
    
    // ============ DEPLOYMENT TESTS ============
    
    function testDeployment() public view {
        assertEq(priceFeedManager.owner(), owner);
        assertEq(priceFeedManager.timelock(), timelock);
        assertEq(address(priceFeedManager.pythContract()), address(mockPyth));
        assertEq(priceFeedManager.STALENESS_THRESHOLD(), 1 hours);
    }
    
    function testDeploymentRevertsOnZeroTimelock() public {
        vm.expectRevert(PriceFeedManager.InvalidTokenAddress.selector);
        new PriceFeedManager(address(0), address(mockPyth));
    }
    
    function testDeploymentRevertsOnZeroPyth() public {
        vm.expectRevert(PriceFeedManager.InvalidPriceFeedAddress.selector);
        new PriceFeedManager(timelock, address(0));
    }
    
    // ============ PRICE FEED MANAGEMENT TESTS ============
    
    function testSetPriceFeed() public {
        vm.expectEmit(true, true, false, true);
        emit PriceFeedUpdated(token, address(mockChainlink), 18);
        
        priceFeedManager.setPriceFeed(token, address(mockChainlink), 18);
        
        assertEq(address(priceFeedManager.priceFeeds(token)), address(mockChainlink));
        assertEq(priceFeedManager.tokenDecimals(token), 18);
        assertTrue(priceFeedManager.hasPriceFeed(token));
    }
    
    function testSetPriceFeedByTimelock() public {
        vm.prank(timelock);
        priceFeedManager.setPriceFeed(token, address(mockChainlink), 18);
        
        assertEq(address(priceFeedManager.priceFeeds(token)), address(mockChainlink));
    }
    
    function testSetPriceFeedRevertsIfUnauthorized() public {
        vm.prank(unauthorized);
        vm.expectRevert(PriceFeedManager.Unauthorized.selector);
        priceFeedManager.setPriceFeed(token, address(mockChainlink), 18);
    }
    
    function testSetPriceFeedRevertsOnZeroToken() public {
        vm.expectRevert(PriceFeedManager.InvalidTokenAddress.selector);
        priceFeedManager.setPriceFeed(address(0), address(mockChainlink), 18);
    }
    
    function testRemovePriceFeed() public {
        // First set a price feed
        priceFeedManager.setPriceFeed(token, address(mockChainlink), 18);
        assertTrue(priceFeedManager.hasPriceFeed(token));
        
        // Then remove it
        vm.expectEmit(true, true, false, true);
        emit PriceFeedUpdated(token, address(0), 0);
        
        priceFeedManager.setPriceFeed(token, address(0), 0);
        
        assertEq(address(priceFeedManager.priceFeeds(token)), address(0));
        assertEq(priceFeedManager.tokenDecimals(token), 0);
    }
    
    function testSetPythPriceId() public {
        vm.expectEmit(true, true, false, false);
        emit PythPriceIdUpdated(token, PYTH_PRICE_ID);
        
        priceFeedManager.setPythPriceId(token, PYTH_PRICE_ID);
        
        assertEq(priceFeedManager.pythPriceIds(token), PYTH_PRICE_ID);
        assertTrue(priceFeedManager.hasPriceFeed(token));
    }
    
    function testSetPythPriceIdRevertsOnZeroToken() public {
        vm.expectRevert(PriceFeedManager.InvalidTokenAddress.selector);
        priceFeedManager.setPythPriceId(address(0), PYTH_PRICE_ID);
    }
    
    function testSetPythPriceIdRevertsOnZeroPriceId() public {
        vm.expectRevert(PriceFeedManager.InvalidPriceId.selector);
        priceFeedManager.setPythPriceId(token, bytes32(0));
    }
    
    // ============ CHAINLINK PRICE TESTS ============
    
    function testGetChainlinkPrice() public {
        priceFeedManager.setPriceFeed(token, address(mockChainlink), 18);
        
        uint256 price = priceFeedManager.getChainlinkPrice(token);
        assertEq(price, 200000000000); // $2000 with 8 decimals
    }
    
    function testGetChainlinkPriceRevertsOnNoPriceFeed() public {
        vm.expectRevert(PriceFeedManager.PriceFeedNotFound.selector);
        priceFeedManager.getChainlinkPrice(token);
    }
    
    function testGetChainlinkPriceRevertsOnNegativePrice() public {
        priceFeedManager.setPriceFeed(token, address(mockChainlink), 18);
        mockChainlink.updatePrice(-100, block.timestamp);
        
        vm.expectRevert(PriceFeedManager.InvalidPrice.selector);
        priceFeedManager.getChainlinkPrice(token);
    }
    
    function testGetChainlinkPriceRevertsOnZeroPrice() public {
        priceFeedManager.setPriceFeed(token, address(mockChainlink), 18);
        mockChainlink.updatePrice(0, block.timestamp);
        
        vm.expectRevert(PriceFeedManager.InvalidPrice.selector);
        priceFeedManager.getChainlinkPrice(token);
    }
    
    function testGetChainlinkPriceRevertsOnStalePrice() public {
        priceFeedManager.setPriceFeed(token, address(mockChainlink), 18);
        mockChainlink.updatePrice(200000000000, block.timestamp);
        
        // Warp time forward to make price stale
        vm.warp(block.timestamp + 2 hours);
        
        vm.expectRevert(PriceFeedManager.StalePrice.selector);
        priceFeedManager.getChainlinkPrice(token);
    }
    
    function testGetChainlinkPriceRevertsOnInvalidRoundData() public {
        priceFeedManager.setPriceFeed(token, address(mockChainlink), 18);
        mockChainlink.updateRoundData(5, 3); // answeredInRound < roundId
        
        vm.expectRevert(PriceFeedManager.InvalidPrice.selector);
        priceFeedManager.getChainlinkPrice(token);
    }
    
    // ============ PYTH PRICE TESTS ============
    
    function testGetPythPrice() public {
        priceFeedManager.setPythPriceId(token, PYTH_PRICE_ID);
        
        uint256 price = priceFeedManager.getPythPrice(token);
        assertEq(price, 200000000000); // $2000 with 8 decimals
    }
    
    function testGetPythPriceRevertsOnNoPriceId() public {
        vm.expectRevert(PriceFeedManager.PriceFeedNotFound.selector);
        priceFeedManager.getPythPrice(token);
    }
    
    function testGetPythPriceRevertsOnNegativePrice() public {
        priceFeedManager.setPythPriceId(token, PYTH_PRICE_ID);
        mockPyth.updatePrice(PYTH_PRICE_ID, -100, -8, block.timestamp);
        
        vm.expectRevert(PriceFeedManager.InvalidPrice.selector);
        priceFeedManager.getPythPrice(token);
    }
    
    function testGetPythPriceRevertsOnZeroPrice() public {
        priceFeedManager.setPythPriceId(token, PYTH_PRICE_ID);
        mockPyth.updatePrice(PYTH_PRICE_ID, 0, -8, block.timestamp);
        
        vm.expectRevert(PriceFeedManager.InvalidPrice.selector);
        priceFeedManager.getPythPrice(token);
    }
    
    function testGetPythPriceRevertsOnStalePrice() public {
        priceFeedManager.setPythPriceId(token, PYTH_PRICE_ID);
        mockPyth.updatePrice(PYTH_PRICE_ID, 2000, -8, block.timestamp);
        
        // Warp time forward to make price stale
        vm.warp(block.timestamp + 2 hours);
        
        vm.expectRevert(PriceFeedManager.StalePrice.selector);
        priceFeedManager.getPythPrice(token);
    }
    
    function testGetPythPriceWithPositiveExponent() public {
        priceFeedManager.setPythPriceId(token, PYTH_PRICE_ID);
        mockPyth.updatePrice(PYTH_PRICE_ID, 2, 3, block.timestamp); // 2 * 10^3 = 2000
        
        uint256 price = priceFeedManager.getPythPrice(token);
        assertEq(price, 200000000000); // 2000 * 10^8
    }
    
    function testGetPythPriceWithDifferentNegativeExponents() public {
        priceFeedManager.setPythPriceId(token, PYTH_PRICE_ID);
        
        // Test -6 exponent: 2000000 * 10^-6 = $2.000000
        // Chainlink format: 2 * 10^8 = 200000000
        mockPyth.updatePrice(PYTH_PRICE_ID, 2000000, -6, block.timestamp);
        uint256 price = priceFeedManager.getPythPrice(token);
        assertEq(price, 200000000);
        
        // Test -10 exponent: 20000000000 * 10^-10 = $2
        // Result: 20000000000 / 10^2 = 200000000
        mockPyth.updatePrice(PYTH_PRICE_ID, 20000000000, -10, block.timestamp);
        price = priceFeedManager.getPythPrice(token);
        assertEq(price, 200000000);
    }
    
    function testGetPythPriceRevertsOnExtremeExponent() public {
        priceFeedManager.setPythPriceId(token, PYTH_PRICE_ID);
        mockPyth.updatePrice(PYTH_PRICE_ID, 2000, 25, block.timestamp); // Extreme positive exponent
        
        vm.expectRevert(PriceFeedManager.InvalidPrice.selector);
        priceFeedManager.getPythPrice(token);
    }
    
    // ============ FALLBACK MECHANISM TESTS ============
    
    function testGetTokenPriceUsesChainlinkFirst() public {
        // Set up both oracles
        priceFeedManager.setPriceFeed(token, address(mockChainlink), 18);
        priceFeedManager.setPythPriceId(token, PYTH_PRICE_ID);
        
        uint256 price = priceFeedManager.getTokenPrice(token);
        assertEq(price, 200000000000); // Should use Chainlink price
    }
    
    function testGetTokenPriceFallbacksToPyth() public {
        // Set up only Pyth (no Chainlink)
        priceFeedManager.setPythPriceId(token, PYTH_PRICE_ID);
        
        uint256 price = priceFeedManager.getTokenPrice(token);
        assertEq(price, 200000000000); // Should use Pyth price
    }
    
    function testGetTokenPriceFallbacksWhenChainlinkStale() public {
        // Set up both oracles
        priceFeedManager.setPriceFeed(token, address(mockChainlink), 18);
        priceFeedManager.setPythPriceId(token, PYTH_PRICE_ID);
        
        // Make Chainlink stale by setting old timestamp
        mockChainlink.updatePrice(200000000000, 1); // Very old timestamp
        mockPyth.updatePrice(PYTH_PRICE_ID, 2000, 0, block.timestamp); // Fresh Pyth
        
        uint256 price = priceFeedManager.getTokenPrice(token);
        assertEq(price, 200000000000); // Should fallback to Pyth
    }
    
    function testGetTokenPriceRevertsWhenBothFail() public {
        // Set up both oracles
        priceFeedManager.setPriceFeed(token, address(mockChainlink), 18);
        priceFeedManager.setPythPriceId(token, PYTH_PRICE_ID);
        
        // Set prices at current time
        mockChainlink.updatePrice(200000000000, block.timestamp);
        mockPyth.updatePrice(PYTH_PRICE_ID, 2000, 0, block.timestamp);
        
        // Warp time forward to make both stale
        vm.warp(block.timestamp + 2 hours);
        
        vm.expectRevert(PriceFeedManager.StalePrice.selector);
        priceFeedManager.getTokenPrice(token);
    }
    
    // ============ USD CONVERSION TESTS ============
    
    function testGetTokenValueInUSD() public {
        priceFeedManager.setPriceFeed(token, address(mockChainlink), 18);
        
        uint256 amount = 1 ether; // 1 token with 18 decimals
        uint256 usdValue = priceFeedManager.getTokenValueInUSD(token, amount);
        
        // 1 token * $2000 = $2000 with 18 decimals
        assertEq(usdValue, 2000 ether);
    }
    
    function testConvertUsdToToken() public {
        priceFeedManager.setPriceFeed(token, address(mockChainlink), 18);
        
        uint256 usdValue = 2000 ether; // $2000 with 18 decimals
        uint256 tokenAmount = priceFeedManager.convertUsdToToken(token, usdValue);
        
        // $2000 / $2000 = 1 token with 18 decimals
        assertEq(tokenAmount, 1 ether);
    }
    
    function testUSDConversionsWithDifferentDecimals() public {
        // Test with 6 decimals (like USDC)
        priceFeedManager.setPriceFeed(token, address(mockChainlink), 6);
        
        uint256 amount = 1000000; // 1 token with 6 decimals
        uint256 usdValue = priceFeedManager.getTokenValueInUSD(token, amount);
        assertEq(usdValue, 2000 ether); // $2000 with 18 decimals
        
        uint256 tokenAmount = priceFeedManager.convertUsdToToken(token, usdValue);
        assertEq(tokenAmount, 1000000); // 1 token with 6 decimals
    }
    
    // ============ FUZZ TESTS ============
    
    function testFuzzChainlinkPrice(int256 price) public {
        vm.assume(price > 0);
        vm.assume(price <= type(int128).max); // Avoid overflow
        
        priceFeedManager.setPriceFeed(token, address(mockChainlink), 18);
        mockChainlink.updatePrice(price, block.timestamp);
        
        uint256 result = priceFeedManager.getChainlinkPrice(token);
        assertEq(result, uint256(price));
    }
    
    function testFuzzPythPrice(int64 price, int32 expo) public {
        vm.assume(price > 1000); // Larger minimum to avoid 0 results
        vm.assume(expo >= -10 && expo <= 6); // Tighter range
        
        priceFeedManager.setPythPriceId(token, PYTH_PRICE_ID);
        mockPyth.updatePrice(PYTH_PRICE_ID, price, expo, block.timestamp);
        
        uint256 result = priceFeedManager.getPythPrice(token);
        assertGt(result, 0);
    }
    
    function testFuzzUSDConversions(uint256 amount, uint8 decimals) public {
        vm.assume(amount > 0 && amount <= type(uint128).max);
        vm.assume(decimals <= 18);
        
        priceFeedManager.setPriceFeed(token, address(mockChainlink), decimals);
        
        uint256 usdValue = priceFeedManager.getTokenValueInUSD(token, amount);
        uint256 backToToken = priceFeedManager.convertUsdToToken(token, usdValue);
        
        // Should be approximately equal (allowing for rounding)
        assertApproxEqRel(backToToken, amount, 1e15); // 0.1% tolerance
    }
}
