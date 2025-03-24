// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

interface IL1MessageQueueV2 {
    /**********
     * Events *
     **********/

    /// @notice Emitted when a new L1 => L2 transaction is appended to the queue.
    /// @param sender The address of the sender account on L2.
    /// @param target The address of the target account on L2.
    /// @param value The ETH value transferred to the target account on L2.
    /// @param queueIndex The index of this transaction in the message queue.
    /// @param gasLimit The gas limit used on L2.
    /// @param data The calldata passed to the target account on L2.
    event QueueTransaction(
        address indexed sender,
        address indexed target,
        uint256 value,
        uint64 queueIndex,
        uint256 gasLimit,
        bytes data
    );

    /// @notice Emitted when some L1 => L2 transactions are finalized on L1.
    /// @param finalizedIndex The index of the last message finalized.
    event FinalizedDequeuedTransaction(uint256 finalizedIndex);

    /*************************
     * Public View Functions *
     *************************/

    /// @notice Return the start index of all messages in this contract.
    function firstCrossDomainMessageIndex() external view returns (uint256);

    /// @notice Return the start index of all unfinalized messages.
    function nextUnfinalizedQueueIndex() external view returns (uint256);

    /// @notice Return the index to be used for the next message.
    /// @dev Also the total number of appended messages, including messages in `L1MessageQueueV1`.
    function nextCrossDomainMessageIndex() external view returns (uint256);

    /// @notice Return the message rolling hash of `queueIndex`.
    /// @param queueIndex The index to query.
    function getMessageRollingHash(uint256 queueIndex) external view returns (bytes32);

    /// @notice Return the message enqueue timestamp of `queueIndex`.
    /// @param queueIndex The index to query.
    function getMessageEnqueueTimestamp(uint256 queueIndex) external view returns (uint256);

    /// @notice Return the first unfinalized message enqueue timestamp.
    function getFirstUnfinalizedMessageEnqueueTime() external view returns (uint256);

    /// @notice Return the amount of ETH that should be paid for a cross-domain message.
    /// @param gasLimit The gas limit required to complete the message relay on L2.
    function estimateCrossDomainMessageFee(uint256 gasLimit) external view returns (uint256);

    /// @notice Return the estimated base fee on L2.
    function estimateL2BaseFee() external view returns (uint256);

    /// @notice Return the intrinsic gas required by the provided cross-domain message.
    /// @param data The calldata of the cross-domain message.
    function calculateIntrinsicGasFee(bytes calldata data) external view returns (uint256);

    /// @notice Compute the transaction hash of an L1 message.
    /// @param sender The address of the sender account.
    /// @param queueIndex The index of this transaction in the message queue.
    /// @param value The ETH value transferred to the target account.
    /// @param target The address of the target account.
    /// @param gasLimit The gas limit provided.
    /// @param data The calldata passed to the target account.
    function computeTransactionHash(
        address sender,
        uint256 queueIndex,
        uint256 value,
        address target,
        uint256 gasLimit,
        bytes calldata data
    ) external view returns (bytes32);

    /*****************************
     * Public Mutating Functions *
     *****************************/

    /// @notice Append a L1 => L2 cross-domain message to the message queue.
    /// @param target The address of the target account on L2.
    /// @param gasLimit The gas limit used on L2.
    /// @param data The calldata passed to the target account on L2.
    /// @dev This function can only be called by `L1ScrollMessenger`.
    function appendCrossDomainMessage(
        address target,
        uint256 gasLimit,
        bytes calldata data
    ) external;

    /// @notice Append an enforced transaction to the message queue.
    /// @param sender The address of the sender account on L2.
    /// @param target The address of the target account on L2.
    /// @param value The ETH value transferred to the target account on L2.
    /// @param gasLimit The gas limit used on L2.
    /// @param data The calldata passed to the target account on L2.
    /// @dev This function can only be called by `EnforcedTxGateway`.
    function appendEnforcedTransaction(
        address sender,
        address target,
        uint256 value,
        uint256 gasLimit,
        bytes calldata data
    ) external;

    /// @notice Mark cross-domain messages as finalized.
    /// @param nextUnfinalizedQueueIndex The index of the first unfinalized message after this call.
    /// @dev This function can only be called by `ScrollChain`.
    function finalizePoppedCrossDomainMessage(uint256 nextUnfinalizedQueueIndex) external;
}
