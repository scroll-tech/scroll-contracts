/* eslint-disable node/no-unpublished-import */
/* eslint-disable node/no-missing-import */
import { HardhatEthersSigner } from "@nomicfoundation/hardhat-ethers/signers";
import { expect } from "chai";
import { hexlify } from "ethers";
import fs from "fs";
import { ethers } from "hardhat";

import { ZkEvmVerifierV1 } from "../typechain";

describe("ZkEvmVerifierV1", async () => {
  let deployer: HardhatEthersSigner;

  let zkEvmVerifier: ZkEvmVerifierV1;

  beforeEach(async () => {
    [deployer] = await ethers.getSigners();

    const bytecode = hexlify(fs.readFileSync("./src/libraries/verifier/plonk-verifier/plonk_verifier_v0.9.8.bin"));
    const tx = await deployer.sendTransaction({ data: bytecode });
    const receipt = await tx.wait();

    const ZkEvmVerifierV1 = await ethers.getContractFactory("ZkEvmVerifierV1", deployer);
    zkEvmVerifier = await ZkEvmVerifierV1.deploy(receipt!.contractAddress!);
  });

  it("should succeed", async () => {
    const proof = hexlify(fs.readFileSync("./hardhat-test/testdata/plonk-verifier/v0.9.8_proof.data"));
    const instances = fs.readFileSync("./hardhat-test/testdata/plonk-verifier/v0.9.8_pi.data");

    const publicInputHash = new Uint8Array(32);
    for (let i = 0; i < 32; i++) {
      publicInputHash[i] = instances[i * 32 + 31];
    }

    expect(hexlify(publicInputHash)).to.eq("0x31b430667bc9e8a8b7eda5e5c76f2250c64023f5f8e0689ac9f4e53f5362da66");

    // verify ok
    await zkEvmVerifier.verify(proof, publicInputHash);
    console.log("Gas Usage:", (await zkEvmVerifier.verify.estimateGas(proof, publicInputHash)).toString());

    // verify failed
    await expect(zkEvmVerifier.verify(proof, publicInputHash.reverse())).to.reverted;
  });
});
