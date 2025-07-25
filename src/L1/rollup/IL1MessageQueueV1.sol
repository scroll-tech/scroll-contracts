// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

/// @custom:deprecated This contract is no longer used in production.
interface IL1MessageQueueV1 {
    /**********
     * Events *
     **********/

    /// @notice Emitted when a new L1 => L2 transaction is appended to the queue.
    /// @param sender The address of account who initiates the transaction.
    /// @param target The address of account who will receive the transaction.
    /// @param value The value passed with the transaction.
    /// @param queueIndex The index of this transaction in the queue.
    /// @param gasLimit Gas limit required to complete the message relay on L2.
    /// @param data The calldata of the transaction.
    event QueueTransaction(
        address indexed sender,
        address indexed target,
        uint256 value,
        uint64 queueIndex,
        uint256 gasLimit,
        bytes data
    );

    /// @notice Emitted when some L1 => L2 transactions are included in L1.
    /// @param startIndex The start index of messages popped.
    /// @param count The number of messages popped.
    /// @param skippedBitmap A bitmap indicates whether a message is skipped.
    event DequeueTransaction(uint256 startIndex, uint256 count, uint256 skippedBitmap);

    /// @notice Emitted when dequeued transactions are reset.
    /// @param startIndex The start index of messages.
    event ResetDequeuedTransaction(uint256 startIndex);

    /// @notice Emitted when some L1 => L2 transactions are finalized in L1.
    /// @param finalizedIndex The last index of messages finalized.
    event FinalizedDequeuedTransaction(uint256 finalizedIndex);

    /// @notice Emitted when a message is dropped from L1.
    /// @param index The index of message dropped.
    event DropTransaction(uint256 index);

    /// @notice Emitted when owner updates gas oracle contract.
    /// @param _oldGasOracle The address of old gas oracle contract.
    /// @param _newGasOracle The address of new gas oracle contract.
    event UpdateGasOracle(address indexed _oldGasOracle, address indexed _newGasOracle);

    /// @notice Emitted when owner updates max gas limit.
    /// @param _oldMaxGasLimit The old max gas limit.
    /// @param _newMaxGasLimit The new max gas limit.
    event UpdateMaxGasLimit(uint256 _oldMaxGasLimit, uint256 _newMaxGasLimit);

    /**********
     * Errors *
     **********/

    /// @dev Thrown when the given address is `address(0)`.
    error ErrorZeroAddress();

    /*************************
     * Public View Functions *
     *************************/

    /// @notice The start index of all pending inclusion messages.
    /// @custom:deprecated Please use `IL1MessageQueueV2.pendingQueueIndex` instead.
    function pendingQueueIndex() external view returns (uint256);

    /// @notice The start index of all unfinalized messages.
    /// @dev All messages from `nextUnfinalizedQueueIndex` to `pendingQueueIndex-1` are committed but not finalized.
    /// @custom:deprecated Please use `IL1MessageQueueV2.nextUnfinalizedQueueIndex` instead.
    function nextUnfinalizedQueueIndex() external view returns (uint256);

    /// @notice Return the index of next appended message.
    /// @dev Also the total number of appended messages.
    /// @custom:deprecated Please use `IL1MessageQueueV2.nextCrossDomainMessageIndex` instead.
    function nextCrossDomainMessageIndex() external view returns (uint256);

    /// @notice Return the message of in `queueIndex`.
    /// @param queueIndex The index to query.
    /// @custom:deprecated Please use `IL1MessageQueueV2.getCrossDomainMessage` instead.
    function getCrossDomainMessage(uint256 queueIndex) external view returns (bytes32);

    /// @notice Return the amount of ETH should pay for cross domain message.
    /// @param gasLimit Gas limit required to complete the message relay on L2.
    /// @custom:deprecated Please use `IL1MessageQueueV2.estimateCrossDomainMessageFee` instead.
    function estimateCrossDomainMessageFee(uint256 gasLimit) external view returns (uint256);

    /// @notice Return the amount of intrinsic gas fee should pay for cross domain message.
    /// @param _calldata The calldata of L1-initiated transaction.
    /// @custom:deprecated Please use `IL1MessageQueueV2.calculateIntrinsicGasFee` instead.
    function calculateIntrinsicGasFee(bytes calldata _calldata) external view returns (uint256);

    /// @notice Return the hash of a L1 message.
    /// @param sender The address of sender.
    /// @param queueIndex The queue index of this message.
    /// @param value The amount of Ether transfer to target.
    /// @param target The address of target.
    /// @param gasLimit The gas limit provided.
    /// @param data The calldata passed to target address.
    /// @custom:deprecated Please use `IL1MessageQueueV2.computeTransactionHash` instead.
    function computeTransactionHash(
        address sender,
        uint256 queueIndex,
        uint256 value,
        address target,
        uint256 gasLimit,
        bytes calldata data
    ) external view returns (bytes32);

    /// @notice Return whether the message is skipped.
    /// @param queueIndex The queue index of the message to check.
    /// @custom:deprecated
    function isMessageSkipped(uint256 queueIndex) external view returns (bool);

    /// @notice Return whether the message is dropped.
    /// @param queueIndex The queue index of the message to check.
    /// @custom:deprecated
    function isMessageDropped(uint256 queueIndex) external view returns (bool);

    /*****************************
     * Public Mutating Functions *
     *****************************/

    /// @notice Append a L1 to L2 message into this contract.
    /// @param target The address of target contract to call in L2.
    /// @param gasLimit The maximum gas should be used for relay this message in L2.
    /// @param data The calldata passed to target contract.
    /// @custom:deprecated Please use `IL1MessageQueueV2.appendCrossDomainMessage` instead.
    function appendCrossDomainMessage(
        address target,
        uint256 gasLimit,
        bytes calldata data
    ) external;

    /// @notice Append an enforced transaction to this contract.
    /// @dev The address of sender should be an EOA.
    /// @param sender The address of sender who will initiate this transaction in L2.
    /// @param target The address of target contract to call in L2.
    /// @param value The value passed
    /// @param gasLimit The maximum gas should be used for this transaction in L2.
    /// @param data The calldata passed to target contract.
    /// @custom:deprecated Please use `IL1MessageQueueV2.appendEnforcedTransaction` instead.
    function appendEnforcedTransaction(
        address sender,
        address target,
        uint256 value,
        uint256 gasLimit,
        bytes calldata data
    ) external;

    /// @notice Pop messages from queue.
    ///
    /// @dev We can pop at most 256 messages each time. And if the message is not skipped,
    ///      the corresponding entry will be cleared.
    ///
    /// @param startIndex The start index to pop.
    /// @param count The number of messages to pop.
    /// @param skippedBitmap A bitmap indicates whether a message is skipped.
    /// @custom:deprecated
    function popCrossDomainMessage(
        uint256 startIndex,
        uint256 count,
        uint256 skippedBitmap
    ) external;

    /// @notice Reset status of popped messages.
    ///
    /// @dev We can only reset unfinalized popped messages.
    ///
    /// @param startIndex The start index to reset.
    /// @custom:deprecated
    function resetPoppedCrossDomainMessage(uint256 startIndex) external;

    /// @notice Finalize status of popped messages.
    /// @param newFinalizedQueueIndexPlusOne The index of message to finalize plus one.
    /// @custom:deprecated
    function finalizePoppedCrossDomainMessage(uint256 newFinalizedQueueIndexPlusOne) external;

    /// @notice Drop a skipped message from the queue.
    /// @custom:deprecated
    function dropCrossDomainMessage(uint256 index) external;
}
