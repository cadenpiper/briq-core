import assert from "node:assert/strict";
import { describe, it } from "node:test";
import { network } from "hardhat";

describe("PriceFeedManager", async function () {
  const { viem } = await network.connect();
  const publicClient = await viem.getPublicClient();

  // Arbitrum mainnet addresses
  const ETH_CHAINLINK_FEED = "0x639Fe6ab55C921f74e7fac1ee960C0B6293ba612";
  const PYTH_CONTRACT = "0xff1a0f4744e8582DF1aE09D5611b887B6a12925C";
  const WETH_ADDRESS = "0x82aF49447D8a07e3bd95BD0d56f35241523fBab1";

  function formatPrice(price: bigint): string {
    return `$${(Number(price) / 1e8).toLocaleString('en-US', { minimumFractionDigits: 2, maximumFractionDigits: 2 })}`;
  }

  it("should deploy PriceFeedManager successfully", async function () {
    const priceFeedManager = await viem.deployContract("PriceFeedManager", [
      "0x0000000000000000000000000000000000000001", // timelock placeholder
      PYTH_CONTRACT
    ]);

    assert(priceFeedManager.address, "Contract should be deployed");
    console.log(`[DEPLOY] PriceFeedManager deployed at: ${priceFeedManager.address}`);
  });

  it("should configure Chainlink price feed", async function () {
    const priceFeedManager = await viem.deployContract("PriceFeedManager", [
      "0x0000000000000000000000000000000000000001",
      PYTH_CONTRACT
    ]);

    // Initially should not have price feed
    let hasFeed = await priceFeedManager.read.hasPriceFeed([WETH_ADDRESS]);
    assert(!hasFeed, "Should not have price feed initially");

    // Add Chainlink feed
    await priceFeedManager.write.setPriceFeed([WETH_ADDRESS, ETH_CHAINLINK_FEED, 18]);

    // Should now have price feed
    hasFeed = await priceFeedManager.read.hasPriceFeed([WETH_ADDRESS]);
    assert(hasFeed, "Should have price feed after configuration");
    console.log("[CONFIG] Chainlink price feed configured for WETH");
  });

  it("should get valid Chainlink price", async function () {
    const priceFeedManager = await viem.deployContract("PriceFeedManager", [
      "0x0000000000000000000000000000000000000001",
      PYTH_CONTRACT
    ]);

    await priceFeedManager.write.setPriceFeed([WETH_ADDRESS, ETH_CHAINLINK_FEED, 18]);

    const price = await priceFeedManager.read.getChainlinkPrice([WETH_ADDRESS]);
    console.log(`[PRICE] Chainlink ETH Price: ${formatPrice(price)}`);
    
    assert(price > 0n, "Price should be positive");
    assert(price > 100000000000n, "ETH price should be > $1000 (reasonable check)");
    assert(price < 1000000000000n, "ETH price should be < $10000 (reasonable check)");
  });

  it("should use Chainlink price in getTokenPrice", async function () {
    const priceFeedManager = await viem.deployContract("PriceFeedManager", [
      "0x0000000000000000000000000000000000000001",
      PYTH_CONTRACT
    ]);

    await priceFeedManager.write.setPriceFeed([WETH_ADDRESS, ETH_CHAINLINK_FEED, 18]);

    const chainlinkPrice = await priceFeedManager.read.getChainlinkPrice([WETH_ADDRESS]);
    const tokenPrice = await priceFeedManager.read.getTokenPrice([WETH_ADDRESS]);

    console.log(`[ORACLE] Direct Chainlink: ${formatPrice(chainlinkPrice)}`);
    console.log(`[ORACLE] getTokenPrice():  ${formatPrice(tokenPrice)}`);

    assert(chainlinkPrice === tokenPrice, "getTokenPrice should return Chainlink price when available");
  });

  it("should detect stale Chainlink data", async function () {
    const priceFeedManager = await viem.deployContract("PriceFeedManager", [
      "0x0000000000000000000000000000000000000001",
      PYTH_CONTRACT
    ]);

    await priceFeedManager.write.setPriceFeed([WETH_ADDRESS, ETH_CHAINLINK_FEED, 18]);

    // Verify price works initially
    const initialPrice = await priceFeedManager.read.getChainlinkPrice([WETH_ADDRESS]);
    assert(initialPrice > 0n, "Initial price should work");
    console.log(`[STALENESS] Initial price: ${formatPrice(initialPrice)} (fresh)`);

    // Make Chainlink stale by advancing time 2 hours
    await publicClient.request({
      method: "evm_increaseTime",
      params: [7200] // 2 hours
    });
    await publicClient.request({
      method: "evm_mine",
      params: []
    });

    // Should now throw StalePrice error
    try {
      await priceFeedManager.read.getChainlinkPrice([WETH_ADDRESS]);
      assert.fail("Should throw error for stale Chainlink data");
    } catch (error) {
      console.log("[STALENESS] Stale data correctly rejected (>1 hour old)");
      assert(error.message.includes("StalePrice"), "Should throw StalePrice error");
    }
  });
});
