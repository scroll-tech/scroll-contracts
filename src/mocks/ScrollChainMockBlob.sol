// SPDX-License-Identifier: MIT

pragma solidity =0.8.24;

import {BatchHeaderV0Codec} from "../libraries/codec/BatchHeaderV0Codec.sol";
import {BatchHeaderV1Codec} from "../libraries/codec/BatchHeaderV1Codec.sol";
import {BatchHeaderV3Codec} from "../libraries/codec/BatchHeaderV3Codec.sol";
import {ScrollChain} from "../L1/rollup/ScrollChain.sol";

contract ScrollChainMockBlob is ScrollChain {
    bytes32 blobVersionedHash;
    bool overrideBatchHashCheck;

    /***************
     * Constructor *
     ***************/

    /// @notice Constructor for `ScrollChain` implementation contract.
    ///
    /// @param _chainId The chain id of L2.
    /// @param _messageQueue The address of `L1MessageQueue` contract.
    /// @param _verifier The address of zkevm verifier contract.
    constructor(
        uint64 _chainId,
        address _messageQueue,
        address _verifier
    ) ScrollChain(_chainId, _messageQueue, _verifier) {}

    /**********************
     * Internal Functions *
     **********************/

    function setBlobVersionedHash(bytes32 _blobVersionedHash) external {
        blobVersionedHash = _blobVersionedHash;
    }

    function setLastFinalizedBatchIndex(uint256 index) external {
        lastFinalizedBatchIndex = index;
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
