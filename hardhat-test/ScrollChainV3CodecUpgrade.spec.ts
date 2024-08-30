/* eslint-disable node/no-missing-import */
/* eslint-disable node/no-unpublished-import */
import * as fs from "fs";
import { expect } from "chai";
import { ZeroAddress, toQuantity } from "ethers";
import { ethers, network } from "hardhat";

const Deployer = "0x0A47CeC6657570831AE93db36367656e5597C310";
const ScrollOwner = "0x798576400F7D662961BA15C6b3F3d813447a26a6";
const MESSENGER = "0x6774Bcbd5ceCeF1336b5300fb5186a12DDD8b367";
const MESSAGE_QUEUE = "0x0d7E906BD9cAFa154b048cFa766Cc1E54E39AF9B";
const SCROLL_CHAIN = "0xa13BAF47339d63B743e7Da8741db5456DAc1E556";
const COMMITTER = "0xcF2898225ED05Be911D3709d9417e86E0b4Cfc8f";
const FINALIZER = "0x356483dC32B004f32Ea0Ce58F7F88879886e9074";

// random real mainnet batches to test compatibility of committing and finalizing
// to run this tests, you need to config `MAINNET_FORK_RPC` in `.env` file and change `it.skip` to `it`.
describe("ScrollChainV3CodecUpgrade.spec", async () => {
  const mockETHBalance = async (account: string, balance: bigint) => {
    await network.provider.send("hardhat_setBalance", [account, toQuantity(balance)]);
    expect(await ethers.provider.getBalance(account)).to.eq(balance);
  };

  const genCommit = async (batch: { index: number; batch_hash: string; commit_tx: string }) => {
    it.skip("should succeed to commit batch: " + batch.index, async () => {
      const provider = new ethers.JsonRpcProvider("https://rpc.ankr.com/eth");
      const originalTx = await provider.getTransaction(batch.commit_tx);
      const originalReceipt = await provider.getTransactionReceipt(batch.commit_tx);

      await network.provider.request({
        method: "hardhat_reset",
        params: [
          {
            forking: {
              jsonRpcUrl: process.env.MAINNET_FORK_RPC!,
              blockNumber: originalReceipt!.blockNumber - 1,
            },
          },
        ],
      });
      await network.provider.request({
        method: "hardhat_impersonateAccount",
        params: [Deployer],
      });
      await network.provider.request({
        method: "hardhat_impersonateAccount",
        params: [ScrollOwner],
      });
      await network.provider.request({
        method: "hardhat_impersonateAccount",
        params: [COMMITTER],
      });

      const deployer = await ethers.getSigner(Deployer);
      const owner = await ethers.getSigner(ScrollOwner);
      const committer = await ethers.getSigner(COMMITTER);
      await mockETHBalance(committer.address, ethers.parseEther("100"));
      await mockETHBalance(deployer.address, ethers.parseEther("100"));
      await mockETHBalance(owner.address, ethers.parseEther("100"));

      const ScrollChainMockBlob = await ethers.getContractFactory("ScrollChainMockBlob", deployer);
      const L1MessageQueueWithGasPriceOracle = await ethers.getContractFactory(
        "L1MessageQueueWithGasPriceOracle",
        deployer
      );
      const MultipleVersionRollupVerifier = await ethers.getContractFactory("MultipleVersionRollupVerifier", deployer);

      const verifier = await MultipleVersionRollupVerifier.deploy(
        [0, 1, 2],
        [
          "0x585DfaD7bF4099E011D185E266907A8ab60DAD2D",
          "0x4b289E4A5331bAFBc6cCb2F10C39B8EDceCDb247",
          "0x63FB51C55d9605a75F8872C80De260a00fACfaA2",
        ]
      );
      const queueImpl = await L1MessageQueueWithGasPriceOracle.deploy(
        MESSENGER,
        SCROLL_CHAIN,
        "0x72CAcBcfDe2d1e19122F8A36a4d6676cd39d7A5d"
      );
      const chainImpl = await ScrollChainMockBlob.deploy(534352, MESSAGE_QUEUE, verifier.getAddress());

      const admin = await ethers.getContractAt("ProxyAdmin", "0xEB803eb3F501998126bf37bB823646Ed3D59d072", deployer);
      await admin.connect(owner).upgrade(SCROLL_CHAIN, chainImpl.getAddress());
      await admin.connect(owner).upgrade(MESSAGE_QUEUE, queueImpl.getAddress());

      const queue = await ethers.getContractAt("L1MessageQueueWithGasPriceOracle", MESSAGE_QUEUE, deployer);
      if ((await queue.whitelistChecker()) === ZeroAddress) {
        await queue.initializeV2();
      }
      await queue.initializeV3();
      const chain = await ethers.getContractAt("ScrollChainMockBlob", SCROLL_CHAIN, deployer);

      if (originalTx!.blobVersionedHashes) {
        await chain.setBlobVersionedHash(originalTx!.blobVersionedHashes[0]);
      }

      const tx = await committer.sendTransaction({
        to: SCROLL_CHAIN,
        data: originalTx!.data,
      });
      await expect(tx).emit(chain, "CommitBatch").withArgs(batch.index, batch.batch_hash);
      expect(await chain.committedBatches(batch.index)).to.eq(batch.batch_hash);
      const r = await tx.wait();
      console.log(
        "Fork At Block:",
        originalReceipt!.blockNumber - 1,
        `OriginalGasUsed[${originalReceipt?.gasUsed}]`,
        `NowGasUsed[${r?.gasUsed}]`
      );
    });
  };

  const genFinalize = async (batch: { index: number; batch_hash: string; finalize_tx: string }) => {
    it.skip("should succeed to finalize batch: " + batch.index, async () => {
      const provider = new ethers.JsonRpcProvider("https://rpc.ankr.com/eth");
      const originalTx = await provider.getTransaction(batch.finalize_tx);
      const originalReceipt = await provider.getTransactionReceipt(batch.finalize_tx);

      await network.provider.request({
        method: "hardhat_reset",
        params: [
          {
            forking: {
              jsonRpcUrl: process.env.MAINNET_FORK_RPC!,
              blockNumber: originalReceipt!.blockNumber - 1,
            },
          },
        ],
      });
      await network.provider.request({
        method: "hardhat_impersonateAccount",
        params: [Deployer],
      });
      await network.provider.request({
        method: "hardhat_impersonateAccount",
        params: [ScrollOwner],
      });
      await network.provider.request({
        method: "hardhat_impersonateAccount",
        params: [FINALIZER],
      });

      const deployer = await ethers.getSigner(Deployer);
      const owner = await ethers.getSigner(ScrollOwner);
      const finalizer = await ethers.getSigner(FINALIZER);
      await mockETHBalance(finalizer.address, ethers.parseEther("100"));
      await mockETHBalance(deployer.address, ethers.parseEther("100"));
      await mockETHBalance(owner.address, ethers.parseEther("100"));

      const ScrollChainMockBlob = await ethers.getContractFactory("ScrollChainMockBlob", deployer);
      const L1MessageQueueWithGasPriceOracle = await ethers.getContractFactory(
        "L1MessageQueueWithGasPriceOracle",
        deployer
      );
      const MultipleVersionRollupVerifier = await ethers.getContractFactory("MultipleVersionRollupVerifier", deployer);

      const verifier = await MultipleVersionRollupVerifier.deploy(
        [0, 1, 2],
        [
          "0x585DfaD7bF4099E011D185E266907A8ab60DAD2D",
          "0x4b289E4A5331bAFBc6cCb2F10C39B8EDceCDb247",
          "0x63FB51C55d9605a75F8872C80De260a00fACfaA2",
        ]
      );
      const queueImpl = await L1MessageQueueWithGasPriceOracle.deploy(
        MESSENGER,
        SCROLL_CHAIN,
        "0x72CAcBcfDe2d1e19122F8A36a4d6676cd39d7A5d"
      );
      const chainImpl = await ScrollChainMockBlob.deploy(534352, MESSAGE_QUEUE, verifier.getAddress());

      const admin = await ethers.getContractAt("ProxyAdmin", "0xEB803eb3F501998126bf37bB823646Ed3D59d072", deployer);
      await admin.connect(owner).upgrade(SCROLL_CHAIN, chainImpl.getAddress());
      await admin.connect(owner).upgrade(MESSAGE_QUEUE, queueImpl.getAddress());

      const queue = await ethers.getContractAt("L1MessageQueueWithGasPriceOracle", MESSAGE_QUEUE, deployer);
      if ((await queue.whitelistChecker()) === ZeroAddress) {
        await queue.initializeV2();
      }
      await queue.initializeV3();
      const chain = await ethers.getContractAt("ScrollChainMockBlob", SCROLL_CHAIN, deployer);

      if (originalTx!.blobVersionedHashes) {
        await chain.setBlobVersionedHash(originalTx!.blobVersionedHashes[0]);
      }

      expect(await chain.lastFinalizedBatchIndex()).to.eq(batch.index - 1);
      const tx = await finalizer.sendTransaction({
        to: SCROLL_CHAIN,
        data: originalTx!.data,
      });
      await expect(tx).emit(chain, "FinalizeBatch");
      expect(await chain.lastFinalizedBatchIndex()).to.eq(batch.index);
      const r = await tx.wait();
      console.log(
        "Fork At Block:",
        originalReceipt!.blockNumber - 1,
        `OriginalGasUsed[${originalReceipt?.gasUsed}]`,
        `NowGasUsed[${r?.gasUsed}]`
      );
    });
  };

  context("commit batches", async () => {
    const batches = fs.readFileSync("./hardhat-test/testdata/batch.commit.txt").toString().split("\n");
    for (const batchStr of batches) {
      const batch: {
        index: number;
        batch_hash: string;
        commit_tx: string;
      } = JSON.parse(batchStr);
      genCommit(batch);
    }
  });

  context("finalize batches", async () => {
    const batches = fs.readFileSync("./hardhat-test/testdata/batch.finalize.txt").toString().split("\n");
    for (const batchStr of batches) {
      const batch: {
        index: number;
        batch_hash: string;
        finalize_tx: string;
      } = JSON.parse(batchStr);
      genFinalize(batch);
    }
  });
});
