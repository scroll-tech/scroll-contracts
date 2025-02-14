// SPDX-License-Identifier: MIT

pragma solidity =0.8.24;

import {ScrollChain} from "../L1/rollup/ScrollChain.sol";

contract ScrollChainMockBlob is ScrollChain {
    bytes32 blobVersionedHash;
    bool overrideBatchHashCheck;

    /***************
     * Constructor *
     ***************/

    constructor(
        uint64 _chainId,
        address _messageQueueV1,
        address _messageQueueV2,
        address _verifier
    ) ScrollChain(_chainId, _messageQueueV1, _messageQueueV2, _verifier, address(0)) {}

    /**********************
     * Internal Functions *
     **********************/

    function setBlobVersionedHash(bytes32 _blobVersionedHash) external {
        blobVersionedHash = _blobVersionedHash;
    }

    function setLastFinalizedBatchIndex(uint256 index) external {
        miscData.lastFinalizedBatchIndex = uint64(index);
    }

    function setFinalizedStateRoots(uint256 index, bytes32 value) external {
        finalizedStateRoots[index] = value;
    }

    function setCommittedBatches(uint256 index, bytes32 value) external {
        committedBatches[index] = value;
    }

    function setOverrideBatchHashCheck(bool status) external {
        overrideBatchHashCheck = status;
    }

    function _getBlobVersionedHash() internal virtual override returns (bytes32 _blobVersionedHash) {
        _blobVersionedHash = blobVersionedHash;
    }

    /// @dev Internal function to load batch header from calldata to memory.
    /// @param _batchHeader The batch header in calldata.
    /// @return batchPtr The start memory offset of loaded batch header.
    /// @return _batchHash The hash of the loaded batch header.
    /// @return _batchIndex The index of this batch.
    /// @param _totalL1MessagesPoppedOverall The number of L1 messages popped after this batch.
    function _loadBatchHeader(bytes calldata _batchHeader)
        internal
        view
        virtual
        override
        returns (
            uint256 batchPtr,
            bytes32 _batchHash,
            uint256 _batchIndex,
            uint256 _totalL1MessagesPoppedOverall
        )
    {
        (batchPtr, _batchHash, _batchIndex, _totalL1MessagesPoppedOverall) = ScrollChain._loadBatchHeader(_batchHeader);

        if (overrideBatchHashCheck) {
            _batchHash = committedBatches[_batchIndex];
        }
    }
}
