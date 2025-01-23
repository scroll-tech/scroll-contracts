// SPDX-License-Identifier: MIT

pragma solidity =0.8.24;

import {console} from "hardhat/console.sol";

import {DSTestPlus} from "solmate/test/utils/DSTestPlus.sol";

import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {ITransparentUpgradeableProxy, TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import {L1MessageQueue} from "../L1/rollup/L1MessageQueue.sol";
import {ScrollChain, IScrollChain} from "../L1/rollup/ScrollChain.sol";
import {BatchHeaderV0Codec} from "../libraries/codec/BatchHeaderV0Codec.sol";
import {BatchHeaderV1Codec} from "../libraries/codec/BatchHeaderV1Codec.sol";
import {BatchHeaderV3Codec} from "../libraries/codec/BatchHeaderV3Codec.sol";
import {ChunkCodecV0} from "../libraries/codec/ChunkCodecV0.sol";
import {ChunkCodecV1} from "../libraries/codec/ChunkCodecV1.sol";
import {EmptyContract} from "../misc/EmptyContract.sol";

import {ScrollChainMockBlob} from "../mocks/ScrollChainMockBlob.sol";
import {MockRollupVerifier} from "./mocks/MockRollupVerifier.sol";

// solhint-disable no-inline-assembly

contract ScrollChainTest is DSTestPlus {
    // from ScrollChain
    event UpdateSequencer(address indexed account, bool status);
    event UpdateProver(address indexed account, bool status);
    event UpdateMaxNumTxInChunk(uint256 oldMaxNumTxInChunk, uint256 newMaxNumTxInChunk);

    event CommitBatch(uint256 indexed batchIndex, bytes32 indexed batchHash);
    event FinalizeBatch(uint256 indexed batchIndex, bytes32 indexed batchHash, bytes32 stateRoot, bytes32 withdrawRoot);
    event RevertBatch(uint256 indexed batchIndex, bytes32 indexed batchHash);

    // from L1MessageQueue
    event DequeueTransaction(uint256 startIndex, uint256 count, uint256 skippedBitmap);
    event ResetDequeuedTransaction(uint256 startIndex);
    event FinalizedDequeuedTransaction(uint256 finalizedIndex);

    ProxyAdmin internal admin;
    EmptyContract private placeholder;

    ScrollChain private rollup;
    L1MessageQueue internal messageQueue;
    MockRollupVerifier internal verifier;

    function setUp() public {
        placeholder = new EmptyContract();
        admin = new ProxyAdmin();
        messageQueue = L1MessageQueue(_deployProxy(address(0)));
        rollup = ScrollChain(_deployProxy(address(0)));
        verifier = new MockRollupVerifier();

        // Upgrade the L1MessageQueue implementation and initialize
        admin.upgrade(
            ITransparentUpgradeableProxy(address(messageQueue)),
            address(new L1MessageQueue(address(this), address(rollup), address(1)))
        );
        messageQueue.initialize(address(this), address(rollup), address(0), address(0), 10000000);
        // Upgrade the ScrollChain implementation and initialize
        admin.upgrade(
            ITransparentUpgradeableProxy(address(rollup)),
            address(new ScrollChain(233, address(messageQueue), address(verifier)))
        );
        rollup.initialize(address(messageQueue), address(verifier), 100);
    }

    function testInitialized() external {
        assertEq(address(this), rollup.owner());
        assertEq(rollup.layer2ChainId(), 233);

        hevm.expectRevert("Initializable: contract is already initialized");
        rollup.initialize(address(messageQueue), address(0), 100);
    }

    function testCommitBatchV3() external {
        bytes memory batchHeader0 = new bytes(89);

        // import 10 L1 messages
        for (uint256 i = 0; i < 10; i++) {
            messageQueue.appendCrossDomainMessage(address(this), 1000000, new bytes(0));
        }
        // import genesis batch first
        assembly {
            mstore(add(batchHeader0, add(0x20, 25)), 1)
        }
        rollup.importGenesisBatch(batchHeader0, bytes32(uint256(1)));
        assertEq(rollup.committedBatches(0), keccak256(batchHeader0));

        // caller not sequencer, revert
        hevm.expectRevert(ScrollChain.ErrorCallerIsNotSequencer.selector);
        rollup.commitBatchWithBlobProof(4, batchHeader0, new bytes[](0), new bytes(0), new bytes(0));
        rollup.addSequencer(address(0));

        // revert when ErrorIncorrectBatchVersion
        hevm.startPrank(address(0));
        hevm.expectRevert(ScrollChain.ErrorIncorrectBatchVersion.selector);
        rollup.commitBatchWithBlobProof(2, batchHeader0, new bytes[](0), new bytes(0), new bytes(0));
        hevm.expectRevert(ScrollChain.ErrorIncorrectBatchVersion.selector);
        rollup.commitBatchWithBlobProof(3, batchHeader0, new bytes[](0), new bytes(0), new bytes(0));
        hevm.stopPrank();

        // revert when ErrorBatchIsEmpty
        hevm.startPrank(address(0));
        hevm.expectRevert(ScrollChain.ErrorBatchIsEmpty.selector);
        rollup.commitBatchWithBlobProof(4, batchHeader0, new bytes[](0), new bytes(0), new bytes(0));
        hevm.stopPrank();

        // revert when ErrorBatchHeaderV3LengthMismatch
        bytes memory header = new bytes(192);
        assembly {
            mstore8(add(header, 0x20), 4) // version
        }
        hevm.startPrank(address(0));
        hevm.expectRevert(BatchHeaderV3Codec.ErrorBatchHeaderV3LengthMismatch.selector);
        rollup.commitBatchWithBlobProof(4, header, new bytes[](1), new bytes(0), new bytes(0));
        hevm.stopPrank();

        // revert when ErrorIncorrectBatchHash
        assembly {
            mstore(add(batchHeader0, add(0x20, 25)), 2) // change data hash for batch0
        }
        hevm.startPrank(address(0));
        hevm.expectRevert(ScrollChain.ErrorIncorrectBatchHash.selector);
        rollup.commitBatchWithBlobProof(4, batchHeader0, new bytes[](1), new bytes(0), new bytes(0));
        hevm.stopPrank();
        assembly {
            mstore(add(batchHeader0, add(0x20, 25)), 1) // change back
        }

        bytes[] memory chunks = new bytes[](1);
        bytes memory chunk0;

        // no block in chunk, revert
        chunk0 = new bytes(1);
        chunks[0] = chunk0;
        hevm.startPrank(address(0));
        hevm.expectRevert(ChunkCodecV1.ErrorNoBlockInChunkV1.selector);
        rollup.commitBatchWithBlobProof(4, batchHeader0, chunks, new bytes(0), new bytes(0));
        hevm.stopPrank();

        // invalid chunk length, revert
        chunk0 = new bytes(1);
        chunk0[0] = bytes1(uint8(1)); // one block in this chunk
        chunks[0] = chunk0;
        hevm.startPrank(address(0));
        hevm.expectRevert(ChunkCodecV1.ErrorIncorrectChunkLengthV1.selector);
        rollup.commitBatchWithBlobProof(4, batchHeader0, chunks, new bytes(0), new bytes(0));
        hevm.stopPrank();

        // cannot skip last L1 message, revert
        chunk0 = new bytes(1 + 60);
        bytes memory bitmap = new bytes(32);
        chunk0[0] = bytes1(uint8(1)); // one block in this chunk
        chunk0[58] = bytes1(uint8(1)); // numTransactions = 1
        chunk0[60] = bytes1(uint8(1)); // numL1Messages = 1
        bitmap[31] = bytes1(uint8(1));
        chunks[0] = chunk0;
        hevm.startPrank(address(0));
        hevm.expectRevert(ScrollChain.ErrorLastL1MessageSkipped.selector);
        rollup.commitBatchWithBlobProof(4, batchHeader0, chunks, bitmap, new bytes(0));
        hevm.stopPrank();

        // num txs less than num L1 msgs, revert
        chunk0 = new bytes(1 + 60);
        bitmap = new bytes(32);
        chunk0[0] = bytes1(uint8(1)); // one block in this chunk
        chunk0[58] = bytes1(uint8(1)); // numTransactions = 1
        chunk0[60] = bytes1(uint8(3)); // numL1Messages = 3
        bitmap[31] = bytes1(uint8(3));
        chunks[0] = chunk0;
        hevm.startPrank(address(0));
        hevm.expectRevert(ScrollChain.ErrorNumTxsLessThanNumL1Msgs.selector);
        rollup.commitBatchWithBlobProof(4, batchHeader0, chunks, bitmap, new bytes(0));
        hevm.stopPrank();

        // revert when ErrorNoBlobFound
        // revert when ErrorNoBlobFound
        chunk0 = new bytes(1 + 60);
        chunk0[0] = bytes1(uint8(1)); // one block in this chunk
        chunks[0] = chunk0;
        hevm.startPrank(address(0));
        hevm.expectRevert(ScrollChain.ErrorNoBlobFound.selector);
        rollup.commitBatchWithBlobProof(4, batchHeader0, chunks, new bytes(0), new bytes(0));
        hevm.stopPrank();

        // @note we cannot check `ErrorFoundMultipleBlobs` here

        // upgrade to ScrollChainMockBlob
        ScrollChainMockBlob impl = new ScrollChainMockBlob(
            rollup.layer2ChainId(),
            rollup.messageQueue(),
            rollup.verifier()
        );
        admin.upgrade(ITransparentUpgradeableProxy(address(rollup)), address(impl));
        // from https://etherscan.io/blob/0x013590dc3544d56629ba81bb14d4d31248f825001653aa575eb8e3a719046757?bid=740652
        bytes32 blobVersionedHash = 0x013590dc3544d56629ba81bb14d4d31248f825001653aa575eb8e3a719046757;
        bytes
            memory blobDataProof = hex"2c9d777660f14ad49803a6442935c0d24a0d83551de5995890bf70a17d24e68753ab0fe6807c7081f0885fe7da741554d658a03730b1fa006f8319f8b993bcb0a5a0c9e8a145c5ef6e415c245690effa2914ec9393f58a7251d30c0657da1453d9ad906eae8b97dd60c9a216f81b4df7af34d01e214e1ec5865f0133ecc16d7459e49dab66087340677751e82097fbdd20551d66076f425775d1758a9dfd186b";
        ScrollChainMockBlob(address(rollup)).setBlobVersionedHash(blobVersionedHash);

        chunk0 = new bytes(1 + 60);
        chunk0[0] = bytes1(uint8(1)); // one block in this chunk
        chunks[0] = chunk0;
        // revert when ErrorCallPointEvaluationPrecompileFailed
        hevm.startPrank(address(0));
        hevm.expectRevert(ScrollChain.ErrorCallPointEvaluationPrecompileFailed.selector);
        rollup.commitBatchWithBlobProof(4, batchHeader0, chunks, new bytes(0), new bytes(0));
        hevm.stopPrank();

        bytes32 batchHash0 = rollup.committedBatches(0);
        bytes memory batchHeader1 = new bytes(193);
        assembly {
            mstore8(add(batchHeader1, 0x20), 4) // version
            mstore(add(batchHeader1, add(0x20, 1)), shl(192, 1)) // batchIndex
            mstore(add(batchHeader1, add(0x20, 9)), 0) // l1MessagePopped
            mstore(add(batchHeader1, add(0x20, 17)), 0) // totalL1MessagePopped
            mstore(add(batchHeader1, add(0x20, 25)), 0x246394445f4fe64ed5598554d55d1682d6fb3fe04bf58eb54ef81d1189fafb51) // dataHash
            mstore(add(batchHeader1, add(0x20, 57)), blobVersionedHash) // blobVersionedHash
            mstore(add(batchHeader1, add(0x20, 89)), batchHash0) // parentBatchHash
            mstore(add(batchHeader1, add(0x20, 121)), 0) // lastBlockTimestamp
            mcopy(add(batchHeader1, add(0x20, 129)), add(blobDataProof, 0x20), 64) // blobDataProof
        }
        // hash is ed32768c5f910a11edaf1c1ec0c0da847def9d24e0a24567c3c3d284061cf935

        // succeed
        hevm.startPrank(address(0));
        assertEq(rollup.committedBatches(1), bytes32(0));
        rollup.commitBatchWithBlobProof(4, batchHeader0, chunks, new bytes(0), blobDataProof);
        hevm.stopPrank();
        assertEq(rollup.committedBatches(1), keccak256(batchHeader1));

        // revert when ErrorBatchIsAlreadyCommitted
        hevm.startPrank(address(0));
        hevm.expectRevert(ScrollChain.ErrorBatchIsAlreadyCommitted.selector);
        rollup.commitBatchWithBlobProof(4, batchHeader0, chunks, new bytes(0), blobDataProof);
        hevm.stopPrank();
    }

    function testFinalizeBundleWithProof() external {
        // caller not prover, revert
        hevm.expectRevert(ScrollChain.ErrorCallerIsNotProver.selector);
        rollup.finalizeBundleWithProof(new bytes(0), bytes32(0), bytes32(0), new bytes(0));

        rollup.addProver(address(0));
        rollup.addSequencer(address(0));

        // import genesis batch
        bytes memory batchHeader0 = new bytes(89);
        assembly {
            mstore(add(batchHeader0, add(0x20, 25)), 1)
        }
        rollup.importGenesisBatch(batchHeader0, bytes32(uint256(1)));

        // upgrade to ScrollChainMockBlob
        ScrollChainMockBlob impl = new ScrollChainMockBlob(
            rollup.layer2ChainId(),
            rollup.messageQueue(),
            rollup.verifier()
        );
        admin.upgrade(ITransparentUpgradeableProxy(address(rollup)), address(impl));
        // from https://etherscan.io/blob/0x013590dc3544d56629ba81bb14d4d31248f825001653aa575eb8e3a719046757?bid=740652
        bytes32 blobVersionedHash = 0x013590dc3544d56629ba81bb14d4d31248f825001653aa575eb8e3a719046757;
        bytes
            memory blobDataProof = hex"2c9d777660f14ad49803a6442935c0d24a0d83551de5995890bf70a17d24e68753ab0fe6807c7081f0885fe7da741554d658a03730b1fa006f8319f8b993bcb0a5a0c9e8a145c5ef6e415c245690effa2914ec9393f58a7251d30c0657da1453d9ad906eae8b97dd60c9a216f81b4df7af34d01e214e1ec5865f0133ecc16d7459e49dab66087340677751e82097fbdd20551d66076f425775d1758a9dfd186b";
        ScrollChainMockBlob(address(rollup)).setBlobVersionedHash(blobVersionedHash);

        bytes[] memory chunks = new bytes[](1);
        bytes memory chunk0;

        bytes32 batchHash0 = rollup.committedBatches(0);
        bytes memory batchHeader1 = new bytes(193);
        assembly {
            mstore8(add(batchHeader1, 0x20), 4) // version
            mstore(add(batchHeader1, add(0x20, 1)), shl(192, 1)) // batchIndex
            mstore(add(batchHeader1, add(0x20, 9)), 0) // l1MessagePopped
            mstore(add(batchHeader1, add(0x20, 17)), 0) // totalL1MessagePopped
            mstore(add(batchHeader1, add(0x20, 25)), 0x246394445f4fe64ed5598554d55d1682d6fb3fe04bf58eb54ef81d1189fafb51) // dataHash
            mstore(add(batchHeader1, add(0x20, 57)), blobVersionedHash) // blobVersionedHash
            mstore(add(batchHeader1, add(0x20, 89)), batchHash0) // parentBatchHash
            mstore(add(batchHeader1, add(0x20, 121)), 0) // lastBlockTimestamp
            mcopy(add(batchHeader1, add(0x20, 129)), add(blobDataProof, 0x20), 64) // blobDataProof
        }
        // hash is ed32768c5f910a11edaf1c1ec0c0da847def9d24e0a24567c3c3d284061cf935

        // commit one batch
        chunk0 = new bytes(1 + 60);
        chunk0[0] = bytes1(uint8(1)); // one block in this chunk
        chunks[0] = chunk0;
        hevm.startPrank(address(0));
        assertEq(rollup.committedBatches(1), bytes32(0));
        rollup.commitBatchWithBlobProof(4, batchHeader0, chunks, new bytes(0), blobDataProof);
        hevm.stopPrank();
        assertEq(rollup.committedBatches(1), keccak256(batchHeader1));

        // revert when ErrorStateRootIsZero
        hevm.startPrank(address(0));
        hevm.expectRevert(ScrollChain.ErrorStateRootIsZero.selector);
        rollup.finalizeBundleWithProof(batchHeader1, bytes32(0), bytes32(0), new bytes(0));
        hevm.stopPrank();

        // revert when ErrorBatchHeaderV3LengthMismatch
        bytes memory header = new bytes(192);
        assembly {
            mstore8(add(header, 0x20), 4) // version
        }
        hevm.startPrank(address(0));
        hevm.expectRevert(BatchHeaderV3Codec.ErrorBatchHeaderV3LengthMismatch.selector);
        rollup.finalizeBundleWithProof(header, bytes32(uint256(1)), bytes32(uint256(2)), new bytes(0));
        hevm.stopPrank();

        // revert when ErrorIncorrectBatchHash
        batchHeader1[1] = bytes1(uint8(1)); // change random byte
        hevm.startPrank(address(0));
        hevm.expectRevert(ScrollChain.ErrorIncorrectBatchHash.selector);
        rollup.finalizeBundleWithProof(batchHeader1, bytes32(uint256(1)), bytes32(uint256(2)), new bytes(0));
        hevm.stopPrank();
        batchHeader1[1] = bytes1(uint8(0)); // change back

        // verify success
        assertBoolEq(rollup.isBatchFinalized(1), false);
        hevm.startPrank(address(0));
        rollup.finalizeBundleWithProof(batchHeader1, bytes32(uint256(2)), bytes32(uint256(3)), new bytes(0));
        hevm.stopPrank();
        assertBoolEq(rollup.isBatchFinalized(1), true);
        assertEq(rollup.finalizedStateRoots(1), bytes32(uint256(2)));
        assertEq(rollup.withdrawRoots(1), bytes32(uint256(3)));
        assertEq(rollup.lastFinalizedBatchIndex(), 1);

        // revert when ErrorBatchIsAlreadyVerified
        hevm.startPrank(address(0));
        hevm.expectRevert(ScrollChain.ErrorBatchIsAlreadyVerified.selector);
        rollup.finalizeBundleWithProof(batchHeader1, bytes32(uint256(2)), bytes32(uint256(3)), new bytes(0));
        hevm.stopPrank();
    }

    function _commitBatchV3()
        internal
        returns (
            bytes memory batchHeader0,
            bytes memory batchHeader1,
            bytes memory batchHeader2
        )
    {
        // import genesis batch first
        batchHeader0 = new bytes(89);
        assembly {
            mstore(add(batchHeader0, add(0x20, 25)), 1)
        }
        rollup.importGenesisBatch(batchHeader0, bytes32(uint256(1)));
        bytes32 batchHash0 = rollup.committedBatches(0);

        // upgrade to ScrollChainMockBlob
        ScrollChainMockBlob impl = new ScrollChainMockBlob(
            rollup.layer2ChainId(),
            rollup.messageQueue(),
            rollup.verifier()
        );
        admin.upgrade(ITransparentUpgradeableProxy(address(rollup)), address(impl));
        // from https://etherscan.io/blob/0x013590dc3544d56629ba81bb14d4d31248f825001653aa575eb8e3a719046757?bid=740652
        bytes32 blobVersionedHash = 0x013590dc3544d56629ba81bb14d4d31248f825001653aa575eb8e3a719046757;
        bytes
            memory blobDataProof = hex"2c9d777660f14ad49803a6442935c0d24a0d83551de5995890bf70a17d24e68753ab0fe6807c7081f0885fe7da741554d658a03730b1fa006f8319f8b993bcb0a5a0c9e8a145c5ef6e415c245690effa2914ec9393f58a7251d30c0657da1453d9ad906eae8b97dd60c9a216f81b4df7af34d01e214e1ec5865f0133ecc16d7459e49dab66087340677751e82097fbdd20551d66076f425775d1758a9dfd186b";
        ScrollChainMockBlob(address(rollup)).setBlobVersionedHash(blobVersionedHash);

        bytes memory bitmap;
        bytes[] memory chunks;
        bytes memory chunk0;
        bytes memory chunk1;

        // commit batch1, one chunk with one block, 1 tx, 1 L1 message, no skip
        // => payload for data hash of chunk0
        //   0000000000000000
        //   0000000000000123
        //   0000000000000000000000000000000000000000000000000000000000000000
        //   0000000000000000
        //   0001
        //   a2277fd30bbbe74323309023b56035b376d7768ad237ae4fc46ead7dc9591ae1
        // => data hash for chunk0
        //   5972b8fa626c873a97abb6db14fb0cb2085e050a6f80ec90b92bb0bbaa12eb5a
        // => data hash for all chunks
        //   f6166fe668c1e6a04e3c75e864452bb02a31358f285efcb7a4e6603eb5750359
        // => payload for batch header
        //   03
        //   0000000000000001
        //   0000000000000001
        //   0000000000000001
        //   f6166fe668c1e6a04e3c75e864452bb02a31358f285efcb7a4e6603eb5750359
        //   013590dc3544d56629ba81bb14d4d31248f825001653aa575eb8e3a719046757
        //   119b828c2a2798d2c957228ebeaff7e10bb099ae0d4e224f3eeb779ff61cba61
        //   0000000000000123
        //   2c9d777660f14ad49803a6442935c0d24a0d83551de5995890bf70a17d24e687
        //   53ab0fe6807c7081f0885fe7da741554d658a03730b1fa006f8319f8b993bcb0
        // => hash for batch header
        //   07e1bede8c5047cf8ca7ac84f5390837fb6224953af83d7e967488fa63a2065e
        batchHeader1 = new bytes(193);
        assembly {
            mstore8(add(batchHeader1, 0x20), 4) // version
            mstore(add(batchHeader1, add(0x20, 1)), shl(192, 1)) // batchIndex = 1
            mstore(add(batchHeader1, add(0x20, 9)), shl(192, 1)) // l1MessagePopped = 1
            mstore(add(batchHeader1, add(0x20, 17)), shl(192, 1)) // totalL1MessagePopped = 1
            mstore(add(batchHeader1, add(0x20, 25)), 0xf6166fe668c1e6a04e3c75e864452bb02a31358f285efcb7a4e6603eb5750359) // dataHash
            mstore(add(batchHeader1, add(0x20, 57)), blobVersionedHash) // blobVersionedHash
            mstore(add(batchHeader1, add(0x20, 89)), batchHash0) // parentBatchHash
            mstore(add(batchHeader1, add(0x20, 121)), shl(192, 0x123)) // lastBlockTimestamp
            mcopy(add(batchHeader1, add(0x20, 129)), add(blobDataProof, 0x20), 64) // blobDataProof
        }
        chunk0 = new bytes(1 + 60);
        assembly {
            mstore(add(chunk0, 0x20), shl(248, 1)) // numBlocks = 1
            mstore(add(chunk0, add(0x21, 8)), shl(192, 0x123)) // timestamp = 0x123
            mstore(add(chunk0, add(0x21, 56)), shl(240, 1)) // numTransactions = 1
            mstore(add(chunk0, add(0x21, 58)), shl(240, 1)) // numL1Messages = 1
        }
        chunks = new bytes[](1);
        chunks[0] = chunk0;
        bitmap = new bytes(32);
        hevm.startPrank(address(0));
        hevm.expectEmit(true, true, false, true);
        emit CommitBatch(1, keccak256(batchHeader1));
        rollup.commitBatchWithBlobProof(4, batchHeader0, chunks, bitmap, blobDataProof);
        hevm.stopPrank();
        assertBoolEq(rollup.isBatchFinalized(1), false);
        bytes32 batchHash1 = rollup.committedBatches(1);
        assertEq(batchHash1, keccak256(batchHeader1));
        assertEq(1, messageQueue.pendingQueueIndex());
        assertEq(0, messageQueue.nextUnfinalizedQueueIndex());
        assertBoolEq(messageQueue.isMessageSkipped(0), false);

        // commit batch2 with two chunks, correctly
        // 1. chunk0 has one block, 3 tx, no L1 messages
        //   => payload for chunk0
        //    0000000000000000
        //    0000000000000456
        //    0000000000000000000000000000000000000000000000000000000000000000
        //    0000000000000000
        //    0003
        //    ... (some tx hashes)
        //   => data hash for chunk0
        //    1c7649f248aed8448fa7997e44db7b7028581deb119c6d6aa1a2d126d62564cf
        // 2. chunk1 has three blocks
        //   2.1 block0 has 5 tx, 3 L1 messages, no skips
        //   2.2 block1 has 10 tx, 5 L1 messages, even is skipped, last is not skipped
        //   2.2 block1 has 300 tx, 256 L1 messages, odd position is skipped, last is not skipped
        //   => payload for chunk1
        //    0000000000000000
        //    0000000000000789
        //    0000000000000000000000000000000000000000000000000000000000000000
        //    0000000000000000
        //    0005
        //    0000000000000000
        //    0000000000001234
        //    0000000000000000000000000000000000000000000000000000000000000000
        //    0000000000000000
        //    000a
        //    0000000000000000
        //    0000000000005678
        //    0000000000000000000000000000000000000000000000000000000000000000
        //    0000000000000000
        //    012c
        //   => data hash for chunk1
        //    4e82cb576135a69a0ecc2b2070c432abfdeb20076594faaa1aeed77f48d7c856
        // => data hash for all chunks
        //   166e9d20206ae8cddcdf0f30093e3acc3866937172df5d7f69fb5567d9595239
        // => payload for batch header
        //  03
        //  0000000000000002
        //  0000000000000108
        //  0000000000000109
        //  166e9d20206ae8cddcdf0f30093e3acc3866937172df5d7f69fb5567d9595239
        //  013590dc3544d56629ba81bb14d4d31248f825001653aa575eb8e3a719046757
        //  07e1bede8c5047cf8ca7ac84f5390837fb6224953af83d7e967488fa63a2065e
        //  0000000000005678
        //  2c9d777660f14ad49803a6442935c0d24a0d83551de5995890bf70a17d24e687
        //  53ab0fe6807c7081f0885fe7da741554d658a03730b1fa006f8319f8b993bcb0
        // => hash for batch header
        //  8a59f0de6f1071c0f48d6a49d9b794008d28b63cc586da0f44f8b2b4e13cb231
        batchHeader2 = new bytes(193);
        assembly {
            mstore8(add(batchHeader2, 0x20), 4) // version
            mstore(add(batchHeader2, add(0x20, 1)), shl(192, 2)) // batchIndex = 2
            mstore(add(batchHeader2, add(0x20, 9)), shl(192, 264)) // l1MessagePopped = 264
            mstore(add(batchHeader2, add(0x20, 17)), shl(192, 265)) // totalL1MessagePopped = 265
            mstore(add(batchHeader2, add(0x20, 25)), 0x166e9d20206ae8cddcdf0f30093e3acc3866937172df5d7f69fb5567d9595239) // dataHash
            mstore(add(batchHeader2, add(0x20, 57)), blobVersionedHash) // blobVersionedHash
            mstore(add(batchHeader2, add(0x20, 89)), batchHash1) // parentBatchHash
            mstore(add(batchHeader2, add(0x20, 121)), shl(192, 0x5678)) // lastBlockTimestamp
            mcopy(add(batchHeader2, add(0x20, 129)), add(blobDataProof, 0x20), 64) // blobDataProof
        }
        chunk0 = new bytes(1 + 60);
        assembly {
            mstore(add(chunk0, 0x20), shl(248, 1)) // numBlocks = 1
            mstore(add(chunk0, add(0x21, 8)), shl(192, 0x456)) // timestamp = 0x456
            mstore(add(chunk0, add(0x21, 56)), shl(240, 3)) // numTransactions = 3
            mstore(add(chunk0, add(0x21, 58)), shl(240, 0)) // numL1Messages = 0
        }
        chunk1 = new bytes(1 + 60 * 3);
        assembly {
            mstore(add(chunk1, 0x20), shl(248, 3)) // numBlocks = 3
            mstore(add(chunk1, add(33, 8)), shl(192, 0x789)) // block0.timestamp = 0x789
            mstore(add(chunk1, add(33, 56)), shl(240, 5)) // block0.numTransactions = 5
            mstore(add(chunk1, add(33, 58)), shl(240, 3)) // block0.numL1Messages = 3
            mstore(add(chunk1, add(93, 8)), shl(192, 0x1234)) // block1.timestamp = 0x1234
            mstore(add(chunk1, add(93, 56)), shl(240, 10)) // block1.numTransactions = 10
            mstore(add(chunk1, add(93, 58)), shl(240, 5)) // block1.numL1Messages = 5
            mstore(add(chunk1, add(153, 8)), shl(192, 0x5678)) // block1.timestamp = 0x5678
            mstore(add(chunk1, add(153, 56)), shl(240, 300)) // block1.numTransactions = 300
            mstore(add(chunk1, add(153, 58)), shl(240, 256)) // block1.numL1Messages = 256
        }
        chunks = new bytes[](2);
        chunks[0] = chunk0;
        chunks[1] = chunk1;
        bitmap = new bytes(64);
        assembly {
            mstore(
                add(bitmap, add(0x20, 0)),
                77194726158210796949047323339125271902179989777093709359638389338608753093160
            ) // bitmap0
            mstore(add(bitmap, add(0x20, 32)), 42) // bitmap1
        }

        // too many txs in one chunk, revert
        rollup.updateMaxNumTxInChunk(2); // 3 - 1
        hevm.startPrank(address(0));
        hevm.expectRevert(ScrollChain.ErrorTooManyTxsInOneChunk.selector);
        rollup.commitBatchWithBlobProof(4, batchHeader1, chunks, bitmap, blobDataProof); // first chunk with too many txs
        hevm.stopPrank();
        rollup.updateMaxNumTxInChunk(185); // 5+10+300 - 2 - 127
        hevm.startPrank(address(0));
        hevm.expectRevert(ScrollChain.ErrorTooManyTxsInOneChunk.selector);
        rollup.commitBatchWithBlobProof(4, batchHeader1, chunks, bitmap, blobDataProof); // second chunk with too many txs
        hevm.stopPrank();

        rollup.updateMaxNumTxInChunk(186);
        hevm.startPrank(address(0));
        hevm.expectEmit(true, true, false, true);
        emit CommitBatch(2, keccak256(batchHeader2));
        rollup.commitBatchWithBlobProof(4, batchHeader1, chunks, bitmap, blobDataProof);
        hevm.stopPrank();
        assertBoolEq(rollup.isBatchFinalized(2), false);
        bytes32 batchHash2 = rollup.committedBatches(2);
        assertEq(batchHash2, keccak256(batchHeader2));
        assertEq(265, messageQueue.pendingQueueIndex());
        assertEq(0, messageQueue.nextUnfinalizedQueueIndex());
    }

    function testCommitAndFinalizeWithL1MessagesV3() external {
        rollup.addSequencer(address(0));
        rollup.addProver(address(0));

        // import 300 L1 messages
        for (uint256 i = 0; i < 300; i++) {
            messageQueue.appendCrossDomainMessage(address(this), 1000000, new bytes(0));
        }

        (bytes memory batchHeader0, bytes memory batchHeader1, bytes memory batchHeader2) = _commitBatchV3();

        // 1 ~ 4, zero
        for (uint256 i = 1; i < 4; i++) {
            assertBoolEq(messageQueue.isMessageSkipped(i), false);
        }
        // 4 ~ 9, even is nonzero, odd is zero
        for (uint256 i = 4; i < 9; i++) {
            if (i % 2 == 1 || i == 8) {
                assertBoolEq(messageQueue.isMessageSkipped(i), false);
            } else {
                assertBoolEq(messageQueue.isMessageSkipped(i), true);
            }
        }
        // 9 ~ 265, even is nonzero, odd is zero
        for (uint256 i = 9; i < 265; i++) {
            if (i % 2 == 1 || i == 264) {
                assertBoolEq(messageQueue.isMessageSkipped(i), false);
            } else {
                assertBoolEq(messageQueue.isMessageSkipped(i), true);
            }
        }

        // finalize batch1 and batch2 together
        assertBoolEq(rollup.isBatchFinalized(1), false);
        assertBoolEq(rollup.isBatchFinalized(2), false);
        hevm.startPrank(address(0));
        rollup.finalizeBundleWithProof(batchHeader2, bytes32(uint256(2)), bytes32(uint256(3)), new bytes(0));
        hevm.stopPrank();
        assertBoolEq(rollup.isBatchFinalized(1), true);
        assertBoolEq(rollup.isBatchFinalized(2), true);
        assertEq(rollup.finalizedStateRoots(1), bytes32(0));
        assertEq(rollup.withdrawRoots(1), bytes32(0));
        assertEq(rollup.finalizedStateRoots(2), bytes32(uint256(2)));
        assertEq(rollup.withdrawRoots(2), bytes32(uint256(3)));
        assertEq(rollup.lastFinalizedBatchIndex(), 2);
        assertEq(265, messageQueue.nextUnfinalizedQueueIndex());
    }

    function testCommitBatchV5() external {
        bytes[] memory headers = _prepareFinalizeBundle();

        assertEq(rollup.initialEuclidBatchIndex(), 0);
        bytes memory v5Header = _commitBatch(5, headers[10], 0);
        assertEq(rollup.initialEuclidBatchIndex(), 11);

        // revert when commit again
        hevm.startPrank(address(0));
        hevm.expectRevert(ScrollChain.ErrorBatchIsAlreadyCommitted.selector);
        rollup.commitBatchWithBlobProof(5, v5Header, new bytes[](0), new bytes(0), new bytes(0));
        hevm.stopPrank();
    }

    function testFinalizeEuclidInitialBatch() external {
        bytes[] memory headers = _prepareFinalizeBundle();

        assertEq(rollup.initialEuclidBatchIndex(), 0);
        bytes memory v5Header = _commitBatch(5, headers[10], 0);
        assertEq(rollup.initialEuclidBatchIndex(), 11);

        // revert when caller is not owner
        hevm.startPrank(address(1));
        hevm.expectRevert("Ownable: caller is not the owner");
        rollup.finalizeEuclidInitialBatch(bytes32(0), bytes32(0));
        hevm.stopPrank();

        // revert when ErrorStateRootIsZero
        hevm.expectRevert(ScrollChain.ErrorStateRootIsZero.selector);
        rollup.finalizeEuclidInitialBatch(bytes32(0), bytes32(0));

        // finalize first 9 batches
        hevm.startPrank(address(0));
        assertEq(rollup.lastFinalizedBatchIndex(), 0);
        rollup.finalizeBundleWithProof(headers[9], keccak256("009"), keccak256("109"), new bytes(0));
        assertEq(rollup.lastFinalizedBatchIndex(), 9);
        hevm.stopPrank();

        // revert when ErrorNotAllV4BatchFinalized
        hevm.expectRevert(ScrollChain.ErrorNotAllV4BatchFinalized.selector);
        rollup.finalizeEuclidInitialBatch(keccak256("011"), keccak256("111"));

        // finalize batch 10
        hevm.startPrank(address(0));
        rollup.finalizeBundleWithProof(headers[10], keccak256("010"), keccak256("110"), new bytes(0));
        assertEq(rollup.lastFinalizedBatchIndex(), 10);
        hevm.stopPrank();

        // succeed
        assertEq(rollup.finalizedStateRoots(11), 0);
        assertEq(rollup.withdrawRoots(11), 0);
        assertEq(rollup.lastFinalizedBatchIndex(), 10);
        hevm.expectEmit(true, true, true, true);
        emit FinalizeBatch(11, keccak256(v5Header), keccak256("011"), keccak256("111"));
        rollup.finalizeEuclidInitialBatch(keccak256("011"), keccak256("111"));
        assertEq(rollup.finalizedStateRoots(11), keccak256("011"));
        assertEq(rollup.withdrawRoots(11), keccak256("111"));

        // revert when ErrorStateRootIsZero
        hevm.expectRevert(ScrollChain.ErrorBatchIsAlreadyVerified.selector);
        rollup.finalizeEuclidInitialBatch(keccak256("011"), keccak256("111"));
    }

    function testFinalizeBundlePostEuclid() external {
        bytes[] memory headers = _prepareFinalizeBundle();

        assertEq(rollup.initialEuclidBatchIndex(), 0);
        bytes memory v5Header = _commitBatch(5, headers[10], 0);
        assertEq(rollup.initialEuclidBatchIndex(), 11);

        for (uint256 i = 1; i <= 10; ++i) {
            assertBoolEq(rollup.isBatchFinalized(i), false);
        }
        assertEq(messageQueue.nextUnfinalizedQueueIndex(), 0);
        hevm.prank(address(0));
        rollup.finalizeBundleWithProof(headers[10], keccak256("010"), keccak256("110"), new bytes(0));
        for (uint256 i = 1; i <= 10; ++i) {
            assertBoolEq(rollup.isBatchFinalized(i), true);
        }
        assertEq(messageQueue.nextUnfinalizedQueueIndex(), 10);

        assertBoolEq(rollup.isBatchFinalized(11), false);
        rollup.finalizeEuclidInitialBatch(keccak256("011"), keccak256("111"));
        assertBoolEq(rollup.isBatchFinalized(11), true);
        assertEq(rollup.lastFinalizedBatchIndex(), 11);

        // commit 3 v6 batches
        bytes memory v6Header1 = _commitBatch(6, v5Header, 1);
        bytes memory v6Header2 = _commitBatch(6, v6Header1, 2);
        bytes memory v6Header3 = _commitBatch(6, v6Header2, 3);

        // revert when ErrorCallerIsNotProver
        hevm.expectRevert(ScrollChain.ErrorCallerIsNotProver.selector);
        rollup.finalizeBundlePostEuclid(new bytes(0), bytes32(0), bytes32(0), new bytes(0));

        // revert when ErrorStateRootIsZero
        hevm.startPrank(address(0));
        hevm.expectRevert(ScrollChain.ErrorStateRootIsZero.selector);
        rollup.finalizeBundlePostEuclid(v6Header1, bytes32(0), bytes32(0), new bytes(0));

        // finalize bundle with one batch
        assertEq(rollup.finalizedStateRoots(12), 0);
        assertEq(rollup.withdrawRoots(12), 0);
        assertEq(rollup.lastFinalizedBatchIndex(), 11);
        assertBoolEq(rollup.isBatchFinalized(12), false);
        assertEq(messageQueue.nextUnfinalizedQueueIndex(), 10);
        hevm.expectEmit(true, true, true, true);
        emit FinalizeBatch(12, keccak256(v6Header1), keccak256("001"), keccak256("101"));
        rollup.finalizeBundlePostEuclid(v6Header1, keccak256("001"), keccak256("101"), new bytes(0));
        assertEq(rollup.finalizedStateRoots(12), keccak256("001"));
        assertEq(rollup.withdrawRoots(12), keccak256("101"));
        assertEq(rollup.lastFinalizedBatchIndex(), 12);
        assertBoolEq(rollup.isBatchFinalized(12), true);
        assertEq(messageQueue.nextUnfinalizedQueueIndex(), 11);

        // revert when ErrorBatchIsAlreadyVerified
        hevm.expectRevert(ScrollChain.ErrorBatchIsAlreadyVerified.selector);
        rollup.finalizeBundlePostEuclid(v6Header1, keccak256("001"), keccak256("101"), new bytes(0));

        // finalize bundle with two batch
        assertEq(rollup.finalizedStateRoots(14), 0);
        assertEq(rollup.withdrawRoots(14), 0);
        assertEq(rollup.lastFinalizedBatchIndex(), 12);
        assertEq(messageQueue.nextUnfinalizedQueueIndex(), 11);
        hevm.expectEmit(true, true, true, true);
        emit FinalizeBatch(14, keccak256(v6Header3), keccak256("003"), keccak256("103"));
        rollup.finalizeBundlePostEuclid(v6Header3, keccak256("003"), keccak256("103"), new bytes(0));
        assertEq(rollup.finalizedStateRoots(14), keccak256("003"));
        assertEq(rollup.withdrawRoots(14), keccak256("103"));
        assertEq(rollup.lastFinalizedBatchIndex(), 14);
        assertEq(messageQueue.nextUnfinalizedQueueIndex(), 16);

        hevm.stopPrank();
    }

    function testRevertBatchWithL1Messages() external {
        rollup.addSequencer(address(0));
        rollup.addProver(address(0));

        // import 300 L1 messages
        for (uint256 i = 0; i < 300; i++) {
            messageQueue.appendCrossDomainMessage(address(this), 1000000, new bytes(0));
        }

        (bytes memory batchHeader0, bytes memory batchHeader1, bytes memory batchHeader2) = _commitBatchV3();

        // 1 ~ 4, zero
        for (uint256 i = 1; i < 4; i++) {
            assertBoolEq(messageQueue.isMessageSkipped(i), false);
        }
        // 4 ~ 9, even is nonzero, odd is zero
        for (uint256 i = 4; i < 9; i++) {
            if (i % 2 == 1 || i == 8) {
                assertBoolEq(messageQueue.isMessageSkipped(i), false);
            } else {
                assertBoolEq(messageQueue.isMessageSkipped(i), true);
            }
        }
        // 9 ~ 265, even is nonzero, odd is zero
        for (uint256 i = 9; i < 265; i++) {
            if (i % 2 == 1 || i == 264) {
                assertBoolEq(messageQueue.isMessageSkipped(i), false);
            } else {
                assertBoolEq(messageQueue.isMessageSkipped(i), true);
            }
        }

        // revert batch 1 and batch 2
        rollup.revertBatch(batchHeader1, batchHeader2);
        assertEq(0, messageQueue.pendingQueueIndex());
        assertEq(0, messageQueue.nextUnfinalizedQueueIndex());
        for (uint256 i = 0; i < 265; i++) {
            assertBoolEq(messageQueue.isMessageSkipped(i), false);
        }
    }

    function testRevertBatch() external {
        bytes[] memory headers = _prepareFinalizeBundle();

        // caller not owner, revert
        hevm.startPrank(address(1));
        hevm.expectRevert("Ownable: caller is not the owner");
        rollup.revertBatch(new bytes(0), new bytes(0));
        hevm.stopPrank();

        // incorrect batch hash of first header, revert
        headers[2][1] = bytes1(uint8(1)); // change random byte
        hevm.expectRevert(ScrollChain.ErrorIncorrectBatchHash.selector);
        rollup.revertBatch(headers[2], headers[1]);
        headers[2][1] = bytes1(uint8(0)); // change back

        // incorrect batch hash of second header, revert
        headers[2][1] = bytes1(uint8(1)); // change random byte
        hevm.expectRevert(ScrollChain.ErrorIncorrectBatchHash.selector);
        rollup.revertBatch(headers[1], headers[2]);
        headers[2][1] = bytes1(uint8(0)); // change back

        // count must be nonzero, revert
        hevm.expectRevert(ScrollChain.ErrorRevertZeroBatches.selector);
        rollup.revertBatch(headers[2], headers[1]);

        // revert middle batch, revert
        hevm.expectRevert(ScrollChain.ErrorRevertNotStartFromEnd.selector);
        rollup.revertBatch(headers[2], headers[3]);

        // can only revert unfinalized batch, revert
        hevm.expectRevert(ScrollChain.ErrorRevertFinalizedBatch.selector);
        rollup.revertBatch(headers[0], headers[10]);

        // succeed to revert batches 9 and 10
        assertEq(rollup.committedBatches(9), keccak256(headers[9]));
        assertEq(rollup.committedBatches(10), keccak256(headers[10]));
        hevm.expectEmit(true, true, false, true);
        emit RevertBatch(10, rollup.committedBatches(10));
        hevm.expectEmit(true, true, false, true);
        emit RevertBatch(9, rollup.committedBatches(9));
        rollup.revertBatch(headers[9], headers[10]);
        assertEq(rollup.committedBatches(9), 0);
        assertEq(rollup.committedBatches(10), 0);

        // revert batches 6-8
        rollup.revertBatch(headers[6], headers[8]);

        // revert batches 4-5, with l1 messages
        assertEq(10, messageQueue.pendingQueueIndex());
        rollup.revertBatch(headers[4], headers[5]);
        assertEq(6, messageQueue.pendingQueueIndex());
    }

    function testAddAndRemoveSequencer(address _sequencer) external {
        // set by non-owner, should revert
        hevm.startPrank(address(1));
        hevm.expectRevert("Ownable: caller is not the owner");
        rollup.addSequencer(_sequencer);
        hevm.expectRevert("Ownable: caller is not the owner");
        rollup.removeSequencer(_sequencer);
        hevm.stopPrank();

        hevm.expectRevert(ScrollChain.ErrorAccountIsNotEOA.selector);
        rollup.addSequencer(address(this));
        hevm.assume(_sequencer.code.length == 0);

        // change to random EOA operator
        hevm.expectEmit(true, false, false, true);
        emit UpdateSequencer(_sequencer, true);

        assertBoolEq(rollup.isSequencer(_sequencer), false);
        rollup.addSequencer(_sequencer);
        assertBoolEq(rollup.isSequencer(_sequencer), true);

        hevm.expectEmit(true, false, false, true);
        emit UpdateSequencer(_sequencer, false);
        rollup.removeSequencer(_sequencer);
        assertBoolEq(rollup.isSequencer(_sequencer), false);
    }

    function testAddAndRemoveProver(address _prover) external {
        // set by non-owner, should revert
        hevm.startPrank(address(1));
        hevm.expectRevert("Ownable: caller is not the owner");
        rollup.addProver(_prover);
        hevm.expectRevert("Ownable: caller is not the owner");
        rollup.removeProver(_prover);
        hevm.stopPrank();

        hevm.expectRevert(ScrollChain.ErrorAccountIsNotEOA.selector);
        rollup.addProver(address(this));
        hevm.assume(_prover.code.length == 0);

        // change to random EOA operator
        hevm.expectEmit(true, false, false, true);
        emit UpdateProver(_prover, true);

        assertBoolEq(rollup.isProver(_prover), false);
        rollup.addProver(_prover);
        assertBoolEq(rollup.isProver(_prover), true);

        hevm.expectEmit(true, false, false, true);
        emit UpdateProver(_prover, false);
        rollup.removeProver(_prover);
        assertBoolEq(rollup.isProver(_prover), false);
    }

    function testSetPause() external {
        rollup.addSequencer(address(0));
        rollup.addProver(address(0));

        // not owner, revert
        hevm.startPrank(address(1));
        hevm.expectRevert("Ownable: caller is not the owner");
        rollup.setPause(false);
        hevm.stopPrank();

        // pause
        rollup.setPause(true);
        assertBoolEq(true, rollup.paused());

        hevm.startPrank(address(0));
        hevm.expectRevert("Pausable: paused");
        rollup.commitBatchWithBlobProof(3, new bytes(0), new bytes[](0), new bytes(0), new bytes(0));
        hevm.expectRevert("Pausable: paused");
        rollup.commitBatchWithBlobProof(4, new bytes(0), new bytes[](0), new bytes(0), new bytes(0));
        hevm.expectRevert("Pausable: paused");
        rollup.finalizeBundleWithProof(new bytes(0), bytes32(0), bytes32(0), new bytes(0));
        hevm.expectRevert("Pausable: paused");
        rollup.finalizeBundlePostEuclid(new bytes(0), bytes32(0), bytes32(0), new bytes(0));
        hevm.stopPrank();

        // unpause
        rollup.setPause(false);
        assertBoolEq(false, rollup.paused());
    }

    function testUpdateMaxNumTxInChunk(uint256 _maxNumTxInChunk) external {
        // set by non-owner, should revert
        hevm.startPrank(address(1));
        hevm.expectRevert("Ownable: caller is not the owner");
        rollup.updateMaxNumTxInChunk(_maxNumTxInChunk);
        hevm.stopPrank();

        // change to random operator
        hevm.expectEmit(false, false, false, true);
        emit UpdateMaxNumTxInChunk(100, _maxNumTxInChunk);

        assertEq(rollup.maxNumTxInChunk(), 100);
        rollup.updateMaxNumTxInChunk(_maxNumTxInChunk);
        assertEq(rollup.maxNumTxInChunk(), _maxNumTxInChunk);
    }

    function testImportGenesisBlock() external {
        bytes memory batchHeader;

        // zero state root, revert
        batchHeader = new bytes(89);
        hevm.expectRevert(ScrollChain.ErrorStateRootIsZero.selector);
        rollup.importGenesisBatch(batchHeader, bytes32(0));

        // batch header length too small, revert
        batchHeader = new bytes(88);
        hevm.expectRevert(BatchHeaderV0Codec.ErrorBatchHeaderV0LengthTooSmall.selector);
        rollup.importGenesisBatch(batchHeader, bytes32(uint256(1)));

        // wrong bitmap length, revert
        batchHeader = new bytes(90);
        hevm.expectRevert(BatchHeaderV0Codec.ErrorIncorrectBitmapLengthV0.selector);
        rollup.importGenesisBatch(batchHeader, bytes32(uint256(1)));

        // not all fields are zero, revert
        batchHeader = new bytes(121);
        batchHeader[0] = bytes1(uint8(1)); // version not zero
        hevm.expectRevert(ScrollChain.ErrorGenesisBatchHasNonZeroField.selector);
        rollup.importGenesisBatch(batchHeader, bytes32(uint256(1)));

        batchHeader = new bytes(89);
        batchHeader[1] = bytes1(uint8(1)); // batchIndex not zero
        hevm.expectRevert(ScrollChain.ErrorGenesisBatchHasNonZeroField.selector);
        rollup.importGenesisBatch(batchHeader, bytes32(uint256(1)));

        batchHeader = new bytes(89 + 32);
        assembly {
            mstore(add(batchHeader, add(0x20, 9)), shl(192, 1)) // l1MessagePopped not zero
        }
        hevm.expectRevert(ScrollChain.ErrorGenesisBatchHasNonZeroField.selector);
        rollup.importGenesisBatch(batchHeader, bytes32(uint256(1)));

        batchHeader = new bytes(89);
        batchHeader[17] = bytes1(uint8(1)); // totalL1MessagePopped not zero
        hevm.expectRevert(ScrollChain.ErrorGenesisBatchHasNonZeroField.selector);
        rollup.importGenesisBatch(batchHeader, bytes32(uint256(1)));

        // zero data hash, revert
        batchHeader = new bytes(89);
        hevm.expectRevert(ScrollChain.ErrorGenesisDataHashIsZero.selector);
        rollup.importGenesisBatch(batchHeader, bytes32(uint256(1)));

        // nonzero parent batch hash, revert
        batchHeader = new bytes(89);
        batchHeader[25] = bytes1(uint8(1)); // dataHash not zero
        batchHeader[57] = bytes1(uint8(1)); // parentBatchHash not zero
        hevm.expectRevert(ScrollChain.ErrorGenesisParentBatchHashIsNonZero.selector);
        rollup.importGenesisBatch(batchHeader, bytes32(uint256(1)));

        // import correctly
        batchHeader = new bytes(89);
        batchHeader[25] = bytes1(uint8(1)); // dataHash not zero
        assertEq(rollup.finalizedStateRoots(0), bytes32(0));
        assertEq(rollup.withdrawRoots(0), bytes32(0));
        assertEq(rollup.committedBatches(0), bytes32(0));
        rollup.importGenesisBatch(batchHeader, bytes32(uint256(1)));
        assertEq(rollup.finalizedStateRoots(0), bytes32(uint256(1)));
        assertEq(rollup.withdrawRoots(0), bytes32(0));
        assertGt(uint256(rollup.committedBatches(0)), 0);

        // Genesis batch imported, revert
        hevm.expectRevert(ScrollChain.ErrorGenesisBatchImported.selector);
        rollup.importGenesisBatch(batchHeader, bytes32(uint256(1)));
    }

    function _deployProxy(address _logic) internal returns (address) {
        if (_logic == address(0)) _logic = address(placeholder);
        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(_logic, address(admin), new bytes(0));
        return address(proxy);
    }

    function _upgradeToMockBlob() internal {
        // upgrade to ScrollChainMockBlob for data mocking
        ScrollChainMockBlob impl = new ScrollChainMockBlob(
            rollup.layer2ChainId(),
            rollup.messageQueue(),
            rollup.verifier()
        );
        admin.upgrade(ITransparentUpgradeableProxy(address(rollup)), address(impl));
        // from https://etherscan.io/blob/0x013590dc3544d56629ba81bb14d4d31248f825001653aa575eb8e3a719046757?bid=740652
        bytes32 blobVersionedHash = 0x013590dc3544d56629ba81bb14d4d31248f825001653aa575eb8e3a719046757;
        ScrollChainMockBlob(address(rollup)).setBlobVersionedHash(blobVersionedHash);
    }

    /// @dev Prepare 10 batches, each of the first 5 has 2 l1 messages, each of the second 5 has no l1 message.
    function _prepareFinalizeBundle() internal returns (bytes[] memory headers) {
        // grant roles
        rollup.addProver(address(0));
        rollup.addSequencer(address(0));
        _upgradeToMockBlob();

        headers = new bytes[](11);
        // import 20 L1 messages
        for (uint256 i = 0; i < 20; i++) {
            messageQueue.appendCrossDomainMessage(address(this), 1000000, new bytes(0));
        }
        // commit genesis batch
        headers[0] = _commitGenesisBatch();
        // commit 5 batches, each has 2 l1 messages
        for (uint256 i = 1; i <= 5; ++i) {
            headers[i] = _commitBatch(4, headers[i - 1], 2);
        }
        // commit 5 batches, each has 0 l1 message
        for (uint256 i = 6; i <= 10; ++i) {
            headers[i] = _commitBatch(4, headers[i - 1], 0);
        }
    }

    function _commitGenesisBatch() internal returns (bytes memory header) {
        header = new bytes(89);
        assembly {
            mstore(add(header, add(0x20, 25)), 1)
        }
        rollup.importGenesisBatch(header, bytes32(uint256(1)));
        assertEq(rollup.committedBatches(0), keccak256(header));
    }

    function _constructBatchStruct(
        uint8 version,
        bytes memory parentHeader,
        uint256 numL1Message
    )
        internal
        view
        returns (
            bytes memory bitmap,
            bytes[] memory chunks,
            bytes memory blobDataProof,
            uint256 index,
            uint256 totalL1MessagePopped,
            bytes memory header
        )
    {
        uint256 batchPtr;
        assembly {
            batchPtr := add(parentHeader, 0x20)
        }
        index = BatchHeaderV0Codec.getBatchIndex(batchPtr) + 1;
        totalL1MessagePopped = BatchHeaderV0Codec.getTotalL1MessagePopped(batchPtr) + numL1Message;
        bytes32 parentHash = keccak256(parentHeader);
        blobDataProof = hex"2c9d777660f14ad49803a6442935c0d24a0d83551de5995890bf70a17d24e68753ab0fe6807c7081f0885fe7da741554d658a03730b1fa006f8319f8b993bcb0a5a0c9e8a145c5ef6e415c245690effa2914ec9393f58a7251d30c0657da1453d9ad906eae8b97dd60c9a216f81b4df7af34d01e214e1ec5865f0133ecc16d7459e49dab66087340677751e82097fbdd20551d66076f425775d1758a9dfd186b";
        bytes32[] memory hashes = new bytes32[](numL1Message);
        for (uint256 i = 0; i < numL1Message; ++i) {
            hashes[i] = messageQueue.getCrossDomainMessage(BatchHeaderV0Codec.getTotalL1MessagePopped(batchPtr) + i);
        }
        // commit batch, one chunk with one block, 1 + numL1Message tx, numL1Message L1 message
        // payload for data hash of chunk0
        //   hex(index)                                                         // block number
        //   hex(index)                                                         // timestamp
        //   0000000000000000000000000000000000000000000000000000000000000000   // baseFee
        //   0000000000000000                                                   // gasLimit
        //   hex(1 + numL1Message)                                              // numTransactions
        //   ...                                                                // l1 messages
        // data hash for chunk0
        //   keccak256(chunk0)
        // data hash for all chunks
        //   keccak256(keccak256(chunk0))
        // => payload for batch header
        //   03                                                                 // version
        //   hex(index)                                                         // batchIndex
        //   hex(numL1Message)                                                  // l1MessagePopped
        //   hex(totalL1MessagePopped)                                          // totalL1MessagePopped
        //   keccak256(keccak256(chunk0))                                       // dataHash
        //   013590dc3544d56629ba81bb14d4d31248f825001653aa575eb8e3a719046757   // blobVersionedHash
        //   keccak256(parentHeader)                                            // parentBatchHash
        //   hex(index)                                                         // lastBlockTimestamp
        //   2c9d777660f14ad49803a6442935c0d24a0d83551de5995890bf70a17d24e687   // blobDataProof
        //   53ab0fe6807c7081f0885fe7da741554d658a03730b1fa006f8319f8b993bcb0   // blobDataProof
        if (numL1Message > 0) bitmap = new bytes(32);
        chunks = new bytes[](1);
        bytes memory chunk0;
        chunk0 = new bytes(1 + 60);
        assembly {
            mstore(add(chunk0, 0x20), shl(248, 1)) // numBlocks = 1
            mstore(add(chunk0, add(0x21, 8)), shl(192, index)) // timestamp = 0x123
            mstore(add(chunk0, add(0x21, 56)), shl(240, add(numL1Message, 1))) // numTransactions = 1 + numL1Message
            mstore(add(chunk0, add(0x21, 58)), shl(240, numL1Message)) // numL1Messages
        }
        chunks[0] = chunk0;
        bytes memory chunkData = new bytes(58 + numL1Message * 32);
        assembly {
            mcopy(add(chunkData, 0x20), add(chunk0, 0x21), 58)
            mcopy(add(chunkData, 0x5a), add(hashes, 0x20), mul(32, mload(hashes)))
        }
        bytes32 dataHash = keccak256(abi.encode(keccak256(chunkData)));
        header = new bytes(193);
        assembly {
            mstore8(add(header, 0x20), version) // version
            mstore(add(header, add(0x20, 1)), shl(192, index)) // batchIndex
            mstore(add(header, add(0x20, 9)), shl(192, numL1Message)) // l1MessagePopped
            mstore(add(header, add(0x20, 17)), shl(192, totalL1MessagePopped)) // totalL1MessagePopped
            mstore(add(header, add(0x20, 25)), dataHash) // dataHash
            mstore(add(header, add(0x20, 57)), 0x013590dc3544d56629ba81bb14d4d31248f825001653aa575eb8e3a719046757) // blobVersionedHash
            mstore(add(header, add(0x20, 89)), parentHash) // parentBatchHash
            mstore(add(header, add(0x20, 121)), shl(192, index)) // lastBlockTimestamp
            mcopy(add(header, add(0x20, 129)), add(blobDataProof, 0x20), 64) // blobDataProof
        }
    }

    function _commitBatch(
        uint8 version,
        bytes memory parentHeader,
        uint256 numL1Message
    ) internal returns (bytes memory) {
        (
            bytes memory bitmap,
            bytes[] memory chunks,
            bytes memory blobDataProof,
            uint256 index,
            uint256 totalL1MessagePopped,
            bytes memory header
        ) = _constructBatchStruct(version, parentHeader, numL1Message);
        hevm.startPrank(address(0));
        if (numL1Message > 0) {
            hevm.expectEmit(false, false, false, true);
            emit DequeueTransaction(totalL1MessagePopped - numL1Message, numL1Message, 0);
        }
        hevm.expectEmit(true, true, false, true);
        emit CommitBatch(index, keccak256(header));
        rollup.commitBatchWithBlobProof(version, parentHeader, chunks, bitmap, blobDataProof);
        hevm.stopPrank();
        assertEq(rollup.committedBatches(index), keccak256(header));
        assertEq(messageQueue.pendingQueueIndex(), totalL1MessagePopped);
        return header;
    }
}
