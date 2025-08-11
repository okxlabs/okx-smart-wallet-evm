import { HardhatUserConfig } from "hardhat/config";
import "@nomicfoundation/hardhat-toolbox";
import "dotenv/config";

const config: HardhatUserConfig = {
  solidity: "0.8.23",
  paths: {
    sources: "./src",
    cache: "./cache",
    artifacts: "./artifacts"
  },
  networks: {
    hardhat: {
      chainId: 31337
    },
    eth: {
      url: "https://eth.drpc.org",
      chainId: 1,
      accounts: [process.env.DEPLOYER_PRIVATE_KEY || ""],
    },
    devnet6: {
      url: "https://rpc.pectra-devnet-6.ethpandaops.io",
      chainId: 7072151312,
      accounts: [process.env.DEPLOYER_PRIVATE_KEY || ""],
    },
    holesky: {
      url: "https://1rpc.io/holesky",
      chainId: 17000,
      accounts: [process.env.DEPLOYER_PRIVATE_KEY || ""],
    },
    bsc: {
      url: "https://bsc-dataseed.binance.org/",
      chainId: 56,
      accounts: [process.env.DEPLOYER_PRIVATE_KEY || ""],
    },
    sepolia: {
      url: "https://ethereum-sepolia-rpc.publicnode.com",
      chainId: 11155111,
      accounts: [process.env.DEPLOYER_PRIVATE_KEY || ""],
    },
  },
};

export default config; 