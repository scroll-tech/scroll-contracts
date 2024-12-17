// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

interface IL1MessageQueueV2 {
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

    /// @notice Emitted when some L1 => L2 transactions are finalized in L1.
    /// @param finalizedIndex The last index of messages finalized.
    event FinalizedDequeuedTransaction(uint256 finalizedIndex);

    event UpdateL2BaseFeeParameters(uint256 overhead, uint256 scalar);

    /// @notice Emitted when owner updates max gas limit.
    /// @param _oldMaxGasLimit The old max gas limit.
    /// @param _newMaxGasLimit The new max gas limit.
    event UpdateMaxGasLimit(uint256 _oldMaxGasLimit, uint256 _newMaxGasLimit);

    /*************************
     * Public View Functions *
     *************************/

    /// @notice The start index of all unfinalized messages.
    function nextUnfinalizedQueueIndex() external view returns (uint256);

    /// @notice Return the index of next appended message.
    /// @dev Also the total number of appended messages, including messages in `L1MessageQueueV1`.
    function nextCrossDomainMessageIndex() external view returns (uint256);

    /// @notice Return the amount of ETH should pay for cross domain message.
    /// @param gasLimit Gas limit required to complete the message relay on L2.
    function estimateCrossDomainMessageFee(uint256 gasLimit) external view returns (uint256);

    /// @notice Return the estimated base fee in L2.
    function estimatedL2BaseFee() external view returns (uint256);

    /// @notice Return the amount of intrinsic gas fee should pay for cross domain message.
    /// @param data The calldata of L1-initiated transaction.
    function calculateIntrinsicGasFee(bytes calldata data) external view returns (uint256);

    /// @notice Return the hash of a L1 message.
    /// @param sender The address of sender.
    /// @param queueIndex The queue index of this message.
    /// @param value The amount of Ether transfer to target.
    /// @param target The address of target.
    /// @param gasLimit The gas limit provided.
    /// @param data The calldata passed to target address.
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

    /// @notice Append a L1 to L2 message into this contract.
    /// @param target The address of target contract to call in L2.
    /// @param gasLimit The maximum gas should be used for relay this message in L2.
    /// @param data The calldata passed to target contract.
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
    function appendEnforcedTransaction(
        address sender,
        address target,
        uint256 value,
        uint256 gasLimit,
        bytes calldata data
    ) external;

    /// @notice Finalize status of popped messages.
    /// @param newFinalizedQueueIndexPlusOne The index of message to finalize plus one.
    function finalizePoppedCrossDomainMessage(uint256 newFinalizedQueueIndexPlusOne) external;
}
