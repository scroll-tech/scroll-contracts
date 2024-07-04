/* eslint-disable node/no-unpublished-import */
/* eslint-disable node/no-missing-import */
import { HardhatEthersSigner } from "@nomicfoundation/hardhat-ethers/signers";
import { expect } from "chai";
import { ethers } from "hardhat";

import { L1MessageQueue, L2GasPriceOracle } from "../typechain";
import { MaxUint256, ZeroAddress, concat, encodeRlp, hexlify, keccak256, randomBytes, toBeHex } from "ethers";

describe("L1MessageQueue", async () => {
  let deployer: HardhatEthersSigner;
  let scrollChain: HardhatEthersSigner;
  let messenger: HardhatEthersSigner;
  let gateway: HardhatEthersSigner;

  let oracle: L2GasPriceOracle;
  let queue: L1MessageQueue;

  const deployProxy = async (name: string, admin: string, args: any[]): Promise<string> => {
    const TransparentUpgradeableProxy = await ethers.getContractFactory("TransparentUpgradeableProxy", deployer);
    const Factory = await ethers.getContractFactory(name, deployer);
    const impl = args.length > 0 ? await Factory.deploy(...args) : await Factory.deploy();
    const proxy = await TransparentUpgradeableProxy.deploy(impl.getAddress(), admin, "0x");
    return proxy.getAddress();
  };

  beforeEach(async () => {
    [deployer, scrollChain, messenger, gateway] = await ethers.getSigners();

    const ProxyAdmin = await ethers.getContractFactory("ProxyAdmin", deployer);
    const admin = await ProxyAdmin.deploy();

    queue = await ethers.getContractAt(
      "L1MessageQueue",
      await deployProxy("L1MessageQueue", await admin.getAddress(), [
        messenger.address,
        scrollChain.address,
        gateway.address,
      ]),
      deployer
    );

    oracle = await ethers.getContractAt(
      "L2GasPriceOracle",
      await deployProxy("L2GasPriceOracle", await admin.getAddress(), []),
      deployer
    );

    await oracle.initialize(21000, 50000, 8, 16);
    await queue.initialize(messenger.address, scrollChain.address, ZeroAddress, oracle.getAddress(), 10000000);
  });

  // other functions are tested in `src/test/L1MessageQueue.t.sol`
  context("#computeTransactionHash", async () => {
    it("should succeed", async () => {
      const sender = "0xb2a70fab1a45b1b9be443b6567849a1702bc1232";
      const target = "0xcb18150e4efefb6786130e289a5f61a82a5b86d7";
      const transactionType = "0x7E";

      for (const nonce of [0n, 1n, 127n, 128n, 22334455n, MaxUint256]) {
        for (const value of [0n, 1n, 127n, 128n, 22334455n, MaxUint256]) {
          for (const gasLimit of [0n, 1n, 127n, 128n, 22334455n, MaxUint256]) {
            for (const dataLen of [0, 1, 2, 3, 4, 55, 56, 100]) {
              const tests = [randomBytes(dataLen)];
              if (dataLen === 1) {
                for (const byte of [0, 1, 127, 128]) {
                  tests.push(Uint8Array.from([byte]));
                }
              }
              for (const data of tests) {
                const transactionPayload = encodeRlp([
                  nonce === 0n ? "0x" : toBeHex(nonce),
                  gasLimit === 0n ? "0x" : toBeHex(gasLimit),
                  target,
                  value === 0n ? "0x" : toBeHex(value),
                  data,
                  sender,
                ]);
                const payload = concat([transactionType, transactionPayload]);
                const expectedHash = keccak256(payload);
                const computedHash = await queue.computeTransactionHash(sender, nonce, value, target, gasLimit, data);
                if (computedHash !== expectedHash) {
                  console.log(hexlify(transactionPayload));
                  console.log(nonce, gasLimit, target, value, data, sender);
                }
                expect(expectedHash).to.eq(computedHash);
              }
            }
          }
        }
      }
    });
  });
});
