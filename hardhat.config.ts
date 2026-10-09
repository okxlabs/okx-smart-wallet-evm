import { HardhatUserConfig } from "hardhat/config";
import { execFileSync } from "node:child_process";
import "@nomicfoundation/hardhat-toolbox";
import "@nomicfoundation/hardhat-foundry";
import "dotenv/config";

interface FoundryCompilerConfig {
  solc: string;
  evm_version: string;
  optimizer: boolean;
  optimizer_runs: number;
  optimizer_details: Record<string, unknown> | null;
  via_ir: boolean;
  bytecode_hash: string;
  cbor_metadata: boolean;
  use_literal_content: boolean;
}

// Foundry is the release build source of truth. Resolve its active profile
// instead of maintaining a second set of compiler settings here.
const foundry: FoundryCompilerConfig = JSON.parse(
  execFileSync("forge", ["config", "--json"], {
    cwd: __dirname,
    encoding: "utf8",
  }),
);

const config: HardhatUserConfig = {
  solidity: {
    version: foundry.solc,
    settings: {
      evmVersion: foundry.evm_version,
      viaIR: foundry.via_ir,
      optimizer: {
        enabled: foundry.optimizer,
        runs: foundry.optimizer_runs,
        details: foundry.optimizer_details ?? undefined,
      },
      metadata: {
        bytecodeHash: foundry.bytecode_hash,
        appendCBOR: foundry.cbor_metadata,
        useLiteralContent: foundry.use_literal_content,
      },
    },
  },
  paths: {
    sources: "./src",
    cache: "./cache",
    artifacts: "./artifacts",
  },
  networks: {
    hardhat: {
      chainId: 31337,
    },
    eth: {
      url: "https://eth.drpc.org",
      chainId: 1,
      accounts: [process.env.DEPLOYER_PRIVATE_KEY || ""],
    },
    xlayer: {
      url: "https://xlayerrpc.okx.com/",
      chainId: 196,
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
