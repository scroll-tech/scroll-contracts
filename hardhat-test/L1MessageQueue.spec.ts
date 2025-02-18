/* eslint-disable node/no-unpublished-import */
/* eslint-disable node/no-missing-import */
import { expect } from "chai";
import { ethers } from "hardhat";

import { L1MessageQueueV1, L1MessageQueueV2 } from "../typechain";
import { MaxUint256, concat, encodeRlp, hexlify, keccak256, randomBytes, toBeHex } from "ethers";

describe("L1MessageQueue", async () => {
  let queueV1: L1MessageQueueV1;
  let queueV2: L1MessageQueueV2;

  beforeEach(async () => {
    const [deployer, scrollChain, messenger, gateway, system] = await ethers.getSigners();

    const L1MessageQueueV1 = await ethers.getContractFactory("L1MessageQueueV1", deployer);
    const L1MessageQueueV2 = await ethers.getContractFactory("L1MessageQueueV2", deployer);
    queueV1 = await L1MessageQueueV1.deploy(messenger.address, scrollChain.address, gateway.address);
    queueV2 = await L1MessageQueueV2.deploy(
      messenger.address,
      scrollChain.address,
      gateway.address,
      queueV1.getAddress(),
      system.address
    );
  });

  // other functions are tested in `src/test/L1MessageQueueV1.t.sol` and `src/test/L1MessageQueueV2.t.sol`
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
                const computedHashV1 = await queueV1.computeTransactionHash(
                  sender,
                  nonce,
                  value,
                  target,
                  gasLimit,
                  data
                );
                const computedHashV2 = await queueV2.computeTransactionHash(
                  sender,
                  nonce,
                  value,
                  target,
                  gasLimit,
                  data
                );
                if (computedHashV1 !== expectedHash || computedHashV2 !== expectedHash) {
                  console.log(hexlify(transactionPayload));
                  console.log(nonce, gasLimit, target, value, data, sender);
                }
                expect(expectedHash).to.eq(computedHashV1);
                expect(expectedHash).to.eq(computedHashV2);
              }
            }
          }
        }
      }
    });
  });
});
