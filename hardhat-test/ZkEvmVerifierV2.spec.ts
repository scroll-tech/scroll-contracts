/* eslint-disable node/no-unpublished-import */
/* eslint-disable node/no-missing-import */
import { HardhatEthersSigner } from "@nomicfoundation/hardhat-ethers/signers";
import { expect } from "chai";
import { hexlify } from "ethers";
import fs from "fs";
import { ethers } from "hardhat";

import { ScrollChainMockBlob, ZkEvmVerifierV2 } from "../typechain";

describe("ZkEvmVerifierV2", async () => {
  let deployer: HardhatEthersSigner;

  let zkEvmVerifier: ZkEvmVerifierV2;
  let chain: ScrollChainMockBlob;

  const genPublicInputs = (instances: Buffer): Uint8Array => {
    // build public inputs
    const publicInputs = new Uint8Array(172);
    publicInputs.fill(0);
    // layer2ChainId, last 8 bytes of instances[0x120:0x140]
    for (let i = 0; i < 8; ++i) {
      publicInputs[i] = instances[0x140 - (8 - i)];
    }
    // numBatches, last 4 bytes of instances[0x180:0x1a0] + 1
    let numBatches = Number(hexlify(instances.subarray(0x180, 0x1a0))) + 1;
    for (let i = 3; i >= 0; --i) {
      publicInputs[8 + i] = numBatches % 256;
      numBatches = Math.floor(numBatches / 256);
    }
    // prevStateRoot, concat(last 16 bytes of instances[0x20:0x40], last 16 bytes of instances[0x40:0x60])
    for (let i = 0; i < 16; ++i) {
      publicInputs[12 + i] = instances[0x40 - (16 - i)];
      publicInputs[12 + 16 + i] = instances[0x60 - (16 - i)];
    }
    // prevBatchHash, concat(last 16 bytes of instances[0x60:0x80], last 16 bytes of instances[0x80:0xa0])
    for (let i = 0; i < 16; ++i) {
      publicInputs[44 + i] = instances[0x80 - (16 - i)];
      publicInputs[44 + 16 + i] = instances[0xa0 - (16 - i)];
    }
    // postStateRoot, concat(last 16 bytes of instances[0xa0:0xc0], last 16 bytes of instances[0xc0:0xe0])
    for (let i = 0; i < 16; ++i) {
      publicInputs[76 + i] = instances[0xc0 - (16 - i)];
      publicInputs[76 + 16 + i] = instances[0xe0 - (16 - i)];
    }
    // batchHash, concat(last 16 bytes of instances[0xe0:0x100], last 16 bytes of instances[0x100:0x120])
    for (let i = 0; i < 16; ++i) {
      publicInputs[108 + i] = instances[0x100 - (16 - i)];
      publicInputs[108 + 16 + i] = instances[0x120 - (16 - i)];
    }
    // withdrawRoot, concat(last 16 bytes of instances[0x140:0x160], last 16 bytes of instances[0x160:0x180])
    for (let i = 0; i < 16; ++i) {
      publicInputs[140 + i] = instances[0x160 - (16 - i)];
      publicInputs[140 + 16 + i] = instances[0x180 - (16 - i)];
    }
    return publicInputs;
  };

  const doTest = async (version: string) => {
    context("test with version:" + version, async () => {
      let instances: Buffer;
      let publicInputs: Uint8Array;

      beforeEach(async () => {
        [deployer] = await ethers.getSigners();

        const bytecode = hexlify(
          fs.readFileSync(`./src/libraries/verifier/plonk-verifier/plonk_verifier_${version}.bin`)
        );
        const tx = await deployer.sendTransaction({ data: bytecode });
        const receipt = await tx.wait();

        instances = fs.readFileSync(`./hardhat-test/testdata/plonk-verifier/${version}_pi.data`);
        publicInputs = genPublicInputs(instances);
        const verifierDigest = hexlify(instances.subarray(0x0, 0x20));
        const layer2ChainId = hexlify(publicInputs.subarray(0, 8));

        console.log("verifierDigest:", verifierDigest, "layer2ChainId:", BigInt(layer2ChainId));
        const ZkEvmVerifierV2 = await ethers.getContractFactory("ZkEvmVerifierV2", deployer);
        zkEvmVerifier = await ZkEvmVerifierV2.deploy(receipt!.contractAddress!, verifierDigest);

        const MultipleVersionRollupVerifier = await ethers.getContractFactory(
          "MultipleVersionRollupVerifier",
          deployer
        );
        const verifier = await MultipleVersionRollupVerifier.deploy([3], [await zkEvmVerifier.getAddress()]);

        const EmptyContract = await ethers.getContractFactory("EmptyContract", deployer);
        const empty = await EmptyContract.deploy();

        const ProxyAdmin = await ethers.getContractFactory("ProxyAdmin", deployer);
        const admin = await ProxyAdmin.deploy();

        const TransparentUpgradeableProxy = await ethers.getContractFactory("TransparentUpgradeableProxy", deployer);
        const chainProxy = await TransparentUpgradeableProxy.deploy(empty.getAddress(), admin.getAddress(), "0x");

        const ScrollChainMockBlob = await ethers.getContractFactory("ScrollChainMockBlob", deployer);
        const chainImpl = await ScrollChainMockBlob.deploy(layer2ChainId, deployer.address, verifier.getAddress());
        await admin.upgrade(chainProxy.getAddress(), chainImpl.getAddress());

        chain = await ethers.getContractAt("ScrollChainMockBlob", await chainProxy.getAddress(), deployer);
        await chain.initialize(deployer.address, deployer.address, 100);
        await chain.addProver(deployer.address);
      });

      it("should succeed when direct call ZkEvmVerifierV2", async () => {
        const proof = hexlify(fs.readFileSync(`./hardhat-test/testdata/plonk-verifier/${version}_proof.data`));

        // verify ok
        const unsignedTx = await zkEvmVerifier.verify.populateTransaction(proof, publicInputs);
        const tx = await deployer.sendTransaction(unsignedTx);
        const receipt = await tx.wait();
        console.log("Gas Usage:", receipt?.gasUsed);

        // verify failed
        await expect(zkEvmVerifier.verify(proof, publicInputs.reverse())).to.reverted;
      });

      it("should succeed when call through ScrollChain", async () => {
        const proof = hexlify(fs.readFileSync(`./hardhat-test/testdata/plonk-verifier/${version}_proof.data`));

        const lastFinalizedBatchIndex = 1;
        const numBatches = Number(BigInt(hexlify(publicInputs.subarray(8, 12))));
        const batchIndex = lastFinalizedBatchIndex + numBatches;
        const prevStateRoot = hexlify(publicInputs.subarray(12, 44));
        const prevBatchHash = hexlify(publicInputs.subarray(44, 76));
        const postStateRoot = hexlify(publicInputs.subarray(76, 108));
        const batchHash = hexlify(publicInputs.subarray(108, 140));
        const withdrawRoot = hexlify(publicInputs.subarray(140, 172));

        await chain.setOverrideBatchHashCheck(true);
        await chain.setLastFinalizedBatchIndex(lastFinalizedBatchIndex);
        await chain.setFinalizedStateRoots(lastFinalizedBatchIndex, prevStateRoot);
        await chain.setCommittedBatches(lastFinalizedBatchIndex, prevBatchHash);
        await chain.setCommittedBatches(batchIndex, batchHash);

        const header = new Uint8Array(193);
        header[0] = 3; // version 3
        let value = batchIndex;
        for (let i = 8; i >= 1; --i) {
          header[i] = value % 256;
          value = Math.floor(value / 256);
        }
        // verify ok
        const tx = await chain.finalizeBundleWithProof(header, postStateRoot, withdrawRoot, proof);
        const receipt = await tx.wait();
        console.log("Gas Usage:", receipt?.gasUsed);
      });
    });
  };

  for (const version of ["v0.12.0-rc.2", "v0.12.0-rc.3"]) {
    await doTest(version);
  }
});
