// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

interface IScrollChainValidium {
    /**********
     * Events *
     **********/

    /// @notice Emitted when a new batch is committed.
    /// @param batchIndex The index of the batch.
    /// @param batchHash The hash of the batch.
    event CommitBatch(uint256 indexed batchIndex, bytes32 indexed batchHash);

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

    /// @notice Emitted when a new encryption key is added.
    /// @param keyId The incremental index of the key.
    /// @param msgIndex The message queue index at the time of key rotation.
    /// @param key The encryption key.
    event NewEncryptionKey(uint256 indexed keyId, uint256 msgIndex, bytes key);

    /*************************
     * Public View Functions *
     *************************/

    /// @return The latest finalized batch index.
    function lastFinalizedBatchIndex() external view returns (uint256);

    /// @return The latest committed batch index.
    function lastCommittedBatchIndex() external view returns (uint256);

    /// @param batchIndex The index of the batch.
    /// @return The batch hash of a committed batch.
    function committedBatches(uint256 batchIndex) external view returns (bytes32);

    /// @param batchIndex The index of the batch.
    /// @return The state root of a committed batch.
    function stateRoots(uint256 batchIndex) external view returns (bytes32);

    /// @param batchIndex The index of the batch.
    /// @return The message root of a committed batch.
    function withdrawRoots(uint256 batchIndex) external view returns (bytes32);

    /// @param batchIndex The index of the batch.
    /// @return Whether the batch is finalized by batch index.
    function isBatchFinalized(uint256 batchIndex) external view returns (bool);

    /// @return The key-id of the latest encryption key.
    /// @return The latest encryption key.
    function getLatestEncryptionKey() external view returns (uint256, bytes memory);

    /// @param keyId The incremental index for the encryption key.
    /// @return The encryption key with the given key-id.
    function getEncryptionKey(uint256 keyId) external view returns (bytes memory);

    /*****************************
     * Public Mutating Functions *
     *****************************/

    /// @notice Commit a pending batch.
    /// @param version The version of this batch.
    /// @param parentBatchHash The hash of parent batch.
    /// @param stateRoot The state root after this batch.
    /// @param withdrawRoot The withdraw trie root after this batch.
    /// @param commitment The data commitment.
    function commitBatch(
        uint8 version,
        bytes32 parentBatchHash,
        bytes32 stateRoot,
        bytes32 withdrawRoot,
        bytes calldata commitment
    ) external;

    /// @notice Revert pending batches.
    /// @dev one can only revert unfinalized batches.
    /// @param batchHeader The header of the first batch we want to revert.
    function revertBatch(bytes calldata batchHeader) external;

    /// @notice Finalize a list of committed batches (i.e. bundle) on layer 1.
    /// @param batchHeader The header of the last batch in this bundle.
    /// @param totalL1MessagesPoppedOverall The number of messages processed after this bundle.
    /// @param aggrProof The aggregation proof for current bundle.
    function finalizeBundle(
        bytes calldata batchHeader,
        uint256 totalL1MessagesPoppedOverall,
        bytes calldata aggrProof
    ) external;
}
