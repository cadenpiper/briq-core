import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";

export default buildModule("BriqCoreModule", (m) => {
  // Deploy PriceFeedManager first
  const priceFeedManager = m.contract("PriceFeedManager");

  // Deploy BriqShares
  const briqShares = m.contract("BriqShares", ["Briq Shares", "BRIQ"]);

  return { 
    priceFeedManager,
    briqShares 
  };
});
