// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

// solhint-disable no-inline-assembly

/// @dev Below is the encoding for `BatchHeaderValidium` V0, total 105 + dynamic bytes.
/// ```text
///   * Field                   Bytes       Type        Index   Comments
///   * version                 1           uint8       0       The batch version.
///   * batchIndex              8           uint64      1       The index of the batch.
///   * parentBatchHash         32          bytes32     9       The parent batch hash.
///   * postStateRoot           32          bytes32     41      The state root after this batch.
///   * withdrawRoot            32          bytes32     73      The withdraw root after this batch.
///   * commitment              dynamic     bytes       105     A dynamic data commitment.
/// ```
library BatchHeaderValidiumV0Codec {
    /// @dev Thrown when the length of batch header is smaller than 105
    error ErrorBatchHeaderV0LengthTooSmall();

    /// @dev The length of fixed parts of the batch header.
    uint256 internal constant BATCH_HEADER_FIXED_LENGTH = 105;

    /// @notice Load batch header in calldata to memory.
    /// @param _batchHeader The encoded batch header bytes in calldata.
    /// @return batchPtr The start memory offset of the batch header in memory.
    /// @return length The length in bytes of the batch header.
    function loadAndValidate(bytes calldata _batchHeader) internal pure returns (uint256 batchPtr, uint256 length) {
        length = _batchHeader.length;
        if (length < BATCH_HEADER_FIXED_LENGTH) revert ErrorBatchHeaderV0LengthTooSmall();

        // copy batch header to memory.
        assembly {
            batchPtr := mload(0x40)
            calldatacopy(batchPtr, _batchHeader.offset, length)
            mstore(0x40, add(batchPtr, length))
        }
    }

    /// @notice Get the version of the batch header.
    /// @param batchPtr The start memory offset of the batch header in memory.
    /// @return _version The version of the batch header.
    function getVersion(uint256 batchPtr) internal pure returns (uint256 _version) {
        assembly {
            _version := shr(248, mload(batchPtr))
        }
    }

    /// @notice Get the batch index of the batch.
    /// @param batchPtr The start memory offset of the batch header in memory.
    /// @return _batchIndex The batch index of the batch.
    function getBatchIndex(uint256 batchPtr) internal pure returns (uint256 _batchIndex) {
        assembly {
            _batchIndex := shr(192, mload(add(batchPtr, 1)))
        }
    }

    /// @notice Get the parent batch hash of the batch.
    /// @param batchPtr The start memory offset of the batch header in memory.
    /// @return _parentBatchHash The parent batch hash.
    function getParentBatchHash(uint256 batchPtr) internal pure returns (bytes32 _parentBatchHash) {
        assembly {
            _parentBatchHash := mload(add(batchPtr, 9))
        }
    }

    /// @notice Get the batch index of the batch.
    /// @param batchPtr The start memory offset of the batch header in memory.
    /// @return _postStateRoot The state root after of the batch.
    function getPostStateRoot(uint256 batchPtr) internal pure returns (bytes32 _postStateRoot) {
        assembly {
            _postStateRoot := mload(add(batchPtr, 41))
        }
    }

    /// @notice Get the withdraw root of the batch.
    /// @param batchPtr The start memory offset of the batch header in memory.
    /// @return _withdrawRoot The withdraw root of the batch.
    function getWithdrawRoot(uint256 batchPtr) internal pure returns (bytes32 _withdrawRoot) {
        assembly {
            _withdrawRoot := mload(add(batchPtr, 73))
        }
    }

    /// @notice Encode necessary fields to batch header bytes.
    ///
    /// @param version The batch version
    /// @param batchIndex The index of the batch
    /// @param parentBatchHash The parent batch hash
    /// @param postStateRoot The state root after this batch.
    /// @param withdrawRoot The withdraw root after this batch.
    /// @param commitment A dynamic data commitment.
    function encode(
        uint8 version,
        uint64 batchIndex,
        bytes32 parentBatchHash,
        bytes32 postStateRoot,
        bytes32 withdrawRoot,
        bytes memory commitment
    ) internal pure returns (bytes memory) {
        return abi.encodePacked(version, batchIndex, parentBatchHash, postStateRoot, withdrawRoot, commitment);
    }

    /// @notice Compute the batch hash.
    /// @dev Caller should make sure that the encoded batch header is correct.
    ///
    /// @param header The bytes of batch header in memory.
    /// @return batchHash The hash of the corresponding batch.
    function computeBatchHash(bytes memory header) internal pure returns (bytes32 batchHash) {
        uint256 dataPtr;
        uint256 length;
        // in the current version, the hash is: keccak(BatchHeader without timestamp)
        assembly {
            dataPtr := header
            length := mload(dataPtr)
        }
        batchHash = computeBatchHash(dataPtr + 32, length);
    }

    /// @notice Compute the batch hash.
    /// @dev Caller should make sure that the encoded batch header is correct.
    ///
    /// @param batchPtr The start memory offset of the batch header in memory.
    /// @param length The length of the batch.
    /// @return batchHash The hash of the corresponding batch.
    function computeBatchHash(uint256 batchPtr, uint256 length) internal pure returns (bytes32 batchHash) {
        // in the current version, the hash is: keccak(BatchHeader without timestamp)
        assembly {
            batchHash := keccak256(batchPtr, length)
        }
    }
}
