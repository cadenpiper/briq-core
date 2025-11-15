import hardhatToolboxViemPlugin from "@nomicfoundation/hardhat-toolbox-viem";
import { configVariable, defineConfig } from "hardhat/config";

export default defineConfig({
  plugins: [hardhatToolboxViemPlugin],
  solidity: {
    profiles: {
      default: {
        version: "0.8.28",
        settings: {
          optimizer: {
            enabled: true,
            runs: 200,
          },
        },
      },
      production: {
        version: "0.8.28",
        settings: {
          optimizer: {
            enabled: true,
            runs: 1000,
          },
        },
      },
    },
  },
  networks: {
    hardhat: {
      type: "edr-simulated",
      chainType: "generic",
      forkingUrl: `https://arb-mainnet.g.alchemy.com/v2/${configVariable("ALCHEMY_API_KEY")}`,
    },
    arbitrum: {
      type: "http",
      chainType: "generic",
      url: `https://arb-mainnet.g.alchemy.com/v2/${configVariable("ALCHEMY_API_KEY")}`,
      accounts: [configVariable("PRIVATE_KEY")],
    },
    arbitrumSepolia: {
      type: "http", 
      chainType: "generic",
      url: `https://arb-sepolia.g.alchemy.com/v2/${configVariable("ALCHEMY_API_KEY")}`,
      accounts: [configVariable("PRIVATE_KEY")],
    },
  },
});
