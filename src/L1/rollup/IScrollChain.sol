// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

/// @title IScrollChain
/// @notice The interface for ScrollChain.
interface IScrollChain {
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

    /// @notice Emitted when a batch is finalized.
    /// @param batchIndex The index of the batch.
    /// @param batchHash The hash of the batch
    /// @param stateRoot The state root on layer 2 after this batch.
    /// @param withdrawRoot The merkle root on layer2 after this batch.
    event FinalizeBatch(uint256 indexed batchIndex, bytes32 indexed batchHash, bytes32 stateRoot, bytes32 withdrawRoot);

    /// @notice Emitted when owner updates the status of sequencer.
    /// @param account The address of account updated.
    /// @param status The status of the account updated.
    event UpdateSequencer(address indexed account, bool status);

    /// @notice Emitted when owner updates the status of prover.
    /// @param account The address of account updated.
    /// @param status The status of the account updated.
    event UpdateProver(address indexed account, bool status);

    /// @notice Emitted when the value of `maxNumTxInChunk` is updated.
    /// @param oldMaxNumTxInChunk The old value of `maxNumTxInChunk`.
    /// @param newMaxNumTxInChunk The new value of `maxNumTxInChunk`.
    event UpdateMaxNumTxInChunk(uint256 oldMaxNumTxInChunk, uint256 newMaxNumTxInChunk);

    /// @notice Emitted when enter enforced batch mode.
    /// @param lastCommittedBatchIndex The index of last committed batch.
    event EnterEnforcedBatchMode(uint256 lastCommittedBatchIndex);

    /// @notice Emitted when exit enforced batch mode.
    /// @param lastCommittedBatchIndex The index of last committed batch.
    event ExitEnforcedBatchMode(uint256 lastCommittedBatchIndex);

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

    /*****************************
     * Public Mutating Functions *
     *****************************/

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

    /// @notice Commit a batch after Euclid phase 2 upgrade.
    /// @param version The version of current batch.
    /// @param parentBatchHash The hash of parent batch.
    function commitBatchesPostEuclidV2(uint8 version, bytes32 parentBatchHash) external;

    /// @notice Revert pending batches.
    /// @dev one can only revert unfinalized batches.
    /// @param batchHeader The header of first batch to revert, see the encoding in comments of `commitBatch`.
    function revertBatch(bytes calldata batchHeader) external;

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

    /// @notice Finalize a list of committed batches (i.e. bundle) on layer 1 after Euclid phase 2 upgrade.
    /// @param batchHeader The header of last batch in current bundle, see the encoding in comments of `commitBatch.
    /// @param lastProcessedQueueIndex The last processed message queue index.
    /// @param postStateRoot The state root after current bundle.
    /// @param withdrawRoot The withdraw trie root after current bundle.
    /// @param aggrProof The aggregation proof for current bundle.
    function finalizeBundlePostEuclidV2(
        bytes calldata batchHeader,
        uint256 lastProcessedQueueIndex,
        bytes32 postStateRoot,
        bytes32 withdrawRoot,
        bytes calldata aggrProof
    ) external;

    /// @param The struct for batch finalization.
    /// @param batchHeader The header of current batch, see the encoding in comments of `commitBatch`.
    /// @param lastProcessedQueueIndex The last processed message queue index.
    /// @param postStateRoot The state root after current batch.
    /// @param withdrawRoot The withdraw trie root after current batch.
    /// @param zkProof The zk proof for current batch (single-batch bundle).
    struct FinalizeStruct {
        bytes batchHeader;
        uint256 lastProcessedQueueIndex;
        bytes32 postStateRoot;
        bytes32 withdrawRoot;
        bytes zkProof;
    }

    /// @notice Commit a batch of transactions on layer 1 and finalize it.
    /// @param version The version of current batch.
    /// @param finalizeStruct The data needed for finalize.
    /// @param parentBatchHash The hash of parent batch.
    function commitAndFinalizeBatch(
        uint8 version,
        bytes32 parentBatchHash,
        FinalizeStruct calldata finalizeStruct
    ) external;
}
