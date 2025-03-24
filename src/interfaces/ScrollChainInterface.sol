// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

/// @notice ScrollChainInterface collects all past and present ScrollChain
/// events and functions that are needed to index data.
/// @dev We store these here for easier access to the full ABI, since some
/// of these functions were removed in later versions of ScrollChain.
interface ScrollChainInterface {
    /**********
     * Events *
     **********/

    /// @notice Emitted when a new batch is committed.
    /// @param batchIndex The index of the batch.
    /// @param batchHash The hash of the batch.
    event CommitBatch(uint256 indexed batchIndex, bytes32 indexed batchHash);

    /// @notice revert a pending batch.
    /// @param batchIndex The index of the batch.
    /// @param batchHash The hash of the batch
    event RevertBatch(uint256 indexed batchIndex, bytes32 indexed batchHash);

    /// @notice revert a range of batches.
    /// @param startBatchIndex The start batch index of the range (inclusive).
    /// @param finishBatchIndex The finish batch index of the range (inclusive).
    event RevertBatch(uint256 indexed startBatchIndex, uint256 indexed finishBatchIndex);

    /// @notice Emitted when a batch is finalized.
    /// @param batchIndex The index of the batch.
    /// @param batchHash The hash of the batch
    /// @param stateRoot The state root on layer 2 after this batch.
    /// @param withdrawRoot The merkle root on layer2 after this batch.
    event FinalizeBatch(uint256 indexed batchIndex, bytes32 indexed batchHash, bytes32 stateRoot, bytes32 withdrawRoot);

    /// @notice Emitted when we enter or exit enforced batch mode.
    /// @param enabled True if we are entering enforced batch mode, false otherwise.
    /// @param lastCommittedBatchIndex The index of the last committed batch.
    event UpdateEnforcedBatchMode(bool enabled, uint256 lastCommittedBatchIndex);

    /*************************
     * Public View Functions *
     *************************/

    /// @return The latest finalized batch index.
    function lastFinalizedBatchIndex() external view returns (uint256);

    /// @param batchIndex The index of the batch.
    /// @return The batch hash of a committed batch.
    function committedBatches(uint256 batchIndex) external view returns (bytes32);

    /// @param batchIndex The index of the batch.
    /// @return The state root of a committed batch.
    function finalizedStateRoots(uint256 batchIndex) external view returns (bytes32);

    /// @param batchIndex The index of the batch.
    /// @return The message root of a committed batch.
    function withdrawRoots(uint256 batchIndex) external view returns (bytes32);

    /// @param batchIndex The index of the batch.
    /// @return Whether the batch is finalized by batch index.
    function isBatchFinalized(uint256 batchIndex) external view returns (bool);

    /********************
     * Commit Functions *
     ********************/

    /// @notice Import layer 2 genesis block
    /// @param _batchHeader The header of the genesis batch.
    /// @param _stateRoot The state root of the genesis block.
    function importGenesisBatch(bytes calldata _batchHeader, bytes32 _stateRoot) external;

    /// @notice Commit a batch of transactions on layer 1.
    ///
    /// @param version The version of current batch.
    /// @param parentBatchHeader The header of parent batch, see the comments of `BatchHeaderV0Codec`.
    /// @param chunks The list of encoded chunks, see the comments of `ChunkCodec`.
    /// @param skippedL1MessageBitmap The bitmap indicates whether each L1 message is skipped or not.
    function commitBatch(
        uint8 version,
        bytes calldata parentBatchHeader,
        bytes[] memory chunks,
        bytes calldata skippedL1MessageBitmap
    ) external;

    /// @notice Commit a batch of transactions on layer 1 with blob data proof.
    ///
    /// @dev Memory layout of `blobDataProof`:
    /// |    z    |    y    | kzg_commitment | kzg_proof |
    /// |---------|---------|----------------|-----------|
    /// | bytes32 | bytes32 |    bytes48     |  bytes48  |
    ///
    /// @param version The version of current batch.
    /// @param parentBatchHeader The header of parent batch.
    /// @param chunks The list of encoded chunks, see the comments of `ChunkCodec`.
    /// @param skippedL1MessageBitmap The bitmap indicates whether each L1 message is skipped or not.
    /// @param blobDataProof The proof for blob data.
    function commitBatchWithBlobProof(
        uint8 version,
        bytes calldata parentBatchHeader,
        bytes[] memory chunks,
        bytes calldata skippedL1MessageBitmap,
        bytes calldata blobDataProof
    ) external;

    /// @notice Commit one or more batches after the EuclidV2 upgrade.
    /// @param version The version of the committed batches.
    /// @param parentBatchHash The hash of parent batch.
    /// @param lastBatchHash The hash of the last committed batch after this call.
    /// @dev The batch payload is stored in the blobs.
    function commitBatches(
        uint8 version,
        bytes32 parentBatchHash,
        bytes32 lastBatchHash
    ) external;

    /********************
     * Revert Functions *
     ********************/

    /// @notice Revert a pending batch.
    /// @dev one can only revert unfinalized batches.
    /// @param batchHeader The header of current batch, see the encoding in comments of `commitBatch`.
    /// @param count The number of subsequent batches to revert, including current batch.
    function revertBatch(bytes calldata batchHeader, uint256 count) external;

    /// @notice Revert pending batches.
    /// @dev one can only revert unfinalized batches.
    /// @param batchHeader The header of the last batch we want to keep.
    function revertBatch(bytes calldata batchHeader) external;

    /**********************
     * Finalize Functions *
     **********************/

    /// @notice Finalize a committed batch on layer 1.
    /// @param batchHeader The header of current batch, see the encoding in comments of `commitBatch.
    /// @param prevStateRoot The state root of parent batch.
    /// @param postStateRoot The state root of current batch.
    /// @param withdrawRoot The withdraw trie root of current batch.
    /// @param aggrProof The aggregation proof for current batch.
    function finalizeBatchWithProof(
        bytes calldata batchHeader,
        bytes32 prevStateRoot,
        bytes32 postStateRoot,
        bytes32 withdrawRoot,
        bytes calldata aggrProof
    ) external;

    /// @notice Finalize a committed batch (with blob) on layer 1.
    ///
    /// @dev Memory layout of `blobDataProof`:
    /// |    z    |    y    | kzg_commitment | kzg_proof |
    /// |---------|---------|----------------|-----------|
    /// | bytes32 | bytes32 |    bytes48     |  bytes48  |
    ///
    /// @param batchHeader The header of current batch, see the encoding in comments of `commitBatch.
    /// @param prevStateRoot The state root of parent batch.
    /// @param postStateRoot The state root of current batch.
    /// @param withdrawRoot The withdraw trie root of current batch.
    /// @param blobDataProof The proof for blob data.
    /// @param aggrProof The aggregation proof for current batch.
    function finalizeBatchWithProof4844(
        bytes calldata batchHeader,
        bytes32 prevStateRoot,
        bytes32 postStateRoot,
        bytes32 withdrawRoot,
        bytes calldata blobDataProof,
        bytes calldata aggrProof
    ) external;

    /// @notice Finalize a list of committed batches (i.e. bundle) on layer 1.
    /// @param batchHeader The header of last batch in current bundle, see the encoding in comments of `commitBatch.
    /// @param postStateRoot The state root after current bundle.
    /// @param withdrawRoot The withdraw trie root after current batch.
    /// @param aggrProof The aggregation proof for current bundle.
    function finalizeBundleWithProof(
        bytes calldata batchHeader,
        bytes32 postStateRoot,
        bytes32 withdrawRoot,
        bytes calldata aggrProof
    ) external;

    /// @notice Finalize the initial Euclid batch.
    /// @param postStateRoot The state root after current batch.
    function finalizeEuclidInitialBatch(bytes32 postStateRoot) external;

    /// @notice Finalize a list of committed batches (i.e. bundle) on layer 1 after the EuclidV2 upgrade.
    /// @param batchHeader The header of the last batch in this bundle.
    /// @param totalL1MessagesPoppedOverall The number of messages processed after this bundle.
    /// @param postStateRoot The state root after this bundle.
    /// @param withdrawRoot The withdraw trie root after this bundle.
    /// @param aggrProof The bundle proof for this bundle.
    /// @dev See `BatchHeaderV7Codec` for the batch header encoding.
    function finalizeBundlePostEuclidV2(
        bytes calldata batchHeader,
        uint256 totalL1MessagesPoppedOverall,
        bytes32 postStateRoot,
        bytes32 withdrawRoot,
        bytes calldata aggrProof
    ) external;

    /**********************
     * Enforced Functions *
     **********************/

    /// @notice The struct for permissionless batch finalization.
    /// @param batchHeader The header of this batch.
    /// @param totalL1MessagesPoppedOverall The number of messages processed after this bundle.
    /// @param postStateRoot The state root after this batch.
    /// @param withdrawRoot The withdraw trie root after this batch.
    /// @param zkProof The bundle proof for this batch (single-batch bundle).
    /// @dev See `BatchHeaderV7Codec` for the batch header encoding.
    struct FinalizeStruct {
        bytes batchHeader;
        uint256 totalL1MessagesPoppedOverall;
        bytes32 postStateRoot;
        bytes32 withdrawRoot;
        bytes zkProof;
    }

    /// @notice Commit and finalize a batch in permissionless mode.
    /// @param version The version of current batch.
    /// @param parentBatchHash The hash of parent batch.
    /// @param finalizeStruct The data needed to finalize this batch.
    /// @dev The batch payload is stored in the blob.
    function commitAndFinalizeBatch(
        uint8 version,
        bytes32 parentBatchHash,
        FinalizeStruct calldata finalizeStruct
    ) external;

    /*********************
     * Mocking Functions *
     *********************/

    /// @notice Finalize batch without proof, See the comments of {finalizeBatchWithProof}.
    function finalizeBatch(
        bytes calldata _batchHeader,
        bytes32 _prevStateRoot,
        bytes32 _postStateRoot,
        bytes32 _withdrawRoot
    ) external;

    /// @notice Finalize 4844 batch without proof, See the comments of {finalizeBatchWithProof4844}.
    function finalizeBatch4844(
        bytes calldata _batchHeader,
        bytes32, /*_prevStateRoot*/
        bytes32 _postStateRoot,
        bytes32 _withdrawRoot,
        bytes calldata _blobDataProof
    ) external;

    /// @notice Finalize bundle without proof, See the comments of {finalizeBundleWithProof}.
    function finalizeBundle(
        bytes calldata batchHeader,
        bytes32 postStateRoot,
        bytes32 withdrawRoot
    ) external;

    /// @notice Finalize post Euclid phase 2 bundle without proof, See the comments of {finalizeBundlePostEuclidV2}.
    function finalizeBundlePostEuclidV2NoProof(
        bytes calldata batchHeader,
        uint256 totalL1MessagesPoppedOverall,
        bytes32 postStateRoot,
        bytes32 withdrawRoot
    ) external;
}
