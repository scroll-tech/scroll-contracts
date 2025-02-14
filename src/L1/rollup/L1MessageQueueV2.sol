// SPDX-License-Identifier: MIT

pragma solidity =0.8.24;

import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

import {AddressAliasHelper} from "../../libraries/common/AddressAliasHelper.sol";
import {IL1MessageQueueV1} from "./IL1MessageQueueV1.sol";
import {IL1MessageQueueV2} from "./IL1MessageQueueV2.sol";

import {SystemConfig} from "../system-contract/SystemConfig.sol";

// solhint-disable no-empty-blocks
// solhint-disable no-inline-assembly
// solhint-disable reason-string

/// @title L1MessageQueueV2
/// @notice This contract will hold all L1 to L2 messages.
/// Each appended message is assigned with a unique and increasing `uint256` index.
contract L1MessageQueueV2 is OwnableUpgradeable, IL1MessageQueueV2 {
    /**********
     * Errors *
     **********/

    /// @dev Thrown when caller is not `L1ScrollMessenger` contract.
    error ErrorCallerIsNotMessenger();

    /// @dev Thrown when caller is not `ScrollChain` contract.
    error ErrorCallerIsNotScrollChain();

    /// @dev Thrown when caller is not `EnforcedTxGateway` contract.
    error ErrorCallerIsNotEnforcedTxGateway();

    /// @dev Thrown when `ScrollChain` finalize old message queue index.
    error ErrorFinalizedIndexTooSmall();

    /// @dev Thrown when `ScrollChain` finalize future massage queue index.
    error ErrorFinalizedIndexTooLarge();

    /// @dev Thrown when the given gas limit exceeds capacity.
    error ErrorGasLimitExceeded();

    /// @dev Thrown when the given gas limit is below intrinsic gas.
    error ErrorGasLimitBelowIntrinsicGas();

    /*************
     * Constants *
     *************/

    /// @notice The intrinsic gas for transaction.
    uint256 private constant INTRINSIC_GAS_TX = 21000;

    /// @notice The appropriate intrinsic gas for each byte.
    uint256 private constant APPROPRIATE_INTRINSIC_GAS_PER_BYTE = 16;

    uint256 private constant PRECISION = 1e18;

    /***********************
     * Immutable Variables *
     ***********************/

    /// @notice The address of L1ScrollMessenger contract.
    address public immutable messenger;

    /// @notice The address of ScrollChain contract.
    address public immutable scrollChain;

    /// @notice The address EnforcedTxGateway contract.
    address public immutable enforcedTxGateway;

    /// @notice The address of L1MessageQueueV1 contract.
    address public immutable messageQueueV1;

    /// @notice The address of `SystemConfig` contract.
    address public immutable systemConfig;

    /*********************
     * Storage Variables *
     *********************/

    /// @dev The list of queued cross domain messages. The encoding for `bytes32` is
    /// ```text
    /// [      32 bits      |   224 bits   ]
    /// [ enqueue timestamp | rolling hash ]
    /// [LSB                            MSB]
    /// ```
    ///
    /// We choose `32` bits for timestamp because it is enough for next 81 years. And the rest `224` bits is secure
    /// enough for the rolling hash.
    mapping(uint256 => bytes32) private messageRollingHashes;

    /// @notice The index of first cross domain message.
    /// @dev It means if `index < firstCrossDomainMessageIndex`, the message is in `L1MessageQueueV1`.
    uint256 public firstCrossDomainMessageIndex;

    /// @inheritdoc IL1MessageQueueV2
    uint256 public nextCrossDomainMessageIndex;

    /// @inheritdoc IL1MessageQueueV2
    uint256 public nextUnfinalizedQueueIndex;

    /// @dev The storage slots for future usage.
    uint256[45] private __gap;

    /**********************
     * Function Modifiers *
     **********************/

    modifier onlyScrollChain() {
        require(_msgSender() == scrollChain, "Only callable by the ScrollChain");
        _;
    }

    /***************
     * Constructor *
     ***************/

    /// @notice Constructor for `L1MessageQueue` implementation contract.
    ///
    /// @param _messenger The address of `L1ScrollMessenger` contract.
    /// @param _scrollChain The address of `ScrollChain` contract.
    /// @param _enforcedTxGateway The address of `EnforcedTxGateway` contract.
    /// @param _messageQueueV1 The address of `L1MessageQueueV1` contract.
    constructor(
        address _messenger,
        address _scrollChain,
        address _enforcedTxGateway,
        address _messageQueueV1,
        address _systemConfig
    ) {
        _disableInitializers();

        messenger = _messenger;
        scrollChain = _scrollChain;
        enforcedTxGateway = _enforcedTxGateway;
        messageQueueV1 = _messageQueueV1;
        systemConfig = _systemConfig;
    }

    /// @notice Initialize the storage of L1MessageQueue.
    function initialize() external initializer {
        OwnableUpgradeable.__Ownable_init();

        uint256 _nextCrossDomainMessageIndex = IL1MessageQueueV1(messageQueueV1).nextCrossDomainMessageIndex();
        nextCrossDomainMessageIndex = _nextCrossDomainMessageIndex;
        nextUnfinalizedQueueIndex = _nextCrossDomainMessageIndex;
    }

    /*************************
     * Public View Functions *
     *************************/

    /// @inheritdoc IL1MessageQueueV2
    function getFirstUnfinalizedMessageEnqueueTime() external view returns (uint256 timestamp) {
        (, timestamp) = _loadAndDecodeRollingHash(nextUnfinalizedQueueIndex);
        if (timestamp == 0) {
            timestamp = block.timestamp;
        }
    }

    /// @inheritdoc IL1MessageQueueV2
    function getMessageRollingHash(uint256 queueIndex) external view returns (bytes32 hash) {
        (hash, ) = _loadAndDecodeRollingHash(queueIndex);
    }

    /// @inheritdoc IL1MessageQueueV2
    function estimatedL2BaseFee() public view returns (uint256) {
        (, uint256 overhead, uint256 scalar) = SystemConfig(systemConfig).messageQueueParameters();
        // this is unlikely to happen, use unchecked here
        unchecked {
            return (block.basefee * scalar) / PRECISION + overhead;
        }
    }

    /// @inheritdoc IL1MessageQueueV2
    function estimateCrossDomainMessageFee(uint256 _gasLimit) external view returns (uint256) {
        return _gasLimit * estimatedL2BaseFee();
    }

    /// @inheritdoc IL1MessageQueueV2
    function calculateIntrinsicGasFee(bytes calldata _calldata) public pure returns (uint256) {
        // no way this can overflow `uint256`
        unchecked {
            return INTRINSIC_GAS_TX + _calldata.length * APPROPRIATE_INTRINSIC_GAS_PER_BYTE;
        }
    }

    /// @inheritdoc IL1MessageQueueV2
    function computeTransactionHash(
        address _sender,
        uint256 _queueIndex,
        uint256 _value,
        address _target,
        uint256 _gasLimit,
        bytes calldata _data
    ) public pure returns (bytes32) {
        // We use EIP-2718 to encode the L1 message, and the encoding of the message is
        //      `TransactionType || TransactionPayload`
        // where
        //  1. `TransactionType` is 0x7E
        //  2. `TransactionPayload` is `rlp([queueIndex, gasLimit, to, value, data, sender])`
        //
        // The spec of rlp: https://ethereum.org/en/developers/docs/data-structures-and-encoding/rlp/
        uint256 transactionType = 0x7E;
        bytes32 hash;
        assembly {
            function get_uint_bytes(v) -> len {
                if eq(v, 0) {
                    len := 1
                    leave
                }
                for {

                } gt(v, 0) {

                } {
                    len := add(len, 1)
                    v := shr(8, v)
                }
            }

            // This is used for both store uint and single byte.
            // Integer zero is special handled by geth to encode as `0x80`
            function store_uint_or_byte(_ptr, v, is_uint) -> ptr {
                ptr := _ptr
                switch lt(v, 128)
                case 1 {
                    switch and(iszero(v), is_uint)
                    case 1 {
                        // integer 0
                        mstore8(ptr, 0x80)
                    }
                    default {
                        // single byte in the [0x00, 0x7f]
                        mstore8(ptr, v)
                    }
                    ptr := add(ptr, 1)
                }
                default {
                    // 1-32 bytes long
                    let len := get_uint_bytes(v)
                    mstore8(ptr, add(len, 0x80))
                    ptr := add(ptr, 1)
                    mstore(ptr, shl(mul(8, sub(32, len)), v))
                    ptr := add(ptr, len)
                }
            }

            function store_address(_ptr, v) -> ptr {
                ptr := _ptr
                // 20 bytes long
                mstore8(ptr, 0x94) // 0x80 + 0x14
                ptr := add(ptr, 1)
                mstore(ptr, shl(96, v))
                ptr := add(ptr, 0x14)
            }

            // 1 byte for TransactionType
            // 4 byte for list payload length
            let start_ptr := add(mload(0x40), 5)
            let ptr := start_ptr
            ptr := store_uint_or_byte(ptr, _queueIndex, 1)
            ptr := store_uint_or_byte(ptr, _gasLimit, 1)
            ptr := store_address(ptr, _target)
            ptr := store_uint_or_byte(ptr, _value, 1)

            switch eq(_data.length, 1)
            case 1 {
                // single byte
                ptr := store_uint_or_byte(ptr, byte(0, calldataload(_data.offset)), 0)
            }
            default {
                switch lt(_data.length, 56)
                case 1 {
                    // a string is 0-55 bytes long
                    mstore8(ptr, add(0x80, _data.length))
                    ptr := add(ptr, 1)
                    calldatacopy(ptr, _data.offset, _data.length)
                    ptr := add(ptr, _data.length)
                }
                default {
                    // a string is more than 55 bytes long
                    let len_bytes := get_uint_bytes(_data.length)
                    mstore8(ptr, add(0xb7, len_bytes))
                    ptr := add(ptr, 1)
                    mstore(ptr, shl(mul(8, sub(32, len_bytes)), _data.length))
                    ptr := add(ptr, len_bytes)
                    calldatacopy(ptr, _data.offset, _data.length)
                    ptr := add(ptr, _data.length)
                }
            }
            ptr := store_address(ptr, _sender)

            let payload_len := sub(ptr, start_ptr)
            let value
            let value_bytes
            switch lt(payload_len, 56)
            case 1 {
                // the total payload of a list is 0-55 bytes long
                value := add(0xc0, payload_len)
                value_bytes := 1
            }
            default {
                // If the total payload of a list is more than 55 bytes long
                let len_bytes := get_uint_bytes(payload_len)
                value_bytes := add(len_bytes, 1)
                value := add(0xf7, len_bytes)
                value := shl(mul(len_bytes, 8), value)
                value := or(value, payload_len)
            }
            value := or(value, shl(mul(8, value_bytes), transactionType))
            value_bytes := add(value_bytes, 1)
            let value_bits := mul(8, value_bytes)
            value := or(shl(sub(256, value_bits), value), shr(value_bits, mload(start_ptr)))
            start_ptr := sub(start_ptr, value_bytes)
            mstore(start_ptr, value)
            hash := keccak256(start_ptr, sub(ptr, start_ptr))
        }
        return hash;
    }

    /*****************************
     * Public Mutating Functions *
     *****************************/

    /// @inheritdoc IL1MessageQueueV2
    function appendCrossDomainMessage(
        address _target,
        uint256 _gasLimit,
        bytes calldata _data
    ) external {
        if (_msgSender() != messenger) revert ErrorCallerIsNotMessenger();

        // validate gas limit
        _validateGasLimit(_gasLimit, _data);

        // do address alias to avoid replay attack in L2.
        _queueTransaction(AddressAliasHelper.applyL1ToL2Alias(_msgSender()), _target, 0, _gasLimit, _data);
    }

    /// @inheritdoc IL1MessageQueueV2
    function appendEnforcedTransaction(
        address _sender,
        address _target,
        uint256 _value,
        uint256 _gasLimit,
        bytes calldata _data
    ) external {
        if (_msgSender() != enforcedTxGateway) revert ErrorCallerIsNotEnforcedTxGateway();

        // validate gas limit
        _validateGasLimit(_gasLimit, _data);
        _queueTransaction(_sender, _target, _value, _gasLimit, _data);
    }

    /// @inheritdoc IL1MessageQueueV2
    function finalizePoppedCrossDomainMessage(uint256 _newFinalizedQueueIndexPlusOne) external onlyScrollChain {
        if (_msgSender() != enforcedTxGateway) revert ErrorCallerIsNotScrollChain();

        uint256 cachedFinalizedQueueIndexPlusOne = nextUnfinalizedQueueIndex;
        if (_newFinalizedQueueIndexPlusOne == cachedFinalizedQueueIndexPlusOne) return;
        if (_newFinalizedQueueIndexPlusOne < cachedFinalizedQueueIndexPlusOne) revert ErrorFinalizedIndexTooSmall();
        if (_newFinalizedQueueIndexPlusOne > nextCrossDomainMessageIndex) revert ErrorFinalizedIndexTooLarge();

        nextUnfinalizedQueueIndex = _newFinalizedQueueIndexPlusOne;
        unchecked {
            // emit FinalizedDequeuedTransaction(_newFinalizedQueueIndexPlusOne - 1);
        }
    }

    /**********************
     * Internal Functions *
     **********************/

    /// @dev Internal function to queue a L1 transaction.
    /// @param _sender The address of sender who will initiate this transaction in L2.
    /// @param _target The address of target contract to call in L2.
    /// @param _value The value passed
    /// @param _gasLimit The maximum gas should be used for this transaction in L2.
    /// @param _data The calldata passed to target contract.
    function _queueTransaction(
        address _sender,
        address _target,
        uint256 _value,
        uint256 _gasLimit,
        bytes calldata _data
    ) internal {
        // compute transaction hash
        uint256 _queueIndex = nextCrossDomainMessageIndex;
        bytes32 _hash = computeTransactionHash(_sender, _queueIndex, _value, _target, _gasLimit, _data);
        unchecked {
            (bytes32 _rollingHash, ) = _loadAndDecodeRollingHash(_queueIndex - 1);
            _rollingHash = _efficientHash(_rollingHash, _hash);
            messageRollingHashes[_queueIndex] = _encodeRollingHash(_rollingHash, block.timestamp);
            nextCrossDomainMessageIndex = _queueIndex + 1;
        }

        // emit event
        // emit QueueTransaction(_sender, _target, _value, uint64(_queueIndex), _gasLimit, _data);
    }

    /// @dev Internal function to validate given gas limit.
    /// @param _gasLimit The value of given gas limit.
    /// @param _calldata The calldata for this message.
    function _validateGasLimit(uint256 _gasLimit, bytes calldata _calldata) internal view {
        (uint256 maxGasLimit, , ) = SystemConfig(systemConfig).messageQueueParameters();
        if (_gasLimit > maxGasLimit) revert ErrorGasLimitExceeded();
        // check if the gas limit is above intrinsic gas
        uint256 intrinsicGas = calculateIntrinsicGasFee(_calldata);
        if (_gasLimit < intrinsicGas) revert ErrorGasLimitBelowIntrinsicGas();
    }

    /// @dev Internal function to load rolling hash from storage.
    /// @param index The index of message to query.
    /// @return hash The rolling hash at the given index.
    /// @return enqueueTimestamp The enqueue timestamp of the message at the given index.
    function _loadAndDecodeRollingHash(uint256 index) internal view returns (bytes32 hash, uint256 enqueueTimestamp) {
        hash = messageRollingHashes[index];
        assembly {
            enqueueTimestamp := and(hash, 0xffffffff)
            hash := shl(32, shr(32, hash))
        }
    }

    /// @dev Internal function to encode rolling hash with enqueue timestamp.
    /// @param hash The rolling hash.
    /// @param enqueueTimestamp The enqueue timestamp.
    /// @return The encoded rolling hash for storage.
    function _encodeRollingHash(bytes32 hash, uint256 enqueueTimestamp) internal pure returns (bytes32) {
        assembly {
            // clear last 32 bits and then encode timestamp to it.
            hash := or(enqueueTimestamp, shl(32, shr(32, hash)))
        }
        return hash;
    }

    /// @dev Internal function to compute keccak256 of two `bytes32` in gas efficient way.
    function _efficientHash(bytes32 a, bytes32 b) private pure returns (bytes32 value) {
        // solhint-disable-next-line no-inline-assembly
        assembly {
            mstore(0x00, a)
            mstore(0x20, b)
            value := keccak256(0x00, 0x40)
        }
    }
}
