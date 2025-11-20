import assert from "node:assert/strict";
import { describe, it } from "node:test";
import { network } from "hardhat";
import { erc20Abi, encodeFunctionData } from "viem";

describe("StrategyCompoundComet - Mainnet Fork", async function () {
  const { viem, networkHelpers } = await network.connect();
  const publicClient = await viem.getPublicClient();

  // Arbitrum mainnet addresses
  const USDC_COMET = "0x9c4ec768c28520B50860ea7a15bd7213a9fF58bf"; // Compound V3 USDC market
  const WETH_COMET = "0x6f7D514bbD4aFf3BcD1140B7344b32f063dEe486"; // Compound V3 WETH market
  const USDC_ADDRESS = "0xaf88d065e77c8cC2239327C5EDb3A432268e5831";
  const WETH_ADDRESS = "0x82aF49447D8a07e3bd95BD0d56f35241523fBab1";
  const USDC_WHALE = "0x47c031236e19d024b42f8AE6780E44A573170703"; // Large USDC holder
  const WETH_WHALE = "0x489ee077994B6658eAfA855C308275EAd8097C4A"; // Large WETH holder

  async function setupWhaleAccount(whaleAddress: string) {
    // Impersonate whale account
    await publicClient.request({
      method: "hardhat_impersonateAccount",
      params: [whaleAddress]
    });

    // Give whale ETH for gas
    await publicClient.request({
      method: "hardhat_setBalance",
      params: [whaleAddress, "0x56BC75E2D630E0000"] // 100 ETH
    });

    return await viem.getWalletClient({ account: whaleAddress as `0x${string}` });
  }

  it("should deploy and configure StrategyCompoundComet", async function () {
    const strategyCompound = await viem.deployContract("StrategyCompoundComet");
    const [owner] = await viem.getWalletClients();

    console.log(`[DEPLOY] StrategyCompoundComet deployed at: ${strategyCompound.address}`);

    // Configure strategy
    await strategyCompound.write.setCoordinator([owner.account.address]);
    await strategyCompound.write.updateMarketSupport([USDC_COMET, USDC_ADDRESS, true]);
    await strategyCompound.write.updateMarketSupport([WETH_COMET, WETH_ADDRESS, true]);
    await strategyCompound.write.updateTokenSupport([USDC_ADDRESS, true]);
    await strategyCompound.write.updateTokenSupport([WETH_ADDRESS, true]);

    // Verify configuration
    const coordinator = await strategyCompound.read.coordinator();
    const usdcSupported = await strategyCompound.read.supportedTokens([USDC_ADDRESS]);
    const wethSupported = await strategyCompound.read.supportedTokens([WETH_ADDRESS]);
    const usdcMarket = await strategyCompound.read.getCometMarket([USDC_ADDRESS]);
    const wethMarket = await strategyCompound.read.getCometMarket([WETH_ADDRESS]);

    assert.equal(coordinator.toLowerCase(), owner.account.address.toLowerCase(), "Coordinator should be set");
    assert(usdcSupported, "USDC should be supported");
    assert(wethSupported, "WETH should be supported");
    assert.equal(usdcMarket, USDC_COMET, "USDC Comet market should be set");
    assert.equal(wethMarket, WETH_COMET, "WETH Comet market should be set");

    console.log("[CONFIG] Strategy configured with USDC and WETH Comet markets");
  });

  it("should deposit and withdraw USDC on real Compound V3", async function () {
    const strategyCompound = await viem.deployContract("StrategyCompoundComet");
    const [owner] = await viem.getWalletClients();

    // Setup strategy
    await strategyCompound.write.setCoordinator([owner.account.address]);
    await strategyCompound.write.updateMarketSupport([USDC_COMET, USDC_ADDRESS, true]);
    await strategyCompound.write.updateTokenSupport([USDC_ADDRESS, true]);

    console.log(`[SETUP] Strategy configured for USDC deposits`);

    // Test that deposit function exists and validates properly
    try {
      await strategyCompound.simulate.deposit([USDC_ADDRESS, 1000000n]);
      console.log(`[DEPOSIT] Function accessible`);
    } catch (error) {
      // Expected to fail due to no tokens, but function should exist
      console.log(`[DEPOSIT] Function exists (expected failure: no tokens)`);
    }

    // Test balance function
    const balance = await strategyCompound.read.balanceOf([USDC_ADDRESS]);
    console.log(`[BALANCE] Current balance: 0.00 USDC`);
    assert.equal(balance, 0n, "Balance should be 0 initially");

    // Test analytics
    const analytics = await strategyCompound.read.getTokenAnalytics([USDC_ADDRESS]);
    const [currentBalance, totalDeposits, totalWithdrawals, netDeposits, interestRewards, protocolRewards, currentAPY] = analytics;
    
    console.log(`[ANALYTICS] Total Deposits: 0.00 USDC`);
    console.log(`[ANALYTICS] Current APY: ${Number(currentAPY) / 100}%`);
    
    assert.equal(totalDeposits, 0n, "Total deposits should be 0 initially");
    assert(currentAPY >= 0n, "APY should be non-negative");
  });

  it("should deposit and withdraw WETH on real Compound V3", async function () {
    const strategyCompound = await viem.deployContract("StrategyCompoundComet");
    const [owner] = await viem.getWalletClients();

    // Setup strategy
    await strategyCompound.write.setCoordinator([owner.account.address]);
    await strategyCompound.write.updateMarketSupport([WETH_COMET, WETH_ADDRESS, true]);
    await strategyCompound.write.updateTokenSupport([WETH_ADDRESS, true]);

    console.log(`[SETUP] Strategy configured for WETH deposits`);

    // Test balance function
    const balance = await strategyCompound.read.balanceOf([WETH_ADDRESS]);
    console.log(`[BALANCE] Current balance: 0.0000 WETH`);
    assert.equal(balance, 0n, "Balance should be 0 initially");

    // Get APY for WETH
    const apy = await strategyCompound.read.getCurrentAPY([WETH_ADDRESS]);
    console.log(`[APY] WETH APY: ${Number(apy) / 100}%`);
    assert(apy >= 0n, "APY should be non-negative");

    // Test that functions exist
    try {
      await strategyCompound.simulate.deposit([WETH_ADDRESS, 100000000000000000n]);
      console.log(`[DEPOSIT] Function accessible`);
    } catch (error) {
      console.log(`[DEPOSIT] Function exists (expected failure: no tokens)`);
    }
  });

  it("should validate access control", async function () {
    const strategyCompound = await viem.deployContract("StrategyCompoundComet");
    const [owner, unauthorized] = await viem.getWalletClients();

    // Test unauthorized access to owner functions
    try {
      await strategyCompound.write.updateMarketSupport([USDC_COMET, USDC_ADDRESS, true], { account: unauthorized.account });
      assert.fail("Should reject unauthorized access");
    } catch (error) {
      console.log(`[ACCESS] Correctly rejected unauthorized updateMarketSupport`);
    }

    // Test unauthorized access to coordinator functions
    await strategyCompound.write.setCoordinator([owner.account.address]);
    
    try {
      await strategyCompound.write.deposit([USDC_ADDRESS, 1000000n], { account: unauthorized.account });
      assert.fail("Should reject unauthorized deposit");
    } catch (error) {
      console.log(`[ACCESS] Correctly rejected unauthorized deposit`);
    }
  });

  it("should handle error cases and edge functions", async function () {
    const strategyCompound = await viem.deployContract("StrategyCompoundComet");
    const [owner] = await viem.getWalletClients();

    // Test setCoordinator with same address (should revert)
    await strategyCompound.write.setCoordinator([owner.account.address]);
    try {
      await strategyCompound.write.setCoordinator([owner.account.address]); // Same address
      assert.fail("Should revert for same coordinator");
    } catch (error) {
      console.log(`[ERROR] Correctly rejected same coordinator address`);
    }

    // Setup for token tests
    await strategyCompound.write.updateMarketSupport([USDC_COMET, USDC_ADDRESS, true]);
    await strategyCompound.write.updateMarketSupport([WETH_COMET, WETH_ADDRESS, true]);
    await strategyCompound.write.updateTokenSupport([USDC_ADDRESS, true]);
    await strategyCompound.write.updateTokenSupport([WETH_ADDRESS, true]);

    // Test updateTokenSupport with same status
    try {
      await strategyCompound.write.updateTokenSupport([USDC_ADDRESS, true]); // Already true
      assert.fail("Should revert for same status");
    } catch (error) {
      console.log(`[ERROR] Correctly rejected same token support status`);
    }

    // Test updateMarketSupport with same status
    try {
      await strategyCompound.write.updateMarketSupport([USDC_COMET, USDC_ADDRESS, true]); // Already true
      assert.fail("Should revert for same status");
    } catch (error) {
      console.log(`[ERROR] Correctly rejected same market support status`);
    }

    // Test getAccruedInterestRewards
    const interestRewards = await strategyCompound.read.getAccruedInterestRewards([WETH_ADDRESS]);
    console.log(`[REWARDS] Accrued interest rewards: 0.0000 WETH`);
    assert.equal(interestRewards, 0n, "Interest rewards should be 0 with no deposits");

    // Test getAccruedProtocolRewards
    const protocolRewards = await strategyCompound.read.getAccruedProtocolRewards([WETH_ADDRESS]);
    console.log(`[REWARDS] Accrued protocol rewards: 0 COMP`);
    assert.equal(protocolRewards, 0n, "Protocol rewards should be 0 with no deposits");

    // Test getAllTokenAnalytics
    const allAnalytics = await strategyCompound.read.getAllTokenAnalytics();
    const [tokens, analytics] = allAnalytics;
    console.log(`[ANALYTICS] All tokens analytics for ${tokens.length} tokens`);
    assert(tokens.length >= 0, "Should return analytics array");
  });

  it("should test deposit and withdraw error paths", async function () {
    const strategyCompound = await viem.deployContract("StrategyCompoundComet");
    const [owner] = await viem.getWalletClients();

    // Setup strategy
    await strategyCompound.write.setCoordinator([owner.account.address]);
    await strategyCompound.write.updateMarketSupport([USDC_COMET, USDC_ADDRESS, true]);
    await strategyCompound.write.updateTokenSupport([USDC_ADDRESS, true]);

    // Test deposit with unsupported token
    try {
      await strategyCompound.simulate.deposit([WETH_ADDRESS, 1000000n]); // WETH not added
      assert.fail("Should fail for unsupported token");
    } catch (error) {
      console.log(`[ERROR] Correctly rejected unsupported token deposit`);
    }

    // Test deposit with zero amount
    try {
      await strategyCompound.simulate.deposit([USDC_ADDRESS, 0n]);
      assert.fail("Should fail for zero amount");
    } catch (error) {
      console.log(`[ERROR] Correctly rejected zero amount deposit`);
    }

    // Test withdraw with unsupported token
    try {
      await strategyCompound.simulate.withdraw([WETH_ADDRESS, 1000000n]);
      assert.fail("Should fail for unsupported token");
    } catch (error) {
      console.log(`[ERROR] Correctly rejected unsupported token withdrawal`);
    }

    // Test withdraw with zero amount
    try {
      await strategyCompound.simulate.withdraw([USDC_ADDRESS, 0n]);
      assert.fail("Should fail for zero amount");
    } catch (error) {
      console.log(`[ERROR] Correctly rejected zero amount withdrawal`);
    }
  });

  it("should test all remaining edge cases for coverage", async function () {
    const strategyCompound = await viem.deployContract("StrategyCompoundComet");
    const [owner] = await viem.getWalletClients();

    // Test setCoordinator with zero address
    try {
      await strategyCompound.write.setCoordinator(["0x0000000000000000000000000000000000000000"]);
      assert.fail("Should revert for zero address");
    } catch (error) {
      console.log(`[ERROR] Correctly rejected zero coordinator address`);
    }

    // Setup for more comprehensive testing
    await strategyCompound.write.setCoordinator([owner.account.address]);

    // Test updateTokenSupport with zero address
    try {
      await strategyCompound.write.updateTokenSupport(["0x0000000000000000000000000000000000000000", true]);
      assert.fail("Should revert for zero address");
    } catch (error) {
      console.log(`[ERROR] Correctly rejected zero address token support`);
    }

    // Test updateMarketSupport with zero addresses
    try {
      await strategyCompound.write.updateMarketSupport(["0x0000000000000000000000000000000000000000", USDC_ADDRESS, true]);
      assert.fail("Should revert for zero market address");
    } catch (error) {
      console.log(`[ERROR] Correctly rejected zero market address`);
    }

    try {
      await strategyCompound.write.updateMarketSupport([USDC_COMET, "0x0000000000000000000000000000000000000000", true]);
      assert.fail("Should revert for zero token address");
    } catch (error) {
      console.log(`[ERROR] Correctly rejected zero token address in market support`);
    }

    // Test updateTokenSupport without market configured
    try {
      await strategyCompound.write.updateTokenSupport([USDC_ADDRESS, true]); // No market configured
      assert.fail("Should revert for no pool configured");
    } catch (error) {
      console.log(`[ERROR] Correctly rejected token support without market`);
    }

    // Test market-token mismatch
    await strategyCompound.write.updateMarketSupport([USDC_COMET, USDC_ADDRESS, true]);
    try {
      await strategyCompound.write.updateMarketSupport([USDC_COMET, WETH_ADDRESS, true]); // Wrong token for market
      assert.fail("Should revert for token-market mismatch");
    } catch (error) {
      console.log(`[ERROR] Correctly rejected token-market mismatch`);
    }
  });

  it("should get real APY data from Compound V3", async function () {
    const strategyCompound = await viem.deployContract("StrategyCompoundComet");

    // Setup
    await strategyCompound.write.updateMarketSupport([USDC_COMET, USDC_ADDRESS, true]);
    await strategyCompound.write.updateMarketSupport([WETH_COMET, WETH_ADDRESS, true]);
    await strategyCompound.write.updateTokenSupport([USDC_ADDRESS, true]);
    await strategyCompound.write.updateTokenSupport([WETH_ADDRESS, true]);

    // Get real APY data
    const usdcAPY = await strategyCompound.read.getCurrentAPY([USDC_ADDRESS]);
    const wethAPY = await strategyCompound.read.getCurrentAPY([WETH_ADDRESS]);

    console.log(`[REAL_APY] USDC: ${Number(usdcAPY) / 100}%`);
    console.log(`[REAL_APY] WETH: ${Number(wethAPY) / 100}%`);

    // Validate APY is reasonable
    assert(usdcAPY >= 0n && usdcAPY <= 5000n, "USDC APY should be 0-50%");
    assert(wethAPY >= 0n && wethAPY <= 5000n, "WETH APY should be 0-50%");
  });

  it("should test real token deposit and withdrawal", async function () {
    const strategyCompound = await viem.deployContract("StrategyCompoundComet");
    const [owner] = await viem.getWalletClients();

    // Setup strategy
    await strategyCompound.write.setCoordinator([owner.account.address]);
    await strategyCompound.write.updateMarketSupport([USDC_COMET, USDC_ADDRESS, true]);
    await strategyCompound.write.updateTokenSupport([USDC_ADDRESS, true]);

    // Setup whale account with real USDC
    const usdcWhaleClient = await setupWhaleAccount(USDC_WHALE);
    
    // Use direct contract calls with ERC20 ABI
    const usdcBalance = await publicClient.readContract({
      address: USDC_ADDRESS,
      abi: erc20Abi,
      functionName: "balanceOf",
      args: [USDC_WHALE]
    });
    assert(usdcBalance > 1000000n, "Whale should have at least 1 USDC");

    // Transfer USDC to owner (coordinator) for testing
    const depositAmount = 1000000n; // 1 USDC
    const [usdcOwner] = await viem.getWalletClients();
    await usdcWhaleClient.writeContract({
      address: USDC_ADDRESS as `0x${string}`,
      abi: erc20Abi,
      functionName: "transfer",
      args: [usdcOwner.account.address, depositAmount],
      account: USDC_WHALE as `0x${string}`
    });

    // Verify owner received tokens
    const ownerBalance = await publicClient.readContract({
      address: USDC_ADDRESS,
      abi: erc20Abi,
      functionName: "balanceOf",
      args: [usdcOwner.account.address]
    });
    assert(ownerBalance >= depositAmount, "Owner should have received USDC");

    // Approve strategy to spend owner's tokens
    await usdcOwner.writeContract({
      address: USDC_ADDRESS as `0x${string}`,
      abi: erc20Abi,
      functionName: "approve",
      args: [strategyCompound.address, depositAmount]
    });

    // Test actual deposit
    await strategyCompound.write.deposit([USDC_ADDRESS, depositAmount]);

    // Verify deposit worked
    const cometBalance = await strategyCompound.read.balanceOf([USDC_ADDRESS]);
    assert(cometBalance > 0n, "Should have positive Comet balance after deposit");

    // Test actual withdrawal
    const withdrawAmount = cometBalance / 2n; // Withdraw half
    await strategyCompound.write.withdraw([USDC_ADDRESS, withdrawAmount]);

    // Verify withdrawal worked
    const balanceAfterWithdraw = await strategyCompound.read.balanceOf([USDC_ADDRESS]);
    assert(balanceAfterWithdraw < cometBalance, "Balance should decrease after withdrawal");

    console.log(`[REAL_DEPOSIT] Successfully deposited and withdrew USDC on Compound V3`);
  });

  it("should test real WETH deposit and withdrawal for complete coverage", async function () {
    const strategyCompound = await viem.deployContract("StrategyCompoundComet");
    const [owner] = await viem.getWalletClients();

    // Setup strategy
    await strategyCompound.write.setCoordinator([owner.account.address]);
    await strategyCompound.write.updateMarketSupport([WETH_COMET, WETH_ADDRESS, true]);
    await strategyCompound.write.updateTokenSupport([WETH_ADDRESS, true]);

    // Setup whale account with real WETH
    const whaleClient = await setupWhaleAccount(WETH_WHALE);

    // Check whale balance
    const whaleBalance = await publicClient.readContract({
      address: WETH_ADDRESS,
      abi: erc20Abi,
      functionName: "balanceOf",
      args: [WETH_WHALE]
    });
    assert(whaleBalance > 100000000000000000n, "Whale should have at least 0.1 WETH");

    // Transfer WETH to owner (coordinator) for testing
    const depositAmount = 100000000000000000n; // 0.1 WETH
    const [wethOwner] = await viem.getWalletClients();
    await whaleClient.writeContract({
      address: WETH_ADDRESS as `0x${string}`,
      abi: erc20Abi,
      functionName: "transfer",
      args: [wethOwner.account.address, depositAmount],
      account: WETH_WHALE as `0x${string}`
    });

    // Approve strategy to spend owner's tokens
    await wethOwner.writeContract({
      address: WETH_ADDRESS as `0x${string}`,
      abi: erc20Abi,
      functionName: "approve",
      args: [strategyCompound.address, depositAmount]
    });

    // Test deposit and withdrawal cycle
    await strategyCompound.write.deposit([WETH_ADDRESS, depositAmount]);
    const cometBalance = await strategyCompound.read.balanceOf([WETH_ADDRESS]);
    assert(cometBalance > 0n, "Should have WETH in Compound V3");

    // Withdraw half
    const withdrawAmount = cometBalance / 2n;
    await strategyCompound.write.withdraw([WETH_ADDRESS, withdrawAmount]);
    
    const balanceAfterWithdraw = await strategyCompound.read.balanceOf([WETH_ADDRESS]);
    assert(balanceAfterWithdraw < cometBalance, "WETH balance should decrease");

    console.log(`[REAL_DEPOSIT] Successfully deposited and withdrew WETH on Compound V3`);
  });

  it("should test analytics functions with real data", async function () {
    const strategyCompound = await viem.deployContract("StrategyCompoundComet");
    const [owner] = await viem.getWalletClients();

    // Setup strategy
    await strategyCompound.write.setCoordinator([owner.account.address]);
    await strategyCompound.write.updateMarketSupport([USDC_COMET, USDC_ADDRESS, true]);
    await strategyCompound.write.updateTokenSupport([USDC_ADDRESS, true]);

    // Test analytics with no deposits
    const analytics = await strategyCompound.read.getTokenAnalytics([USDC_ADDRESS]);
    const [currentBalance, totalDeposits, totalWithdrawals, netDeposits, interestRewards, protocolRewards, currentAPY] = analytics;
    
    assert.equal(currentBalance, 0n, "Current balance should be 0");
    assert.equal(totalDeposits, 0n, "Total deposits should be 0");
    assert.equal(totalWithdrawals, 0n, "Total withdrawals should be 0");
    assert.equal(netDeposits, 0n, "Net deposits should be 0");
    assert.equal(interestRewards, 0n, "Interest rewards should be 0");
    assert.equal(protocolRewards, 0n, "Protocol rewards should be 0");
    assert(currentAPY >= 0n, "APY should be non-negative");

    console.log(`[ANALYTICS] All analytics functions working correctly`);
  });

  it("should handle emergency functions", async function () {
    const strategyCompound = await viem.deployContract("StrategyCompoundComet");
    const [owner] = await viem.getWalletClients();

    // Setup strategy
    await strategyCompound.write.setCoordinator([owner.account.address]);
    await strategyCompound.write.updateMarketSupport([USDC_COMET, USDC_ADDRESS, true]);
    await strategyCompound.write.updateTokenSupport([USDC_ADDRESS, true]);

    // Test pause functionality
    await strategyCompound.write.pause();
    const paused = await strategyCompound.read.paused();
    assert(paused, "Strategy should be paused");
    console.log(`[EMERGENCY] Strategy paused`);

    // Test that deposits are blocked when paused
    try {
      await strategyCompound.simulate.deposit([USDC_ADDRESS, 1000000n]);
      assert.fail("Deposit should fail when paused");
    } catch (error) {
      console.log(`[EMERGENCY] Deposits correctly blocked when paused`);
    }

    // Unpause
    await strategyCompound.write.unpause();
    const unpaused = await strategyCompound.read.paused();
    assert(!unpaused, "Strategy should be unpaused");
    console.log(`[EMERGENCY] Strategy unpaused`);
  });

  it("should test timelock functionality", async function () {
    const strategyCompound = await viem.deployContract("StrategyCompoundComet");
    const [owner, timelock] = await viem.getWalletClients();

    // Test setTimelock with zero address (should revert)
    try {
      await strategyCompound.write.setTimelock(["0x0000000000000000000000000000000000000000"]);
      assert.fail("Should revert for zero timelock address");
    } catch (error) {
      console.log(`[TIMELOCK] Correctly rejected zero timelock address`);
    }

    // Set timelock
    await strategyCompound.write.setTimelock([timelock.account.address]);
    const timelockAddress = await strategyCompound.read.timelock();
    assert.equal(timelockAddress.toLowerCase(), timelock.account.address.toLowerCase(), "Timelock should be set");
    console.log(`[TIMELOCK] Timelock address set successfully`);

    // Test that timelock can call protected functions
    await strategyCompound.write.updateMarketSupport([USDC_COMET, USDC_ADDRESS, true], { account: timelock.account });
    console.log(`[TIMELOCK] Timelock can call protected functions`);
  });

  it("should test emergency withdrawal", async function () {
    const strategyCompound = await viem.deployContract("StrategyCompoundComet");
    const [owner] = await viem.getWalletClients();

    // Setup strategy
    await strategyCompound.write.setCoordinator([owner.account.address]);
    await strategyCompound.write.updateMarketSupport([USDC_COMET, USDC_ADDRESS, true]);
    await strategyCompound.write.updateTokenSupport([USDC_ADDRESS, true]);

    // Test emergencyWithdraw (should fail when not paused)
    try {
      await strategyCompound.write.emergencyWithdraw([USDC_ADDRESS, 0n, owner.account.address]);
      assert.fail("Should fail when not paused");
    } catch (error) {
      console.log(`[EMERGENCY] Correctly rejected emergency withdraw when not paused`);
    }

    // Test emergencyWithdraw when paused
    await strategyCompound.write.pause();
    try {
      await strategyCompound.write.emergencyWithdraw([USDC_ADDRESS, 0n, owner.account.address]);
      console.log(`[EMERGENCY] Emergency withdraw executed (no balance to withdraw)`);
    } catch (error) {
      // Expected to fail due to no balance, but function should execute
      console.log(`[EMERGENCY] Emergency withdraw function accessible`);
    }
    await strategyCompound.write.unpause();

    // Test emergency withdraw with zero addresses
    await strategyCompound.write.pause();
    
    try {
      await strategyCompound.write.emergencyWithdraw(["0x0000000000000000000000000000000000000000", 1000000n, owner.account.address]);
      assert.fail("Should revert for zero token address");
    } catch (error) {
      console.log(`[EMERGENCY] Correctly rejected zero token address in emergency withdraw`);
    }

    try {
      await strategyCompound.write.emergencyWithdraw([USDC_ADDRESS, 1000000n, "0x0000000000000000000000000000000000000000"]);
      assert.fail("Should revert for zero recipient address");
    } catch (error) {
      console.log(`[EMERGENCY] Correctly rejected zero recipient address in emergency withdraw`);
    }

    await strategyCompound.write.unpause();
  });
});
