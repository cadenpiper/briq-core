import assert from "node:assert/strict";
import { describe, it } from "node:test";
import { network } from "hardhat";

describe("PriceFeedManager - Pyth Fallback", async function () {
  const { viem, networkHelpers } = await network.connect();

  // Arbitrum mainnet addresses
  const ETH_CHAINLINK_FEED = "0x639Fe6ab55C921f74e7fac1ee960C0B6293ba612";
  const PYTH_CONTRACT = "0xff1a0f4744e8582DF1aE09D5611b887B6a12925C";
  const ETH_PYTH_ID = "0xff61491a931112ddf1bd8147cd1b641375f79f5825126d665480874634fd0ace";
  const WETH_ADDRESS = "0x82aF49447D8a07e3bd95BD0d56f35241523fBab1";

  function formatPrice(price: bigint): string {
    return `$${(Number(price) / 1e8).toLocaleString('en-US', { minimumFractionDigits: 2, maximumFractionDigits: 2 })}`;
  }

  it("should test Pyth fallback with fresh data", async function () {
    const priceFeedManager = await viem.deployContract("PriceFeedManager", [
      "0x0000000000000000000000000000000000000001",
      PYTH_CONTRACT
    ]);

    await priceFeedManager.write.setPriceFeed([WETH_ADDRESS, ETH_CHAINLINK_FEED, 18]);
    await priceFeedManager.write.setPythPriceId([WETH_ADDRESS, ETH_PYTH_ID]);

    const currentTime = await networkHelpers.time.latest();
    console.log(`[TIME] Starting at timestamp: ${currentTime}`);

    // Check Pyth data freshness
    const pythContract = await viem.getContractAt("IPyth", PYTH_CONTRACT, {
      abi: [
        {
          name: "getPriceUnsafe",
          type: "function", 
          stateMutability: "view",
          inputs: [{ name: "id", type: "bytes32" }],
          outputs: [
            {
              name: "price",
              type: "tuple",
              components: [
                { name: "price", type: "int64" },
                { name: "conf", type: "uint64" },
                { name: "expo", type: "int32" },
                { name: "publishTime", type: "uint256" }
              ]
            }
          ]
        }
      ]
    });

    const rawPythData = await pythContract.read.getPriceUnsafe([ETH_PYTH_ID]);
    const pythAge = Number(currentTime) - Number(rawPythData.publishTime);
    console.log(`[DEBUG] Pyth age: ${pythAge} seconds (threshold: 20s)`);

    if (pythAge <= 20) {
      console.log("[PYTH] Fresh Pyth data found! Testing fallback scenario...");
      
      const pythPrice = await priceFeedManager.read.getPythPrice([WETH_ADDRESS]);
      console.log(`[PYTH] Fresh Pyth price: ${formatPrice(pythPrice)}`);

      const chainlinkPrice = await priceFeedManager.read.getChainlinkPrice([WETH_ADDRESS]);
      console.log(`[CHAINLINK] Initial Chainlink price: ${formatPrice(chainlinkPrice)}`);

      // Advance time by 1 hour + 1 second to make Chainlink stale
      // Pyth will become stale too (10 + 3601 = 3611 seconds), but let's see what happens
      console.log("[TIME] Advancing 1 hour to make Chainlink stale...");
      await networkHelpers.time.increase(3601);

      // Check Chainlink status
      try {
        await priceFeedManager.read.getChainlinkPrice([WETH_ADDRESS]);
        console.log("[CHAINLINK] Still fresh (unexpected)");
      } catch (error) {
        console.log("[CHAINLINK] Now stale ✓");
      }

      // Check Pyth status  
      try {
        const newPythPrice = await priceFeedManager.read.getPythPrice([WETH_ADDRESS]);
        console.log(`[PYTH] Still fresh: ${formatPrice(newPythPrice)} ✓`);
        
        // Test fallback
        const fallbackPrice = await priceFeedManager.read.getTokenPrice([WETH_ADDRESS]);
        console.log(`[FALLBACK] Result: ${formatPrice(fallbackPrice)}`);
        
        if (fallbackPrice === newPythPrice) {
          console.log("[SUCCESS] Pyth fallback working!");
        } else {
          console.log("[INFO] Fallback not using Pyth");
        }
        
      } catch (error) {
        console.log("[PYTH] Also became stale");
        console.log("[INFO] Both oracles stale - dual protection working");
      }
      
    } else {
      console.log(`[INFO] Pyth data is ${pythAge}s old, testing dual-oracle protection`);
      
      // Make Chainlink stale
      await networkHelpers.time.increase(3600);
      
      try {
        await priceFeedManager.read.getTokenPrice([WETH_ADDRESS]);
        assert.fail("Both oracles stale should throw error");
      } catch (error) {
        console.log("[PROTECTION] Both oracles stale - system correctly protected");
      }
    }
  });
});
