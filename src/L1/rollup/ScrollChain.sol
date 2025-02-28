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
import {ChunkCodecV0} from "../../libraries/codec/ChunkCodecV0.sol";
import {ChunkCodecV1} from "../../libraries/codec/ChunkCodecV1.sol";
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

    /// @dev Thrown when committing a committed batch.
    error ErrorBatchIsAlreadyCommitted();

    /// @dev Thrown when finalizing a verified batch.
    error ErrorBatchIsAlreadyVerified();

    /// @dev Thrown when committing empty batch (batch without chunks)
    error ErrorBatchIsEmpty();

    /// @dev Thrown when call precompile failed.
    error ErrorCallPointEvaluationPrecompileFailed();

    /// @dev Thrown when the caller is not prover.
    error ErrorCallerIsNotProver();

    /// @dev Thrown when the caller is not sequencer.
    error ErrorCallerIsNotSequencer();

    /// @dev Thrown when the transaction has multiple blobs.
    error ErrorFoundMultipleBlobs();

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

    /// @dev Thrown when the bitmap length is incorrect.
    error ErrorIncorrectBitmapLength();

    /// @dev Thrown when the last message is skipped.
    error ErrorLastL1MessageSkipped();

    /// @dev Thrown when no blob found in the transaction.
    error ErrorNoBlobFound();

    /// @dev Thrown when the number of transactions is less than number of L1 message in one block.
    error ErrorNumTxsLessThanNumL1Msgs();

    /// @dev Thrown when reverting a finalized batch.
    error ErrorRevertFinalizedBatch();

    /// @dev Thrown when the given state root is zero.
    error ErrorStateRootIsZero();

    /// @dev Thrown when a chunk contains too many transactions.
    error ErrorTooManyTxsInOneChunk();

    /// @dev Thrown when the precompile output is incorrect.
    error ErrorUnexpectedPointEvaluationPrecompileOutput();

    /// @dev Thrown when the given address is `address(0)`.
    error ErrorZeroAddress();

    /// @dev Thrown when commit batch with lower version.
    error ErrorCannotDowngradeVersion();

    /// @dev Thrown when we try to commit or finalize normal batch in enforced batch mode.
    error ErrorInEnforcedBatchMode();

    /// @dev Thrown when we try to commit enforced batch while not in enforced batch mode.
    error ErrorNotInEnforcedBatchMode();

    /// @dev Thrown when commit old batch after Euclid fork is enabled.
    error ErrorEuclidForkEnabled();

    /// @dev Thrown when the committed v5 batch doesn't contain only one chunk.
    error ErrorV5BatchNotContainsOnlyOneChunk();

    /// @dev Thrown when the committed v5 batch doesn't contain only one block.
    error ErrorV5BatchNotContainsOnlyOneBlock();

    /// @dev Thrown when the committed v5 batch contains some transactions (L1 or L2).
    error ErrorV5BatchContainsTransactions();

    /// @dev Thrown when finalize v4/v5, v5/v6, v4/v5/v6 batches in the same bundle.
    error ErrorFinalizePreAndPostEuclidBatchInOneBundle();

    /// @dev Thrown when finalize v7 batches while some v1 messages still unfinalized.
    error ErrorNotAllV1MessagesAreFinalized();

    /// @dev Thrown when the committed batch hash doesn't match off-chain computed one.
    error InconsistentBatchHash(uint256 batchIndex, bytes32 expected, bytes32 actual);

    /// @dev Thrown when given batch is not committed before.
    error ErrorBatchNotCommitted();

    /*************
     * Constants *
     *************/

    /// @dev Address of the point evaluation precompile used for EIP-4844 blob verification.
    address internal constant POINT_EVALUATION_PRECOMPILE_ADDR = address(0x0A);

    /// @dev BLS Modulus value defined in EIP-4844 and the magic value returned from a successful call to the
    /// point evaluation precompile
    uint256 internal constant BLS_MODULUS =
        52435875175126190479447740508185965837690552500527637822603658699938581184513;

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

    /// @notice The maximum number of transactions allowed in each chunk.
    uint256 public maxNumTxInChunk;

    /// @dev The storage slot used as L1MessageQueue contract, which is deprecated now.
    address private __messageQueue;

    /// @dev The storage slot used as RollupVerifier contract, which is deprecated now.
    address private __verifier;

    /// @notice Whether an account is a sequencer.
    mapping(address => bool) public isSequencer;

    /// @notice Whether an account is a prover.
    mapping(address => bool) public isProver;

    /// @dev The storage slot used as `lastFinalizedBatchIndex`, which is deprecated now.
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

        maxNumTxInChunk = _maxNumTxInChunk;
        __verifier = _verifier;
        __messageQueue = _messageQueue;

        emit UpdateMaxNumTxInChunk(0, _maxNumTxInChunk);
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
    ///
    /// @dev This function will revert unless all V0/V1/V2 batches are finalized. This is because we start to
    /// pop L1 messages in `commitBatchWithBlobProof` but not in `commitBatch`. We also introduce `finalizedQueueIndex`
    /// in `L1MessageQueue`. If one of V0/V1/V2 batches not finalized, `L1MessageQueue.pendingQueueIndex` will not
    /// match `parentBatchHeader.totalL1MessagePopped` and thus revert.
    ///
    /// @dev This function now only accept batches with 4 <= version <= 6. And for `_version=5`, we should make sure this
    /// batch contains only one empty block, since it is the Euclid initial batch for zkt/mpt transition.
    function commitBatchWithBlobProof(
        uint8 _version,
        bytes calldata _parentBatchHeader,
        bytes[] memory _chunks,
        bytes calldata _skippedL1MessageBitmap,
        bytes calldata _blobDataProof
    ) external override OnlySequencer whenNotPaused whenEnforcedBatchNotEnabled {
        // only accept 4 <= version <= 6
        if (_version < 4) {
            revert ErrorIncorrectBatchVersion();
        } else if (_version == 5) {
            // only commit once for Euclid initial batch
            if (initialEuclidBatchIndex != 0) revert ErrorBatchIsAlreadyCommitted();
        } else if (_version > 6) {
            revert ErrorIncorrectBatchVersion();
        }
        // @note We suppose to check v6 batches cannot be committed without initial Euclid Batch.
        // However it will introduce extra sload (2000 gas), we let the sequencer to do this check offchain.
        // Even if the sequencer commits v6 batches without v5 batch, the security council can still revert it.

        uint256 batchIndex = _commitBatchFromV2ToV6(
            _version,
            _parentBatchHeader,
            _chunks,
            _skippedL1MessageBitmap,
            _blobDataProof
        );
        // Don't allow to commit version 4 after Euclid upgrade.
        // This check is to avoid sequencer committing wrong batch due to human error.
        // And This check won't introduce much gas overhead (likely less than 100).
        if (_version == 4) {
            uint256 euclidForkBatchIndex = initialEuclidBatchIndex;
            if (euclidForkBatchIndex > 0 && batchIndex > euclidForkBatchIndex) revert ErrorEuclidForkEnabled();
        } else if (_version == 5) {
            initialEuclidBatchIndex = batchIndex;
        }
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
    /// @dev All batches in the given bundle should have the same version and version <= 4 or version >= 6.
    function finalizeBundleWithProof(
        bytes calldata batchHeader,
        bytes32 postStateRoot,
        bytes32 withdrawRoot,
        bytes calldata aggrProof
    ) external override OnlyProver whenNotPaused whenEnforcedBatchNotEnabled {
        // actions before verification
        (
            uint256 version,
            bytes32 batchHash,
            uint256 batchIndex,
            uint256 totalL1MessagesPoppedOverall,
            uint256 prevBatchIndex
        ) = _beforeFinalizeBatch(batchHeader, postStateRoot);

        uint256 euclidForkBatchIndex = initialEuclidBatchIndex;
        // Make sure we don't finalize v4, v5 and v6 batches in the same bundle, that
        // means `batchIndex < euclidForkBatchIndex` or `prevBatchIndex >= euclidForkBatchIndex`.
        if (prevBatchIndex < euclidForkBatchIndex && euclidForkBatchIndex <= batchIndex) {
            revert ErrorFinalizePreAndPostEuclidBatchInOneBundle();
        }

        bytes memory publicInputs = abi.encodePacked(
            layer2ChainId,
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
        _afterFinalizeBatch(batchIndex, batchHash, totalL1MessagesPoppedOverall, postStateRoot, withdrawRoot, true);
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
    ) external {
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

    /// @notice Update the value of `maxNumTxInChunk`.
    /// @param _maxNumTxInChunk The new value of `maxNumTxInChunk`.
    function updateMaxNumTxInChunk(uint256 _maxNumTxInChunk) external onlyOwner {
        uint256 _oldMaxNumTxInChunk = maxNumTxInChunk;
        maxNumTxInChunk = _maxNumTxInChunk;

        emit UpdateMaxNumTxInChunk(_oldMaxNumTxInChunk, _maxNumTxInChunk);
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

    /// @dev Internal function to do common checks before actual batch committing.
    /// @param _version The version of the batch to commit.
    /// @param _parentBatchHeader The parent batch header in calldata.
    /// @param _chunks The list of chunks in memory.
    /// @param _lastCommittedBatchIndex The index of the last committed batch.
    /// @return _parentBatchHash The batch hash of parent batch header.
    /// @return _batchIndex The index of current batch.
    /// @return _totalL1MessagesPoppedOverall The total number of L1 messages popped before current batch.
    function _beforeCommitBatch(
        uint8 _version,
        bytes calldata _parentBatchHeader,
        bytes[] memory _chunks,
        uint256 _lastCommittedBatchIndex
    )
        private
        view
        returns (
            bytes32 _parentBatchHash,
            uint256 _batchIndex,
            uint256 _totalL1MessagesPoppedOverall
        )
    {
        // check whether the batch is empty
        if (_chunks.length == 0) revert ErrorBatchIsEmpty();
        uint256 batchPtr;
        (batchPtr, _parentBatchHash, _batchIndex, _totalL1MessagesPoppedOverall) = _loadBatchHeader(
            _parentBatchHeader,
            _lastCommittedBatchIndex
        );
        // version should non-decreasing
        if (BatchHeaderV0Codec.getVersion(batchPtr) > _version) revert ErrorCannotDowngradeVersion();

        if (_batchIndex != _lastCommittedBatchIndex) revert ErrorBatchIsAlreadyCommitted();
        unchecked {
            _batchIndex += 1;
        }
    }

    /// @dev Internal function to do common actions after actual batch committing.
    /// @param _batchIndex The index of current batch.
    /// @param _batchHash The hash of current batch.
    function _afterCommitBatch(uint256 _batchIndex, bytes32 _batchHash) private {
        miscData.lastCommittedBatchIndex = uint64(_batchIndex);
        committedBatches[_batchIndex] = _batchHash;
        emit CommitBatch(_batchIndex, _batchHash);
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

    /// @dev Internal function to check the `SkippedL1MessageBitmap`.
    /// @param _totalL1MessagesPoppedOverall The total number of L1 messages popped after current batch.
    /// @param _totalL1MessagesPoppedInBatch The total number of L1 messages popped in current batch.
    /// @param _skippedL1MessageBitmap The skipped L1 message bitmap in calldata.
    /// @param _doPopMessage Whether we actually pop the messages from message queue.
    function _checkSkippedL1MessageBitmap(
        uint256 _totalL1MessagesPoppedOverall,
        uint256 _totalL1MessagesPoppedInBatch,
        bytes calldata _skippedL1MessageBitmap,
        bool _doPopMessage
    ) private {
        // check the length of bitmap
        unchecked {
            if (((_totalL1MessagesPoppedInBatch + 255) / 256) * 32 != _skippedL1MessageBitmap.length) {
                revert ErrorIncorrectBitmapLength();
            }
        }
        if (_doPopMessage) {
            _popL1MessagesCalldata(
                _skippedL1MessageBitmap,
                _totalL1MessagesPoppedOverall,
                _totalL1MessagesPoppedInBatch
            );
        }
    }

    /// @dev Internal function to get and check the blob versioned hash.
    /// @param _blobDataProof The blob data proof passing to point evaluation precompile.
    /// @return _blobVersionedHash The retrieved blob versioned hash.
    function _getAndCheckBlobVersionedHash(bytes calldata _blobDataProof)
        internal
        returns (bytes32 _blobVersionedHash)
    {
        _blobVersionedHash = _getBlobVersionedHash();

        // Calls the point evaluation precompile and verifies the output
        (bool success, bytes memory data) = POINT_EVALUATION_PRECOMPILE_ADDR.staticcall(
            abi.encodePacked(_blobVersionedHash, _blobDataProof)
        );
        // We verify that the point evaluation precompile call was successful by testing the latter 32 bytes of the
        // response is equal to BLS_MODULUS as defined in https://eips.ethereum.org/EIPS/eip-4844#point-evaluation-precompile
        if (!success) revert ErrorCallPointEvaluationPrecompileFailed();
        (, uint256 result) = abi.decode(data, (uint256, uint256));
        if (result != BLS_MODULUS) revert ErrorUnexpectedPointEvaluationPrecompileOutput();
    }

    /// @dev Internal function to get the blob versioned hash.
    /// @return _blobVersionedHash The retrieved blob versioned hash.
    function _getBlobVersionedHash() internal virtual returns (bytes32 _blobVersionedHash) {
        bytes32 _secondBlob;
        // Get blob's versioned hash
        assembly {
            _blobVersionedHash := blobhash(0)
            _secondBlob := blobhash(1)
        }
        if (_blobVersionedHash == bytes32(0)) revert ErrorNoBlobFound();
        if (_secondBlob != bytes32(0)) revert ErrorFoundMultipleBlobs();
    }

    /// @dev Internal function to get the blob versioned hash.
    /// @return _blobVersionedHash The retrieved blob versioned hash.
    function _getBlobVersionedHash(uint256 index) internal virtual returns (bytes32 _blobVersionedHash) {
        // Get blob's versioned hash
        assembly {
            _blobVersionedHash := blobhash(index)
        }
    }

    /// @dev We make sure v5 batch only contains one empty block here.
    function _validateV5Batch(bytes[] memory chunks) internal pure {
        if (chunks.length != 1) revert ErrorV5BatchNotContainsOnlyOneChunk();
        bytes memory chunk = chunks[0];
        uint256 chunkPtr;
        uint256 blockPtr;
        assembly {
            chunkPtr := add(chunk, 0x20) // skip chunkLength
            blockPtr := add(chunkPtr, 1)
        }

        uint256 numBlocks = ChunkCodecV1.validateChunkLength(chunkPtr, chunk.length);
        if (numBlocks != 1) revert ErrorV5BatchNotContainsOnlyOneBlock();
        uint256 numTransactions = ChunkCodecV1.getNumTransactions(blockPtr);
        if (numTransactions != 0) revert ErrorV5BatchContainsTransactions();
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

    /// @dev Internal function to commit batches from V2 to V6 (except V5, since it is Euclid initial batch)
    function _commitBatchFromV2ToV6(
        uint8 _version,
        bytes calldata _parentBatchHeader,
        bytes[] memory _chunks,
        bytes calldata _skippedL1MessageBitmap,
        bytes calldata _blobDataProof
    ) internal returns (uint256) {
        // do extra checks for batch v5.
        if (_version == 5) {
            _validateV5Batch(_chunks);
        }

        // allocate memory of batch header and store entries if necessary, the order matters
        // @note why store entries if necessary, to avoid stack overflow problem.
        // The codes for `version`, `batchIndex`, `l1MessagePopped`, `totalL1MessagePopped` and `dataHash`
        // are the same as `BatchHeaderV0Codec`.
        // The codes for `blobVersionedHash`, and `parentBatchHash` are the same as `BatchHeaderV1Codec`.
        uint256 batchPtr = BatchHeaderV3Codec.allocate();
        BatchHeaderV0Codec.storeVersion(batchPtr, _version);

        (bytes32 _parentBatchHash, uint256 _batchIndex, uint256 _totalL1MessagesPoppedOverall) = _beforeCommitBatch(
            _version,
            _parentBatchHeader,
            _chunks,
            miscData.lastCommittedBatchIndex
        );
        BatchHeaderV0Codec.storeBatchIndex(batchPtr, _batchIndex);

        // versions 2 to 6 both use ChunkCodecV1
        (bytes32 _dataHash, uint256 _totalL1MessagesPoppedInBatch) = _commitChunksV1(
            _totalL1MessagesPoppedOverall,
            _chunks,
            _skippedL1MessageBitmap
        );
        unchecked {
            _totalL1MessagesPoppedOverall += _totalL1MessagesPoppedInBatch;
        }

        // verify skippedL1MessageBitmap
        _checkSkippedL1MessageBitmap(
            _totalL1MessagesPoppedOverall,
            _totalL1MessagesPoppedInBatch,
            _skippedL1MessageBitmap,
            true
        );
        BatchHeaderV0Codec.storeL1MessagePopped(batchPtr, _totalL1MessagesPoppedInBatch);
        BatchHeaderV0Codec.storeTotalL1MessagePopped(batchPtr, _totalL1MessagesPoppedOverall);
        BatchHeaderV0Codec.storeDataHash(batchPtr, _dataHash);

        // verify blob versioned hash
        BatchHeaderV1Codec.storeBlobVersionedHash(batchPtr, _getAndCheckBlobVersionedHash(_blobDataProof));
        BatchHeaderV1Codec.storeParentBatchHash(batchPtr, _parentBatchHash);

        uint256 lastBlockTimestamp;
        {
            bytes memory lastChunk = _chunks[_chunks.length - 1];
            lastBlockTimestamp = ChunkCodecV1.getLastBlockTimestamp(lastChunk);
        }
        BatchHeaderV3Codec.storeLastBlockTimestamp(batchPtr, lastBlockTimestamp);
        BatchHeaderV3Codec.storeBlobDataProof(batchPtr, _blobDataProof);

        // compute batch hash, V2~V6 has same code as V0
        bytes32 _batchHash = BatchHeaderV0Codec.computeBatchHash(
            batchPtr,
            BatchHeaderV3Codec.BATCH_HEADER_FIXED_LENGTH
        );

        _afterCommitBatch(_batchIndex, _batchHash);

        return _batchIndex;
    }

    /// @dev Internal function to commit chunks with version 1
    /// @param _totalL1MessagesPoppedOverall The number of L1 messages popped before the list of chunks.
    /// @param _chunks The list of chunks to commit.
    /// @param _skippedL1MessageBitmap The bitmap indicates whether each L1 message is skipped or not.
    /// @return _batchDataHash The computed data hash for the list of chunks.
    /// @return _totalL1MessagesPoppedInBatch The total number of L1 messages popped in this batch, including skipped one.
    function _commitChunksV1(
        uint256 _totalL1MessagesPoppedOverall,
        bytes[] memory _chunks,
        bytes calldata _skippedL1MessageBitmap
    ) internal view returns (bytes32 _batchDataHash, uint256 _totalL1MessagesPoppedInBatch) {
        uint256 _chunksLength = _chunks.length;

        // load `batchDataHashPtr` and reserve the memory region for chunk data hashes
        uint256 batchDataHashPtr;
        assembly {
            batchDataHashPtr := mload(0x40)
            mstore(0x40, add(batchDataHashPtr, mul(_chunksLength, 32)))
        }

        // compute the data hash for each chunk
        for (uint256 i = 0; i < _chunksLength; i++) {
            uint256 _totalNumL1MessagesInChunk;
            bytes32 _chunkDataHash;
            (_chunkDataHash, _totalNumL1MessagesInChunk) = _commitChunkV1(
                _chunks[i],
                _totalL1MessagesPoppedInBatch,
                _totalL1MessagesPoppedOverall,
                _skippedL1MessageBitmap
            );
            unchecked {
                _totalL1MessagesPoppedInBatch += _totalNumL1MessagesInChunk;
                _totalL1MessagesPoppedOverall += _totalNumL1MessagesInChunk;
            }
            assembly {
                mstore(batchDataHashPtr, _chunkDataHash)
                batchDataHashPtr := add(batchDataHashPtr, 0x20)
            }
        }

        // compute the data hash for current batch
        assembly {
            let dataLen := mul(_chunksLength, 0x20)
            _batchDataHash := keccak256(sub(batchDataHashPtr, dataLen), dataLen)
        }
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

    /// @dev Internal function to commit a chunk with version 1.
    /// @param _chunk The encoded chunk to commit.
    /// @param _totalL1MessagesPoppedInBatch The total number of L1 messages popped in current batch.
    /// @param _totalL1MessagesPoppedOverall The total number of L1 messages popped in all batches including current batch.
    /// @param _skippedL1MessageBitmap The bitmap indicates whether each L1 message is skipped or not.
    /// @return _dataHash The computed data hash for this chunk.
    /// @return _totalNumL1MessagesInChunk The total number of L1 message popped in current chunk
    function _commitChunkV1(
        bytes memory _chunk,
        uint256 _totalL1MessagesPoppedInBatch,
        uint256 _totalL1MessagesPoppedOverall,
        bytes calldata _skippedL1MessageBitmap
    ) internal view returns (bytes32 _dataHash, uint256 _totalNumL1MessagesInChunk) {
        uint256 chunkPtr;
        uint256 startDataPtr;
        uint256 dataPtr;

        assembly {
            dataPtr := mload(0x40)
            startDataPtr := dataPtr
            chunkPtr := add(_chunk, 0x20) // skip chunkLength
        }

        uint256 _numBlocks = ChunkCodecV1.validateChunkLength(chunkPtr, _chunk.length);
        // concatenate block contexts, use scope to avoid stack too deep
        for (uint256 i = 0; i < _numBlocks; i++) {
            dataPtr = ChunkCodecV1.copyBlockContext(chunkPtr, dataPtr, i);
            uint256 blockPtr = chunkPtr + 1 + i * ChunkCodecV1.BLOCK_CONTEXT_LENGTH;
            uint256 _numL1MessagesInBlock = ChunkCodecV1.getNumL1Messages(blockPtr);
            unchecked {
                _totalNumL1MessagesInChunk += _numL1MessagesInBlock;
            }
        }
        assembly {
            mstore(0x40, add(dataPtr, mul(_totalNumL1MessagesInChunk, 0x20))) // reserve memory for l1 message hashes
            chunkPtr := add(chunkPtr, 1)
        }

        // the number of actual transactions in one chunk: non-skipped l1 messages + l2 txs
        uint256 _totalTransactionsInChunk;
        // concatenate tx hashes
        while (_numBlocks > 0) {
            // concatenate l1 message hashes
            uint256 _numL1MessagesInBlock = ChunkCodecV1.getNumL1Messages(chunkPtr);
            uint256 startPtr = dataPtr;
            dataPtr = _loadL1MessageHashes(
                dataPtr,
                _numL1MessagesInBlock,
                _totalL1MessagesPoppedInBatch,
                _totalL1MessagesPoppedOverall,
                _skippedL1MessageBitmap
            );
            uint256 _numTransactionsInBlock = ChunkCodecV1.getNumTransactions(chunkPtr);
            if (_numTransactionsInBlock < _numL1MessagesInBlock) revert ErrorNumTxsLessThanNumL1Msgs();
            unchecked {
                _totalTransactionsInChunk += (dataPtr - startPtr) / 32; // number of non-skipped l1 messages
                _totalTransactionsInChunk += _numTransactionsInBlock - _numL1MessagesInBlock; // number of l2 txs
                _totalL1MessagesPoppedInBatch += _numL1MessagesInBlock;
                _totalL1MessagesPoppedOverall += _numL1MessagesInBlock;

                _numBlocks -= 1;
                chunkPtr += ChunkCodecV1.BLOCK_CONTEXT_LENGTH;
            }
        }

        // check the actual number of transactions in the chunk
        if (_totalTransactionsInChunk > maxNumTxInChunk) {
            revert ErrorTooManyTxsInOneChunk();
        }

        // compute data hash and store to memory
        assembly {
            _dataHash := keccak256(startDataPtr, sub(dataPtr, startDataPtr))
        }
    }

    /// @dev Internal function to load L1 message hashes from the message queue.
    /// @param _ptr The memory offset to store the transaction hash.
    /// @param _numL1Messages The number of L1 messages to load.
    /// @param _totalL1MessagesPoppedInBatch The total number of L1 messages popped in current batch.
    /// @param _totalL1MessagesPoppedOverall The total number of L1 messages popped in all batches including current batch.
    /// @param _skippedL1MessageBitmap The bitmap indicates whether each L1 message is skipped or not.
    /// @return uint256 The new memory offset after loading.
    function _loadL1MessageHashes(
        uint256 _ptr,
        uint256 _numL1Messages,
        uint256 _totalL1MessagesPoppedInBatch,
        uint256 _totalL1MessagesPoppedOverall,
        bytes calldata _skippedL1MessageBitmap
    ) internal view returns (uint256) {
        if (_numL1Messages == 0) return _ptr;
        IL1MessageQueueV1 _messageQueue = IL1MessageQueueV1(messageQueueV1);

        unchecked {
            uint256 _bitmap;
            uint256 rem;
            for (uint256 i = 0; i < _numL1Messages; i++) {
                uint256 quo = _totalL1MessagesPoppedInBatch >> 8;
                rem = _totalL1MessagesPoppedInBatch & 0xff;

                // load bitmap every 256 bits
                if (i == 0 || rem == 0) {
                    assembly {
                        _bitmap := calldataload(add(_skippedL1MessageBitmap.offset, mul(0x20, quo)))
                    }
                }
                if (((_bitmap >> rem) & 1) == 0) {
                    // message not skipped
                    bytes32 _hash = _messageQueue.getCrossDomainMessage(_totalL1MessagesPoppedOverall);
                    assembly {
                        mstore(_ptr, _hash)
                        _ptr := add(_ptr, 0x20)
                    }
                }

                _totalL1MessagesPoppedInBatch += 1;
                _totalL1MessagesPoppedOverall += 1;
            }

            // check last L1 message is not skipped, _totalL1MessagesPoppedInBatch must > 0
            rem = (_totalL1MessagesPoppedInBatch - 1) & 0xff;
            if (((_bitmap >> rem) & 1) > 0) revert ErrorLastL1MessageSkipped();
        }

        return _ptr;
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

    /// @dev Internal function to pop l1 messages from `skippedL1MessageBitmap` in calldata.
    /// @param skippedL1MessageBitmap The `skippedL1MessageBitmap` in calldata.
    /// @param totalL1MessagesPoppedOverall The total number of L1 messages popped in all batches including current batch.
    /// @param totalL1MessagesPoppedInBatch The number of L1 messages popped in current batch.
    function _popL1MessagesCalldata(
        bytes calldata skippedL1MessageBitmap,
        uint256 totalL1MessagesPoppedOverall,
        uint256 totalL1MessagesPoppedInBatch
    ) internal {
        if (totalL1MessagesPoppedInBatch == 0) return;
        uint256 bitmapPtr;
        assembly {
            bitmapPtr := skippedL1MessageBitmap.offset
        }
        _popL1Messages(true, bitmapPtr, totalL1MessagesPoppedOverall, totalL1MessagesPoppedInBatch);
    }

    /// @dev Internal function to pop l1 messages from `skippedL1MessageBitmap` in calldata or memory.
    /// @param isCalldata Whether the `skippedL1MessageBitmap` is in calldata or memory.
    /// @param bitmapPtr The offset of `skippedL1MessageBitmap` in calldata or memory.
    /// @param totalL1MessagesPoppedOverall The total number of L1 messages popped in all batches including current batch.
    /// @param totalL1MessagesPoppedInBatch The number of L1 messages popped in current batch.
    function _popL1Messages(
        bool isCalldata,
        uint256 bitmapPtr,
        uint256 totalL1MessagesPoppedOverall,
        uint256 totalL1MessagesPoppedInBatch
    ) internal {
        if (totalL1MessagesPoppedInBatch == 0) return;

        unchecked {
            uint256 startIndex = totalL1MessagesPoppedOverall - totalL1MessagesPoppedInBatch;
            uint256 bitmap;

            for (uint256 i = 0; i < totalL1MessagesPoppedInBatch; i += 256) {
                uint256 _count = 256;
                if (totalL1MessagesPoppedInBatch - i < _count) {
                    _count = totalL1MessagesPoppedInBatch - i;
                }
                assembly {
                    switch isCalldata
                    case 1 {
                        bitmap := calldataload(bitmapPtr)
                    }
                    default {
                        bitmap := mload(bitmapPtr)
                    }
                    bitmapPtr := add(bitmapPtr, 0x20)
                }
                IL1MessageQueueV1(messageQueueV1).popCrossDomainMessage(startIndex, _count, bitmap);
                startIndex += 256;
            }
        }
    }
}
