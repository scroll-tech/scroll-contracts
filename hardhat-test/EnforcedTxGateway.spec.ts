/* eslint-disable node/no-unpublished-import */
/* eslint-disable node/no-missing-import */
import { HardhatEthersSigner, SignerWithAddress } from "@nomicfoundation/hardhat-ethers/signers";
import { expect } from "chai";
import { BigNumberish, BytesLike, MaxUint256, ZeroAddress, getAddress, getBytes, toBeHex } from "ethers";
import { ethers, network } from "hardhat";

import { EnforcedTxGateway, L1MessageQueueV2, MockCaller, SystemConfig } from "../typechain";

describe("EnforcedTxGateway.spec", async () => {
  let deployer: HardhatEthersSigner;
  let feeVault: HardhatEthersSigner;
  let signer: HardhatEthersSigner;

  let caller: MockCaller;
  let system: SystemConfig;
  let gateway: EnforcedTxGateway;
  let queue: L1MessageQueueV2;

  const deployProxy = async (name: string, admin: string, args: any[]): Promise<string> => {
    const TransparentUpgradeableProxy = await ethers.getContractFactory("TransparentUpgradeableProxy", deployer);
    const Factory = await ethers.getContractFactory(name, deployer);
    const impl = args.length > 0 ? await Factory.deploy(...args) : await Factory.deploy();
    const proxy = await TransparentUpgradeableProxy.deploy(impl.getAddress(), admin, "0x");
    return proxy.getAddress();
  };

  beforeEach(async () => {
    [deployer, feeVault, signer] = await ethers.getSigners();

    const ProxyAdmin = await ethers.getContractFactory("ProxyAdmin", deployer);
    const admin = await ProxyAdmin.deploy();

    gateway = await ethers.getContractAt(
      "EnforcedTxGateway",
      await deployProxy("EnforcedTxGateway", await admin.getAddress(), []),
      deployer
    );

    system = await ethers.getContractAt(
      "SystemConfig",
      await deployProxy("SystemConfig", await admin.getAddress(), []),
      deployer
    );

    const queueV1 = await ethers.getContractAt(
      "L1MessageQueueV1",
      await deployProxy("L1MessageQueueV1", await admin.getAddress(), [
        deployer.address,
        deployer.address,
        await gateway.getAddress(),
      ]),
      deployer
    );

    queue = await ethers.getContractAt(
      "L1MessageQueueV2",
      await deployProxy("L1MessageQueueV2", await admin.getAddress(), [
        deployer.address,
        deployer.address,
        await gateway.getAddress(),
        await queueV1.getAddress(),
        await system.getAddress(),
      ]),
      deployer
    );

    const MockCaller = await ethers.getContractFactory("MockCaller", deployer);
    caller = await MockCaller.deploy();

    await system.initialize(
      deployer.address,
      deployer.address,
      {
        maxGasLimit: 1000000,
        baseFeeOverhead: 10n ** 9n,
        baseFeeScalar: 10n ** 18n,
      },
      { maxDelayEnterEnforcedMode: 0, maxDelayMessageQueue: 0 }
    );
    await queue.initialize();
    await gateway.initialize(queue.getAddress(), feeVault.address);
  });

  context("auth", async () => {
    it("should initialize correctly", async () => {
      expect(await gateway.owner()).to.eq(deployer.address);
      expect(await gateway.messageQueue()).to.eq(await queue.getAddress());
      expect(await gateway.feeVault()).to.eq(feeVault.address);
      expect(await gateway.paused()).to.eq(false);
    });

    it("should revert, when initialize again", async () => {
      await expect(gateway.initialize(ZeroAddress, ZeroAddress)).to.revertedWith(
        "Initializable: contract is already initialized"
      );
    });

    context("#updateFeeVault", async () => {
      it("should revert, when non-owner call", async () => {
        await expect(gateway.connect(signer).updateFeeVault(ZeroAddress)).to.revertedWith(
          "Ownable: caller is not the owner"
        );
      });

      it("should succeed", async () => {
        expect(await gateway.feeVault()).to.eq(feeVault.address);
        await expect(gateway.updateFeeVault(deployer.address))
          .to.emit(gateway, "UpdateFeeVault")
          .withArgs(feeVault.address, deployer.address);
        expect(await gateway.feeVault()).to.eq(deployer.address);
      });
    });

    context("#setPause", async () => {
      it("should revert, when non-owner call", async () => {
        await expect(gateway.connect(signer).setPause(false)).to.revertedWith("Ownable: caller is not the owner");
      });

      it("should succeed", async () => {
        expect(await gateway.paused()).to.eq(false);
        await expect(gateway.setPause(true)).to.emit(gateway, "Paused").withArgs(deployer.address);
        expect(await gateway.paused()).to.eq(true);
        await expect(gateway.setPause(false)).to.emit(gateway, "Unpaused").withArgs(deployer.address);
        expect(await gateway.paused()).to.eq(false);
      });
    });
  });

  context("#sendTransaction, by EOA", async () => {
    it("should revert, when contract is paused", async () => {
      await gateway.setPause(true);
      await expect(
        gateway.connect(signer)["sendTransaction(address,uint256,uint256,bytes)"](signer.address, 0, 0, "0x")
      ).to.revertedWith("Pausable: paused");
    });

    it("should revert, when insufficient value for fee", async () => {
      const fee = await queue.estimateCrossDomainMessageFee(1000000);
      await network.provider.send("hardhat_setNextBlockBaseFeePerGas", ["0"]);
      await expect(
        gateway
          .connect(signer)
          ["sendTransaction(address,uint256,uint256,bytes)"](signer.address, 0, 1000000, "0x", { value: fee - 1n })
      ).to.revertedWith("Insufficient value for fee");
    });

    it("should revert, when failed to deduct the fee", async () => {
      await gateway.updateFeeVault(gateway.getAddress());
      const fee = await queue.estimateCrossDomainMessageFee(1000000);
      await network.provider.send("hardhat_setNextBlockBaseFeePerGas", ["0"]);
      await expect(
        gateway
          .connect(signer)
          ["sendTransaction(address,uint256,uint256,bytes)"](signer.address, 0, 1000000, "0x", { value: fee * 10n })
      ).to.revertedWith("Failed to deduct the fee");
    });

    it("should succeed, with refund", async () => {
      const fee = await queue.estimateCrossDomainMessageFee(1000000);
      const feeVaultBalanceBefore = await ethers.provider.getBalance(feeVault.address);
      const signerBalanceBefore = await ethers.provider.getBalance(signer.address);
      await network.provider.send("hardhat_setNextBlockBaseFeePerGas", ["0"]);
      const tx = await gateway
        .connect(signer)
        ["sendTransaction(address,uint256,uint256,bytes)"](deployer.address, 0, 1000000, "0x", { value: fee + 100n });
      await expect(tx)
        .to.emit(queue, "QueueTransaction")
        .withArgs(signer.address, deployer.address, 0, 0, 1000000, "0x");
      const receipt = await tx.wait();
      const feeVaultBalanceAfter = await ethers.provider.getBalance(feeVault.address);
      const signerBalanceAfter = await ethers.provider.getBalance(signer.address);
      expect(feeVaultBalanceAfter - feeVaultBalanceBefore).to.eq(fee);
      expect(signerBalanceBefore - signerBalanceAfter).to.eq(receipt!.gasUsed * receipt!.gasPrice + fee);
    });
  });

  context("#sendTransaction, by Contract", async () => {
    it("should revert, when contract is paused", async () => {
      await gateway.setPause(true);
      await expect(
        caller.callTarget(
          gateway.getAddress(),
          gateway.interface.encodeFunctionData("sendTransaction(address,uint256,uint256,bytes)", [
            signer.address,
            0,
            0,
            "0x",
          ])
        )
      ).to.revertedWith("Pausable: paused");
    });

    it("should revert, when insufficient value for fee", async () => {
      const fee = await queue.estimateCrossDomainMessageFee(1000000);
      await network.provider.send("hardhat_setNextBlockBaseFeePerGas", ["0"]);
      await expect(
        caller.callTarget(
          gateway.getAddress(),
          gateway.interface.encodeFunctionData("sendTransaction(address,uint256,uint256,bytes)", [
            signer.address,
            0,
            1000000,
            "0x",
          ]),
          { value: fee - 1n }
        )
      ).to.revertedWith("Insufficient value for fee");
    });

    it("should revert, when failed to deduct the fee", async () => {
      await gateway.updateFeeVault(gateway.getAddress());
      const fee = await queue.estimateCrossDomainMessageFee(1000000);
      await network.provider.send("hardhat_setNextBlockBaseFeePerGas", ["0"]);
      await expect(
        caller.callTarget(
          gateway.getAddress(),
          gateway.interface.encodeFunctionData("sendTransaction(address,uint256,uint256,bytes)", [
            signer.address,
            0,
            1000000,
            "0x",
          ]),
          { value: fee * 10n }
        )
      ).to.revertedWith("Failed to deduct the fee");
    });

    it("should succeed, with refund", async () => {
      const fee = await queue.estimateCrossDomainMessageFee(1000000);
      const callerBalanceBefore = await ethers.provider.getBalance(caller.getAddress());
      const feeVaultBalanceBefore = await ethers.provider.getBalance(feeVault.address);
      const signerBalanceBefore = await ethers.provider.getBalance(signer.address);
      await network.provider.send("hardhat_setNextBlockBaseFeePerGas", ["0"]);
      const sender = getAddress(
        "0x" +
          toBeHex(
            (BigInt(await caller.getAddress()) + BigInt("0x1111000000000000000000000000000000001111")) % 2n ** 160n
          )
            .slice(2)
            .padStart(40, "0")
      );
      const tx = await caller
        .connect(signer)
        .callTarget(
          gateway.getAddress(),
          gateway.interface.encodeFunctionData("sendTransaction(address,uint256,uint256,bytes)", [
            deployer.address,
            0,
            1000000,
            "0x",
          ]),
          { value: fee + 100n }
        );
      await expect(tx).to.emit(queue, "QueueTransaction").withArgs(sender, deployer.address, 0, 0, 1000000, "0x");
      const receipt = await tx.wait();
      const callerBalanceAfter = await ethers.provider.getBalance(caller.getAddress());
      const feeVaultBalanceAfter = await ethers.provider.getBalance(feeVault.address);
      const signerBalanceAfter = await ethers.provider.getBalance(signer.address);
      expect(callerBalanceAfter - callerBalanceBefore).to.eq(100n);
      expect(feeVaultBalanceAfter - feeVaultBalanceBefore).to.eq(fee);
      expect(signerBalanceBefore - signerBalanceAfter).to.eq(receipt!.gasUsed * receipt!.gasPrice + fee + 100n);
    });
  });

  context("#sendTransaction, with signatures", async () => {
    const getSignature = async (
      signer: SignerWithAddress,
      target: string,
      value: BigNumberish,
      gasLimit: BigNumberish,
      data: BytesLike
    ) => {
      const enforcedTx = {
        sender: signer.address,
        target,
        value,
        gasLimit,
        data: getBytes(data),
        nonce: await gateway.nonces(signer.address),
        deadline: MaxUint256,
      };

      const domain = {
        name: "EnforcedTxGateway",
        version: "1",
        chainId: (await ethers.provider.getNetwork()).chainId,
        verifyingContract: await gateway.getAddress(),
      };

      const types = {
        EnforcedTransaction: [
          {
            name: "sender",
            type: "address",
          },
          {
            name: "target",
            type: "address",
          },
          {
            name: "value",
            type: "uint256",
          },
          {
            name: "gasLimit",
            type: "uint256",
          },
          {
            name: "data",
            type: "bytes",
          },
          {
            name: "nonce",
            type: "uint256",
          },
          {
            name: "deadline",
            type: "uint256",
          },
        ],
      };

      const signature = await signer.signTypedData(domain, types, enforcedTx);
      return signature;
    };

    it("should revert, when contract is paused", async () => {
      await gateway.setPause(true);
      await expect(
        gateway
          .connect(deployer)
          ["sendTransaction(address,address,uint256,uint256,bytes,uint256,bytes,address)"](
            signer.address,
            signer.address,
            0,
            0,
            "0x",
            MaxUint256,
            "0x",
            ZeroAddress
          )
      ).to.revertedWith("Pausable: paused");
    });

    it("should revert, when signature expired", async () => {
      const timestamp = (await ethers.provider.getBlock("latest"))!.timestamp;
      await expect(
        gateway
          .connect(deployer)
          ["sendTransaction(address,address,uint256,uint256,bytes,uint256,bytes,address)"](
            signer.address,
            signer.address,
            0,
            0,
            "0x",
            timestamp - 1,
            "0x",
            ZeroAddress
          )
      ).to.revertedWith("signature expired");
    });

    it("should revert, when signature is wrong", async () => {
      const signature = await signer.signMessage("0x00");
      await expect(
        gateway
          .connect(deployer)
          ["sendTransaction(address,address,uint256,uint256,bytes,uint256,bytes,address)"](
            signer.address,
            signer.address,
            0,
            0,
            "0x",
            MaxUint256,
            signature,
            ZeroAddress
          )
      ).to.revertedWith("Incorrect signature");
    });

    it("should revert, when insufficient value for fee", async () => {
      const signature = await getSignature(signer, signer.address, 0, 1000000, "0x");
      const fee = await queue.estimateCrossDomainMessageFee(1000000);
      await network.provider.send("hardhat_setNextBlockBaseFeePerGas", ["0"]);
      await expect(
        gateway
          .connect(deployer)
          ["sendTransaction(address,address,uint256,uint256,bytes,uint256,bytes,address)"](
            signer.address,
            signer.address,
            0,
            1000000,
            "0x",
            MaxUint256,
            signature,
            signer.address,
            { value: fee - 1n }
          )
      ).to.revertedWith("Insufficient value for fee");
    });

    it("should revert, when failed to deduct the fee", async () => {
      await gateway.updateFeeVault(gateway.getAddress());
      const signature = await getSignature(signer, signer.address, 0, 1000000, "0x");
      const fee = await queue.estimateCrossDomainMessageFee(1000000);
      await network.provider.send("hardhat_setNextBlockBaseFeePerGas", ["0"]);
      await expect(
        gateway
          .connect(deployer)
          ["sendTransaction(address,address,uint256,uint256,bytes,uint256,bytes,address)"](
            signer.address,
            signer.address,
            0,
            1000000,
            "0x",
            MaxUint256,
            signature,
            signer.address,
            { value: fee }
          )
      ).to.revertedWith("Failed to deduct the fee");
    });

    it("should succeed, no refund", async () => {
      const signature = await getSignature(signer, deployer.address, 0, 1000000, "0x");
      const fee = await queue.estimateCrossDomainMessageFee(1000000);
      const feeVaultBalanceBefore = await ethers.provider.getBalance(feeVault.address);
      expect(await gateway.nonces(signer.address)).to.eq(0);
      await network.provider.send("hardhat_setNextBlockBaseFeePerGas", ["0"]);
      await expect(
        gateway
          .connect(deployer)
          ["sendTransaction(address,address,uint256,uint256,bytes,uint256,bytes,address)"](
            signer.address,
            deployer.address,
            0,
            1000000,
            "0x",
            MaxUint256,
            signature,
            signer.address,
            { value: fee }
          )
      )
        .to.emit(queue, "QueueTransaction")
        .withArgs(signer.address, deployer.address, 0, 0, 1000000, "0x");
      expect(await gateway.nonces(signer.address)).to.eq(1);
      const feeVaultBalanceAfter = await ethers.provider.getBalance(feeVault.address);
      expect(feeVaultBalanceAfter - feeVaultBalanceBefore).to.eq(fee);

      // use the same nonce to sign should fail
      await expect(
        gateway
          .connect(deployer)
          ["sendTransaction(address,address,uint256,uint256,bytes,uint256,bytes,address)"](
            signer.address,
            deployer.address,
            0,
            1000000,
            "0x",
            MaxUint256,
            signature,
            signer.address,
            { value: fee }
          )
      ).to.revertedWith("Incorrect signature");
    });

    it("should succeed, with refund", async () => {
      const signature = await getSignature(signer, deployer.address, 0, 1000000, "0x");
      const fee = await queue.estimateCrossDomainMessageFee(1000000);
      const feeVaultBalanceBefore = await ethers.provider.getBalance(feeVault.address);
      const signerBalanceBefore = await ethers.provider.getBalance(signer.address);
      expect(await gateway.nonces(signer.address)).to.eq(0);
      await network.provider.send("hardhat_setNextBlockBaseFeePerGas", ["0"]);
      await expect(
        gateway
          .connect(deployer)
          ["sendTransaction(address,address,uint256,uint256,bytes,uint256,bytes,address)"](
            signer.address,
            deployer.address,
            0,
            1000000,
            "0x",
            MaxUint256,
            signature,
            signer.address,
            { value: fee + 100n }
          )
      )
        .to.emit(queue, "QueueTransaction")
        .withArgs(signer.address, deployer.address, 0, 0, 1000000, "0x");
      expect(await gateway.nonces(signer.address)).to.eq(1);
      const feeVaultBalanceAfter = await ethers.provider.getBalance(feeVault.address);
      const signerBalanceAfter = await ethers.provider.getBalance(signer.address);
      expect(feeVaultBalanceAfter - feeVaultBalanceBefore).to.eq(fee);
      expect(signerBalanceAfter - signerBalanceBefore).to.eq(100n);

      // use the same nonce to sign should fail
      await expect(
        gateway
          .connect(deployer)
          ["sendTransaction(address,address,uint256,uint256,bytes,uint256,bytes,address)"](
            signer.address,
            deployer.address,
            0,
            1000000,
            "0x",
            MaxUint256,
            signature,
            signer.address,
            { value: fee + 100n }
          )
      ).to.revertedWith("Incorrect signature");
    });

    it("should revert, when refund failed", async () => {
      const signature = await getSignature(signer, signer.address, 0, 1000000, "0x1234");
      const fee = await queue.estimateCrossDomainMessageFee(1000000);
      await network.provider.send("hardhat_setNextBlockBaseFeePerGas", ["0"]);
      await expect(
        gateway
          .connect(deployer)
          ["sendTransaction(address,address,uint256,uint256,bytes,uint256,bytes,address)"](
            signer.address,
            signer.address,
            0,
            1000000,
            "0x1234",
            MaxUint256,
            signature,
            gateway.getAddress(),
            { value: fee + 100n }
          )
      ).to.revertedWith("Failed to refund the fee");
    });
  });
});
