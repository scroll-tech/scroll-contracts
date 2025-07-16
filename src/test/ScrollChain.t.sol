// SPDX-License-Identifier: MIT

pragma solidity =0.8.24;

import {DSTestPlus} from "solmate/test/utils/DSTestPlus.sol";

import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {ITransparentUpgradeableProxy, TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import {L1MessageQueueV1} from "../L1/rollup/L1MessageQueueV1.sol";
import {L1MessageQueueV2} from "../L1/rollup/L1MessageQueueV2.sol";
import {ScrollChain, IScrollChain} from "../L1/rollup/ScrollChain.sol";
import {SystemConfig} from "../L1/system-contract/SystemConfig.sol";
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
    // from https://etherscan.io/blob/0x013590dc3544d56629ba81bb14d4d31248f825001653aa575eb8e3a719046757?bid=740652
    bytes32 private constant blobVersionedHash = 0x013590dc3544d56629ba81bb14d4d31248f825001653aa575eb8e3a719046757;

    // from ScrollChain
    event UpdateSequencer(address indexed account, bool status);
    event UpdateProver(address indexed account, bool status);
    event UpdateMaxNumTxInChunk(uint256 oldMaxNumTxInChunk, uint256 newMaxNumTxInChunk);

    event CommitBatch(uint256 indexed batchIndex, bytes32 indexed batchHash);
    event FinalizeBatch(uint256 indexed batchIndex, bytes32 indexed batchHash, bytes32 stateRoot, bytes32 withdrawRoot);
    event RevertBatch(uint256 indexed batchIndex, bytes32 indexed batchHash);
    event RevertBatch(uint256 indexed startBatchIndex, uint256 indexed finishBatchIndex);

    // from L1MessageQueue
    event DequeueTransaction(uint256 startIndex, uint256 count, uint256 skippedBitmap);
    event ResetDequeuedTransaction(uint256 startIndex);
    event FinalizedDequeuedTransaction(uint256 finalizedIndex);

    ProxyAdmin internal admin;
    EmptyContract private placeholder;

    SystemConfig private system;
    ScrollChain private rollup;
    L1MessageQueueV1 internal messageQueueV1;
    L1MessageQueueV2 internal messageQueueV2;
    MockRollupVerifier internal verifier;

    function setUp() public {
        placeholder = new EmptyContract();
        admin = new ProxyAdmin();
        system = SystemConfig(_deployProxy(address(0)));
        messageQueueV1 = L1MessageQueueV1(_deployProxy(address(0)));
        messageQueueV2 = L1MessageQueueV2(_deployProxy(address(0)));
        rollup = ScrollChain(_deployProxy(address(0)));
        verifier = new MockRollupVerifier();

        // Upgrade the SystemConfig implementation and initialize
        admin.upgrade(ITransparentUpgradeableProxy(address(system)), address(new SystemConfig()));
        system.initialize(
            address(this),
            address(uint160(1)),
            SystemConfig.MessageQueueParameters({maxGasLimit: 1000000, baseFeeOverhead: 0, baseFeeScalar: 0}),
            SystemConfig.EnforcedBatchParameters({maxDelayEnterEnforcedMode: 86400, maxDelayMessageQueue: 86400})
        );

        // Upgrade the L1MessageQueueV1 implementation and initialize
        admin.upgrade(
            ITransparentUpgradeableProxy(address(messageQueueV1)),
            address(new L1MessageQueueV1(address(this), address(rollup), address(1)))
        );
        messageQueueV1.initialize(address(this), address(rollup), address(0), address(0), 10000000);

        // Upgrade the L1MessageQueueV2 implementation
        admin.upgrade(
            ITransparentUpgradeableProxy(address(messageQueueV2)),
            address(
                new L1MessageQueueV2(
                    address(this),
                    address(rollup),
                    address(1),
                    address(messageQueueV1),
                    address(system)
                )
            )
        );

        // Upgrade the ScrollChain implementation and initialize
        admin.upgrade(
            ITransparentUpgradeableProxy(address(rollup)),
            address(
                new ScrollChain(
                    233,
                    address(messageQueueV1),
                    address(messageQueueV2),
                    address(verifier),
                    address(system)
                )
            )
        );
        rollup.initialize(address(messageQueueV1), address(verifier), 100);
    }

    function testInitialized() external {
        assertEq(address(this), rollup.owner());
        assertEq(address(messageQueueV1), rollup.messageQueueV1());
        assertEq(address(messageQueueV2), rollup.messageQueueV2());
        assertEq(address(system), rollup.systemConfig());
        assertEq(address(verifier), rollup.verifier());
        assertEq(rollup.layer2ChainId(), 233);

        hevm.expectRevert("Initializable: contract is already initialized");
        rollup.initialize(address(messageQueueV1), address(0), 100);
    }

    function testInitializeV2(uint256 batches, uint32 time) external {
        batches = bound(batches, 0, 100);

        rollup.addSequencer(address(0));
        _upgradeToMockBlob();

        bytes memory header = _commitGenesisBatch();
        for (uint256 i = 0; i < batches; ++i) {
            header = _commitBatchV7Codec(7, header);
        }
        assertEq(rollup.committedBatches(batches), keccak256(header));

        hevm.warp(time);
        rollup.initializeV2();
        (uint256 lastCommittedBatchIndex, uint256 lastFinalizedBatchIndex, uint256 lastFinalizeTimestamp, , ) = rollup
            .miscData();
        assertEq(lastCommittedBatchIndex, batches);
        assertEq(lastFinalizedBatchIndex, 0);
        assertEq(lastFinalizeTimestamp, time);
        assertBoolEq(rollup.isEnforcedModeEnabled(), false);
    }

    function testCommitBatchV7Codec() external {
        bytes[] memory headers = _prepareBatchesV7Codec(7);
        (, bytes memory h11) = _constructBatchStructCodecV7(7, headers[10]);
        (, bytes memory h12) = _constructBatchStructCodecV7(7, h11);
        (, bytes memory h13) = _constructBatchStructCodecV7(7, h12);

        // caller not sequencer, revert
        hevm.expectRevert(ScrollChain.ErrorCallerIsNotSequencer.selector);
        rollup.commitBatches(7, bytes32(0), keccak256(headers[10]));

        // revert ErrorIncorrectBatchVersion
        hevm.startPrank(address(0));
        hevm.expectRevert(ScrollChain.ErrorIncorrectBatchVersion.selector);
        rollup.commitBatches(6, bytes32(0), keccak256(headers[10]));
        hevm.stopPrank();

        ScrollChainMockBlob(address(rollup)).setBlobVersionedHash(0, bytes32(0));
        // revert ErrorBatchIsEmpty
        hevm.startPrank(address(0));
        hevm.expectRevert(ScrollChain.ErrorBatchIsEmpty.selector);
        rollup.commitBatches(7, keccak256(headers[10]), keccak256(headers[10]));
        hevm.stopPrank();

        // succeed, commit only one batch
        ScrollChainMockBlob(address(rollup)).setBlobVersionedHash(0, blobVersionedHash);
        ScrollChainMockBlob(address(rollup)).setBlobVersionedHash(1, bytes32(0));
        (uint256 lastCommittedBatchIndex, , , , ) = rollup.miscData();
        assertEq(lastCommittedBatchIndex, 10);
        hevm.startPrank(address(0));
        rollup.commitBatches(7, keccak256(headers[10]), keccak256(h11));
        hevm.stopPrank();
        (lastCommittedBatchIndex, , , , ) = rollup.miscData();
        assertEq(lastCommittedBatchIndex, 11);
        assertGt(uint256(rollup.committedBatches(11)), 0);

        // succeed, commit only two batch
        ScrollChainMockBlob(address(rollup)).setBlobVersionedHash(0, blobVersionedHash);
        ScrollChainMockBlob(address(rollup)).setBlobVersionedHash(1, blobVersionedHash);
        ScrollChainMockBlob(address(rollup)).setBlobVersionedHash(2, bytes32(0));
        hevm.startPrank(address(0));
        rollup.commitBatches(7, keccak256(h11), keccak256(h13));
        hevm.stopPrank();
        (lastCommittedBatchIndex, , , , ) = rollup.miscData();
        assertEq(lastCommittedBatchIndex, 13);
        assertEq(uint256(rollup.committedBatches(12)), 0);
        assertGt(uint256(rollup.committedBatches(13)), 0);
    }

    function testFinalizeBundlePostEuclidV2() external {
        messageQueueV2.initialize();
        rollup.initializeV2();
        // import 10 L1 messages into message queue V2
        for (uint256 i = 0; i < 10; i++) {
            messageQueueV2.appendCrossDomainMessage(address(this), 1000000, new bytes(0));
        }
        // 0: genesis
        // 1-10: v6
        // 11-20: v7
        bytes[] memory headers = new bytes[](21);
        {
            bytes[] memory headersV7 = _prepareBatchesV7Codec(7);
            for (uint256 i = 0; i <= 10; ++i) {
                headers[i] = headersV7[i];
            }
        }
        for (uint256 i = 11; i < 21; ++i) {
            headers[i] = _commitBatchV7Codec(7, headers[i - 1]);
        }

        // revert ErrorCallerIsNotProver
        hevm.expectRevert(ScrollChain.ErrorCallerIsNotProver.selector);
        rollup.finalizeBundlePostEuclidV2(new bytes(0), 0, bytes32(0), bytes32(0), new bytes(0));

        // revert ErrorNotAllV1MessagesAreFinalized
        // hevm.startPrank(address(0));
        // hevm.expectRevert(ScrollChain.ErrorNotAllV1MessagesAreFinalized.selector);
        // rollup.finalizeBundlePostEuclidV2(headers[20], 0, bytes32(0), bytes32(0), new bytes(0));
        // hevm.stopPrank();

        // finalize all v6 batches
        (, uint256 lastFinalizedBatchIndex, uint256 lastFinalizeTimestamp, uint256 flags, ) = rollup.miscData();
        assertEq(lastFinalizedBatchIndex, 0);
        assertEq(lastFinalizeTimestamp, 0);
        assertEq(flags, 0);
        hevm.warp(100);
        hevm.startPrank(address(0));
        rollup.finalizeBundlePostEuclidV2(headers[10], 10, keccak256("x10"), keccak256("y10"), new bytes(0));
        hevm.stopPrank();
        (, lastFinalizedBatchIndex, lastFinalizeTimestamp, flags, ) = rollup.miscData();
        assertEq(lastFinalizedBatchIndex, 10);
        assertEq(lastFinalizeTimestamp, 100);
        assertEq(flags, 1);
        assertEq(rollup.lastFinalizedBatchIndex(), lastFinalizedBatchIndex);
        assertEq(rollup.finalizedStateRoots(10), keccak256("x10"));
        assertEq(rollup.withdrawRoots(10), keccak256("y10"));
        // assertEq(messageQueueV1.nextUnfinalizedQueueIndex(), 10);

        // revert ErrorStateRootIsZero
        hevm.startPrank(address(0));
        hevm.expectRevert(ScrollChain.ErrorStateRootIsZero.selector);
        rollup.finalizeBundlePostEuclidV2(headers[11], 9, bytes32(0), bytes32(0), new bytes(0));
        hevm.stopPrank();

        // finalize batch 11, no l1 messages
        hevm.warp(101);
        hevm.startPrank(address(0));
        hevm.expectEmit(true, true, true, true);
        emit FinalizeBatch(11, keccak256(headers[11]), keccak256("x11"), keccak256("y11"));
        rollup.finalizeBundlePostEuclidV2(headers[11], 10, keccak256("x11"), keccak256("y11"), new bytes(0));
        hevm.stopPrank();
        (, lastFinalizedBatchIndex, lastFinalizeTimestamp, flags, ) = rollup.miscData();
        assertEq(lastFinalizedBatchIndex, 11);
        assertEq(lastFinalizeTimestamp, 101);
        assertEq(flags, 1);
        assertEq(rollup.lastFinalizedBatchIndex(), lastFinalizedBatchIndex);
        assertEq(rollup.finalizedStateRoots(11), keccak256("x11"));
        assertEq(rollup.withdrawRoots(11), keccak256("y11"));
        assertEq(messageQueueV2.nextUnfinalizedQueueIndex(), 10);

        // import 10 L1 messages into message queue V2
        for (uint256 i = 0; i < 10; i++) {
            messageQueueV2.appendCrossDomainMessage(address(this), 1000000, new bytes(0));
        }
        assertEq(messageQueueV2.nextCrossDomainMessageIndex(), 20);

        // finalize batch 12, 13, 14 and 15, with 7 l1 messages
        hevm.warp(102);
        hevm.startPrank(address(0));
        hevm.expectEmit(false, false, false, true);
        emit FinalizedDequeuedTransaction(16);
        hevm.expectEmit(true, true, true, true);
        emit FinalizeBatch(15, keccak256(headers[15]), keccak256("x15"), keccak256("y15"));
        rollup.finalizeBundlePostEuclidV2(headers[15], 17, keccak256("x15"), keccak256("y15"), new bytes(0));
        hevm.stopPrank();
        (, lastFinalizedBatchIndex, lastFinalizeTimestamp, flags, ) = rollup.miscData();
        assertEq(lastFinalizedBatchIndex, 15);
        assertEq(lastFinalizeTimestamp, 102);
        assertEq(flags, 1);
        assertEq(rollup.lastFinalizedBatchIndex(), lastFinalizedBatchIndex);
        assertEq(rollup.finalizedStateRoots(15), keccak256("x15"));
        assertEq(rollup.withdrawRoots(15), keccak256("y15"));
        assertEq(messageQueueV2.nextUnfinalizedQueueIndex(), 17);

        // finalize batch 16~20, with 3 l1 messages
        hevm.warp(103);
        hevm.startPrank(address(0));
        hevm.expectEmit(false, false, false, true);
        emit FinalizedDequeuedTransaction(19);
        hevm.expectEmit(true, true, true, true);
        emit FinalizeBatch(20, keccak256(headers[20]), keccak256("x20"), keccak256("y20"));
        rollup.finalizeBundlePostEuclidV2(headers[20], 20, keccak256("x20"), keccak256("y20"), new bytes(0));
        hevm.stopPrank();
        (, lastFinalizedBatchIndex, lastFinalizeTimestamp, flags, ) = rollup.miscData();
        assertEq(lastFinalizedBatchIndex, 20);
        assertEq(lastFinalizeTimestamp, 103);
        assertEq(flags, 1);
        assertEq(rollup.lastFinalizedBatchIndex(), lastFinalizedBatchIndex);
        assertEq(rollup.finalizedStateRoots(20), keccak256("x20"));
        assertEq(rollup.withdrawRoots(20), keccak256("y20"));
        assertEq(messageQueueV2.nextUnfinalizedQueueIndex(), 20);

        // revert ErrorBatchIsAlreadyVerified
        hevm.startPrank(address(0));
        hevm.expectRevert(ScrollChain.ErrorBatchIsAlreadyVerified.selector);
        rollup.finalizeBundlePostEuclidV2(headers[20], 20, keccak256("x20"), keccak256("y20"), new bytes(0));
        hevm.stopPrank();
    }

    function testCommitAndFinalizeBatchByExpiredMessage() external {
        messageQueueV2.initialize();
        rollup.initializeV2();
        // import 10 L1 messages into message queue V2
        for (uint256 i = 0; i < 10; i++) {
            messageQueueV2.appendCrossDomainMessage(address(this), 1000000, new bytes(0));
        }
        // 0: genesis
        // 1-10: v6
        // 11-20: v7
        bytes[] memory headers = new bytes[](21);
        {
            bytes[] memory headersV7 = _prepareBatchesV7Codec(7);
            for (uint256 i = 0; i <= 10; ++i) {
                headers[i] = headersV7[i];
            }
        }
        for (uint256 i = 11; i < 21; ++i) {
            headers[i] = _commitBatchV7Codec(7, headers[i - 1]);
        }
        // finalize all v6 batches
        hevm.startPrank(address(0));
        rollup.finalizeBundlePostEuclidV2(headers[10], 10, keccak256("x10"), keccak256("y10"), new bytes(0));
        hevm.stopPrank();
        // finalize two v7 batches
        hevm.startPrank(address(0));
        rollup.finalizeBundlePostEuclidV2(headers[12], 10, keccak256("x12"), keccak256("y12"), new bytes(0));
        hevm.stopPrank();

        // revert when ErrorNotInEnforcedBatchMode
        hevm.expectRevert(ScrollChain.ErrorNotInEnforcedBatchMode.selector);
        hevm.startPrank(address(0x00a329c0648769A73afAc7F9381E08FB43dBEA72));
        rollup.commitAndFinalizeBatch(
            7,
            bytes32(0),
            IScrollChain.FinalizeStruct({
                batchHeader: new bytes(0),
                totalL1MessagesPoppedOverall: 0,
                postStateRoot: bytes32(0),
                withdrawRoot: bytes32(0),
                zkProof: new bytes(0)
            })
        );
        hevm.stopPrank();

        system.updateEnforcedBatchParameters(
            SystemConfig.EnforcedBatchParameters({
                maxDelayEnterEnforcedMode: type(uint24).max,
                maxDelayMessageQueue: 86400
            })
        );
        hevm.warp(100);
        // import 10 L1 messages into message queue V2
        for (uint256 i = 0; i < 10; i++) {
            messageQueueV2.appendCrossDomainMessage(address(this), 1000000, new bytes(0));
        }
        assertEq(messageQueueV2.nextUnfinalizedQueueIndex(), 10);
        assertEq(messageQueueV2.nextCrossDomainMessageIndex(), 20);
        assertEq(messageQueueV2.getFirstUnfinalizedMessageEnqueueTime(), 100);
        hevm.warp(100 + 86400 + 1);

        // succeed to call commitAndFinalizeBatch 13
        ScrollChainMockBlob(address(rollup)).setBlobVersionedHash(0, blobVersionedHash);
        ScrollChainMockBlob(address(rollup)).setBlobVersionedHash(1, bytes32(0));
        hevm.startPrank(address(0x00a329c0648769A73afAc7F9381E08FB43dBEA72));
        rollup.commitAndFinalizeBatch(
            7,
            keccak256(headers[12]),
            IScrollChain.FinalizeStruct({
                batchHeader: headers[13],
                totalL1MessagesPoppedOverall: 20,
                postStateRoot: keccak256("x13"),
                withdrawRoot: keccak256("y13"),
                zkProof: new bytes(0)
            })
        );
        hevm.stopPrank();
        (uint256 lastCommittedBatchIndex, uint256 lastFinalizedBatchIndex, uint256 lastFinalizeTimestamp, , ) = rollup
            .miscData();
        assertEq(lastCommittedBatchIndex, 13);
        assertEq(lastFinalizedBatchIndex, 13);
        assertEq(lastFinalizeTimestamp, 100 + 86400 + 1);
        assertBoolEq(rollup.isEnforcedModeEnabled(), true);
        assertEq(messageQueueV2.nextUnfinalizedQueueIndex(), 20);
        assertEq(messageQueueV2.nextCrossDomainMessageIndex(), 20);
        assertEq(messageQueueV2.getFirstUnfinalizedMessageEnqueueTime(), 100 + 86400 + 1);

        // revert when do commit
        hevm.startPrank(address(0));
        hevm.expectRevert(ScrollChain.ErrorInEnforcedBatchMode.selector);
        rollup.commitBatches(0, bytes32(0), bytes32(0));
        hevm.stopPrank();

        // revert when do finalize
        hevm.startPrank(address(0));
        hevm.expectRevert(ScrollChain.ErrorInEnforcedBatchMode.selector);
        rollup.finalizeBundlePostEuclidV2(new bytes(0), 0, bytes32(0), bytes32(0), new bytes(0));
        hevm.stopPrank();

        // succeed to call commitAndFinalizeBatch 14, no need to warp time
        ScrollChainMockBlob(address(rollup)).setBlobVersionedHash(0, blobVersionedHash);
        ScrollChainMockBlob(address(rollup)).setBlobVersionedHash(1, bytes32(0));
        hevm.startPrank(address(0x00a329c0648769A73afAc7F9381E08FB43dBEA72));
        rollup.commitAndFinalizeBatch(
            7,
            keccak256(headers[13]),
            IScrollChain.FinalizeStruct({
                batchHeader: headers[14],
                totalL1MessagesPoppedOverall: 20,
                postStateRoot: keccak256("x14"),
                withdrawRoot: keccak256("y14"),
                zkProof: new bytes(0)
            })
        );
        hevm.stopPrank();
        (lastCommittedBatchIndex, lastFinalizedBatchIndex, lastFinalizeTimestamp, , ) = rollup.miscData();
        assertEq(lastCommittedBatchIndex, 14);
        assertEq(lastFinalizedBatchIndex, 14);
        assertEq(lastFinalizeTimestamp, 100 + 86400 + 1);
        assertBoolEq(rollup.isEnforcedModeEnabled(), true);
        assertEq(messageQueueV2.nextUnfinalizedQueueIndex(), 20);
        assertEq(messageQueueV2.nextCrossDomainMessageIndex(), 20);
        assertEq(messageQueueV2.getFirstUnfinalizedMessageEnqueueTime(), 100 + 86400 + 1);

        // admin disableEnforcedBatchMode
        rollup.disableEnforcedBatchMode();
        (lastCommittedBatchIndex, lastFinalizedBatchIndex, lastFinalizeTimestamp, , ) = rollup.miscData();
        assertEq(lastCommittedBatchIndex, 14);
        assertEq(lastFinalizedBatchIndex, 14);
        assertEq(lastFinalizeTimestamp, 100 + 86400 + 1);
        assertBoolEq(rollup.isEnforcedModeEnabled(), false);

        // not in enforced mode
        hevm.expectRevert(ScrollChain.ErrorNotInEnforcedBatchMode.selector);
        hevm.startPrank(address(0x00a329c0648769A73afAc7F9381E08FB43dBEA72));
        rollup.commitAndFinalizeBatch(
            7,
            keccak256(headers[13]),
            IScrollChain.FinalizeStruct({
                batchHeader: headers[14],
                totalL1MessagesPoppedOverall: 20,
                postStateRoot: keccak256("x13"),
                withdrawRoot: keccak256("y13"),
                zkProof: new bytes(0)
            })
        );
        hevm.stopPrank();
    }

    function testCommitAndFinalizeBatchByExpiredBatch() external {
        hevm.warp(100);
        messageQueueV2.initialize();
        rollup.initializeV2();
        // import 10 L1 messages into message queue V2
        for (uint256 i = 0; i < 10; i++) {
            messageQueueV2.appendCrossDomainMessage(address(this), 1000000, new bytes(0));
        }
        // 0: genesis
        // 1-10: v6
        // 11-20: v7
        bytes[] memory headers = new bytes[](21);
        {
            bytes[] memory headersV7 = _prepareBatchesV7Codec(7);
            for (uint256 i = 0; i <= 10; ++i) {
                headers[i] = headersV7[i];
            }
        }
        for (uint256 i = 11; i < 21; ++i) {
            headers[i] = _commitBatchV7Codec(7, headers[i - 1]);
        }
        // finalize all v6 batches
        hevm.startPrank(address(0));
        rollup.finalizeBundlePostEuclidV2(headers[10], 10, keccak256("x10"), keccak256("y10"), new bytes(0));
        hevm.stopPrank();
        // finalize two v7 batches
        hevm.startPrank(address(0));
        rollup.finalizeBundlePostEuclidV2(headers[12], 10, keccak256("x12"), keccak256("y12"), new bytes(0));
        hevm.stopPrank();

        // revert when ErrorNotInEnforcedBatchMode
        hevm.expectRevert(ScrollChain.ErrorNotInEnforcedBatchMode.selector);
        hevm.startPrank(address(0x00a329c0648769A73afAc7F9381E08FB43dBEA72));
        rollup.commitAndFinalizeBatch(
            7,
            bytes32(0),
            IScrollChain.FinalizeStruct({
                batchHeader: new bytes(0),
                totalL1MessagesPoppedOverall: 0,
                postStateRoot: bytes32(0),
                withdrawRoot: bytes32(0),
                zkProof: new bytes(0)
            })
        );
        hevm.stopPrank();

        system.updateEnforcedBatchParameters(
            SystemConfig.EnforcedBatchParameters({
                maxDelayEnterEnforcedMode: 86400,
                maxDelayMessageQueue: type(uint24).max
            })
        );

        hevm.warp(100 + 86400 + 1);
        // succeed to call commitAndFinalizeBatch 13
        ScrollChainMockBlob(address(rollup)).setBlobVersionedHash(0, blobVersionedHash);
        ScrollChainMockBlob(address(rollup)).setBlobVersionedHash(1, bytes32(0));
        hevm.startPrank(address(0x00a329c0648769A73afAc7F9381E08FB43dBEA72));
        rollup.commitAndFinalizeBatch(
            7,
            keccak256(headers[12]),
            IScrollChain.FinalizeStruct({
                batchHeader: headers[13],
                totalL1MessagesPoppedOverall: 10,
                postStateRoot: keccak256("x13"),
                withdrawRoot: keccak256("y13"),
                zkProof: new bytes(0)
            })
        );
        hevm.stopPrank();
        (uint256 lastCommittedBatchIndex, uint256 lastFinalizedBatchIndex, uint256 lastFinalizeTimestamp, , ) = rollup
            .miscData();
        assertEq(lastCommittedBatchIndex, 13);
        assertEq(lastFinalizedBatchIndex, 13);
        assertEq(lastFinalizeTimestamp, 100 + 86400 + 1);
        assertBoolEq(rollup.isEnforcedModeEnabled(), true);
        assertEq(messageQueueV2.nextUnfinalizedQueueIndex(), 10);
        assertEq(messageQueueV2.nextCrossDomainMessageIndex(), 10);
        assertEq(messageQueueV2.getFirstUnfinalizedMessageEnqueueTime(), 100 + 86400 + 1);
    }

    function testRevertBatch() external {
        messageQueueV2.initialize();
        rollup.initializeV2();
        // import 10 L1 messages into message queue V2
        for (uint256 i = 0; i < 10; i++) {
            messageQueueV2.appendCrossDomainMessage(address(this), 1000000, new bytes(0));
        }
        // 0: genesis
        // 1-10: v6
        // 11-20: v7
        bytes[] memory headers = new bytes[](21);
        {
            bytes[] memory headersV7 = _prepareBatchesV7Codec(7);
            for (uint256 i = 0; i <= 10; ++i) {
                headers[i] = headersV7[i];
            }
        }
        for (uint256 i = 11; i < 21; ++i) {
            headers[i] = _commitBatchV7Codec(7, headers[i - 1]);
        }
        // finalize two v7 batches
        hevm.startPrank(address(0));
        rollup.finalizeBundlePostEuclidV2(headers[12], 10, keccak256("x12"), keccak256("y12"), new bytes(0));
        hevm.stopPrank();

        // caller not owner, revert
        hevm.startPrank(address(1));
        hevm.expectRevert("Ownable: caller is not the owner");
        rollup.revertBatch(new bytes(0));
        hevm.stopPrank();

        // revert ErrorIncorrectBatchVersion
        // hevm.expectRevert(ScrollChain.ErrorIncorrectBatchVersion.selector);
        // rollup.revertBatch(headers[10]);

        // revert ErrorRevertFinalizedBatch
        hevm.expectRevert(ScrollChain.ErrorRevertFinalizedBatch.selector);
        rollup.revertBatch(headers[11]);

        (uint256 lastCommittedBatchIndex, , , , ) = rollup.miscData();
        assertEq(lastCommittedBatchIndex, 20);

        // revert batch 20
        hevm.expectEmit(true, true, true, true);
        emit RevertBatch(20, 20);
        rollup.revertBatch(headers[19]);
        (lastCommittedBatchIndex, , , , ) = rollup.miscData();
        assertEq(lastCommittedBatchIndex, 19);

        // revert batch 18 and 19
        hevm.expectEmit(true, true, true, true);
        emit RevertBatch(18, 19);
        rollup.revertBatch(headers[17]);
        (lastCommittedBatchIndex, , , , ) = rollup.miscData();
        assertEq(lastCommittedBatchIndex, 17);

        // revert all batches
        rollup.revertBatch(headers[12]);
        (lastCommittedBatchIndex, , , , ) = rollup.miscData();
        assertEq(lastCommittedBatchIndex, 12);
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
        rollup.commitBatches(7, bytes32(0), bytes32(0));
        hevm.expectRevert("Pausable: paused");
        rollup.finalizeBundlePostEuclidV2(new bytes(0), 0, bytes32(0), bytes32(0), new bytes(0));
        hevm.stopPrank();

        // unpause
        rollup.setPause(false);
        assertBoolEq(false, rollup.paused());
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
        hevm.expectRevert(ScrollChain.ErrorBatchNotCommitted.selector);
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
            rollup.messageQueueV1(),
            rollup.messageQueueV2(),
            rollup.verifier(),
            rollup.systemConfig()
        );
        admin.upgrade(ITransparentUpgradeableProxy(address(rollup)), address(impl));
        ScrollChainMockBlob(address(rollup)).setBlobVersionedHash(0, blobVersionedHash);
    }

    function _commitGenesisBatch() internal returns (bytes memory header) {
        header = new bytes(89);
        assembly {
            mstore(add(header, add(0x20, 25)), 1)
        }
        rollup.importGenesisBatch(header, bytes32(uint256(1)));
        assertEq(rollup.committedBatches(0), keccak256(header));
    }

    function _constructBatchStructCodecV7(uint8 version, bytes memory parentHeader)
        internal
        pure
        returns (uint256 index, bytes memory header)
    {
        uint256 batchPtr;
        assembly {
            batchPtr := add(parentHeader, 0x20)
        }
        index = BatchHeaderV0Codec.getBatchIndex(batchPtr) + 1;
        bytes32 parentHash = keccak256(parentHeader);
        header = new bytes(73);
        assembly {
            mstore8(add(header, 0x20), version) // version
            mstore(add(header, add(0x20, 1)), shl(192, index)) // batchIndex
            mstore(add(header, add(0x20, 9)), 0x013590dc3544d56629ba81bb14d4d31248f825001653aa575eb8e3a719046757) // blobVersionedHash
            mstore(add(header, add(0x20, 41)), parentHash) // parentBatchHash
        }
    }

    function _commitBatchV7Codec(uint8 version, bytes memory parentHeader) internal returns (bytes memory) {
        (uint256 index, bytes memory header) = _constructBatchStructCodecV7(version, parentHeader);
        hevm.startPrank(address(0));
        hevm.expectEmit(true, true, false, true);
        emit CommitBatch(index, keccak256(header));
        rollup.commitBatches(version, keccak256(parentHeader), keccak256(header));
        hevm.stopPrank();
        assertEq(rollup.committedBatches(index), keccak256(header));
        return header;
    }

    /// @dev Prepare 10 batches, each of the first 5 has 2 l1 messages, each of the second 5 has no l1 message.
    function _prepareBatchesV7Codec(uint8 version) internal returns (bytes[] memory headers) {
        // grant roles
        rollup.addProver(address(0));
        rollup.addSequencer(address(0));
        _upgradeToMockBlob();

        headers = new bytes[](11);
        // commit genesis batch
        headers[0] = _commitGenesisBatch();
        // commit 5 batches, each has 2 l1 messages
        for (uint256 i = 1; i <= 5; ++i) {
            headers[i] = _commitBatchV7Codec(version, headers[i - 1]);
        }
        // commit 5 batches, each has 0 l1 message
        for (uint256 i = 6; i <= 10; ++i) {
            headers[i] = _commitBatchV7Codec(version, headers[i - 1]);
        }
    }
}
