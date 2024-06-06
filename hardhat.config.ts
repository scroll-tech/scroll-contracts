import * as dotenv from "dotenv";

import { HardhatUserConfig, subtask } from "hardhat/config";
import * as toml from "toml";
import "@nomicfoundation/hardhat-verify";
import "@nomicfoundation/hardhat-ethers";
import "@nomicfoundation/hardhat-chai-matchers";
import "@typechain/hardhat";
import "hardhat-gas-reporter";
import "solidity-coverage";
import { readFileSync } from "fs";
import { TASK_COMPILE_SOLIDITY_GET_SOURCE_PATHS } from "hardhat/builtin-tasks/task-names";

dotenv.config();

const L1_DEPLOYER_PRIVATE_KEY = process.env.L1_DEPLOYER_PRIVATE_KEY || "1".repeat(64);
const L2_DEPLOYER_PRIVATE_KEY = process.env.L2_DEPLOYER_PRIVATE_KEY || "1".repeat(64);

const SOLC_DEFAULT = "0.8.24";

// try use forge config
let foundry: any;
try {
  foundry = toml.parse(readFileSync("./foundry.toml").toString());
  foundry.default.solc = foundry.default["solc-version"] ? foundry.default["solc-version"] : SOLC_DEFAULT;
} catch (error) {
  foundry = {
    default: {
      solc: SOLC_DEFAULT,
    },
  };
}

// prune forge style tests from hardhat paths
subtask(TASK_COMPILE_SOLIDITY_GET_SOURCE_PATHS).setAction(async (_, __, runSuper) => {
  const paths = await runSuper();
  return paths.filter((p: string) => !p.endsWith(".t.sol")).filter((p: string) => !p.includes("test/mocks"));
});

const config: HardhatUserConfig = {
  solidity: {
    version: foundry.default?.solc_version || SOLC_DEFAULT,
    settings: {
      optimizer: {
        enabled: foundry.default?.optimizer || true,
        runs: foundry.default?.optimizer_runs || 200,
      },
      evmVersion: "cancun",
    },
  },
  networks: {
    ethereum: {
      url: "https://1rpc.io/eth",
      accounts: [L1_DEPLOYER_PRIVATE_KEY],
    },
    sepolia: {
      url: "https://1rpc.io/sepolia",
      accounts: [L1_DEPLOYER_PRIVATE_KEY],
    },
    scroll: {
      url: "https://rpc.scroll.io",
      accounts: [L2_DEPLOYER_PRIVATE_KEY],
    },
    scroll_sepolia: {
      url: "https://sepolia-rpc.scroll.io",
      accounts: [L2_DEPLOYER_PRIVATE_KEY],
    },
  },
  paths: {
    artifacts: "./artifacts-hardhat",
    cache: "./cache-hardhat",
    sources: "./src",
    tests: "./hardhat-test",
  },
  typechain: {
    outDir: "./typechain",
    target: "ethers-v6",
  },
  gasReporter: {
    enabled: process.env.REPORT_GAS !== undefined,
    excludeContracts: ["src/test"],
    currency: "USD",
  },
  etherscan: {
    apiKey: {
      mainnet: process.env.ETHERSCAN_API_KEY || "",
      sepolia: process.env.ETHERSCAN_API_KEY || "",
      scroll: process.env.SCROLLSCAN_API_KEY || "",
      scroll_sepolia: process.env.SCROLLSCAN_API_KEY || "",
    },
    customChains: [
      {
        network: "scroll",
        chainId: 534352,
        urls: {
          apiURL: "https://api.scrollscan.com/api",
          browserURL: "https://www.scrollscan.com/",
        },
      },
      {
        network: "scroll_sepolia",
        chainId: 534351,
        urls: {
          apiURL: "https://api-sepolia.scrollscan.com/api",
          browserURL: "https://sepolia.scrollscan.com/",
        },
      },
    ],
  },
  mocha: {
    timeout: 10000000,
  },
};

export default config;
