// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import {BatchHeaderV0Codec} from "./BatchHeaderV0Codec.sol";

// solhint-disable no-inline-assembly

/// @dev Below is the encoding for `BatchHeader` V1, total 121 + ceil(l1MessagePopped / 256) * 32 bytes.
/// ```text
///   * Field                   Bytes       Type        Index   Comments
///   * version                 1           uint8       0       The batch version
///   * batchIndex              8           uint64      1       The index of the batch
///   * l1MessagePopped         8           uint64      9       Number of L1 messages popped in the batch
///   * totalL1MessagePopped    8           uint64      17      Number of total L1 messages popped after the batch
///   * dataHash                32          bytes32     25      The data hash of the batch
///   * blobVersionedHash       32          bytes32     57      The versioned hash of the blob with this batch’s data
///   * parentBatchHash         32          bytes32     89      The parent batch hash
///   * skippedL1MessageBitmap  dynamic     uint256[]   121     A bitmap to indicate which L1 messages are skipped in the batch
/// ```
///
/// The codes for `version`, `batchIndex`, `l1MessagePopped`, `totalL1MessagePopped`, `dataHash` and `computeBatchHash`
/// are the same as `BatchHeaderV0Codec`. However, we won't reuse the codes in this library since they are very simple.
/// Reusing the codes will introduce extra code jump in solidity, which increase gas costs.
library BatchHeaderV1Codec {
    /// @dev Thrown when the length of batch header is smaller than 121.
    error ErrorBatchHeaderV1LengthTooSmall();

    /// @dev Thrown when the length of skippedL1MessageBitmap is incorrect.
    error ErrorIncorrectBitmapLengthV1();

    /// @dev The length of fixed parts of the batch header.
    uint256 internal constant BATCH_HEADER_FIXED_LENGTH = 121;

    /// @notice Load batch header in calldata to memory.
    /// @param _batchHeader The encoded batch header bytes in calldata.
    /// @return batchPtr The start memory offset of the batch header in memory.
    /// @return length The length in bytes of the batch header.
    function loadAndValidate(bytes calldata _batchHeader) internal pure returns (uint256 batchPtr, uint256 length) {
        length = _batchHeader.length;
        if (length < BATCH_HEADER_FIXED_LENGTH) revert ErrorBatchHeaderV1LengthTooSmall();

        // copy batch header to memory.
        assembly {
            batchPtr := mload(0x40)
            calldatacopy(batchPtr, _batchHeader.offset, length)
            mstore(0x40, add(batchPtr, length))
        }

        // check batch header length
        uint256 _l1MessagePopped = BatchHeaderV0Codec.getL1MessagePopped(batchPtr);

        unchecked {
            if (length != BATCH_HEADER_FIXED_LENGTH + ((_l1MessagePopped + 255) / 256) * 32)
                revert ErrorIncorrectBitmapLengthV1();
        }
    }

    /// @notice Get the blob versioned hash of the batch header.
    /// @param batchPtr The start memory offset of the batch header in memory.
    /// @return _blobVersionedHash The blob versioned hash of the batch header.
    function getBlobVersionedHash(uint256 batchPtr) internal pure returns (bytes32 _blobVersionedHash) {
        assembly {
            _blobVersionedHash := mload(add(batchPtr, 57))
        }
    }

    /// @notice Get the parent batch hash of the batch header.
    /// @param batchPtr The start memory offset of the batch header in memory.
    /// @return _parentBatchHash The parent batch hash of the batch header.
    function getParentBatchHash(uint256 batchPtr) internal pure returns (bytes32 _parentBatchHash) {
        assembly {
            _parentBatchHash := mload(add(batchPtr, 89))
        }
    }

    /// @notice Get the start memory offset for skipped L1 messages bitmap.
    /// @param batchPtr The start memory offset of the batch header in memory.
    /// @return _bitmapPtr the start memory offset for skipped L1 messages bitmap.
    function getSkippedBitmapPtr(uint256 batchPtr) internal pure returns (uint256 _bitmapPtr) {
        assembly {
            _bitmapPtr := add(batchPtr, BATCH_HEADER_FIXED_LENGTH)
        }
    }

    /// @notice Get the skipped L1 messages bitmap.
    /// @param batchPtr The start memory offset of the batch header in memory.
    /// @param index The index of bitmap to load.
    /// @return _bitmap The bitmap from bits `index * 256` to `index * 256 + 255`.
    function getSkippedBitmap(uint256 batchPtr, uint256 index) internal pure returns (uint256 _bitmap) {
        assembly {
            batchPtr := add(batchPtr, BATCH_HEADER_FIXED_LENGTH)
            _bitmap := mload(add(batchPtr, mul(index, 32)))
        }
    }

    /// @notice Store the parent batch hash of batch header.
    /// @param batchPtr The start memory offset of the batch header in memory.
    /// @param _blobVersionedHash The versioned hash of the blob with this batch’s data.
    function storeBlobVersionedHash(uint256 batchPtr, bytes32 _blobVersionedHash) internal pure {
        assembly {
            mstore(add(batchPtr, 57), _blobVersionedHash)
        }
    }

    /// @notice Store the parent batch hash of batch header.
    /// @param batchPtr The start memory offset of the batch header in memory.
    /// @param _parentBatchHash The parent batch hash.
    function storeParentBatchHash(uint256 batchPtr, bytes32 _parentBatchHash) internal pure {
        assembly {
            mstore(add(batchPtr, 89), _parentBatchHash)
        }
    }

    /// @notice Store the skipped L1 message bitmap of batch header.
    /// @param batchPtr The start memory offset of the batch header in memory.
    /// @param _skippedL1MessageBitmap The skipped L1 message bitmap.
    function storeSkippedBitmap(uint256 batchPtr, bytes calldata _skippedL1MessageBitmap) internal pure {
        assembly {
            calldatacopy(
                add(batchPtr, BATCH_HEADER_FIXED_LENGTH),
                _skippedL1MessageBitmap.offset,
                _skippedL1MessageBitmap.length
            )
        }
    }
}
