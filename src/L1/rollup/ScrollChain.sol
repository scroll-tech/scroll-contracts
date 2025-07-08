// SPDX-License-Identifier: MIT

pragma solidity =0.8.24;

import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";

import {IL1MessageQueueV1} from "./IL1MessageQueueV1.sol";
import {IL1MessageQueueV2} from "./IL1MessageQueueV2.sol";
import {IScrollChain} from "./IScrollChain.sol";
import {BatchHeaderV0Codec} from "../../libraries/codec/BatchHeaderV0Codec.sol";
import {BatchHeaderV1Codec} from "../../libraries/codec/BatchHeaderV1Codec.sol";
import {BatchHeaderV3Codec} from "../../libraries/codec/BatchHeaderV3Codec.sol";
import {BatchHeaderV7Codec} from "../../libraries/codec/BatchHeaderV7Codec.sol";
import {IRollupVerifier} from "../../libraries/verifier/IRollupVerifier.sol";

import {SystemConfig} from "../system-contract/SystemConfig.sol";

// solhint-disable no-inline-assembly
// solhint-disable reason-string

/// @title ScrollChain
/// @notice This contract maintains data for the Scroll rollup.
contract ScrollChain is OwnableUpgradeable, PausableUpgradeable, IScrollChain {
    /**********
     * Errors *
     **********/

    /// @dev Thrown when the given account is not EOA account.
    error ErrorAccountIsNotEOA();

    /// @dev Thrown when finalizing a verified batch.
    error ErrorBatchIsAlreadyVerified();

    /// @dev Thrown when committing empty batch (batch without chunks)
    error ErrorBatchIsEmpty();

    /// @dev Thrown when the caller is not prover.
    error ErrorCallerIsNotProver();

    /// @dev Thrown when the caller is not sequencer.
    error ErrorCallerIsNotSequencer();

    /// @dev Thrown when some fields are not zero in genesis batch.
    error ErrorGenesisBatchHasNonZeroField();

    /// @dev Thrown when importing genesis batch twice.
    error ErrorGenesisBatchImported();

    /// @dev Thrown when data hash in genesis batch is zero.
    error ErrorGenesisDataHashIsZero();

    /// @dev Thrown when the parent batch hash in genesis batch is zero.
    error ErrorGenesisParentBatchHashIsNonZero();

    /// @dev Thrown when the batch hash is incorrect.
    error ErrorIncorrectBatchHash();

    /// @dev Thrown when the batch version is incorrect.
    error ErrorIncorrectBatchVersion();

    /// @dev Thrown when reverting a finalized batch.
    error ErrorRevertFinalizedBatch();

    /// @dev Thrown when the given state root is zero.
    error ErrorStateRootIsZero();

    /// @dev Thrown when the given address is `address(0)`.
    error ErrorZeroAddress();

    /// @dev Thrown when we try to commit or finalize normal batch in enforced batch mode.
    error ErrorInEnforcedBatchMode();

    /// @dev Thrown when we try to commit enforced batch while not in enforced batch mode.
    error ErrorNotInEnforcedBatchMode();

    /// @dev Thrown when finalize v7 batches while some v1 messages still unfinalized.
    error ErrorNotAllV1MessagesAreFinalized();

    /// @dev Thrown when the committed batch hash doesn't match off-chain computed one.
    error InconsistentBatchHash(uint256 batchIndex, bytes32 expected, bytes32 actual);

    /// @dev Thrown when given batch is not committed before.
    error ErrorBatchNotCommitted();

    /// @dev Thrown when the function call is not the top-level call in the transaction.
    /// @dev This is checked so that indexers that need to decode calldata continue to work.
    error ErrorTopLevelCallRequired();

    /*************
     * Constants *
     *************/

    /// @dev offsets in miscData.flags
    uint256 private constant V1_MESSAGES_FINALIZED_OFFSET = 0;
    uint256 private constant ENFORCED_MODE_OFFSET = 1;

    /// @notice The chain id of the corresponding layer 2 chain.
    uint64 public immutable layer2ChainId;

    /// @notice The address of `L1MessageQueueV1`.
    address public immutable messageQueueV1;

    /// @notice The address of `L1MessageQueueV2`.
    address public immutable messageQueueV2;

    /// @notice The address of `MultipleVersionRollupVerifier`.
    address public immutable verifier;

    /// @notice The address of `SystemConfig`.
    address public immutable systemConfig;

    /***********
     * Structs *
     ***********/

    /// @param lastCommittedBatchIndex The index of the last committed batch.
    /// @param lastFinalizedBatchIndex The index of the last finalized batch.
    /// @param lastFinalizeTimestamp The timestamp of the last finalize transaction.
    /// @param flags Various flags for saving gas. It has 8 bits.
    ///        + bit 0 indicates whether all v1 messages are finalized, 1 means finalized and 0 means not.
    ///        + bit 1 indicates whether the enforced batch mode is enabled, 1 means enabled and 0 means disabled.
    /// @dev We use `32` bits for the timestamp, which works until `Feb 07 2106 06:28:15 GMT+0000`.
    struct ScrollChainMiscData {
        uint64 lastCommittedBatchIndex;
        uint64 lastFinalizedBatchIndex;
        uint32 lastFinalizeTimestamp;
        uint8 flags;
        uint88 reserved;
    }

    /*************
     * Variables *
     *************/

    /// @dev The maximum number of transactions allowed in each chunk.
    /// @custom:deprecated This is no longer used.
    uint256 private __maxNumTxInChunk;

    /// @dev The storage slot used as L1MessageQueue contract, which is deprecated now.
    /// @custom:deprecated This is no longer used.
    address private __messageQueue;

    /// @dev The storage slot used as RollupVerifier contract, which is deprecated now.
    /// @custom:deprecated This is no longer used.
    address private __verifier;

    /// @notice Whether an account is a sequencer.
    mapping(address => bool) public isSequencer;

    /// @notice Whether an account is a prover.
    mapping(address => bool) public isProver;

    /// @dev The storage slot used as `lastFinalizedBatchIndex`, which is deprecated now.
    /// @custom:deprecated This is no longer used.
    uint256 private __lastFinalizedBatchIndex;

    /// @inheritdoc IScrollChain
    /// @dev Starting from EuclidV2, this array is sparse: it only contains
    /// the last batch hash per commit transaction, and not intermediate ones.
    mapping(uint256 => bytes32) public override committedBatches;

    /// @inheritdoc IScrollChain
    /// @dev Starting from Darwin, this array is sparse: it only contains
    /// the last state root per finalized bundle, and not intermediate ones.
    mapping(uint256 => bytes32) public override finalizedStateRoots;

    /// @inheritdoc IScrollChain
    /// @dev Starting from Darwin, this array is sparse: it only contains
    /// the last withdraw root per finalized bundle, and not intermediate ones.
    mapping(uint256 => bytes32) public override withdrawRoots;

    /// @notice The index of first Euclid batch.
    uint256 public initialEuclidBatchIndex;

    /// @notice The misc data of ScrollChain.
    ScrollChainMiscData public miscData;

    /**********************
     * Function Modifiers *
     **********************/

    modifier OnlySequencer() {
        // @note In the decentralized mode, it should be only called by a list of validator.
        if (!isSequencer[_msgSender()]) revert ErrorCallerIsNotSequencer();
        _;
    }

    modifier OnlyProver() {
        if (!isProver[_msgSender()]) revert ErrorCallerIsNotProver();
        _;
    }

    modifier whenEnforcedBatchNotEnabled() {
        if (isEnforcedModeEnabled()) revert ErrorInEnforcedBatchMode();
        _;
    }

    modifier OnlyTopLevelCall() {
        // disallow contract accounts and delegated EOAs
        if (msg.sender != tx.origin || msg.sender.code.length != 0) {
            revert ErrorTopLevelCallRequired();
        }
        _;
    }

    /***************
     * Constructor *
     ***************/

    /// @notice Constructor for `ScrollChain` implementation contract.
    ///
    /// @param _chainId The chain id of L2.
    /// @param _messageQueueV1 The address of `L1MessageQueueV1`.
    /// @param _messageQueueV2 The address of `L1MessageQueueV2`.
    /// @param _verifier The address of `MultipleVersionRollupVerifier`.
    /// @param _systemConfig The address of `SystemConfig`.
    constructor(
        uint64 _chainId,
        address _messageQueueV1,
        address _messageQueueV2,
        address _verifier,
        address _systemConfig
    ) {
        if (
            _messageQueueV1 == address(0) ||
            _messageQueueV2 == address(0) ||
            _verifier == address(0) ||
            _systemConfig == address(0)
        ) {
            revert ErrorZeroAddress();
        }

        _disableInitializers();

        layer2ChainId = _chainId;
        messageQueueV1 = _messageQueueV1;
        messageQueueV2 = _messageQueueV2;
        verifier = _verifier;
        systemConfig = _systemConfig;
    }

    /// @notice Initialize the storage of ScrollChain.
    ///
    /// @dev The parameters `_messageQueue` and `_verifier` are no longer used.
    ///
    /// @param _messageQueue The address of `L1MessageQueue` contract.
    /// @param _verifier The address of zkevm verifier contract.
    /// @param _maxNumTxInChunk The maximum number of transactions allowed in each chunk.
    function initialize(
        address _messageQueue,
        address _verifier,
        uint256 _maxNumTxInChunk
    ) external initializer {
        OwnableUpgradeable.__Ownable_init();

        __maxNumTxInChunk = _maxNumTxInChunk;
        __verifier = _verifier;
        __messageQueue = _messageQueue;
    }

    function initializeV2() external reinitializer(2) {
        // binary search on lastCommittedBatchIndex
        uint256 index = __lastFinalizedBatchIndex;
        uint256 step = 1;
        unchecked {
            while (committedBatches[index + step] != bytes32(0)) {
                step <<= 1;
            }
            step >>= 1;
            while (step > 0) {
                if (committedBatches[index + step] != bytes32(0)) {
                    index += step;
                }
                step >>= 1;
            }
        }

        miscData = ScrollChainMiscData({
            lastCommittedBatchIndex: uint64(index),
            lastFinalizedBatchIndex: uint64(__lastFinalizedBatchIndex),
            lastFinalizeTimestamp: uint32(block.timestamp),
            flags: 0,
            reserved: 0
        });
    }

    /*************************
     * Public View Functions *
     *************************/

    /// @inheritdoc IScrollChain
    function isBatchFinalized(uint256 _batchIndex) external view override returns (bool) {
        return _batchIndex <= miscData.lastFinalizedBatchIndex;
    }

    /// @inheritdoc IScrollChain
    function lastFinalizedBatchIndex() external view returns (uint256) {
        return miscData.lastFinalizedBatchIndex;
    }

    /// @notice Return whether we are in enforced batch mode.
    function isEnforcedModeEnabled() public view returns (bool) {
        return _decodeBoolFromFlag(miscData.flags, ENFORCED_MODE_OFFSET);
    }

    /*****************************
     * Public Mutating Functions *
     *****************************/

    /// @notice Import layer 2 genesis block
    /// @param _batchHeader The header of the genesis batch.
    /// @param _stateRoot The state root of the genesis block.
    function importGenesisBatch(bytes calldata _batchHeader, bytes32 _stateRoot) external {
        // check genesis batch header length
        if (_stateRoot == bytes32(0)) revert ErrorStateRootIsZero();

        // check whether the genesis batch is imported
        if (finalizedStateRoots[0] != bytes32(0)) revert ErrorGenesisBatchImported();

        (uint256 memPtr, bytes32 _batchHash, , ) = _loadBatchHeader(_batchHeader, 0);

        // check all fields except `dataHash` and `lastBlockHash` are zero
        unchecked {
            uint256 sum = BatchHeaderV0Codec.getVersion(memPtr) +
                BatchHeaderV0Codec.getBatchIndex(memPtr) +
                BatchHeaderV0Codec.getL1MessagePopped(memPtr) +
                BatchHeaderV0Codec.getTotalL1MessagePopped(memPtr);
            if (sum != 0) revert ErrorGenesisBatchHasNonZeroField();
        }
        if (BatchHeaderV0Codec.getDataHash(memPtr) == bytes32(0)) revert ErrorGenesisDataHashIsZero();
        if (BatchHeaderV0Codec.getParentBatchHash(memPtr) != bytes32(0)) revert ErrorGenesisParentBatchHashIsNonZero();

        committedBatches[0] = _batchHash;
        finalizedStateRoots[0] = _stateRoot;

        emit CommitBatch(0, _batchHash);
        emit FinalizeBatch(0, _batchHash, _stateRoot, bytes32(0));
    }

    /// @inheritdoc IScrollChain
    function commitBatches(
        uint8 version,
        bytes32 parentBatchHash,
        bytes32 lastBatchHash
    ) external override OnlySequencer whenNotPaused whenEnforcedBatchNotEnabled {
        _commitBatchesFromV7(version, parentBatchHash, lastBatchHash, false);
    }

    /// @inheritdoc IScrollChain
    /// @dev This function cannot revert V6 and V7 batches at the same time, so we will assume all batches are V7.
    /// If we need to revert V6 batches, we can downgrade the contract to the previous version and call this function.
    /// @dev During commit batch we only store the last batch hash into storage. As a result, we cannot revert intermediate batches.
    function revertBatch(bytes calldata batchHeader) external onlyOwner {
        uint256 lastBatchIndex = miscData.lastCommittedBatchIndex;
        (uint256 batchPtr, , uint256 startBatchIndex, ) = _loadBatchHeader(batchHeader, lastBatchIndex);
        // only revert v7 batches
        if (BatchHeaderV0Codec.getVersion(batchPtr) < 7) revert ErrorIncorrectBatchVersion();
        // check finalization
        if (startBatchIndex < miscData.lastFinalizedBatchIndex) revert ErrorRevertFinalizedBatch();

        // actual revert
        for (uint256 i = lastBatchIndex; i > startBatchIndex; --i) {
            bytes32 hash = committedBatches[i];
            if (hash != bytes32(0)) delete committedBatches[i];
        }
        emit RevertBatch(startBatchIndex + 1, lastBatchIndex);

        // update `lastCommittedBatchIndex`
        miscData.lastCommittedBatchIndex = uint64(startBatchIndex);
    }

    /// @inheritdoc IScrollChain
    function finalizeBundlePostEuclidV2(
        bytes calldata batchHeader,
        uint256 totalL1MessagesPoppedOverall,
        bytes32 postStateRoot,
        bytes32 withdrawRoot,
        bytes calldata aggrProof
    ) external override OnlyProver whenNotPaused whenEnforcedBatchNotEnabled {
        uint256 flags = miscData.flags;
        bool isV1MessageFinalized = _decodeBoolFromFlag(flags, V1_MESSAGES_FINALIZED_OFFSET);
        if (!isV1MessageFinalized) {
            if (
                IL1MessageQueueV1(messageQueueV1).nextUnfinalizedQueueIndex() !=
                IL1MessageQueueV2(messageQueueV2).firstCrossDomainMessageIndex()
            ) {
                revert ErrorNotAllV1MessagesAreFinalized();
            }
            miscData.flags = uint8(_insertBoolToFlag(flags, V1_MESSAGES_FINALIZED_OFFSET, true));
        }

        _finalizeBundlePostEuclidV2(batchHeader, totalL1MessagesPoppedOverall, postStateRoot, withdrawRoot, aggrProof);
    }

    /// @inheritdoc IScrollChain
    /// @dev We only consider batch version >= 7 here.
    function commitAndFinalizeBatch(
        uint8 version,
        bytes32 parentBatchHash,
        FinalizeStruct calldata finalizeStruct
    ) external OnlyTopLevelCall {
        ScrollChainMiscData memory cachedMiscData = miscData;
        if (!isEnforcedModeEnabled()) {
            (uint256 maxDelayEnterEnforcedMode, uint256 maxDelayMessageQueue) = SystemConfig(systemConfig)
                .enforcedBatchParameters();
            uint256 firstUnfinalizedMessageTime = IL1MessageQueueV2(messageQueueV2)
                .getFirstUnfinalizedMessageEnqueueTime();
            if (
                firstUnfinalizedMessageTime + maxDelayMessageQueue < block.timestamp ||
                cachedMiscData.lastFinalizeTimestamp + maxDelayEnterEnforcedMode < block.timestamp
            ) {
                if (cachedMiscData.lastFinalizedBatchIndex < cachedMiscData.lastCommittedBatchIndex) {
                    // be careful with the gas costs, maybe should call revertBatch first.
                    for (
                        uint256 i = cachedMiscData.lastCommittedBatchIndex;
                        i > cachedMiscData.lastFinalizedBatchIndex;
                        --i
                    ) {
                        bytes32 hash = committedBatches[i];
                        if (hash != bytes32(0)) delete committedBatches[i];
                    }
                    emit RevertBatch(
                        cachedMiscData.lastFinalizedBatchIndex + 1,
                        cachedMiscData.lastCommittedBatchIndex
                    );
                }
                // explicitly enable enforced batch mode
                cachedMiscData.flags = uint8(_insertBoolToFlag(cachedMiscData.flags, ENFORCED_MODE_OFFSET, true));
                // reset `lastCommittedBatchIndex`
                cachedMiscData.lastCommittedBatchIndex = uint64(cachedMiscData.lastFinalizedBatchIndex);
                miscData = cachedMiscData;
                emit UpdateEnforcedBatchMode(true, cachedMiscData.lastCommittedBatchIndex);
            } else {
                revert ErrorNotInEnforcedBatchMode();
            }
        }

        bytes32 batchHash = keccak256(finalizeStruct.batchHeader);
        _commitBatchesFromV7(version, parentBatchHash, batchHash, true);

        // finalize with zk proof
        _finalizeBundlePostEuclidV2(
            finalizeStruct.batchHeader,
            finalizeStruct.totalL1MessagesPoppedOverall,
            finalizeStruct.postStateRoot,
            finalizeStruct.withdrawRoot,
            finalizeStruct.zkProof
        );
    }

    /************************
     * Restricted Functions *
     ************************/

    /// @notice Add an account to the sequencer list.
    /// @param _account The address of account to add.
    function addSequencer(address _account) external onlyOwner {
        // @note Currently many external services rely on EOA sequencer to decode metadata directly from tx.calldata.
        // So we explicitly make sure the account is EOA.
        if (_account.code.length > 0) revert ErrorAccountIsNotEOA();

        isSequencer[_account] = true;

        emit UpdateSequencer(_account, true);
    }

    /// @notice Remove an account from the sequencer list.
    /// @param _account The address of account to remove.
    function removeSequencer(address _account) external onlyOwner {
        isSequencer[_account] = false;

        emit UpdateSequencer(_account, false);
    }

    /// @notice Add an account to the prover list.
    /// @param _account The address of account to add.
    function addProver(address _account) external onlyOwner {
        // @note Currently many external services rely on EOA prover to decode metadata directly from tx.calldata.
        // So we explicitly make sure the account is EOA.
        if (_account.code.length > 0) revert ErrorAccountIsNotEOA();
        isProver[_account] = true;

        emit UpdateProver(_account, true);
    }

    /// @notice Add an account from the prover list.
    /// @param _account The address of account to remove.
    function removeProver(address _account) external onlyOwner {
        isProver[_account] = false;

        emit UpdateProver(_account, false);
    }

    /// @notice Pause the contract
    /// @param _status The pause status to update.
    function setPause(bool _status) external onlyOwner {
        if (_status) {
            _pause();
        } else {
            _unpause();
        }
    }

    /// @notice Exit from enforced batch mode.
    function disableEnforcedBatchMode() external onlyOwner {
        miscData.flags = uint8(_insertBoolToFlag(miscData.flags, ENFORCED_MODE_OFFSET, false));
        emit UpdateEnforcedBatchMode(false, miscData.lastCommittedBatchIndex);
    }

    /**********************
     * Internal Functions *
     **********************/

    /// @dev Caller should make sure bit is smaller than 256.
    function _decodeBoolFromFlag(uint256 flag, uint256 bit) internal pure returns (bool) {
        return (flag >> bit) & 1 == 1;
    }

    /// @dev Caller should make sure bit is smaller than 256.
    function _insertBoolToFlag(
        uint256 flag,
        uint256 bit,
        bool value
    ) internal pure returns (uint256) {
        flag = flag ^ (flag & (1 << bit)); // reset value at bit
        if (value) {
            flag |= (1 << bit);
        }
        return flag;
    }

    /// @dev Internal function to do common actions before actual batch finalization.
    function _beforeFinalizeBatch(bytes calldata batchHeader, bytes32 postStateRoot)
        internal
        view
        returns (
            uint256 version,
            bytes32 batchHash,
            uint256 batchIndex,
            uint256 totalL1MessagesPoppedOverall,
            uint256 prevBatchIndex
        )
    {
        if (postStateRoot == bytes32(0)) revert ErrorStateRootIsZero();

        ScrollChainMiscData memory cachedMiscData = miscData;
        uint256 batchPtr;
        // compute pending batch hash and verify
        (batchPtr, batchHash, batchIndex, totalL1MessagesPoppedOverall) = _loadBatchHeader(
            batchHeader,
            cachedMiscData.lastCommittedBatchIndex
        );

        // make sure don't finalize batch multiple times
        prevBatchIndex = cachedMiscData.lastFinalizedBatchIndex;
        if (batchIndex <= prevBatchIndex) revert ErrorBatchIsAlreadyVerified();

        version = BatchHeaderV0Codec.getVersion(batchPtr);
    }

    /// @dev Internal function to do common actions after actual batch finalization.
    function _afterFinalizeBatch(
        uint256 batchIndex,
        bytes32 batchHash,
        uint256 totalL1MessagesPoppedOverall,
        bytes32 postStateRoot,
        bytes32 withdrawRoot,
        bool isV1
    ) internal {
        ScrollChainMiscData memory cachedMiscData = miscData;
        cachedMiscData.lastFinalizedBatchIndex = uint64(batchIndex);
        cachedMiscData.lastFinalizeTimestamp = uint32(block.timestamp);
        miscData = cachedMiscData;
        // @note we do not store intermediate finalized roots
        finalizedStateRoots[batchIndex] = postStateRoot;
        withdrawRoots[batchIndex] = withdrawRoot;

        // Pop finalized and non-skipped message from L1MessageQueue.
        _finalizePoppedL1Messages(totalL1MessagesPoppedOverall, isV1);

        emit FinalizeBatch(batchIndex, batchHash, postStateRoot, withdrawRoot);
    }

    /// @dev Internal function to get the blob versioned hash.
    /// @return _blobVersionedHash The retrieved blob versioned hash.
    function _getBlobVersionedHash(uint256 index) internal virtual returns (bytes32 _blobVersionedHash) {
        // Get blob's versioned hash
        assembly {
            _blobVersionedHash := blobhash(index)
        }
    }

    /// @dev Internal function to commit one ore more batches after the EuclidV2 upgrade.
    /// @param version The version of the batches (version >= 7).
    /// @param parentBatchHash The hash of parent batch.
    /// @param lastBatchHash The hash of the last committed batch after this call.
    /// @param onlyOne If true, we will only process the first blob.
    function _commitBatchesFromV7(
        uint8 version,
        bytes32 parentBatchHash,
        bytes32 lastBatchHash,
        bool onlyOne
    ) internal {
        if (version < 7) {
            // only accept version >= 7
            revert ErrorIncorrectBatchVersion();
        }

        uint256 lastCommittedBatchIndex = miscData.lastCommittedBatchIndex;
        if (parentBatchHash != committedBatches[lastCommittedBatchIndex]) revert ErrorIncorrectBatchHash();
        for (uint256 i = 0; ; i++) {
            bytes32 blobVersionedHash = _getBlobVersionedHash(i);
            if (blobVersionedHash == bytes32(0)) {
                if (i == 0) revert ErrorBatchIsEmpty();
                break;
            }

            lastCommittedBatchIndex += 1;
            // see comments in `src/libraries/codec/BatchHeaderV7Codec.sol` for encodings
            uint256 batchPtr = BatchHeaderV7Codec.allocate();
            BatchHeaderV0Codec.storeVersion(batchPtr, version);
            BatchHeaderV0Codec.storeBatchIndex(batchPtr, lastCommittedBatchIndex);
            BatchHeaderV7Codec.storeParentBatchHash(batchPtr, parentBatchHash);
            BatchHeaderV7Codec.storeBlobVersionedHash(batchPtr, blobVersionedHash);
            bytes32 batchHash = BatchHeaderV0Codec.computeBatchHash(
                batchPtr,
                BatchHeaderV7Codec.BATCH_HEADER_FIXED_LENGTH
            );
            emit CommitBatch(lastCommittedBatchIndex, batchHash);
            parentBatchHash = batchHash;
            if (onlyOne) break;
        }

        // Make sure that the batch hash matches the one computed by the batch committer off-chain.
        // This check can fail if:
        // 1. faulty batch producers commit a wrong batch or the local computation is wrong.
        // 2. unexpected `parentBatch` in case commit transactions get reordered
        // 3. two batch producers commit at the same time with the same `parentBatch`.
        if (parentBatchHash != lastBatchHash) {
            revert InconsistentBatchHash(lastCommittedBatchIndex, lastBatchHash, parentBatchHash);
        }
        // only store last batch hash in storage
        committedBatches[lastCommittedBatchIndex] = parentBatchHash;
        miscData.lastCommittedBatchIndex = uint64(lastCommittedBatchIndex);
    }

    /// @dev Internal function to finalize a bundle after the EuclidV2 upgrade.
    /// @param batchHeader The header of the last batch in this bundle.
    /// @param totalL1MessagesPoppedOverall The number of messages processed after this bundle.
    /// @param postStateRoot The state root after this bundle.
    /// @param withdrawRoot The withdraw trie root after this bundle.
    /// @param aggrProof The bundle proof for this bundle.
    function _finalizeBundlePostEuclidV2(
        bytes calldata batchHeader,
        uint256 totalL1MessagesPoppedOverall,
        bytes32 postStateRoot,
        bytes32 withdrawRoot,
        bytes calldata aggrProof
    ) internal {
        // actions before verification
        (uint256 version, bytes32 batchHash, uint256 batchIndex, , uint256 prevBatchIndex) = _beforeFinalizeBatch(
            batchHeader,
            postStateRoot
        );

        // L1 message hashes are chained,
        // this hash commits to the whole queue up to and including `totalL1MessagesPoppedOverall-1`
        bytes32 messageQueueHash = totalL1MessagesPoppedOverall == 0
            ? bytes32(0)
            : IL1MessageQueueV2(messageQueueV2).getMessageRollingHash(totalL1MessagesPoppedOverall - 1);

        bytes memory publicInputs = abi.encodePacked(
            layer2ChainId,
            messageQueueHash,
            uint32(batchIndex - prevBatchIndex), // numBatches
            finalizedStateRoots[prevBatchIndex], // _prevStateRoot
            committedBatches[prevBatchIndex], // _prevBatchHash
            postStateRoot,
            batchHash,
            withdrawRoot
        );

        // verify bundle, choose the correct verifier based on the last batch
        // our off-chain service will make sure all unfinalized batches have the same batch version.
        IRollupVerifier(verifier).verifyBundleProof(version, batchIndex, aggrProof, publicInputs);

        // actions after verification
        _afterFinalizeBatch(batchIndex, batchHash, totalL1MessagesPoppedOverall, postStateRoot, withdrawRoot, false);
    }

    /// @dev Internal function to load batch header from calldata to memory.
    /// @param _batchHeader The batch header in calldata.
    /// @param _lastCommittedBatchIndex The index of the last committed batch.
    /// @return batchPtr The start memory offset of loaded batch header.
    /// @return _batchHash The hash of the loaded batch header.
    /// @return _batchIndex The index of this batch.
    /// @return _totalL1MessagesPoppedOverall The number of L1 messages popped after this batch.
    /// @dev This function only works with batches whose hashes are stored in `committedBatches`.
    function _loadBatchHeader(bytes calldata _batchHeader, uint256 _lastCommittedBatchIndex)
        internal
        view
        virtual
        returns (
            uint256 batchPtr,
            bytes32 _batchHash,
            uint256 _batchIndex,
            uint256 _totalL1MessagesPoppedOverall
        )
    {
        // load version from batch header, it is always the first byte.
        uint256 version;
        assembly {
            version := shr(248, calldataload(_batchHeader.offset))
        }

        uint256 _length;
        if (version == 0) {
            (batchPtr, _length) = BatchHeaderV0Codec.loadAndValidate(_batchHeader);
        } else if (version <= 2) {
            (batchPtr, _length) = BatchHeaderV1Codec.loadAndValidate(_batchHeader);
        } else if (version <= 6) {
            (batchPtr, _length) = BatchHeaderV3Codec.loadAndValidate(_batchHeader);
        } else {
            (batchPtr, _length) = BatchHeaderV7Codec.loadAndValidate(_batchHeader);
        }

        // the code for compute batch hash is the same for V0~V6
        // also the `_batchIndex` and `_totalL1MessagesPoppedOverall`.
        _batchHash = BatchHeaderV0Codec.computeBatchHash(batchPtr, _length);
        _batchIndex = BatchHeaderV0Codec.getBatchIndex(batchPtr);
        // we don't have totalL1MessagesPoppedOverall in V7~
        if (version <= 6) {
            _totalL1MessagesPoppedOverall = BatchHeaderV0Codec.getTotalL1MessagePopped(batchPtr);
        }

        if (_batchIndex > _lastCommittedBatchIndex) revert ErrorBatchNotCommitted();

        // only check when genesis is imported
        if (committedBatches[_batchIndex] != _batchHash && finalizedStateRoots[0] != bytes32(0)) {
            revert ErrorIncorrectBatchHash();
        }
    }

    /// @param totalL1MessagesPoppedOverall The total number of L1 messages popped in all batches including current batch.
    function _finalizePoppedL1Messages(uint256 totalL1MessagesPoppedOverall, bool isV1) internal {
        if (totalL1MessagesPoppedOverall > 0) {
            if (isV1) {
                IL1MessageQueueV1(messageQueueV1).finalizePoppedCrossDomainMessage(totalL1MessagesPoppedOverall);
            } else {
                IL1MessageQueueV2(messageQueueV2).finalizePoppedCrossDomainMessage(totalL1MessagesPoppedOverall);
            }
        }
    }
}
