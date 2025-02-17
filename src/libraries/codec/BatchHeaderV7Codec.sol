// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

// solhint-disable no-inline-assembly

/// @dev Below is the encoding for `BatchHeader` V7, total 73 bytes.
/// ```text
///   * Field                   Bytes       Type        Index   Comments
///   * version                 1           uint8       0       The batch version
///   * batchIndex              8           uint64      1       The index of the batch
///   * blobVersionedHash       32          bytes32     9       The versioned hash of the blob with this batch’s data
///   * parentBatchHash         32          bytes32     41      The parent batch hash
/// ```
/// The codes for `version`, `batchIndex` and `computeBatchHash` are the same as `BatchHeaderV0Codec`.
/// However, we won't reuse the codes since they are very simple. Reusing the codes will introduce
/// extra code jump in solidity, which increase gas costs.
library BatchHeaderV7Codec {
    /// @dev Thrown when the length of batch header is not equal to 73.
    error ErrorBatchHeaderV7LengthMismatch();

    /// @dev The length of fixed parts of the batch header.
    uint256 internal constant BATCH_HEADER_FIXED_LENGTH = 73;

    /// @notice Allocate memory for batch header.
    function allocate() internal pure returns (uint256 batchPtr) {
        assembly {
            batchPtr := mload(0x40)
            // This is `BatchHeaderV7Codec.BATCH_HEADER_FIXED_LENGTH`, use `73` here to reduce code complexity.
            mstore(0x40, add(batchPtr, 73))
        }
    }

    /// @notice Load batch header in calldata to memory.
    /// @param _batchHeader The encoded batch header bytes in calldata.
    /// @return batchPtr The start memory offset of the batch header in memory.
    /// @return length The length in bytes of the batch header.
    function loadAndValidate(bytes calldata _batchHeader) internal pure returns (uint256 batchPtr, uint256 length) {
        length = _batchHeader.length;
        if (length != BATCH_HEADER_FIXED_LENGTH) {
            revert ErrorBatchHeaderV7LengthMismatch();
        }

        // copy batch header to memory.
        batchPtr = allocate();
        assembly {
            calldatacopy(batchPtr, _batchHeader.offset, length)
        }
    }

    /// @notice Get the blob versioned hash of the batch header.
    /// @param batchPtr The start memory offset of the batch header in memory.
    /// @return _blobVersionedHash The blob versioned hash of the batch header.
    function getBlobVersionedHash(uint256 batchPtr) internal pure returns (bytes32 _blobVersionedHash) {
        assembly {
            _blobVersionedHash := mload(add(batchPtr, 9))
        }
    }

    /// @notice Get the parent batch hash of the batch header.
    /// @param batchPtr The start memory offset of the batch header in memory.
    /// @return _parentBatchHash The parent batch hash of the batch header.
    function getParentBatchHash(uint256 batchPtr) internal pure returns (bytes32 _parentBatchHash) {
        assembly {
            _parentBatchHash := mload(add(batchPtr, 41))
        }
    }

    /// @notice Store the blob versioned hash of batch header.
    /// @param batchPtr The start memory offset of the batch header in memory.
    /// @param _blobVersionedHash The versioned hash of the blob with this batch’s data.
    function storeBlobVersionedHash(uint256 batchPtr, bytes32 _blobVersionedHash) internal pure {
        assembly {
            mstore(add(batchPtr, 9), _blobVersionedHash)
        }
    }

    /// @notice Store the parent batch hash of batch header.
    /// @param batchPtr The start memory offset of the batch header in memory.
    /// @param _parentBatchHash The parent batch hash.
    function storeParentBatchHash(uint256 batchPtr, bytes32 _parentBatchHash) internal pure {
        assembly {
            mstore(add(batchPtr, 41), _parentBatchHash)
        }
    }
}
