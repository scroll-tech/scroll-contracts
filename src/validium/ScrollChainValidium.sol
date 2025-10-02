// SPDX-License-Identifier: MIT

pragma solidity =0.8.24;

import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";

import {IL1MessageQueueV2} from "../L1/rollup/IL1MessageQueueV2.sol";
import {IRollupVerifier} from "../libraries/verifier/IRollupVerifier.sol";
import {IScrollChainValidium} from "./IScrollChainValidium.sol";

import {BatchHeaderValidiumV0Codec} from "./codec/BatchHeaderValidiumV0Codec.sol";

// solhint-disable no-inline-assembly
// solhint-disable reason-string

/// @title ScrollChainValidium
contract ScrollChainValidium is AccessControlUpgradeable, PausableUpgradeable, IScrollChainValidium {
    /**********
     * Errors *
     **********/

    /// @dev Thrown when the given genesis batch is invalid.
    error ErrorInvalidGenesisBatch();

    /// @dev Thrown when finalizing a verified batch.
    error ErrorBatchIsAlreadyVerified();

    /// @dev Thrown when importing genesis batch twice.
    error ErrorGenesisBatchImported();

    /// @dev Thrown when the batch hash is incorrect.
    error ErrorIncorrectBatchHash();

    /// @dev Thrown when reverting a finalized batch.
    error ErrorRevertFinalizedBatch();

    /// @dev Thrown when the given state root is zero.
    error ErrorStateRootIsZero();

    /// @dev Thrown when given batch is not committed before.
    error ErrorBatchNotCommitted();

    /// @dev Error thrown when encryption key length is invalid.
    error ErrorInvalidEncryptionKeyLength();

    /// @dev Error thrown the user attempts to use an encryption key that is unknown.
    error ErrorUnknownEncryptionKey();

    /// @dev Error thrown the user attempts to use an encryption key that is deprecated.
    error ErrorDeprecatedEncryptionKey();

    /*************
     * Constants *
     *************/

    /// @notice The role for import genesis batch.
    bytes32 public constant GENESIS_IMPORTER_ROLE = keccak256("GENESIS_IMPORTER_ROLE");

    /// @notice The role for sequencer who can commit batch.
    bytes32 public constant SEQUENCER_ROLE = keccak256("SEQUENCER_ROLE");

    /// @notice The role for prover who can finalize batch.
    bytes32 public constant PROVER_ROLE = keccak256("PROVER_ROLE");

    /// @notice The role that can rotate encryption keys.
    bytes32 public constant KEY_MANAGER_ROLE = keccak256("KEY_MANAGER_ROLE");

    /***********************
     * Immutable Variables *
     ***********************/

    /// @notice The chain id of the corresponding layer 2 chain.
    uint64 public immutable layer2ChainId;

    /// @notice The address of `L1MessageQueueV2`.
    address public immutable messageQueueV2;

    /// @notice The address of `MultipleVersionRollupVerifier`.
    address public immutable verifier;

    /***********
     * Structs *
     ***********/

    struct EncryptionKey {
        // The on-chain message index when the key was set.
        uint256 msgIndex;
        // The 33-bytes compressed public key, i.e. encryption key.
        bytes key;
    }

    /*********************
     * Storage Variables *
     *********************/

    /// @inheritdoc IScrollChainValidium
    uint256 public override lastFinalizedBatchIndex;

    /// @inheritdoc IScrollChainValidium
    uint256 public override lastCommittedBatchIndex;

    /// @dev Mapping from batch index to batch hash.
    mapping(uint256 => bytes32) public override committedBatches;

    /// @dev Mapping from batch index to corresponding state root in Validium L3.
    mapping(uint256 => bytes32) public override stateRoots;

    /// @dev Mapping from batch index to corresponding withdraw root in Validium L3.
    mapping(uint256 => bytes32) public override withdrawRoots;

    /// @dev An array of encryption keys.
    EncryptionKey[] public encryptionKeys;

    /// @dev The storage slots reserved for future usage.
    uint256[50] private __gap;

    /***************
     * Constructor *
     ***************/

    /// @notice Constructor for `ScrollChainValidium` implementation contract.
    ///
    /// @param _chainId The chain id of L2.
    /// @param _messageQueueV2 The address of `L1MessageQueueV2`.
    /// @param _verifier The address of `MultipleVersionRollupVerifier`.
    constructor(
        uint64 _chainId,
        address _messageQueueV2,
        address _verifier
    ) {
        _disableInitializers();

        layer2ChainId = _chainId;
        messageQueueV2 = _messageQueueV2;
        verifier = _verifier;
    }

    /// @notice Initialize the storage of ScrollChainValidium.
    /// @param _admin The address of the admin.
    function initialize(address _admin) external initializer {
        __Context_init();
        __ERC165_init();
        __AccessControl_init();
        __Pausable_init();

        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
    }

    /*************************
     * Public View Functions *
     *************************/

    /// @inheritdoc IScrollChainValidium
    function isBatchFinalized(uint256 _batchIndex) external view override returns (bool) {
        return _batchIndex <= lastFinalizedBatchIndex;
    }

    /// @inheritdoc IScrollChainValidium
    function getLatestEncryptionKey() external view override returns (uint256, bytes memory) {
        uint256 _numKeys = encryptionKeys.length;
        if (_numKeys == 0) revert ErrorUnknownEncryptionKey();
        return (_numKeys - 1, encryptionKeys[_numKeys - 1].key);
    }

    /// @inheritdoc IScrollChainValidium
    function getEncryptionKey(uint256 _keyId) external view override returns (bytes memory) {
        uint256 _numKeys = encryptionKeys.length;
        if (_numKeys == 0) revert ErrorUnknownEncryptionKey();
        if (_keyId >= _numKeys) revert ErrorUnknownEncryptionKey();
        if (_keyId < _numKeys - 1) revert ErrorDeprecatedEncryptionKey();
        return encryptionKeys[_numKeys - 1].key;
    }

    /*****************************
     * Public Mutating Functions *
     *****************************/

    /// @notice Import layer 2 genesis block
    /// @param _batchHeader The header of the genesis batch.
    function importGenesisBatch(bytes calldata _batchHeader) external onlyRole(GENESIS_IMPORTER_ROLE) {
        (uint256 batchPtr, uint256 _length) = BatchHeaderValidiumV0Codec.loadAndValidate(_batchHeader);
        // batch index should be 0 for genesis batch
        if (BatchHeaderValidiumV0Codec.getBatchIndex(batchPtr) != 0) {
            revert ErrorInvalidGenesisBatch();
        }
        // parant batch hash should be 0 for genesis batch
        if (BatchHeaderValidiumV0Codec.getParentBatchHash(batchPtr) != bytes32(0)) {
            revert ErrorInvalidGenesisBatch();
        }
        // withdraw root should be 0 for genesis batch
        if (BatchHeaderValidiumV0Codec.getWithdrawRoot(batchPtr) != bytes32(0)) {
            revert ErrorInvalidGenesisBatch();
        }

        bytes32 _postStateRoot = BatchHeaderValidiumV0Codec.getPostStateRoot(batchPtr);

        // check state root
        if (_postStateRoot == bytes32(0)) revert ErrorStateRootIsZero();

        // check whether the genesis batch is imported
        if (stateRoots[0] != bytes32(0)) revert ErrorGenesisBatchImported();

        bytes32 _batchHash = BatchHeaderValidiumV0Codec.computeBatchHash(batchPtr, _length);

        committedBatches[0] = _batchHash;
        stateRoots[0] = _postStateRoot;

        emit CommitBatch(0, _batchHash);
        emit FinalizeBatch(0, _batchHash, _postStateRoot, bytes32(0));
    }

    /// @inheritdoc IScrollChainValidium
    function commitBatch(
        uint8 version,
        bytes32 parentBatchHash,
        bytes32 postStateRoot,
        bytes32 withdrawRoot,
        bytes calldata commitment
    ) external onlyRole(SEQUENCER_ROLE) whenNotPaused {
        if (postStateRoot == bytes32(0)) revert ErrorStateRootIsZero();

        uint256 cachedLastCommittedBatchIndex = lastCommittedBatchIndex;
        if (parentBatchHash != committedBatches[cachedLastCommittedBatchIndex]) {
            revert ErrorIncorrectBatchHash();
        }

        cachedLastCommittedBatchIndex += 1;
        bytes memory batchHeader = BatchHeaderValidiumV0Codec.encode(
            version,
            uint64(cachedLastCommittedBatchIndex),
            parentBatchHash,
            postStateRoot,
            withdrawRoot,
            commitment
        );
        bytes32 batchHash = BatchHeaderValidiumV0Codec.computeBatchHash(batchHeader);

        lastCommittedBatchIndex = cachedLastCommittedBatchIndex;
        committedBatches[cachedLastCommittedBatchIndex] = batchHash;
        stateRoots[cachedLastCommittedBatchIndex] = postStateRoot;
        withdrawRoots[cachedLastCommittedBatchIndex] = withdrawRoot;

        emit CommitBatch(cachedLastCommittedBatchIndex, batchHash);
    }

    /// @inheritdoc IScrollChainValidium
    function revertBatch(bytes calldata batchHeader) external onlyRole(DEFAULT_ADMIN_ROLE) {
        uint256 lastBatchIndex = lastCommittedBatchIndex;
        (, , uint256 startBatchIndex) = _loadBatchHeader(batchHeader, lastBatchIndex);

        // check finalization
        if (startBatchIndex <= lastFinalizedBatchIndex) revert ErrorRevertFinalizedBatch();

        // actual revert
        for (uint256 i = lastBatchIndex; i >= startBatchIndex; --i) {
            delete committedBatches[i];
            delete stateRoots[i];
            delete withdrawRoots[i];
        }
        emit RevertBatch(startBatchIndex, lastBatchIndex);

        // update `lastCommittedBatchIndex`
        lastCommittedBatchIndex = startBatchIndex - 1;
    }

    /// @inheritdoc IScrollChainValidium
    function finalizeBundle(
        bytes calldata batchHeader,
        uint256 totalL1MessagesPoppedOverall,
        bytes calldata aggrProof
    ) external override onlyRole(PROVER_ROLE) whenNotPaused {
        _finalizeBundle(batchHeader, totalL1MessagesPoppedOverall, aggrProof);
    }

    /************************
     * Restricted Functions *
     ************************/

    function registerNewEncryptionKey(bytes memory _key) external onlyRole(KEY_MANAGER_ROLE) {
        if (_key.length != 33) revert ErrorInvalidEncryptionKeyLength();
        uint256 _keyId = encryptionKeys.length;

        // The message from `nextCrossDomainMessageIndex` will utilise the newly registered encryption key.
        uint256 _msgIndex = IL1MessageQueueV2(messageQueueV2).nextCrossDomainMessageIndex();
        encryptionKeys.push(EncryptionKey(_msgIndex, _key));

        emit NewEncryptionKey(_keyId, _msgIndex, _key);
    }

    /// @notice Pause the contract
    /// @param _status The pause status to update.
    function setPause(bool _status) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (_status) {
            _pause();
        } else {
            _unpause();
        }
    }

    /**********************
     * Internal Functions *
     **********************/

    /// @dev Internal function to do common actions before actual batch finalization.
    function _beforeFinalizeBatch(bytes calldata batchHeader)
        internal
        view
        returns (
            uint256 version,
            bytes32 batchHash,
            uint256 batchIndex,
            uint256 prevBatchIndex
        )
    {
        uint256 batchPtr;
        // compute pending batch hash and verify
        (batchPtr, batchHash, batchIndex) = _loadBatchHeader(batchHeader, lastCommittedBatchIndex);

        // make sure don't finalize batch multiple times
        prevBatchIndex = lastFinalizedBatchIndex;
        if (batchIndex <= prevBatchIndex) revert ErrorBatchIsAlreadyVerified();

        version = BatchHeaderValidiumV0Codec.getVersion(batchPtr);
    }

    /// @dev Internal function to do common actions after actual batch finalization.
    function _afterFinalizeBatch(
        uint256 batchIndex,
        bytes32 batchHash,
        uint256 totalL1MessagesPoppedOverall,
        bytes32 postStateRoot,
        bytes32 withdrawRoot
    ) internal {
        lastFinalizedBatchIndex = batchIndex;

        if (totalL1MessagesPoppedOverall > 0) {
            IL1MessageQueueV2(messageQueueV2).finalizePoppedCrossDomainMessage(totalL1MessagesPoppedOverall);
        }

        emit FinalizeBatch(batchIndex, batchHash, postStateRoot, withdrawRoot);
    }

    /// @dev Internal function to finalize a bundle.
    /// @param batchHeader The header of the last batch in this bundle.
    /// @param totalL1MessagesPoppedOverall The number of messages processed after this bundle.
    /// @param aggrProof The bundle proof for this bundle.
    function _finalizeBundle(
        bytes calldata batchHeader,
        uint256 totalL1MessagesPoppedOverall,
        bytes calldata aggrProof
    ) internal virtual {
        // actions before verification
        (uint256 version, bytes32 batchHash, uint256 batchIndex, uint256 prevBatchIndex) = _beforeFinalizeBatch(
            batchHeader
        );

        // L1 message hashes are chained,
        // this hash commits to the whole queue up to and including `totalL1MessagesPoppedOverall-1`
        bytes32 messageQueueHash = totalL1MessagesPoppedOverall == 0
            ? bytes32(0)
            : IL1MessageQueueV2(messageQueueV2).getMessageRollingHash(totalL1MessagesPoppedOverall - 1);

        bytes32 postStateRoot = stateRoots[batchIndex];
        bytes32 withdrawRoot = withdrawRoots[batchIndex];

        // Get the encryption key at the time of on-chain message queue index.
        bytes memory encryptionKey = totalL1MessagesPoppedOverall == 0
            ? _getEncryptionKey(0)
            : _getEncryptionKey(totalL1MessagesPoppedOverall - 1);

        bytes memory publicInputs = abi.encodePacked(
            layer2ChainId,
            messageQueueHash,
            uint32(batchIndex - prevBatchIndex), // numBatches
            stateRoots[prevBatchIndex], // _prevStateRoot
            committedBatches[prevBatchIndex], // _prevBatchHash
            postStateRoot,
            batchHash,
            withdrawRoot,
            encryptionKey
        );

        // verify bundle, choose the correct verifier based on the last batch
        // our off-chain service will make sure all unfinalized batches have the same batch version.
        IRollupVerifier(verifier).verifyBundleProof(version, batchIndex, aggrProof, publicInputs);

        // actions after verification
        _afterFinalizeBatch(batchIndex, batchHash, totalL1MessagesPoppedOverall, postStateRoot, withdrawRoot);
    }

    /// @dev Internal function to load batch header from calldata to memory.
    /// @param _batchHeader The batch header in calldata.
    /// @param _lastCommittedBatchIndex The index of the last committed batch.
    /// @return batchPtr The start memory offset of loaded batch header.
    /// @return _batchHash The hash of the loaded batch header.
    /// @return _batchIndex The index of this batch.
    /// @dev This function only works with batches whose hashes are stored in `committedBatches`.
    function _loadBatchHeader(bytes calldata _batchHeader, uint256 _lastCommittedBatchIndex)
        internal
        view
        virtual
        returns (
            uint256 batchPtr,
            bytes32 _batchHash,
            uint256 _batchIndex
        )
    {
        // load version from batch header, it is always the first byte.
        uint256 version;
        assembly {
            version := shr(248, calldataload(_batchHeader.offset))
        }

        uint256 length;
        (batchPtr, length) = BatchHeaderValidiumV0Codec.loadAndValidate(_batchHeader);

        _batchIndex = BatchHeaderValidiumV0Codec.getBatchIndex(batchPtr);

        if (_batchIndex > _lastCommittedBatchIndex) revert ErrorBatchNotCommitted();

        // check against local storage
        _batchHash = BatchHeaderValidiumV0Codec.computeBatchHash(batchPtr, length);
        if (committedBatches[_batchIndex] != _batchHash) {
            revert ErrorIncorrectBatchHash();
        }
    }

    /// @dev Internal function to get the relevant encryption key that was used to encrypt messages up to the provided message index.
    /// @param _msgIndex The on-chain message queue index being finalised.
    /// @return The encryption key used at the time of the provided on-chain message queue index.
    function _getEncryptionKey(uint256 _msgIndex) internal view returns (bytes memory) {
        // Start from the "latest" key and continue fetching keys until we find the key
        // that was rotated before the message index we have been provided.
        uint256 _numKeys = encryptionKeys.length;
        if (_numKeys == 0) revert ErrorUnknownEncryptionKey();
        EncryptionKey memory _encryptionKey = encryptionKeys[--_numKeys];

        while (_encryptionKey.msgIndex > _msgIndex) {
            if (_numKeys == 0) revert ErrorUnknownEncryptionKey();
            _encryptionKey = encryptionKeys[--_numKeys];
        }

        return _encryptionKey.key;
    }
}
