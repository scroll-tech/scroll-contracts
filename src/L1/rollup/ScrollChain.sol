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

    /// @dev Thrown when reverting a unresolved state.
    error ErrorRevertUnresolvedState();

    /// @dev Thrown when the given state root is zero.
    error ErrorStateRootIsZero();

    /// @dev Thrown when a chunk contains too many transactions.
    error ErrorTooManyTxsInOneChunk();

    /// @dev Thrown when the precompile output is incorrect.
    error ErrorUnexpectedPointEvaluationPrecompileOutput();

    /// @dev Thrown when the given address is `address(0)`.
    error ErrorZeroAddress();

    /// @dev Thrown when no unresolved state exists.
    error ErrorNoUnresolvedState();

    /// @dev Thrown when the finalization is paused.
    error ErrorFinalizationPaused();

    /// @dev Thrown when the batch is not finalized with zk proof.
    error ErrorBatchNotVerifiedWithZKProof();

    /// @dev Thrown when the batch index mismatch.
    error ErrorBatchIndexMismatch();

    error ErrorNotInEnforcedBatchMode();

    error ErrorNotIncludeAllExpiredMessages();

    error ErrorMessageNotFinalizedBeforeMaxDelay();

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

    /// @notice The address of `MultipleVersionRollupVerifier` for zk proof.
    address public immutable zkpVerifier;

    /// @notice The address of `MultipleVersionRollupVerifier` for tee proof.
    address public immutable teeVerifier;

    /***********
     * Structs *
     ***********/

    struct UnresolvedState {
        uint256 batchIndex;
        bytes32 stateRoot;
        bytes32 withdrawRoot;
    }

    /// @dev Assume one message is enqueued at timestamp `t`. The `maxInclusionDelay` means if this
    /// message wasn't included by timestamp `t+maxInclusionDelay` in batch committing, the sequencer
    /// cannot commit any batches unless it includes all expired messages before any L2 transactions.
    /// The `maxFinalizeDelay` means if this message wasn't finalized by timestamp `t+maxFinalizeDelay`,
    /// the prover cannot finalize any batches. The `maxDelayEnterEnforcedMode` means if this message
    /// wasn't finalized by timestamp `t+maxDelayEnterEnforcedMode`, we will enter enforced mode. Anyone
    /// can commit and finalize a batch without permission.
    /// So if the sequencer or prover encountered some recoverable problem, we must resolve it between
    /// timestamp `[t+maxFinalizeDelay, t+maxDelayEnterEnforcedMode]`.
    struct EnforcedBatchParameters {
        uint64 maxInclusionDelay;
        uint64 maxFinalizeDelay;
        uint64 maxDelayEnterEnforcedMode;
        uint56 lastCommittedBatchIndex;
        bool enforcedModeEnabled;
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

    /// @inheritdoc IScrollChain
    uint256 public override lastZkpVerifiedBatchIndex;

    /// @inheritdoc IScrollChain
    mapping(uint256 => bytes32) public override committedBatches;

    /// @inheritdoc IScrollChain
    mapping(uint256 => bytes32) public override finalizedStateRoots;

    /// @inheritdoc IScrollChain
    mapping(uint256 => bytes32) public override withdrawRoots;

    /// @inheritdoc IScrollChain
    uint256 public override lastTeeVerifiedBatchIndex;

    /// @notice The state for mismatched batch
    UnresolvedState public unresolvedState;

    /// @notice The parameters related to enforced batch feature.
    /// @dev The value of `lastCommittedBatchIndex` will be initialized in the first batch commit after upgrade.
    EnforcedBatchParameters public enforcedBatchParameters;

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

    modifier whenFinalizeNotPaused() {
        if (unresolvedState.batchIndex > 0) revert ErrorFinalizationPaused();
        _;
    }

    modifier whenEnforcedBatchNotEnable() {
        if (enforcedBatchParameters.enforcedModeEnabled) revert ErrorNotInEnforcedBatchMode();
        _;
    }

    /***************
     * Constructor *
     ***************/

    /// @notice Constructor for `ScrollChain` implementation contract.
    ///
    /// @param _chainId The chain id of L2.
    /// @param _messageQueue The address of `L1MessageQueue` contract.
    /// @param _zkpVerifier The address of zkevm verifier contract.
    /// @param _teeVerifier The address of tee verifier contract.
    constructor(
        uint64 _chainId,
        address _messageQueue,
        address _zkpVerifier,
        address _teeVerifier
    ) {
        if (_messageQueue == address(0) || _zkpVerifier == address(0) || _teeVerifier == address(0)) {
            revert ErrorZeroAddress();
        }

        _disableInitializers();

        layer2ChainId = _chainId;
        messageQueue = _messageQueue;
        zkpVerifier = _zkpVerifier;
        teeVerifier = _teeVerifier;
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

    function initializeV2() external reinitializer(2) {
        uint256 cachedIndex = lastZkpVerifiedBatchIndex;
        lastTeeVerifiedBatchIndex = cachedIndex;
        emit VerifyBatchWithTee(cachedIndex);
    }

    /*************************
     * Public View Functions *
     *************************/

    /// @inheritdoc IScrollChain
    function lastFinalizedBatchIndex() public view returns (uint256) {
        return lastTeeVerifiedBatchIndex;
    }

    /// @inheritdoc IScrollChain
    function isBatchFinalized(uint256 _batchIndex) external view override returns (bool) {
        return _batchIndex <= lastFinalizedBatchIndex();
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
    /// @dev `_skippedL1MessageBitmap` is no longer used, will remove in next version.
    function commitBatchWithBlobProof(
        uint8 _version,
        bytes calldata _parentBatchHeader,
        bytes[] memory _chunks,
        bytes calldata, /*_skippedL1MessageBitmap*/
        bytes calldata _blobDataProof
    ) external override {
        commitBatchWithBlobProof(_version, _parentBatchHeader, _chunks, _blobDataProof);
    }

    /// @inheritdoc IScrollChain
    function commitBatchWithBlobProof(
        uint8 _version,
        bytes calldata _parentBatchHeader,
        bytes[] memory _chunks,
        bytes calldata _blobDataProof
    ) public override OnlySequencer whenEnforcedBatchNotEnable {
        _commitBatchWithBlobProof(_version, _parentBatchHeader, _chunks, _blobDataProof);
    }

    /// @inheritdoc IScrollChain
    function finalizeBundleWithProof(
        bytes calldata _batchHeader,
        bytes32 _postStateRoot,
        bytes32 _withdrawRoot,
        bytes calldata _aggrProof
    ) external override OnlyProver whenFinalizeNotPaused {
        _checkFinalizationAllowed(enforcedBatchParameters.maxFinalizeDelay);
        _finalizeBundleWithZkProof(_batchHeader, _postStateRoot, _withdrawRoot, _aggrProof);
    }

    /// @inheritdoc IScrollChain
    function finalizeBundleWithTeeProof(
        bytes calldata _batchHeader,
        bytes32 _postStateRoot,
        bytes32 _withdrawRoot,
        bytes calldata _teeProof
    ) external override OnlyProver whenFinalizeNotPaused {
        _checkFinalizationAllowed(enforcedBatchParameters.maxFinalizeDelay);
        _finalizeBundleWithTeeProof(_batchHeader, _postStateRoot, _withdrawRoot, _teeProof);
    }

    /// @inheritdoc IScrollChain
    function commitAndFinalizeBatch(CommitStruct calldata commitStruct, FinalizeStruct calldata finalizeStruct)
        external
        whenFinalizeNotPaused
    {
        //
        EnforcedBatchParameters memory parameters = enforcedBatchParameters;
        if (!parameters.enforcedModeEnabled) {
            uint256 timestamp = IL1MessageQueue(messageQueue).getFirstUnfinalizedMessageTimestamp();
            if (timestamp > 0 && timestamp + parameters.maxDelayEnterEnforcedMode < block.timestamp) {
                // explicit set enforce batch enable
                parameters.enforcedModeEnabled = true;
                // reset `lastCommittedBatchIndex`
                uint256 zkpIndex = lastZkpVerifiedBatchIndex;
                uint256 teeIndex = lastTeeVerifiedBatchIndex;
                if (zkpIndex < teeIndex) {
                    parameters.lastCommittedBatchIndex = uint56(zkpIndex);
                } else {
                    parameters.lastCommittedBatchIndex = uint56(teeIndex);
                }
                enforcedBatchParameters = parameters;
            } else {
                revert ErrorNotInEnforcedBatchMode();
            }
        }

        // commit batch
        bytes32 batchHash = _commitBatchWithBlobProof(
            commitStruct.version,
            commitStruct.parentBatchHeader,
            commitStruct.chunks,
            commitStruct.blobDataProof
        );

        if (batchHash != keccak256(finalizeStruct.batchHeader)) {
            revert ErrorIncorrectBatchHash();
        }

        // finalize with zk proof
        _finalizeBundleWithZkProof(
            finalizeStruct.batchHeader,
            finalizeStruct.postStateRoot,
            finalizeStruct.withdrawRoot,
            finalizeStruct.zkProof
        );

        // finalize with tee proof
        _finalizeBundleWithTeeProof(
            finalizeStruct.batchHeader,
            finalizeStruct.postStateRoot,
            finalizeStruct.withdrawRoot,
            finalizeStruct.teeProof
        );
    }

    /************************
     * Restricted Functions *
     ************************/

    /// @notice Resolve mismatched state.
    ///
    /// @dev This should only be called by Security Council.
    ///
    /// @param useSGXState Whether we want to use the state root from SGX prover.
    function resolveStateMismatch(bytes calldata _batchHeader, bool useSGXState) external onlyOwner {
        UnresolvedState memory state = unresolvedState;
        if (state.batchIndex == 0) {
            revert ErrorNoUnresolvedState();
        }
        (, , uint256 _batchIndex, uint256 _totalL1MessagesPoppedOverall) = _loadBatchHeader(_batchHeader);
        if (_batchIndex != state.batchIndex) revert ErrorBatchIndexMismatch();
        if (useSGXState) {
            finalizedStateRoots[state.batchIndex] = state.stateRoot;
            withdrawRoots[state.batchIndex] = state.withdrawRoot;
            emit ResolveState(state.batchIndex, state.stateRoot, state.withdrawRoot);

            // reset zkp verified batch index, zk prover need to reprove everything after this batch
            lastZkpVerifiedBatchIndex = state.batchIndex;
        }

        lastTeeVerifiedBatchIndex = state.batchIndex;

        // Pop finalized and non-skipped message from L1MessageQueue.
        _finalizePoppedL1Messages(_totalL1MessagesPoppedOverall);

        // emit events
        emit VerifyBatchWithTee(state.batchIndex);
        emit FinalizeBatch(state.batchIndex, committedBatches[state.batchIndex], state.stateRoot, state.withdrawRoot);

        // clear state
        unresolvedState.batchIndex = 0;
        unresolvedState.stateRoot = bytes32(0);
        unresolvedState.withdrawRoot = bytes32(0);
    }

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

    /// @notice Exit from enforced batch mode.
    function disableEnforcedBatch() external onlyOwner {
        enforcedBatchParameters.enforcedModeEnabled = false;
    }

    /**********************
     * Internal Functions *
     **********************/

    function _commitBatchWithBlobProof(
        uint8 _version,
        bytes calldata _parentBatchHeader,
        bytes[] memory _chunks,
        bytes calldata _blobDataProof
    ) internal returns (bytes32) {
        if (_version <= 2) {
            revert ErrorIncorrectBatchVersion();
        }

        // allocate memory of batch header and store entries if necessary, the order matters
        // @note why store entries if necessary, to avoid stack overflow problem.
        // The codes for `version`, `batchIndex`, `l1MessagePopped`, `totalL1MessagePopped` and `dataHash`
        // are the same as `BatchHeaderV0Codec`.
        // The codes for `blobVersionedHash`, and `parentBatchHash` are the same as `BatchHeaderV1Codec`.
        uint256 batchPtr;
        assembly {
            batchPtr := mload(0x40)
            // This is `BatchHeaderV3Codec.BATCH_HEADER_FIXED_LENGTH`, use `193` here to reduce code
            // complexity. Be careful that the length may changed in future versions.
            mstore(0x40, add(batchPtr, 193))
        }
        BatchHeaderV0Codec.storeVersion(batchPtr, _version);

        //EnforcedBatchParameters memory parameters = enforcedBatchParameters;
        (bytes32 _parentBatchHash, uint256 _batchIndex, uint256 _totalL1MessagesPoppedOverall) = _beforeCommitBatch(
            _parentBatchHeader,
            _chunks,
            0
        );
        BatchHeaderV0Codec.storeBatchIndex(batchPtr, _batchIndex);

        // versions 2 and 3 both use ChunkCodecV1
        (bytes32 _dataHash, uint256 _totalL1MessagesPoppedInBatch) = _commitChunksV1(
            _totalL1MessagesPoppedOverall,
            _chunks,
            0 // parameters.maxInclusionDelay
        );
        unchecked {
            _totalL1MessagesPoppedOverall += _totalL1MessagesPoppedInBatch;
        }

        // pop messages
        if (_totalL1MessagesPoppedInBatch > 0) {
            IL1MessageQueue(messageQueue).popCrossDomainMessage(_totalL1MessagesPoppedInBatch);
        }
        BatchHeaderV0Codec.storeL1MessagePopped(batchPtr, _totalL1MessagesPoppedInBatch);
        BatchHeaderV0Codec.storeTotalL1MessagePopped(batchPtr, _totalL1MessagesPoppedOverall);
        BatchHeaderV0Codec.storeDataHash(batchPtr, _dataHash);

        // verify blob versioned hash
        bytes32 _blobVersionedHash = _getBlobVersionedHash();
        _checkBlobVersionedHash(_blobVersionedHash, _blobDataProof);
        BatchHeaderV1Codec.storeBlobVersionedHash(batchPtr, _blobVersionedHash);
        BatchHeaderV1Codec.storeParentBatchHash(batchPtr, _parentBatchHash);

        uint256 lastBlockTimestamp;
        {
            bytes memory lastChunk = _chunks[_chunks.length - 1];
            lastBlockTimestamp = ChunkCodecV1.getLastBlockTimestamp(lastChunk);
        }
        BatchHeaderV3Codec.storeLastBlockTimestamp(batchPtr, lastBlockTimestamp);
        BatchHeaderV3Codec.storeBlobDataProof(batchPtr, _blobDataProof);

        // compute batch hash, V3 has same code as V0
        bytes32 _batchHash = BatchHeaderV0Codec.computeBatchHash(
            batchPtr,
            BatchHeaderV3Codec.BATCH_HEADER_FIXED_LENGTH
        );

        // store state and emit event
        enforcedBatchParameters.lastCommittedBatchIndex = uint56(_batchIndex);
        committedBatches[_batchIndex] = _batchHash;
        emit CommitBatch(_batchIndex, _batchHash);

        return _batchHash;
    }

    function _finalizeBundleWithZkProof(
        bytes calldata _batchHeader,
        bytes32 _postStateRoot,
        bytes32 _withdrawRoot,
        bytes calldata _aggrProof
    ) internal {
        if (_postStateRoot == bytes32(0)) revert ErrorStateRootIsZero();

        // compute pending batch hash and verify
        (uint256 batchPtr, bytes32 _batchHash, uint256 _batchIndex, ) = _loadBatchHeader(_batchHeader);

        // retrieve finalized state root and batch hash from storage to construct the public input
        uint256 _lastVerifiedBatchIndex = lastZkpVerifiedBatchIndex;
        if (_batchIndex <= _lastVerifiedBatchIndex) revert ErrorBatchIsAlreadyVerified();

        bytes memory _publicInput = abi.encodePacked(
            layer2ChainId,
            uint32(_batchIndex - _lastVerifiedBatchIndex), // numBatches
            finalizedStateRoots[_lastVerifiedBatchIndex], // _prevStateRoot
            committedBatches[_lastVerifiedBatchIndex], // _prevBatchHash
            _postStateRoot,
            _batchHash,
            _withdrawRoot
        );

        // load version from batch header, it is always the first byte.
        uint256 batchVersion = BatchHeaderV0Codec.getVersion(batchPtr);

        // verify bundle, choose the correct verifier based on the last batch
        // our off-chain service will make sure all unfinalized batches have the same batch version.
        IRollupVerifier(zkpVerifier).verifyBundleProof(batchVersion, _batchIndex, _aggrProof, _publicInput);

        // store in state
        // @note we do not store intermediate finalized roots
        lastZkpVerifiedBatchIndex = _batchIndex;
        finalizedStateRoots[_batchIndex] = _postStateRoot;
        withdrawRoots[_batchIndex] = _withdrawRoot;

        // @note we will pop finalized and non-skipped message in `finalizeBundleWithTeeProof`
        // _finalizePoppedL1Messages(_totalL1MessagesPoppedOverall);

        emit VerifyBatchWithZkp(_batchIndex, _batchHash, _postStateRoot, _withdrawRoot);
    }

    function _finalizeBundleWithTeeProof(
        bytes calldata _batchHeader,
        bytes32 _postStateRoot,
        bytes32 _withdrawRoot,
        bytes calldata _teeProof
    ) internal {
        // compute pending batch hash and verify
        (
            uint256 batchPtr,
            bytes32 _batchHash,
            uint256 _batchIndex,
            uint256 _totalL1MessagesPoppedOverall
        ) = _loadBatchHeader(_batchHeader);

        // Check if this state root is verified and set by zk proof.
        // It is possible that `finalizedStateRoots[_batchIndex]` is nonzero and it is not verified by zkp.
        // Since we may reset the `lastZkpVerifiedBatchIndex` in `resolveStateMismatch` function.
        // However, it's still possible that the batch is "finalized" by zkp but it's in the middle of the bundle,
        // so we do not have it stored in state. We don't consider this case here.
        bytes32 cachedStateRoot = finalizedStateRoots[_batchIndex];
        if (cachedStateRoot == bytes32(0) || _batchIndex > lastZkpVerifiedBatchIndex) {
            revert ErrorBatchNotVerifiedWithZKProof();
        }

        uint256 _lastVerifiedBatchIndex = lastTeeVerifiedBatchIndex;
        if (_batchIndex <= _lastVerifiedBatchIndex) {
            revert ErrorBatchIsAlreadyVerified();
        }

        bytes memory _publicInput = abi.encodePacked(
            layer2ChainId,
            uint32(_batchIndex - _lastVerifiedBatchIndex), // numBatches
            finalizedStateRoots[_lastVerifiedBatchIndex], // _prevStateRoot
            committedBatches[_lastVerifiedBatchIndex], // _prevBatchHash
            _postStateRoot,
            _batchHash,
            _withdrawRoot
        );

        uint256 batchVersion = BatchHeaderV0Codec.getVersion(batchPtr);
        IRollupVerifier(teeVerifier).verifyBundleProof(batchVersion, _batchIndex, _teeProof, _publicInput);

        // check withdraw root and state root match with zk proof
        if (withdrawRoots[_batchIndex] != _withdrawRoot || cachedStateRoot != _postStateRoot) {
            unresolvedState.batchIndex = _batchIndex;
            unresolvedState.stateRoot = _postStateRoot;
            unresolvedState.withdrawRoot = _withdrawRoot;
            emit StateMismatch(_batchIndex, _postStateRoot, _withdrawRoot);
            return;
        }

        lastTeeVerifiedBatchIndex = _batchIndex;

        // Pop finalized and non-skipped message from L1MessageQueue.
        _finalizePoppedL1Messages(_totalL1MessagesPoppedOverall);

        emit VerifyBatchWithTee(_batchIndex);
        emit FinalizeBatch(_batchIndex, _batchHash, _postStateRoot, _withdrawRoot);
    }

    function _checkFinalizationAllowed(uint256 maxFinalizeDelay) private view {
        uint256 timestamp = IL1MessageQueue(messageQueue).getFirstUnfinalizedMessageTimestamp();
        if (timestamp > 0 && timestamp + maxFinalizeDelay < block.timestamp) {
            revert ErrorMessageNotFinalizedBeforeMaxDelay();
        }
    }

    /// @dev Internal function to do common checks before actual batch committing.
    /// @param _parentBatchHeader The parent batch header in calldata.
    /// @param _chunks The list of chunks in memory.
    /// @param lastCommittedBatchIndex The index of last committed batch.
    /// @return _parentBatchHash The batch hash of parent batch header.
    /// @return _batchIndex The index of current batch.
    /// @return _totalL1MessagesPoppedOverall The total number of L1 messages popped before current batch.
    function _beforeCommitBatch(
        bytes calldata _parentBatchHeader,
        bytes[] memory _chunks,
        uint256 lastCommittedBatchIndex
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
        (, _parentBatchHash, _batchIndex, _totalL1MessagesPoppedOverall) = _loadBatchHeader(_parentBatchHeader);
        unchecked {
            _batchIndex += 1;
        }
        // Since the value of `lastCommittedBatchIndex` will be initialized in the first batch commit after upgrade,
        // we won't use it until it is initialized. Instead, we will check `committedBatches[_batchIndex]`.
        if (lastCommittedBatchIndex != 0) {
            unchecked {
                if (_batchIndex != lastCommittedBatchIndex + 1) {
                    revert ErrorBatchIsAlreadyCommitted();
                }
            }
        } else {
            // This is only used when `lastCommittedBatchIndex` is uninitialized. Because, when enter enforced batch
            // mode, it is not true and we are allowed to override committed but unfinalized batch.
            if (committedBatches[_batchIndex] != 0) {
                revert ErrorBatchIsAlreadyCommitted();
            }
        }
    }

    /// @dev Internal function to check blob versioned hash.
    /// @param _blobVersionedHash The blob versioned hash to check.
    /// @param _blobDataProof The blob data proof used to verify the blob versioned hash.
    function _checkBlobVersionedHash(bytes32 _blobVersionedHash, bytes calldata _blobDataProof) internal view {
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

    /// @dev Internal function to commit chunks with version 1
    /// @param _totalL1MessagesPoppedOverall The number of L1 messages popped before the list of chunks.
    /// @param _chunks The list of chunks to commit.
    /// @return _batchDataHash The computed data hash for the list of chunks.
    /// @return _totalL1MessagesPoppedInBatch The total number of L1 messages popped in this batch, including skipped one.
    function _commitChunksV1(
        uint256 _totalL1MessagesPoppedOverall,
        bytes[] memory _chunks,
        uint256 maxInclusionDelay
    ) internal view returns (bytes32 _batchDataHash, uint256 _totalL1MessagesPoppedInBatch) {
        uint256 _chunksLength = _chunks.length;

        // load `batchDataHashPtr` and reserve the memory region for chunk data hashes
        uint256 batchDataHashPtr;
        assembly {
            batchDataHashPtr := mload(0x40)
            mstore(0x40, add(batchDataHashPtr, mul(_chunksLength, 32)))
        }

        uint256 _totalNumTransactionsInBatch;
        // compute the data hash for each chunk
        for (uint256 i = 0; i < _chunksLength; i++) {
            uint256 _totalNumL1MessagesInChunk;
            uint256 _totalNumTransactionsInChunk;
            bytes32 _chunkDataHash;
            (_chunkDataHash, _totalNumL1MessagesInChunk, _totalNumTransactionsInChunk) = _commitChunkV1(
                _chunks[i],
                _totalL1MessagesPoppedInBatch,
                _totalL1MessagesPoppedOverall
            );
            unchecked {
                _totalL1MessagesPoppedInBatch += _totalNumL1MessagesInChunk;
                _totalL1MessagesPoppedOverall += _totalNumL1MessagesInChunk;
                _totalNumTransactionsInBatch += _totalNumTransactionsInChunk;
            }
            assembly {
                mstore(batchDataHashPtr, _chunkDataHash)
                batchDataHashPtr := add(batchDataHashPtr, 0x20)
            }
        }

        // Check expired message status here.
        // If some messages expired for inclusion, all expired messages should be included in current batch,
        // unless this batch cannot include that many messages (i.e. totalNumTransactionsInBatch=totalL1MessagesPoppedInBatch).
        {
            uint256 timestamp = IL1MessageQueue(messageQueue).getFirstPendingMessageTimestamp();
            if (
                timestamp > 0 &&
                timestamp + maxInclusionDelay < block.timestamp &&
                _totalNumTransactionsInBatch > _totalL1MessagesPoppedInBatch
            ) {
                timestamp = IL1MessageQueue(messageQueue).getMessageTimestamp(
                    _totalL1MessagesPoppedOverall + _totalL1MessagesPoppedInBatch
                );
                if (timestamp + maxInclusionDelay < block.timestamp) {
                    revert ErrorNotIncludeAllExpiredMessages();
                }
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

        // the code for compute batch hash is the same for V0, V1, V2, V3
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
    /// @return _dataHash The computed data hash for this chunk.
    /// @return _totalNumL1MessagesInChunk The total number of L1 message popped in current chunk
    /// @return _totalTransactionsInChunk The total number of transactions (non-skipped l1 messages + l2 txs) in current chunk.
    function _commitChunkV1(
        bytes memory _chunk,
        uint256 _totalL1MessagesPoppedInBatch,
        uint256 _totalL1MessagesPoppedOverall
    )
        internal
        view
        returns (
            bytes32 _dataHash,
            uint256 _totalNumL1MessagesInChunk,
            uint256 _totalTransactionsInChunk
        )
    {
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

        // concatenate tx hashes
        while (_numBlocks > 0) {
            // concatenate l1 message hashes
            uint256 _numL1MessagesInBlock = ChunkCodecV1.getNumL1Messages(chunkPtr);
            uint256 startPtr = dataPtr;
            dataPtr = _loadL1MessageHashes(
                dataPtr,
                _numL1MessagesInBlock,
                _totalL1MessagesPoppedInBatch,
                _totalL1MessagesPoppedOverall
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
    /// @return ptr The new memory offset after loading.
    function _loadL1MessageHashes(
        uint256 _ptr,
        uint256 _numL1Messages,
        uint256 _totalL1MessagesPoppedInBatch,
        uint256 _totalL1MessagesPoppedOverall
    ) internal view returns (uint256) {
        if (_numL1Messages == 0) return _ptr;
        IL1MessageQueue _messageQueue = IL1MessageQueue(messageQueue);

        unchecked {
            // all messages are non-skipped
            for (uint256 i = 0; i < _numL1Messages; i++) {
                bytes32 _hash = _messageQueue.getCrossDomainMessage(_totalL1MessagesPoppedOverall);
                assembly {
                    mstore(_ptr, _hash)
                    _ptr := add(_ptr, 0x20)
                }
                _totalL1MessagesPoppedOverall += 1;
            }
            _totalL1MessagesPoppedInBatch += _numL1Messages;
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
}
