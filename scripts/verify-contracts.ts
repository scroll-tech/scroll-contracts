import { config } from "dotenv";
import axios from "axios";
import * as fs from "fs";
import * as path from "path";
import qs from "qs";

config();

interface ContractToVerify {
  name: string;
  address: string;
  sourceFile: string;
}

async function verifyContract(contract: ContractToVerify): Promise<void> {
  const sourceCode = fs.readFileSync(path.join(__dirname, "..", "src", contract.sourceFile), "utf8");
  const apiUrl = "https://blockscout-api.dogeos.doge.xyz/api"; // Confirmed base endpoint

  console.log(`Verifying ${contract.name} at ${contract.address}...`);

  // Include module, action, and codeformat in the body
  const data = qs.stringify({
    module: "contract",
    action: "verifysourcecode",
    contractaddress: contract.address,
    contractname: contract.name,
    compilerversion: "v0.8.24",
    optimizationUsed: "1", // "1" for enabled, "0" for disabled
    optimizationRuns: "200", // Number of runs from Hardhat config
    sourceCode,
    codeformat: "solidity-single-file", // Added required field
  });

  try {
    const response = await axios.post(apiUrl, data, {
      headers: {
        "Content-Type": "application/x-www-form-urlencoded",
      },
    });

    console.log("Response from API:", JSON.stringify(response.data, null, 2));
    console.log(`Successfully verified ${contract.name}`);
    console.log(`View at: https://blockscout.dogeos.doge.xyz/address/${contract.address}/contracts`);
  } catch (error: any) {
    console.error("Request URL:", apiUrl);
    console.error("Request Data:", data);
    if (axios.isAxiosError(error) && error.response) {
      console.error(`Status: ${error.response.status}`);
      console.error(`Response: ${JSON.stringify(error.response.data)}`);
      throw new Error(`Failed to verify ${contract.name}: ${JSON.stringify(error.response.data)}`);
    } else {
      throw new Error(`Failed to verify ${contract.name}: ${error.message}`);
    }
  }
}

async function main() {
  const contracts: ContractToVerify[] = [
    {
      name: "L2MessageQueue",
      address: "0x5300000000000000000000000000000000000000",
      sourceFile: "L2/predeploys/L2MessageQueue.sol",
    },
    {
      name: "L2GasPriceOracle",
      address: "0x5300000000000000000000000000000000000002",
      sourceFile: "L2/predeploys/L1GasPriceOracle.sol",
    },
    {
      name: "L2Whitelist",
      address: "0x5300000000000000000000000000000000000003",
      sourceFile: "L2/predeploys/Whitelist.sol",
    },
    {
      name: "L2WETH",
      address: "0x5300000000000000000000000000000000000004",
      sourceFile: "L2/predeploys/WrappedEther.sol",
    },
    {
      name: "L2TxFeeVault",
      address: "0x5300000000000000000000000000000000000005",
      sourceFile: "L2/predeploys/L2TxFeeVault.sol",
    },
    {
      name: "L2ScrollMessenger",
      address: "0x1e901FF9D4CC5963094AdAD3339764f742276150",
      sourceFile: "L2/L2ScrollMessenger.sol",
    },
    {
      name: "L2ETHGateway",
      address: "0x90B038e179975CEb2fAf53167C2D9b3d50348e92",
      sourceFile: "L2/gateways/L2ETHGateway.sol",
    },
    {
      name: "L2WETHGateway",
      address: "0xC607215232eDD9fce217ABd375Be1C43690B04D8",
      sourceFile: "L2/gateways/L2WETHGateway.sol",
    },
    {
      name: "L2StandardERC20Gateway",
      address: "0x71F58c2A6ECC556dA0F690ff938cC7a945d9eEc4",
      sourceFile: "L2/gateways/L2StandardERC20Gateway.sol",
    },
    {
      name: "L2CustomERC20Gateway",
      address: "0x2aef9Ed38d78f84C543c26F8442Ba98a08f9b265",
      sourceFile: "L2/gateways/L2CustomERC20Gateway.sol",
    },
    {
      name: "L2ERC721Gateway",
      address: "0xAC4267F5e10D246783DAb7C73813e76a3A716415",
      sourceFile: "L2/gateways/L2ERC721Gateway.sol",
    },
    {
      name: "L2ERC1155Gateway",
      address: "0x480C8f9e6dfD9Eef4420B01B5ff1272e00D73E8f",
      sourceFile: "L2/gateways/L2ERC1155Gateway.sol",
    },
  ];

  for (const contract of contracts) {
    await verifyContract(contract);
  }
}

main().catch((error) => {
  console.error("Verification failed:", error);
});
