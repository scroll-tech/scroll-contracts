// SPDX-License-Identifier: MIT

pragma solidity =0.8.24;

import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";

import {IL1MessageQueue} from "./IL1MessageQueue.sol";
import {IScrollChain} from "./IScrollChain.sol";
import {BatchHeaderV0Codec} from "../../libraries/codec/BatchHeaderV0Codec.sol";
import {BatchHeaderV1Codec} from "../../libraries/codec/BatchHeaderV1Codec.sol";
import {BatchHeaderV3Codec} from "../../libraries/codec/BatchHeaderV3Codec.sol";
import {ChunkCodecV0} from "../../libraries/codec/ChunkCodecV0.sol";
import {ChunkCodecV1} from "../../libraries/codec/ChunkCodecV1.sol";
import {IRollupVerifier} from "../../libraries/verifier/IRollupVerifier.sol";

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

    /// @dev Thrown when the l2 transaction is incomplete.
    error ErrorIncompleteL2TransactionData();

    /// @dev Thrown when the batch hash is incorrect.
    error ErrorIncorrectBatchHash();

    /// @dev Thrown when the batch index is incorrect.
    error ErrorIncorrectBatchIndex();

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

    /// @dev Thrown when the number of batches to revert is zero.
    error ErrorRevertZeroBatches();

    /// @dev Thrown when the reverted batches are not in the ending of committed batch chain.
    error ErrorRevertNotStartFromEnd();

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

    /// @dev Thrown when commit old batch after Euclid fork is enabled.
    error ErrorEuclidForkEnabled();

    /// @dev Thrown when SC finalize V5 batch before all v4 batches are finalized.
    error ErrorNotAllV4BatchFinalized();

    /// @dev Thrown when the committed v5 batch doesn't contain only one chunk.
    error ErrorV5BatchNotContainsOnlyOneChunk();

    /// @dev Thrown when the committed v5 batch doesn't contain only one block.
    error ErrorV5BatchNotContainsOnlyOneBlock();

    /// @dev Thrown when the committed v5 batch contains some transactions (L1 or L2).
    error ErrorV5BatchContainsTransactions();

    /// @dev Thrown when finalize v4/v5, v5/v6, v4/v5/v6 batches in the same bundle.
    error ErrorFinalizePreAndPostEuclidBatchInOneBundle();

    /*************
     * Constants *
     *************/

    /// @dev Address of the point evaluation precompile used for EIP-4844 blob verification.
    address internal constant POINT_EVALUATION_PRECOMPILE_ADDR = address(0x0A);

    /// @dev BLS Modulus value defined in EIP-4844 and the magic value returned from a successful call to the
    /// point evaluation precompile
    uint256 internal constant BLS_MODULUS =
        52435875175126190479447740508185965837690552500527637822603658699938581184513;

    /// @notice The chain id of the corresponding layer 2 chain.
    uint64 public immutable layer2ChainId;

    /// @notice The address of L1MessageQueue contract.
    address public immutable messageQueue;

    /// @notice The address of RollupVerifier.
    address public immutable verifier;

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

    /// @inheritdoc IScrollChain
    uint256 public override lastFinalizedBatchIndex;

    /// @inheritdoc IScrollChain
    mapping(uint256 => bytes32) public override committedBatches;

    /// @inheritdoc IScrollChain
    mapping(uint256 => bytes32) public override finalizedStateRoots;

    /// @inheritdoc IScrollChain
    mapping(uint256 => bytes32) public override withdrawRoots;

    /// @notice The index of first Euclid batch.
    uint256 public initialEuclidBatchIndex;

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

    /***************
     * Constructor *
     ***************/

    /// @notice Constructor for `ScrollChain` implementation contract.
    ///
    /// @param _chainId The chain id of L2.
    /// @param _messageQueue The address of `L1MessageQueue` contract.
    /// @param _verifier The address of zkevm verifier contract.
    constructor(
        uint64 _chainId,
        address _messageQueue,
        address _verifier
    ) {
        if (_messageQueue == address(0) || _verifier == address(0)) {
            revert ErrorZeroAddress();
        }

        _disableInitializers();

        layer2ChainId = _chainId;
        messageQueue = _messageQueue;
        verifier = _verifier;
    }

    /// @notice Initialize the storage of ScrollChain.
    ///
    /// @dev The parameters `_messageQueue` are no longer used.
    ///
    /// @param _messageQueue The address of `L1MessageQueue` contract.
    /// @param _verifier The address of zkevm verifier contract.
    /// @param _maxNumTxInChunk The maximum number of transactions allowed in each chunk.
    function initialize(
        address _messageQueue,
        address _verifier,
        uint256 _maxNumTxInChunk
    ) public initializer {
        OwnableUpgradeable.__Ownable_init();

        maxNumTxInChunk = _maxNumTxInChunk;
        __verifier = _verifier;
        __messageQueue = _messageQueue;

        emit UpdateMaxNumTxInChunk(0, _maxNumTxInChunk);
    }

    /*************************
     * Public View Functions *
     *************************/

    /// @inheritdoc IScrollChain
    function isBatchFinalized(uint256 _batchIndex) external view override returns (bool) {
        return _batchIndex <= lastFinalizedBatchIndex;
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

        (uint256 memPtr, bytes32 _batchHash, , ) = _loadBatchHeader(_batchHeader);

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
    /// @dev This function now only accept batches with version >= 4. And for `_version=5`, we should make sure this
    /// batch contains only one empty block, since it is the Euclid initial batch for zkt/mpt transition.
    function commitBatchWithBlobProof(
        uint8 _version,
        bytes calldata _parentBatchHeader,
        bytes[] memory _chunks,
        bytes calldata _skippedL1MessageBitmap,
        bytes calldata _blobDataProof
    ) external override OnlySequencer whenNotPaused {
        if (_version < 4) {
            // only accept version >= 4
            revert ErrorIncorrectBatchVersion();
        } else if (_version == 5) {
            // only commit once for Euclid initial batch
            if (initialEuclidBatchIndex != 0) revert ErrorBatchIsAlreadyCommitted();
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
    /// @dev If the owner want to revert a sequence of batches by sending multiple transactions,
    ///      make sure to revert recent batches first.
    function revertBatch(bytes calldata _firstBatchHeader, bytes calldata _lastBatchHeader) external onlyOwner {
        (
            uint256 firstBatchPtr,
            ,
            uint256 _firstBatchIndex,
            uint256 _totalL1MessagesPoppedOverallFirstBatch
        ) = _loadBatchHeader(_firstBatchHeader);
        (, , uint256 _lastBatchIndex, ) = _loadBatchHeader(_lastBatchHeader);
        if (_firstBatchIndex > _lastBatchIndex) revert ErrorRevertZeroBatches();

        // make sure no gap is left when reverting from the ending to the beginning.
        if (committedBatches[_lastBatchIndex + 1] != bytes32(0)) revert ErrorRevertNotStartFromEnd();

        // check finalization
        if (_firstBatchIndex <= lastFinalizedBatchIndex) revert ErrorRevertFinalizedBatch();

        // actual revert
        uint256 _initialEuclidBatchIndex = initialEuclidBatchIndex;
        for (uint256 _batchIndex = _lastBatchIndex; _batchIndex >= _firstBatchIndex; --_batchIndex) {
            bytes32 _batchHash = committedBatches[_batchIndex];
            committedBatches[_batchIndex] = bytes32(0);

            // also revert initial Euclid batch
            if (_initialEuclidBatchIndex == _batchIndex) {
                initialEuclidBatchIndex = 0;
            }

            emit RevertBatch(_batchIndex, _batchHash);
        }

        // `getL1MessagePopped` codes are the same in V0~V6
        uint256 l1MessagePoppedFirstBatch = BatchHeaderV0Codec.getL1MessagePopped(firstBatchPtr);
        unchecked {
            IL1MessageQueue(messageQueue).resetPoppedCrossDomainMessage(
                _totalL1MessagesPoppedOverallFirstBatch - l1MessagePoppedFirstBatch
            );
        }
    }

    /// @inheritdoc IScrollChain
    /// @dev All batches in the given bundle should have the same version and version <= 4 or version >= 6.
    function finalizeBundleWithProof(
        bytes calldata batchHeader,
        bytes32 postStateRoot,
        bytes32 withdrawRoot,
        bytes calldata aggrProof
    ) external override OnlyProver whenNotPaused {
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
        _afterFinalizeBatch(batchIndex, batchHash, totalL1MessagesPoppedOverall, postStateRoot, withdrawRoot);
    }

    /// @inheritdoc IScrollChain
    /// @dev This function will only allow security council to call once.
    function finalizeEuclidInitialBatch(bytes32 postStateRoot) external override onlyOwner {
        if (postStateRoot == bytes32(0)) revert ErrorStateRootIsZero();

        uint256 batchIndex = initialEuclidBatchIndex;
        // make sure only finalize once
        if (finalizedStateRoots[batchIndex] != bytes32(0)) revert ErrorBatchIsAlreadyVerified();
        // all v4 batches should be finalized
        if (lastFinalizedBatchIndex + 1 != batchIndex) revert ErrorNotAllV4BatchFinalized();

        // update storage
        lastFinalizedBatchIndex = batchIndex;
        // batch is guaranteed to contain a single empty block, so withdraw root does not change
        bytes32 withdrawRoot = withdrawRoots[batchIndex - 1];
        finalizedStateRoots[batchIndex] = postStateRoot;
        withdrawRoots[batchIndex] = withdrawRoot;

        emit FinalizeBatch(batchIndex, committedBatches[batchIndex], postStateRoot, withdrawRoot);
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

    /**********************
     * Internal Functions *
     **********************/

    /// @dev Internal function to do common checks before actual batch committing.
    /// @param _parentBatchHeader The parent batch header in calldata.
    /// @param _chunks The list of chunks in memory.
    /// @return _parentBatchHash The batch hash of parent batch header.
    /// @return _batchIndex The index of current batch.
    /// @return _totalL1MessagesPoppedOverall The total number of L1 messages popped before current batch.
    function _beforeCommitBatch(bytes calldata _parentBatchHeader, bytes[] memory _chunks)
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
        (, _parentBatchHash, _batchIndex, _totalL1MessagesPoppedOverall) = _loadBatchHeader(_parentBatchHeader);
        unchecked {
            _batchIndex += 1;
        }
        if (committedBatches[_batchIndex] != 0) revert ErrorBatchIsAlreadyCommitted();
    }

    /// @dev Internal function to do common actions after actual batch committing.
    /// @param _batchIndex The index of current batch.
    /// @param _batchHash The hash of current batch.
    function _afterCommitBatch(uint256 _batchIndex, bytes32 _batchHash) private {
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

        uint256 batchPtr;
        // compute pending batch hash and verify
        (batchPtr, batchHash, batchIndex, totalL1MessagesPoppedOverall) = _loadBatchHeader(batchHeader);

        // make sure don't finalize batch multiple times
        prevBatchIndex = lastFinalizedBatchIndex;
        if (batchIndex <= prevBatchIndex) revert ErrorBatchIsAlreadyVerified();

        version = BatchHeaderV0Codec.getVersion(batchPtr);
    }

    /// @dev Internal function to do common actions after actual batch finalization.
    function _afterFinalizeBatch(
        uint256 batchIndex,
        bytes32 batchHash,
        uint256 totalL1MessagesPoppedOverall,
        bytes32 postStateRoot,
        bytes32 withdrawRoot
    ) internal {
        // @note we do not store intermediate finalized roots
        lastFinalizedBatchIndex = batchIndex;
        finalizedStateRoots[batchIndex] = postStateRoot;
        withdrawRoots[batchIndex] = withdrawRoot;

        // Pop finalized and non-skipped message from L1MessageQueue.
        _finalizePoppedL1Messages(totalL1MessagesPoppedOverall);

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
            _parentBatchHeader,
            _chunks
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
    /// @return batchPtr The start memory offset of loaded batch header.
    /// @return _batchHash The hash of the loaded batch header.
    /// @return _batchIndex The index of this batch.
    /// @param _totalL1MessagesPoppedOverall The number of L1 messages popped after this batch.
    function _loadBatchHeader(bytes calldata _batchHeader)
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
        } else if (version >= 3) {
            (batchPtr, _length) = BatchHeaderV3Codec.loadAndValidate(_batchHeader);
        }

        // the code for compute batch hash is the same for V0~V6
        // also the `_batchIndex` and `_totalL1MessagesPoppedOverall`.
        _batchHash = BatchHeaderV0Codec.computeBatchHash(batchPtr, _length);
        _batchIndex = BatchHeaderV0Codec.getBatchIndex(batchPtr);
        _totalL1MessagesPoppedOverall = BatchHeaderV0Codec.getTotalL1MessagePopped(batchPtr);

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
        IL1MessageQueue _messageQueue = IL1MessageQueue(messageQueue);

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
    function _finalizePoppedL1Messages(uint256 totalL1MessagesPoppedOverall) internal {
        if (totalL1MessagesPoppedOverall > 0) {
            unchecked {
                IL1MessageQueue(messageQueue).finalizePoppedCrossDomainMessage(totalL1MessagesPoppedOverall);
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
                IL1MessageQueue(messageQueue).popCrossDomainMessage(startIndex, _count, bitmap);
                startIndex += 256;
            }
        }
    }
}
