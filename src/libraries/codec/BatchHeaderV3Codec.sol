// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

// solhint-disable no-inline-assembly

/// @dev Below is the encoding for `BatchHeader` V3, total 193 bytes.
/// ```text
///   * Field                   Bytes       Type        Index   Comments
///   * version                 1           uint8       0       The batch version
///   * batchIndex              8           uint64      1       The index of the batch
///   * l1MessagePopped         8           uint64      9       Number of L1 messages popped in the batch
///   * totalL1MessagePopped    8           uint64      17      Number of total L1 messages popped after the batch
///   * dataHash                32          bytes32     25      The data hash of the batch
///   * blobVersionedHash       32          bytes32     57      The versioned hash of the blob with this batch’s data
///   * parentBatchHash         32          bytes32     89      The parent batch hash
///   * lastBlockTimestamp      8           uint64      121     A bitmap to indicate which L1 messages are skipped in the batch
///   * blobDataProof           64          bytes64     129     The blob data proof: z (32), y (32)
/// ```
/// The codes for `version`, `batchIndex`, `l1MessagePopped`, `totalL1MessagePopped`, `dataHash` and `computeBatchHash`
/// are the same as `BatchHeaderV0Codec`. The codes for `blobVersionedHash` and `parentBatchHash` are the same as
/// `BatchHeaderV1Codec`. However, we won't reuse the codes since they are very simple. Reusing the codes will introduce
/// extra code jump in solidity, which increase gas costs.
library BatchHeaderV3Codec {
    /// @dev Thrown when the length of batch header is not equal to 193.
    error ErrorBatchHeaderV3LengthMismatch();

    /// @dev The length of fixed parts of the batch header.
    uint256 internal constant BATCH_HEADER_FIXED_LENGTH = 193;

    /// @notice Allocate memory for batch header.
    function allocate() internal pure returns (uint256 batchPtr) {
        assembly {
            batchPtr := mload(0x40)
            // This is `BatchHeaderV3Codec.BATCH_HEADER_FIXED_LENGTH`, use `193` here to reduce code complexity.
            mstore(0x40, add(batchPtr, 193))
        }
    }

    /// @notice Load batch header in calldata to memory.
    /// @param _batchHeader The encoded batch header bytes in calldata.
    /// @return batchPtr The start memory offset of the batch header in memory.
    /// @return length The length in bytes of the batch header.
    function loadAndValidate(bytes calldata _batchHeader) internal pure returns (uint256 batchPtr, uint256 length) {
        length = _batchHeader.length;
        if (length != BATCH_HEADER_FIXED_LENGTH) {
            revert ErrorBatchHeaderV3LengthMismatch();
        }

        // copy batch header to memory.
        batchPtr = allocate();
        assembly {
            calldatacopy(batchPtr, _batchHeader.offset, length)
        }
    }

    /// @notice Store the last block timestamp of batch header.
    /// @param batchPtr The start memory offset of the batch header in memory.
    /// @param _lastBlockTimestamp The timestamp of the last block in this batch.
    function storeLastBlockTimestamp(uint256 batchPtr, uint256 _lastBlockTimestamp) internal pure {
        assembly {
            mstore(add(batchPtr, 121), shl(192, _lastBlockTimestamp))
        }
    }

    /// @notice Store the last block timestamp of batch header.
    /// @param batchPtr The start memory offset of the batch header in memory.
    /// @param blobDataProof The blob data proof: z (32), y (32)
    function storeBlobDataProof(uint256 batchPtr, bytes calldata blobDataProof) internal pure {
        assembly {
            // z and y is in the first 64 bytes of `blobDataProof`
            calldatacopy(add(batchPtr, 129), blobDataProof.offset, 64)
        }
    }
}
