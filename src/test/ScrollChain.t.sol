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
    event RevertBatch(uint256 indexed batchIndex, bytes32 indexed batchHash);
    event VerifyBatchWithZkp(
        uint256 indexed batchIndex,
        bytes32 indexed batchHash,
        bytes32 stateRoot,
        bytes32 withdrawRoot
    );
    event VerifyBatchWithTee(
        uint256 indexed batchIndex,
        bytes32 indexed batchHash,
        bytes32 stateRoot,
        bytes32 withdrawRoot
    );
    event FinalizeBatch(uint256 indexed batchIndex, bytes32 indexed batchHash, bytes32 stateRoot, bytes32 withdrawRoot);
    event StateMismatch(uint256 indexed batchIndex, bytes32 stateRoot, bytes32 withdrawRoot);
    event ResolveState(uint256 indexed batchIndex, bytes32 stateRoot, bytes32 withdrawRoot);
    event ChangeBundleSize(uint256 index, uint256 size, uint256 batchIndex);

    // from L1MessageQueue
    event DequeueTransaction(uint256 startIndex, uint256 count, uint256 skippedBitmap);
    event ResetDequeuedTransaction(uint256 startIndex);
    event FinalizedDequeuedTransaction(uint256 finalizedIndex);

    ProxyAdmin internal admin;
    EmptyContract private placeholder;

    ScrollChain private rollup;
    L1MessageQueue internal messageQueue;
    MockRollupVerifier internal zkpVerifier;
    MockRollupVerifier internal teeVerifier;

    function setUp() public {
        placeholder = new EmptyContract();
        admin = new ProxyAdmin();
        messageQueue = L1MessageQueue(_deployProxy(address(0)));
        rollup = ScrollChain(_deployProxy(address(0)));
        zkpVerifier = new MockRollupVerifier();
        teeVerifier = new MockRollupVerifier();

        // Upgrade the L1MessageQueue implementation and initialize
        admin.upgrade(
            ITransparentUpgradeableProxy(address(messageQueue)),
            address(new L1MessageQueue(address(this), address(rollup), address(1)))
        );
        messageQueue.initialize(address(this), address(rollup), address(0), address(0), 10000000);
        // Upgrade the ScrollChain implementation and initialize
        admin.upgrade(
            ITransparentUpgradeableProxy(address(rollup)),
            address(new ScrollChain(233, address(messageQueue), address(zkpVerifier), address(teeVerifier), 0))
        );
        rollup.initialize(address(messageQueue), address(zkpVerifier), 100);
        rollup.initializeV2(1);
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
        rollup.commitBatchWithBlobProof(3, batchHeader0, new bytes[](0), new bytes(0), new bytes(0));
        rollup.addSequencer(address(0));

        // revert when ErrorIncorrectBatchVersion
        hevm.startPrank(address(0));
        hevm.expectRevert(ScrollChain.ErrorIncorrectBatchVersion.selector);
        rollup.commitBatchWithBlobProof(2, batchHeader0, new bytes[](0), new bytes(0), new bytes(0));
        hevm.stopPrank();

        // revert when ErrorBatchIsEmpty
        hevm.startPrank(address(0));
        hevm.expectRevert(ScrollChain.ErrorBatchIsEmpty.selector);
        rollup.commitBatchWithBlobProof(3, batchHeader0, new bytes[](0), new bytes(0), new bytes(0));
        hevm.stopPrank();

        // revert when ErrorBatchHeaderV3LengthMismatch
        bytes memory header = new bytes(192);
        assembly {
            mstore8(add(header, 0x20), 3) // version
        }
        hevm.startPrank(address(0));
        hevm.expectRevert(BatchHeaderV3Codec.ErrorBatchHeaderV3LengthMismatch.selector);
        rollup.commitBatchWithBlobProof(3, header, new bytes[](1), new bytes(0), new bytes(0));
        hevm.stopPrank();

        // revert when ErrorIncorrectBatchHash
        assembly {
            mstore(add(batchHeader0, add(0x20, 25)), 2) // change data hash for batch0
        }
        hevm.startPrank(address(0));
        hevm.expectRevert(ScrollChain.ErrorIncorrectBatchHash.selector);
        rollup.commitBatchWithBlobProof(3, batchHeader0, new bytes[](1), new bytes(0), new bytes(0));
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
        rollup.commitBatchWithBlobProof(3, batchHeader0, chunks, new bytes(0), new bytes(0));
        hevm.stopPrank();

        // invalid chunk length, revert
        chunk0 = new bytes(1);
        chunk0[0] = bytes1(uint8(1)); // one block in this chunk
        chunks[0] = chunk0;
        hevm.startPrank(address(0));
        hevm.expectRevert(ChunkCodecV1.ErrorIncorrectChunkLengthV1.selector);
        rollup.commitBatchWithBlobProof(3, batchHeader0, chunks, new bytes(0), new bytes(0));
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
        rollup.commitBatchWithBlobProof(3, batchHeader0, chunks, bitmap, new bytes(0));
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
        rollup.commitBatchWithBlobProof(3, batchHeader0, chunks, bitmap, new bytes(0));
        hevm.stopPrank();

        // revert when ErrorNoBlobFound
        // revert when ErrorNoBlobFound
        chunk0 = new bytes(1 + 60);
        chunk0[0] = bytes1(uint8(1)); // one block in this chunk
        chunks[0] = chunk0;
        hevm.startPrank(address(0));
        hevm.expectRevert(ScrollChain.ErrorNoBlobFound.selector);
        rollup.commitBatchWithBlobProof(3, batchHeader0, chunks, new bytes(0), new bytes(0));
        hevm.stopPrank();

        // @note we cannot check `ErrorFoundMultipleBlobs` here

        // upgrade to ScrollChainMockBlob
        ScrollChainMockBlob impl = new ScrollChainMockBlob(
            rollup.layer2ChainId(),
            rollup.messageQueue(),
            rollup.zkpVerifier(),
            rollup.teeVerifier(),
            0
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
        rollup.commitBatchWithBlobProof(3, batchHeader0, chunks, new bytes(0), new bytes(0));
        hevm.stopPrank();

        bytes32 batchHash0 = rollup.committedBatches(0);
        bytes memory batchHeader1 = new bytes(193);
        assembly {
            mstore8(add(batchHeader1, 0x20), 3) // version
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
        rollup.commitBatchWithBlobProof(3, batchHeader0, chunks, new bytes(0), blobDataProof);
        hevm.stopPrank();
        assertEq(rollup.committedBatches(1), keccak256(batchHeader1));

        // revert when ErrorBatchIsAlreadyCommitted
        hevm.startPrank(address(0));
        hevm.expectRevert(ScrollChain.ErrorBatchIsAlreadyCommitted.selector);
        rollup.commitBatchWithBlobProof(3, batchHeader0, chunks, new bytes(0), blobDataProof);
        hevm.stopPrank();
    }

    function testFinalizeBundleWithOnlyZkProof() external {
        hevm.warp(100000);

        // revert ErrorCallerIsNotProver
        hevm.expectRevert(ScrollChain.ErrorCallerIsNotProver.selector);
        rollup.finalizeBundleWithProof(new bytes(0), bytes32(0), bytes32(0), new bytes(0));

        bytes[] memory headers = _prepareFinalizeBundle();

        // revert when ErrorBatchHeaderV3LengthMismatch
        bytes memory header = new bytes(192);
        assembly {
            mstore8(add(header, 0x20), 3) // version
        }
        hevm.startPrank(address(0));
        hevm.expectRevert(BatchHeaderV3Codec.ErrorBatchHeaderV3LengthMismatch.selector);
        rollup.finalizeBundleWithProof(header, bytes32(uint256(1)), bytes32(uint256(2)), new bytes(0));
        hevm.stopPrank();

        // revert ErrorIncorrectBatchHash
        headers[1][1] = bytes1(uint8(1)); // change random byte
        hevm.startPrank(address(0));
        hevm.expectRevert(ScrollChain.ErrorIncorrectBatchHash.selector);
        rollup.finalizeBundleWithProof(headers[1], bytes32(uint256(1)), bytes32(uint256(2)), new bytes(0));
        hevm.stopPrank();
        headers[1][1] = bytes1(uint8(0)); // change back

        // revert ErrorBundleSizeMismatch
        hevm.startPrank(address(0));
        hevm.expectRevert(ScrollChain.ErrorBundleSizeMismatch.selector);
        rollup.finalizeBundleWithProof(headers[2], bytes32(uint256(1)), bytes32(uint256(2)), new bytes(0));
        hevm.stopPrank();

        // only enable zk proof
        ScrollChainMockBlob(address(rollup)).setEnabledProofTypeMask(1);

        // revert ErrorFinalizationPaused
        hevm.startPrank(address(0));
        hevm.expectRevert(ScrollChain.ErrorFinalizationPaused.selector);
        rollup.finalizeBundleWithTeeProof(headers[1], bytes32(uint256(1001)), bytes32(uint256(2001)), new bytes(0));
        hevm.stopPrank();

        // prove batch 1, bundle size = 1
        hevm.startPrank(address(0));
        hevm.expectEmit(true, false, false, true);
        emit VerifyBatchWithZkp(1, keccak256(headers[1]), bytes32(uint256(1001)), bytes32(uint256(2001)));
        hevm.expectEmit(false, false, false, true);
        emit FinalizedDequeuedTransaction(1);
        hevm.expectEmit(true, false, false, true);
        emit FinalizeBatch(1, keccak256(headers[1]), bytes32(uint256(1001)), bytes32(uint256(2001)));
        rollup.finalizeBundleWithProof(headers[1], bytes32(uint256(1001)), bytes32(uint256(2001)), new bytes(0));
        hevm.stopPrank();
        assertEq(rollup.lastTeeVerifiedBatchIndex(), 0);
        assertEq(rollup.lastZkpVerifiedBatchIndex(), 1);
        assertEq(rollup.lastFinalizedBatchIndex(), 1);
        assertEq(rollup.finalizedStateRoots(1), bytes32(uint256(1001)));
        assertEq(rollup.withdrawRoots(1), bytes32(uint256(2001)));
        ScrollChainMockBlob(address(rollup)).setBatchCommittedTimestamp(1, block.timestamp - 99);
        assertBoolEq(rollup.isBatchFinalized(1), false);
        ScrollChainMockBlob(address(rollup)).setBatchCommittedTimestamp(1, block.timestamp - 100);
        assertBoolEq(rollup.isBatchFinalized(1), true);
        assertEq(messageQueue.nextUnfinalizedQueueIndex(), 2);

        // change bundle size to 3, starting with batch index 3
        rollup.updateBundleSize(3, 2);

        // prove batch 2, bundle size = 1
        hevm.startPrank(address(0));
        hevm.expectEmit(true, false, false, true);
        emit VerifyBatchWithZkp(2, keccak256(headers[2]), bytes32(uint256(1002)), bytes32(uint256(2002)));
        hevm.expectEmit(false, false, false, true);
        emit FinalizedDequeuedTransaction(3);
        hevm.expectEmit(true, false, false, true);
        emit FinalizeBatch(2, keccak256(headers[2]), bytes32(uint256(1002)), bytes32(uint256(2002)));
        rollup.finalizeBundleWithProof(headers[2], bytes32(uint256(1002)), bytes32(uint256(2002)), new bytes(0));
        hevm.stopPrank();
        assertEq(rollup.lastTeeVerifiedBatchIndex(), 0);
        assertEq(rollup.lastZkpVerifiedBatchIndex(), 2);
        assertEq(rollup.lastFinalizedBatchIndex(), 2);
        assertEq(rollup.finalizedStateRoots(2), bytes32(uint256(1002)));
        assertEq(rollup.withdrawRoots(2), bytes32(uint256(2002)));
        assertEq(messageQueue.nextUnfinalizedQueueIndex(), 4);

        // change bundle size to 5, starting with batch index 6
        rollup.updateBundleSize(5, 5);

        // prove batch 3~5, bundle size = 3
        hevm.startPrank(address(0));
        hevm.expectEmit(true, false, false, true);
        emit VerifyBatchWithZkp(5, keccak256(headers[5]), bytes32(uint256(1005)), bytes32(uint256(2005)));
        hevm.expectEmit(false, false, false, true);
        emit FinalizedDequeuedTransaction(9);
        hevm.expectEmit(true, false, false, true);
        emit FinalizeBatch(5, keccak256(headers[5]), bytes32(uint256(1005)), bytes32(uint256(2005)));
        rollup.finalizeBundleWithProof(headers[5], bytes32(uint256(1005)), bytes32(uint256(2005)), new bytes(0));
        hevm.stopPrank();
        assertEq(rollup.lastTeeVerifiedBatchIndex(), 0);
        assertEq(rollup.lastZkpVerifiedBatchIndex(), 5);
        assertEq(rollup.lastFinalizedBatchIndex(), 5);
        assertEq(rollup.finalizedStateRoots(5), bytes32(uint256(1005)));
        assertEq(rollup.withdrawRoots(5), bytes32(uint256(2005)));
        assertEq(messageQueue.nextUnfinalizedQueueIndex(), 10);

        // prove batch 6~10, bundle size = 5
        hevm.startPrank(address(0));
        hevm.expectEmit(true, false, false, true);
        emit VerifyBatchWithZkp(10, keccak256(headers[10]), bytes32(uint256(1010)), bytes32(uint256(2010)));
        hevm.expectEmit(true, false, false, true);
        emit FinalizeBatch(10, keccak256(headers[10]), bytes32(uint256(1010)), bytes32(uint256(2010)));
        rollup.finalizeBundleWithProof(headers[10], bytes32(uint256(1010)), bytes32(uint256(2010)), new bytes(0));
        hevm.stopPrank();
        assertEq(rollup.lastTeeVerifiedBatchIndex(), 0);
        assertEq(rollup.lastZkpVerifiedBatchIndex(), 10);
        assertEq(rollup.lastFinalizedBatchIndex(), 10);
        assertEq(rollup.finalizedStateRoots(10), bytes32(uint256(1010)));
        assertEq(rollup.withdrawRoots(10), bytes32(uint256(2010)));
        assertEq(messageQueue.nextUnfinalizedQueueIndex(), 10);
    }

    function testFinalizeBundleWithOnlyTeeProof() external {
        hevm.warp(100000);

        bytes[] memory headers = _prepareFinalizeBundle();

        // revert when ErrorBatchHeaderV3LengthMismatch
        bytes memory header = new bytes(192);
        assembly {
            mstore8(add(header, 0x20), 3) // version
        }
        hevm.startPrank(address(0));
        hevm.expectRevert(BatchHeaderV3Codec.ErrorBatchHeaderV3LengthMismatch.selector);
        rollup.finalizeBundleWithTeeProof(header, bytes32(uint256(1)), bytes32(uint256(2)), new bytes(0));
        hevm.stopPrank();

        // revert ErrorIncorrectBatchHash
        headers[1][1] = bytes1(uint8(1)); // change random byte
        hevm.startPrank(address(0));
        hevm.expectRevert(ScrollChain.ErrorIncorrectBatchHash.selector);
        rollup.finalizeBundleWithTeeProof(headers[1], bytes32(uint256(1)), bytes32(uint256(2)), new bytes(0));
        hevm.stopPrank();
        headers[1][1] = bytes1(uint8(0)); // change back

        // revert ErrorBundleSizeMismatch
        hevm.startPrank(address(0));
        hevm.expectRevert(ScrollChain.ErrorBundleSizeMismatch.selector);
        rollup.finalizeBundleWithTeeProof(headers[2], bytes32(uint256(1)), bytes32(uint256(2)), new bytes(0));
        hevm.stopPrank();

        // only enable zk proof
        ScrollChainMockBlob(address(rollup)).setEnabledProofTypeMask(2);

        // revert ErrorFinalizationPaused
        hevm.startPrank(address(0));
        hevm.expectRevert(ScrollChain.ErrorFinalizationPaused.selector);
        rollup.finalizeBundleWithProof(headers[1], bytes32(uint256(1001)), bytes32(uint256(2001)), new bytes(0));
        hevm.stopPrank();

        // prove batch 1, bundle size = 1
        hevm.startPrank(address(0));
        hevm.expectEmit(true, false, false, true);
        emit VerifyBatchWithTee(1, keccak256(headers[1]), bytes32(uint256(1001)), bytes32(uint256(2001)));
        hevm.expectEmit(false, false, false, true);
        emit FinalizedDequeuedTransaction(1);
        hevm.expectEmit(true, false, false, true);
        emit FinalizeBatch(1, keccak256(headers[1]), bytes32(uint256(1001)), bytes32(uint256(2001)));
        rollup.finalizeBundleWithTeeProof(headers[1], bytes32(uint256(1001)), bytes32(uint256(2001)), new bytes(0));
        hevm.stopPrank();
        assertEq(rollup.lastZkpVerifiedBatchIndex(), 0);
        assertEq(rollup.lastTeeVerifiedBatchIndex(), 1);
        assertEq(rollup.lastFinalizedBatchIndex(), 1);
        assertEq(rollup.finalizedStateRoots(1), bytes32(uint256(1001)));
        assertEq(rollup.withdrawRoots(1), bytes32(uint256(2001)));
        ScrollChainMockBlob(address(rollup)).setBatchCommittedTimestamp(1, block.timestamp - 99);
        assertBoolEq(rollup.isBatchFinalized(1), false);
        ScrollChainMockBlob(address(rollup)).setBatchCommittedTimestamp(1, block.timestamp - 100);
        assertBoolEq(rollup.isBatchFinalized(1), true);
        assertEq(messageQueue.nextUnfinalizedQueueIndex(), 2);

        // change bundle size to 3, starting with batch index 3
        rollup.updateBundleSize(3, 2);

        // prove batch 2, bundle size = 1
        hevm.startPrank(address(0));
        hevm.expectEmit(true, false, false, true);
        emit VerifyBatchWithTee(2, keccak256(headers[2]), bytes32(uint256(1002)), bytes32(uint256(2002)));
        hevm.expectEmit(false, false, false, true);
        emit FinalizedDequeuedTransaction(3);
        hevm.expectEmit(true, false, false, true);
        emit FinalizeBatch(2, keccak256(headers[2]), bytes32(uint256(1002)), bytes32(uint256(2002)));
        rollup.finalizeBundleWithTeeProof(headers[2], bytes32(uint256(1002)), bytes32(uint256(2002)), new bytes(0));
        hevm.stopPrank();
        assertEq(rollup.lastZkpVerifiedBatchIndex(), 0);
        assertEq(rollup.lastTeeVerifiedBatchIndex(), 2);
        assertEq(rollup.lastFinalizedBatchIndex(), 2);
        assertEq(rollup.finalizedStateRoots(2), bytes32(uint256(1002)));
        assertEq(rollup.withdrawRoots(2), bytes32(uint256(2002)));
        assertEq(messageQueue.nextUnfinalizedQueueIndex(), 4);

        // change bundle size to 5, starting with batch index 6
        rollup.updateBundleSize(5, 5);

        // prove batch 3~5, bundle size = 3
        hevm.startPrank(address(0));
        hevm.expectEmit(true, false, false, true);
        emit VerifyBatchWithTee(5, keccak256(headers[5]), bytes32(uint256(1005)), bytes32(uint256(2005)));
        hevm.expectEmit(false, false, false, true);
        emit FinalizedDequeuedTransaction(9);
        hevm.expectEmit(true, false, false, true);
        emit FinalizeBatch(5, keccak256(headers[5]), bytes32(uint256(1005)), bytes32(uint256(2005)));
        rollup.finalizeBundleWithTeeProof(headers[5], bytes32(uint256(1005)), bytes32(uint256(2005)), new bytes(0));
        hevm.stopPrank();
        assertEq(rollup.lastZkpVerifiedBatchIndex(), 0);
        assertEq(rollup.lastTeeVerifiedBatchIndex(), 5);
        assertEq(rollup.lastFinalizedBatchIndex(), 5);
        assertEq(rollup.finalizedStateRoots(5), bytes32(uint256(1005)));
        assertEq(rollup.withdrawRoots(5), bytes32(uint256(2005)));
        assertEq(messageQueue.nextUnfinalizedQueueIndex(), 10);

        // prove batch 6~10, bundle size = 5
        hevm.startPrank(address(0));
        hevm.expectEmit(true, false, false, true);
        emit VerifyBatchWithTee(10, keccak256(headers[10]), bytes32(uint256(1010)), bytes32(uint256(2010)));
        hevm.expectEmit(true, false, false, true);
        emit FinalizeBatch(10, keccak256(headers[10]), bytes32(uint256(1010)), bytes32(uint256(2010)));
        rollup.finalizeBundleWithTeeProof(headers[10], bytes32(uint256(1010)), bytes32(uint256(2010)), new bytes(0));
        hevm.stopPrank();
        assertEq(rollup.lastZkpVerifiedBatchIndex(), 0);
        assertEq(rollup.lastTeeVerifiedBatchIndex(), 10);
        assertEq(rollup.lastFinalizedBatchIndex(), 10);
        assertEq(rollup.finalizedStateRoots(10), bytes32(uint256(1010)));
        assertEq(rollup.withdrawRoots(10), bytes32(uint256(2010)));
        assertEq(messageQueue.nextUnfinalizedQueueIndex(), 10);
    }

    function testFinalizeBundleWithBothProof() external {
        bytes[] memory headers = _prepareFinalizeBundle();

        // verify batch 1 with tee, bundle size = 1
        hevm.startPrank(address(0));
        hevm.expectEmit(true, false, false, true);
        emit VerifyBatchWithTee(1, keccak256(headers[1]), bytes32(uint256(1001)), bytes32(uint256(2001)));
        rollup.finalizeBundleWithTeeProof(headers[1], bytes32(uint256(1001)), bytes32(uint256(2001)), new bytes(0));
        hevm.stopPrank();
        assertEq(rollup.lastZkpVerifiedBatchIndex(), 0);
        assertEq(rollup.lastTeeVerifiedBatchIndex(), 1);
        assertEq(rollup.lastFinalizedBatchIndex(), 0);
        assertEq(rollup.finalizedStateRoots(1), bytes32(uint256(1001)));
        assertEq(rollup.withdrawRoots(1), bytes32(uint256(2001)));
        assertBoolEq(rollup.isBatchFinalized(1), false);

        // verify batch 1 with zkp, bundle size = 1
        hevm.startPrank(address(0));
        hevm.expectEmit(true, false, false, true);
        emit VerifyBatchWithZkp(1, keccak256(headers[1]), bytes32(uint256(1001)), bytes32(uint256(2001)));
        hevm.expectEmit(false, false, false, true);
        emit FinalizedDequeuedTransaction(1);
        hevm.expectEmit(true, false, false, true);
        emit FinalizeBatch(1, keccak256(headers[1]), bytes32(uint256(1001)), bytes32(uint256(2001)));
        rollup.finalizeBundleWithProof(headers[1], bytes32(uint256(1001)), bytes32(uint256(2001)), new bytes(0));
        hevm.stopPrank();
        assertEq(rollup.lastZkpVerifiedBatchIndex(), 1);
        assertEq(rollup.lastTeeVerifiedBatchIndex(), 1);
        assertEq(rollup.lastFinalizedBatchIndex(), 1);
        assertEq(rollup.finalizedStateRoots(1), bytes32(uint256(1001)));
        assertEq(rollup.withdrawRoots(1), bytes32(uint256(2001)));
        assertBoolEq(rollup.isBatchFinalized(1), true);
        assertEq(messageQueue.nextUnfinalizedQueueIndex(), 2);

        // change bundle size to 3, starting with batch index 3
        rollup.updateBundleSize(3, 2);

        // verify batch 2 with zkp, bundle size = 1
        hevm.startPrank(address(0));
        hevm.expectEmit(true, false, false, true);
        emit VerifyBatchWithZkp(2, keccak256(headers[2]), bytes32(uint256(1002)), bytes32(uint256(2002)));
        rollup.finalizeBundleWithProof(headers[2], bytes32(uint256(1002)), bytes32(uint256(2002)), new bytes(0));
        hevm.stopPrank();
        assertEq(rollup.lastZkpVerifiedBatchIndex(), 2);
        assertEq(rollup.lastTeeVerifiedBatchIndex(), 1);
        assertEq(rollup.lastFinalizedBatchIndex(), 1);
        assertEq(rollup.finalizedStateRoots(2), bytes32(uint256(1002)));
        assertEq(rollup.withdrawRoots(2), bytes32(uint256(2002)));
        assertEq(messageQueue.nextUnfinalizedQueueIndex(), 2);

        // verify batch 2 with tee, bundle size = 1
        hevm.startPrank(address(0));
        hevm.expectEmit(true, false, false, true);
        emit VerifyBatchWithTee(2, keccak256(headers[2]), bytes32(uint256(1002)), bytes32(uint256(2002)));
        hevm.expectEmit(false, false, false, true);
        emit FinalizedDequeuedTransaction(3);
        hevm.expectEmit(true, false, false, true);
        emit FinalizeBatch(2, keccak256(headers[2]), bytes32(uint256(1002)), bytes32(uint256(2002)));
        rollup.finalizeBundleWithTeeProof(headers[2], bytes32(uint256(1002)), bytes32(uint256(2002)), new bytes(0));
        hevm.stopPrank();
        assertEq(rollup.lastZkpVerifiedBatchIndex(), 2);
        assertEq(rollup.lastTeeVerifiedBatchIndex(), 2);
        assertEq(rollup.lastFinalizedBatchIndex(), 2);
        assertEq(rollup.finalizedStateRoots(2), bytes32(uint256(1002)));
        assertEq(rollup.withdrawRoots(2), bytes32(uint256(2002)));
        assertEq(messageQueue.nextUnfinalizedQueueIndex(), 4);

        // change bundle size to 5, starting with batch index 6
        rollup.updateBundleSize(5, 5);

        // prove batch 3~5 with tee and then zkp, bundle size = 3
        hevm.startPrank(address(0));
        hevm.expectEmit(true, false, false, true);
        emit VerifyBatchWithTee(5, keccak256(headers[5]), bytes32(uint256(1005)), bytes32(uint256(2005)));
        rollup.finalizeBundleWithTeeProof(headers[5], bytes32(uint256(1005)), bytes32(uint256(2005)), new bytes(0));
        hevm.expectEmit(true, false, false, true);
        emit VerifyBatchWithZkp(5, keccak256(headers[5]), bytes32(uint256(1005)), bytes32(uint256(2005)));
        hevm.expectEmit(false, false, false, true);
        emit FinalizedDequeuedTransaction(9);
        hevm.expectEmit(true, false, false, true);
        emit FinalizeBatch(5, keccak256(headers[5]), bytes32(uint256(1005)), bytes32(uint256(2005)));
        rollup.finalizeBundleWithProof(headers[5], bytes32(uint256(1005)), bytes32(uint256(2005)), new bytes(0));
        hevm.stopPrank();
        assertEq(rollup.lastZkpVerifiedBatchIndex(), 5);
        assertEq(rollup.lastTeeVerifiedBatchIndex(), 5);
        assertEq(rollup.lastFinalizedBatchIndex(), 5);
        assertEq(rollup.finalizedStateRoots(5), bytes32(uint256(1005)));
        assertEq(rollup.withdrawRoots(5), bytes32(uint256(2005)));
        assertEq(messageQueue.nextUnfinalizedQueueIndex(), 10);

        // prove batch 6~10 with zkp and then tee, bundle size = 5
        hevm.startPrank(address(0));
        hevm.expectEmit(true, false, false, true);
        emit VerifyBatchWithZkp(10, keccak256(headers[10]), bytes32(uint256(1010)), bytes32(uint256(2010)));
        rollup.finalizeBundleWithProof(headers[10], bytes32(uint256(1010)), bytes32(uint256(2010)), new bytes(0));
        hevm.expectEmit(true, false, false, true);
        emit VerifyBatchWithTee(10, keccak256(headers[10]), bytes32(uint256(1010)), bytes32(uint256(2010)));
        hevm.expectEmit(true, false, false, true);
        emit FinalizeBatch(10, keccak256(headers[10]), bytes32(uint256(1010)), bytes32(uint256(2010)));
        rollup.finalizeBundleWithTeeProof(headers[10], bytes32(uint256(1010)), bytes32(uint256(2010)), new bytes(0));
        hevm.stopPrank();
        assertEq(rollup.lastZkpVerifiedBatchIndex(), 10);
        assertEq(rollup.lastTeeVerifiedBatchIndex(), 10);
        assertEq(rollup.lastFinalizedBatchIndex(), 10);
        assertEq(rollup.finalizedStateRoots(10), bytes32(uint256(1010)));
        assertEq(rollup.withdrawRoots(10), bytes32(uint256(2010)));
        assertEq(messageQueue.nextUnfinalizedQueueIndex(), 10);
    }

    function testFinalizeBundleWithBothProofMismatch() external {
        // 11 batches, including genesis
        bytes[] memory headers = _prepareFinalizeBundle();

        // revert ErrorNoUnresolvedState
        hevm.expectRevert(ScrollChain.ErrorNoUnresolvedState.selector);
        rollup.resolveStateMismatch(headers[1], false);

        (ScrollChain.ProofType urProofType, uint248 urBatchIndex, bytes32 urStateRoot, bytes32 urWithdrawRoot) = rollup
            .unresolvedState();
        assertEq(uint8(urProofType), 0);
        assertEq(urBatchIndex, 0);
        assertEq(urStateRoot, bytes32(0));
        assertEq(urWithdrawRoot, bytes32(0));

        // batch 1, have unresolved state, both tee and zkp paused
        hevm.startPrank(address(0));
        hevm.expectEmit(true, false, false, true);
        emit VerifyBatchWithTee(1, keccak256(headers[1]), bytes32(uint256(1001)), bytes32(uint256(2001)));
        rollup.finalizeBundleWithTeeProof(headers[1], bytes32(uint256(1001)), bytes32(uint256(2001)), new bytes(0));
        hevm.expectEmit(true, false, false, true);
        emit StateMismatch(1, bytes32(uint256(3001)), bytes32(uint256(4001)));
        rollup.finalizeBundleWithProof(headers[1], bytes32(uint256(3001)), bytes32(uint256(4001)), new bytes(0));
        hevm.stopPrank();
        (urProofType, urBatchIndex, urStateRoot, urWithdrawRoot) = rollup.unresolvedState();
        assertEq(uint8(urProofType), 0);
        assertEq(urBatchIndex, 1);
        assertEq(urStateRoot, bytes32(uint256(3001)));
        assertEq(urWithdrawRoot, bytes32(uint256(4001)));

        // revert ErrorFinalizationPaused
        hevm.startPrank(address(0));
        hevm.expectRevert(ScrollChain.ErrorFinalizationPaused.selector);
        rollup.finalizeBundleWithTeeProof(headers[1], bytes32(uint256(1001)), bytes32(uint256(2001)), new bytes(0));
        hevm.expectRevert(ScrollChain.ErrorFinalizationPaused.selector);
        rollup.finalizeBundleWithProof(headers[1], bytes32(uint256(3001)), bytes32(uint256(4001)), new bytes(0));
        hevm.stopPrank();

        // revert ErrorBatchIndexMismatch
        hevm.expectRevert(ScrollChain.ErrorBatchIndexMismatch.selector);
        rollup.resolveStateMismatch(headers[2], false);

        // resolve mismatch and enable both proof again
        hevm.expectEmit(true, false, false, true);
        emit ResolveState(1, bytes32(uint256(1001)), bytes32(uint256(2001)));
        hevm.expectEmit(false, false, false, true);
        emit FinalizedDequeuedTransaction(1);
        hevm.expectEmit(true, false, false, true);
        emit FinalizeBatch(1, keccak256(headers[1]), bytes32(uint256(1001)), bytes32(uint256(2001)));
        rollup.resolveStateMismatch(headers[1], false);
        assertEq(rollup.lastZkpVerifiedBatchIndex(), 1);
        assertEq(rollup.lastTeeVerifiedBatchIndex(), 1);
        assertEq(rollup.lastFinalizedBatchIndex(), 1);
        assertEq(messageQueue.nextUnfinalizedQueueIndex(), 2);
        assertEq(rollup.finalizedStateRoots(1), bytes32(uint256(1001)));
        assertEq(rollup.withdrawRoots(1), bytes32(uint256(2001)));
        rollup.enableProofTypes(3);

        // batch 2, tee behind zkp, tee wrong, state root mismatch, withdraw root match
        hevm.startPrank(address(0));
        hevm.expectEmit(true, false, false, true);
        emit VerifyBatchWithZkp(2, keccak256(headers[2]), bytes32(uint256(1002)), bytes32(uint256(2002)));
        rollup.finalizeBundleWithProof(headers[2], bytes32(uint256(1002)), bytes32(uint256(2002)), new bytes(0));
        hevm.expectEmit(true, false, false, true);
        emit StateMismatch(2, bytes32(uint256(3002)), bytes32(uint256(2002)));
        rollup.finalizeBundleWithTeeProof(headers[2], bytes32(uint256(3002)), bytes32(uint256(2002)), new bytes(0));
        hevm.stopPrank();
        (urProofType, urBatchIndex, urStateRoot, urWithdrawRoot) = rollup.unresolvedState();
        assertEq(uint8(urProofType), 1);
        assertEq(urBatchIndex, 2);
        assertEq(urStateRoot, bytes32(uint256(3002)));
        assertEq(urWithdrawRoot, bytes32(uint256(2002)));

        // resolve mismatch and enable both proof again
        hevm.expectEmit(true, false, false, true);
        emit ResolveState(2, bytes32(uint256(1002)), bytes32(uint256(2002)));
        hevm.expectEmit(false, false, false, true);
        emit FinalizedDequeuedTransaction(3);
        hevm.expectEmit(true, true, false, true);
        emit FinalizeBatch(2, keccak256(headers[2]), bytes32(uint256(1002)), bytes32(uint256(2002)));
        rollup.resolveStateMismatch(headers[2], false);
        assertEq(rollup.lastZkpVerifiedBatchIndex(), 2);
        assertEq(rollup.lastTeeVerifiedBatchIndex(), 2);
        assertEq(rollup.lastFinalizedBatchIndex(), 2);
        assertEq(rollup.enabledProofTypeMask(), 1);
        assertEq(messageQueue.nextUnfinalizedQueueIndex(), 4);
        (urProofType, urBatchIndex, urStateRoot, urWithdrawRoot) = rollup.unresolvedState();
        assertEq(uint8(urProofType), 0);
        assertEq(urBatchIndex, 0);
        assertEq(urStateRoot, bytes32(uint256(0)));
        assertEq(urWithdrawRoot, bytes32(uint256(0)));
        assertEq(rollup.finalizedStateRoots(2), bytes32(uint256(1002)));
        assertEq(rollup.withdrawRoots(2), bytes32(uint256(2002)));
        rollup.enableProofTypes(3);

        // batch 3, tee behind zkp, zkp wrong, state root match, withdraw root mismatch
        hevm.startPrank(address(0));
        hevm.expectEmit(true, false, false, true);
        emit VerifyBatchWithZkp(3, keccak256(headers[3]), bytes32(uint256(1003)), bytes32(uint256(4003)));
        rollup.finalizeBundleWithProof(headers[3], bytes32(uint256(1003)), bytes32(uint256(4003)), new bytes(0));
        hevm.expectEmit(true, false, false, true);
        emit VerifyBatchWithTee(3, keccak256(headers[3]), bytes32(uint256(1003)), bytes32(uint256(2003)));
        hevm.expectEmit(true, false, false, true);
        emit StateMismatch(3, bytes32(uint256(1003)), bytes32(uint256(2003)));
        rollup.finalizeBundleWithTeeProof(headers[3], bytes32(uint256(1003)), bytes32(uint256(2003)), new bytes(0));
        hevm.stopPrank();
        (urProofType, urBatchIndex, urStateRoot, urWithdrawRoot) = rollup.unresolvedState();
        assertEq(uint8(urProofType), 1);
        assertEq(urBatchIndex, 3);
        assertEq(urStateRoot, bytes32(uint256(1003)));
        assertEq(urWithdrawRoot, bytes32(uint256(2003)));

        // resolve mismatch and enable both proof again
        hevm.expectEmit(true, false, false, true);
        emit ResolveState(3, bytes32(uint256(1003)), bytes32(uint256(2003)));
        hevm.expectEmit(false, false, false, true);
        emit FinalizedDequeuedTransaction(5);
        hevm.expectEmit(true, true, false, true);
        emit FinalizeBatch(3, keccak256(headers[3]), bytes32(uint256(1003)), bytes32(uint256(2003)));
        rollup.resolveStateMismatch(headers[3], true);
        assertEq(rollup.lastZkpVerifiedBatchIndex(), 3);
        assertEq(rollup.lastTeeVerifiedBatchIndex(), 3);
        assertEq(rollup.lastFinalizedBatchIndex(), 3);
        assertEq(rollup.enabledProofTypeMask(), 2);
        assertEq(messageQueue.nextUnfinalizedQueueIndex(), 6);
        (urProofType, urBatchIndex, urStateRoot, urWithdrawRoot) = rollup.unresolvedState();
        assertEq(uint8(urProofType), 0);
        assertEq(urBatchIndex, 0);
        assertEq(urStateRoot, bytes32(uint256(0)));
        assertEq(urWithdrawRoot, bytes32(uint256(0)));
        assertEq(rollup.finalizedStateRoots(3), bytes32(uint256(1003)));
        assertEq(rollup.withdrawRoots(3), bytes32(uint256(2003)));
        rollup.enableProofTypes(3);

        // batch 4, zkp behind tee, zkp wrong, state root mismatch, withdraw root mismatch
        hevm.startPrank(address(0));
        hevm.expectEmit(true, false, false, true);
        emit VerifyBatchWithTee(4, keccak256(headers[4]), bytes32(uint256(1004)), bytes32(uint256(2004)));
        rollup.finalizeBundleWithTeeProof(headers[4], bytes32(uint256(1004)), bytes32(uint256(2004)), new bytes(0));
        hevm.expectEmit(true, false, false, true);
        emit VerifyBatchWithZkp(4, keccak256(headers[4]), bytes32(uint256(3004)), bytes32(uint256(4004)));
        hevm.expectEmit(true, false, false, true);
        emit StateMismatch(4, bytes32(uint256(3004)), bytes32(uint256(4004)));
        rollup.finalizeBundleWithProof(headers[4], bytes32(uint256(3004)), bytes32(uint256(4004)), new bytes(0));
        hevm.stopPrank();
        (urProofType, urBatchIndex, urStateRoot, urWithdrawRoot) = rollup.unresolvedState();
        assertEq(uint8(urProofType), 0);
        assertEq(urBatchIndex, 4);
        assertEq(urStateRoot, bytes32(uint256(3004)));
        assertEq(urWithdrawRoot, bytes32(uint256(4004)));

        // resolve mismatch and enable both proof again
        hevm.expectEmit(true, false, false, true);
        emit ResolveState(4, bytes32(uint256(1004)), bytes32(uint256(2004)));
        hevm.expectEmit(false, false, false, true);
        emit FinalizedDequeuedTransaction(7);
        hevm.expectEmit(true, true, false, true);
        emit FinalizeBatch(4, keccak256(headers[4]), bytes32(uint256(1004)), bytes32(uint256(2004)));
        rollup.resolveStateMismatch(headers[4], false);
        assertEq(rollup.lastZkpVerifiedBatchIndex(), 4);
        assertEq(rollup.lastTeeVerifiedBatchIndex(), 4);
        assertEq(rollup.lastFinalizedBatchIndex(), 4);
        assertEq(rollup.enabledProofTypeMask(), 2);
        assertEq(messageQueue.nextUnfinalizedQueueIndex(), 8);
        (urProofType, urBatchIndex, urStateRoot, urWithdrawRoot) = rollup.unresolvedState();
        assertEq(uint8(urProofType), 0);
        assertEq(urBatchIndex, 0);
        assertEq(urStateRoot, bytes32(uint256(0)));
        assertEq(urWithdrawRoot, bytes32(uint256(0)));
        assertEq(rollup.finalizedStateRoots(4), bytes32(uint256(1004)));
        assertEq(rollup.withdrawRoots(4), bytes32(uint256(2004)));
        rollup.enableProofTypes(3);

        // batch 5, zkp behind tee, tee wrong, state root mismatch, withdraw root mismatch
        hevm.startPrank(address(0));
        hevm.expectEmit(true, false, false, true);
        emit VerifyBatchWithTee(5, keccak256(headers[5]), bytes32(uint256(3005)), bytes32(uint256(2005)));
        rollup.finalizeBundleWithTeeProof(headers[5], bytes32(uint256(3005)), bytes32(uint256(2005)), new bytes(0));
        hevm.expectEmit(true, false, false, true);
        emit VerifyBatchWithZkp(5, keccak256(headers[5]), bytes32(uint256(1005)), bytes32(uint256(2005)));
        hevm.expectEmit(true, false, false, true);
        emit StateMismatch(5, bytes32(uint256(1005)), bytes32(uint256(2005)));
        rollup.finalizeBundleWithProof(headers[5], bytes32(uint256(1005)), bytes32(uint256(2005)), new bytes(0));
        hevm.stopPrank();
        (urProofType, urBatchIndex, urStateRoot, urWithdrawRoot) = rollup.unresolvedState();
        assertEq(uint8(urProofType), 0);
        assertEq(urBatchIndex, 5);
        assertEq(urStateRoot, bytes32(uint256(1005)));
        assertEq(urWithdrawRoot, bytes32(uint256(2005)));

        // resolve mismatch and enable both proof again
        hevm.expectEmit(true, false, false, true);
        emit ResolveState(5, bytes32(uint256(1005)), bytes32(uint256(2005)));
        hevm.expectEmit(false, false, false, true);
        emit FinalizedDequeuedTransaction(9);
        hevm.expectEmit(true, true, false, true);
        emit FinalizeBatch(5, keccak256(headers[5]), bytes32(uint256(1005)), bytes32(uint256(2005)));
        rollup.resolveStateMismatch(headers[5], true);
        assertEq(rollup.lastZkpVerifiedBatchIndex(), 5);
        assertEq(rollup.lastTeeVerifiedBatchIndex(), 5);
        assertEq(rollup.lastFinalizedBatchIndex(), 5);
        assertEq(rollup.enabledProofTypeMask(), 1);
        assertEq(messageQueue.nextUnfinalizedQueueIndex(), 10);
        (urProofType, urBatchIndex, urStateRoot, urWithdrawRoot) = rollup.unresolvedState();
        assertEq(uint8(urProofType), 0);
        assertEq(urBatchIndex, 0);
        assertEq(urStateRoot, bytes32(uint256(0)));
        assertEq(urWithdrawRoot, bytes32(uint256(0)));
        assertEq(rollup.finalizedStateRoots(5), bytes32(uint256(1005)));
        assertEq(rollup.withdrawRoots(5), bytes32(uint256(2005)));
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
            rollup.zkpVerifier(),
            rollup.teeVerifier(),
            0
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
            mstore8(add(batchHeader1, 0x20), 3) // version
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
        rollup.commitBatchWithBlobProof(3, batchHeader0, chunks, bitmap, blobDataProof);
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
            mstore8(add(batchHeader2, 0x20), 3) // version
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

        hevm.startPrank(address(0));
        hevm.expectEmit(true, true, false, true);
        emit CommitBatch(2, keccak256(batchHeader2));
        rollup.commitBatchWithBlobProof(3, batchHeader1, chunks, bitmap, blobDataProof);
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

        rollup.updateBundleSize(2, 1);
        // finalize batch1 and batch2 together
        assertBoolEq(rollup.isBatchFinalized(1), false);
        assertBoolEq(rollup.isBatchFinalized(2), false);
        hevm.startPrank(address(0));
        rollup.finalizeBundleWithProof(batchHeader2, bytes32(uint256(2)), bytes32(uint256(3)), new bytes(0));
        hevm.stopPrank();
        assertBoolEq(rollup.isBatchFinalized(1), false);
        assertBoolEq(rollup.isBatchFinalized(2), false);
        assertEq(rollup.finalizedStateRoots(1), bytes32(0));
        assertEq(rollup.withdrawRoots(1), bytes32(0));
        assertEq(rollup.finalizedStateRoots(2), bytes32(uint256(2)));
        assertEq(rollup.withdrawRoots(2), bytes32(uint256(3)));
        assertEq(rollup.lastFinalizedBatchIndex(), 0);
        assertEq(rollup.lastZkpVerifiedBatchIndex(), 2);
        assertEq(0, messageQueue.nextUnfinalizedQueueIndex());
        hevm.startPrank(address(0));
        rollup.finalizeBundleWithTeeProof(batchHeader2, bytes32(uint256(2)), bytes32(uint256(3)), new bytes(0));
        hevm.stopPrank();
        assertBoolEq(rollup.isBatchFinalized(1), true);
        assertBoolEq(rollup.isBatchFinalized(2), true);
        assertEq(rollup.lastFinalizedBatchIndex(), 2);
        assertEq(rollup.lastTeeVerifiedBatchIndex(), 2);
        assertEq(265, messageQueue.nextUnfinalizedQueueIndex());
    }

    /*
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
        // upgrade to ScrollChainMockBlob
        ScrollChainMockBlob impl = new ScrollChainMockBlob(
            rollup.layer2ChainId(),
            rollup.messageQueue(),
            rollup.zkpVerifier(),
            rollup.teeVerifier(),
            0
        );
        admin.upgrade(ITransparentUpgradeableProxy(address(rollup)), address(impl));

        // from https://etherscan.io/blob/0x013590dc3544d56629ba81bb14d4d31248f825001653aa575eb8e3a719046757?bid=740652
        bytes32 blobVersionedHash = 0x013590dc3544d56629ba81bb14d4d31248f825001653aa575eb8e3a719046757;
        bytes
            memory blobDataProof = hex"2c9d777660f14ad49803a6442935c0d24a0d83551de5995890bf70a17d24e68753ab0fe6807c7081f0885fe7da741554d658a03730b1fa006f8319f8b993bcb0a5a0c9e8a145c5ef6e415c245690effa2914ec9393f58a7251d30c0657da1453d9ad906eae8b97dd60c9a216f81b4df7af34d01e214e1ec5865f0133ecc16d7459e49dab66087340677751e82097fbdd20551d66076f425775d1758a9dfd186b";
        ScrollChainMockBlob(address(rollup)).setBlobVersionedHash(blobVersionedHash);

        // caller not owner, revert
        hevm.startPrank(address(1));
        hevm.expectRevert("Ownable: caller is not the owner");
        rollup.revertBatch(new bytes(89), new bytes(89));
        hevm.stopPrank();

        rollup.addSequencer(address(0));

        bytes memory batchHeader0 = new bytes(89);

        // import genesis batch
        assembly {
            mstore(add(batchHeader0, add(0x20, 25)), 1)
        }
        rollup.importGenesisBatch(batchHeader0, bytes32(uint256(1)));
        bytes32 batchHash0 = rollup.committedBatches(0);

        bytes[] memory chunks = new bytes[](1);
        bytes memory chunk0;

        // commit one batch
        chunk0 = new bytes(1 + 60);
        chunk0[0] = bytes1(uint8(1)); // one block in this chunk
        chunks[0] = chunk0;
        hevm.startPrank(address(0));
        rollup.commitBatch(1, batchHeader0, chunks, new bytes(0));
        bytes32 batchHash1 = rollup.committedBatches(1);
        hevm.stopPrank();

        bytes memory batchHeader1 = new bytes(121);
        assembly {
            mstore8(add(batchHeader1, 0x20), 1) // version
            mstore(add(batchHeader1, add(0x20, 1)), shl(192, 1)) // batchIndex
            mstore(add(batchHeader1, add(0x20, 9)), 0) // l1MessagePopped
            mstore(add(batchHeader1, add(0x20, 17)), 0) // totalL1MessagePopped
            mstore(add(batchHeader1, add(0x20, 25)), 0x246394445f4fe64ed5598554d55d1682d6fb3fe04bf58eb54ef81d1189fafb51) // dataHash
            mstore(add(batchHeader1, add(0x20, 57)), blobVersionedHash) // blobVersionedHash
            mstore(add(batchHeader1, add(0x20, 89)), batchHash0) // parentBatchHash
        }

        // commit another batch
        hevm.startPrank(address(0));
        rollup.commitBatch(1, batchHeader1, chunks, new bytes(0));
        hevm.stopPrank();

        bytes memory batchHeader2 = new bytes(121);
        assembly {
            mstore8(add(batchHeader2, 0x20), 1) // version
            mstore(add(batchHeader2, add(0x20, 1)), shl(192, 2)) // batchIndex
            mstore(add(batchHeader2, add(0x20, 9)), 0) // l1MessagePopped
            mstore(add(batchHeader2, add(0x20, 17)), 0) // totalL1MessagePopped
            mstore(add(batchHeader2, add(0x20, 25)), 0x246394445f4fe64ed5598554d55d1682d6fb3fe04bf58eb54ef81d1189fafb51) // dataHash
            mstore(add(batchHeader2, add(0x20, 57)), blobVersionedHash) // blobVersionedHash
            mstore(add(batchHeader2, add(0x20, 89)), batchHash1) // parentBatchHash
        }

        // incorrect batch hash of first header, revert
        batchHeader1[1] = bytes1(uint8(1)); // change random byte
        hevm.expectRevert(ScrollChain.ErrorIncorrectBatchHash.selector);
        rollup.revertBatch(batchHeader1, batchHeader0);
        batchHeader1[1] = bytes1(uint8(0)); // change back

        // incorrect batch hash of second header, revert
        batchHeader1[1] = bytes1(uint8(1)); // change random byte
        hevm.expectRevert(ScrollChain.ErrorIncorrectBatchHash.selector);
        rollup.revertBatch(batchHeader0, batchHeader1);
        batchHeader1[1] = bytes1(uint8(0)); // change back

        // count must be nonzero, revert
        hevm.expectRevert(ScrollChain.ErrorRevertZeroBatches.selector);
        rollup.revertBatch(batchHeader1, batchHeader0);

        // revert middle batch, revert
        hevm.expectRevert(ScrollChain.ErrorRevertNotStartFromEnd.selector);
        rollup.revertBatch(batchHeader1, batchHeader1);

        // can only revert unfinalized batch, revert
        hevm.expectRevert(ScrollChain.ErrorRevertFinalizedBatch.selector);
        rollup.revertBatch(batchHeader0, batchHeader2);

        // succeed to revert next two pending batches.

        hevm.expectEmit(true, true, false, true);
        emit RevertBatch(2, rollup.committedBatches(2));
        hevm.expectEmit(true, true, false, true);
        emit RevertBatch(1, rollup.committedBatches(1));

        assertGt(uint256(rollup.committedBatches(1)), 0);
        assertGt(uint256(rollup.committedBatches(2)), 0);
        rollup.revertBatch(batchHeader1, batchHeader2);
        assertEq(uint256(rollup.committedBatches(1)), 0);
        assertEq(uint256(rollup.committedBatches(2)), 0);
    }
    */

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
        rollup.finalizeBundleWithProof(new bytes(0), bytes32(0), bytes32(0), new bytes(0));
        hevm.expectRevert("Pausable: paused");
        rollup.finalizeBundleWithTeeProof(new bytes(0), bytes32(0), bytes32(0), new bytes(0));
        hevm.stopPrank();

        // unpause
        rollup.setPause(false);
        assertBoolEq(false, rollup.paused());
    }

    function testUpdateBundleSize() external {
        // not owner, revert
        hevm.startPrank(address(1));
        hevm.expectRevert("Ownable: caller is not the owner");
        rollup.updateBundleSize(0, 0);
        hevm.stopPrank();

        // upgrade to ScrollChainMockBlob
        ScrollChainMockBlob impl = new ScrollChainMockBlob(
            rollup.layer2ChainId(),
            rollup.messageQueue(),
            rollup.zkpVerifier(),
            rollup.teeVerifier(),
            0
        );
        admin.upgrade(ITransparentUpgradeableProxy(address(rollup)), address(impl));
        ScrollChainMockBlob(address(rollup)).setLastZkpVerifiedBatchIndex(100);
        ScrollChainMockBlob(address(rollup)).setLastTeeVerifiedBatchIndex(90);

        // revert ErrorUseFinalizedBatch, when index < lastTeeVerifiedBatchIndex
        hevm.expectRevert(ScrollChain.ErrorUseFinalizedBatch.selector);
        rollup.updateBundleSize(1, 89);
        // revert ErrorUseFinalizedBatch, when index < lastZkpVerifiedBatchIndex
        hevm.expectRevert(ScrollChain.ErrorUseFinalizedBatch.selector);
        rollup.updateBundleSize(1, 99);

        // no array item 1
        hevm.expectRevert(new bytes(0));
        rollup.bundleSize(1);

        // update one
        hevm.expectEmit(false, false, false, true);
        emit ChangeBundleSize(1, 5, 200);
        rollup.updateBundleSize(5, 200);
        (uint256 size, uint256 index) = rollup.bundleSize(1);
        assertEq(size, 5);
        assertEq(index, 200);
        assertEq(rollup.getBundleSizeGivenEndBatchIndex(200), 1);
        assertEq(rollup.getBundleSizeGivenEndBatchIndex(205), 5);
        assertEq(rollup.getBundleSizeGivenEndBatchIndex(300), 5);

        ScrollChainMockBlob(address(rollup)).setLastZkpVerifiedBatchIndex(300);
        ScrollChainMockBlob(address(rollup)).setLastTeeVerifiedBatchIndex(300);

        // revert ErrorBatchIndexDeltaNotMultipleOfBundleSize, last is past batch index
        hevm.expectRevert(ScrollChain.ErrorBatchIndexDeltaNotMultipleOfBundleSize.selector);
        rollup.updateBundleSize(6, 401);

        // succeed to append another one
        hevm.expectEmit(false, false, false, true);
        emit ChangeBundleSize(2, 10, 400);
        rollup.updateBundleSize(10, 400);
        (size, index) = rollup.bundleSize(2);
        assertEq(size, 10);
        assertEq(index, 400);

        // revert ErrorBatchIndexDeltaNotMultipleOfBundleSize, replace last with smaller index
        hevm.expectRevert(ScrollChain.ErrorBatchIndexDeltaNotMultipleOfBundleSize.selector);
        rollup.updateBundleSize(6, 401);

        // succeed to update last one
        hevm.expectEmit(false, false, false, true);
        emit ChangeBundleSize(2, 20, 350);
        rollup.updateBundleSize(20, 350);
        (size, index) = rollup.bundleSize(2);
        assertEq(size, 20);
        assertEq(index, 350);

        // no array item 3
        hevm.expectRevert(new bytes(0));
        rollup.bundleSize(3);
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

    /// @dev Prepare 10 batches, each of the first 5 has 2 l1 messages, each of the second 5 has no l1 message.
    function _prepareFinalizeBundle() internal returns (bytes[] memory headers) {
        // grant roles
        rollup.addProver(address(0));
        rollup.addSequencer(address(0));

        headers = new bytes[](11);

        // upgrade to ScrollChainMockBlob for data mocking
        ScrollChainMockBlob impl = new ScrollChainMockBlob(
            rollup.layer2ChainId(),
            rollup.messageQueue(),
            rollup.zkpVerifier(),
            rollup.teeVerifier(),
            100
        );
        admin.upgrade(ITransparentUpgradeableProxy(address(rollup)), address(impl));
        // from https://etherscan.io/blob/0x013590dc3544d56629ba81bb14d4d31248f825001653aa575eb8e3a719046757?bid=740652
        bytes32 blobVersionedHash = 0x013590dc3544d56629ba81bb14d4d31248f825001653aa575eb8e3a719046757;
        ScrollChainMockBlob(address(rollup)).setBlobVersionedHash(blobVersionedHash);

        // import 10 L1 messages
        for (uint256 i = 0; i < 10; i++) {
            messageQueue.appendCrossDomainMessage(address(this), 1000000, new bytes(0));
        }
        // commit genesis batch
        headers[0] = _commitGenesisBatch();
        // commit 5 batches, each has 2 l1 messages
        for (uint256 i = 1; i <= 5; ++i) {
            headers[i] = _commitBatch(headers[i - 1], 2);
        }
        // commit 5 batches, each has 0 l1 message
        for (uint256 i = 6; i <= 10; ++i) {
            headers[i] = _commitBatch(headers[i - 1], 0);
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

    function _commitBatch(bytes memory parentHeader, uint256 numL1Message) internal returns (bytes memory header) {
        uint256 batchPtr;
        assembly {
            batchPtr := add(parentHeader, 0x20)
        }
        uint256 index = BatchHeaderV0Codec.getBatchIndex(batchPtr) + 1;
        uint256 totalL1MessagePopped = BatchHeaderV0Codec.getTotalL1MessagePopped(batchPtr) + numL1Message;
        bytes32 parentHash = keccak256(parentHeader);
        bytes
            memory blobDataProof = hex"2c9d777660f14ad49803a6442935c0d24a0d83551de5995890bf70a17d24e68753ab0fe6807c7081f0885fe7da741554d658a03730b1fa006f8319f8b993bcb0a5a0c9e8a145c5ef6e415c245690effa2914ec9393f58a7251d30c0657da1453d9ad906eae8b97dd60c9a216f81b4df7af34d01e214e1ec5865f0133ecc16d7459e49dab66087340677751e82097fbdd20551d66076f425775d1758a9dfd186b";
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
        bytes memory bitmap;
        if (numL1Message > 0) bitmap = new bytes(32);
        bytes[] memory chunks = new bytes[](1);
        {
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
                mstore8(add(header, 0x20), 3) // version
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

        hevm.startPrank(address(0));
        if (numL1Message > 0) {
            hevm.expectEmit(false, false, false, true);
            emit DequeueTransaction(BatchHeaderV0Codec.getTotalL1MessagePopped(batchPtr), numL1Message, 0);
        }
        hevm.expectEmit(true, true, false, true);
        emit CommitBatch(index, keccak256(header));
        rollup.commitBatchWithBlobProof(3, parentHeader, chunks, bitmap, blobDataProof);
        hevm.stopPrank();
        assertBoolEq(rollup.isBatchFinalized(1), false);
        assertEq(rollup.committedBatches(index), keccak256(header));
        assertEq(messageQueue.pendingQueueIndex(), totalL1MessagePopped);
        assertEq(messageQueue.nextUnfinalizedQueueIndex(), 0);
    }
}
