// SPDX-License-Identifier: MIT

pragma solidity =0.8.24;

import {ScrollChain} from "../L1/rollup/ScrollChain.sol";

import {BatchHeaderV0Codec} from "../libraries/codec/BatchHeaderV0Codec.sol";
import {BatchHeaderV1Codec} from "../libraries/codec/BatchHeaderV1Codec.sol";

contract ScrollChainMockFinalize is ScrollChain {
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

    /*****************************
     * Public Mutating Functions *
     *****************************/

    /// @notice Finalize 4844 batch without proof, See the comments of {ScrollChain-finalizeBatchWithProof4844}.
    function finalizeBatch4844(
        bytes calldata _batchHeader,
        bytes32, /*_prevStateRoot*/
        bytes32 _postStateRoot,
        bytes32 _withdrawRoot,
        bytes calldata _blobDataProof
    ) external OnlyProver whenNotPaused {
        (uint256 batchPtr, bytes32 _batchHash, uint256 _batchIndex) = _beforeFinalizeBatch(
            _batchHeader,
            _postStateRoot
        );

        // verify blob versioned hash
        bytes32 _blobVersionedHash = BatchHeaderV1Codec.getBlobVersionedHash(batchPtr);
        _checkBlobVersionedHash(_blobVersionedHash, _blobDataProof);

        // Pop finalized and non-skipped message from L1MessageQueue.
        uint256 _totalL1MessagesPoppedOverall = BatchHeaderV0Codec.getTotalL1MessagePopped(batchPtr);
        _popL1MessagesMemory(
            BatchHeaderV1Codec.getSkippedBitmapPtr(batchPtr),
            _totalL1MessagesPoppedOverall,
            BatchHeaderV0Codec.getL1MessagePopped(batchPtr)
        );

        _afterFinalizeBatch(_totalL1MessagesPoppedOverall, _batchIndex, _batchHash, _postStateRoot, _withdrawRoot);
    }

    /// @notice Finalize bundle without proof, See the comments of {ScrollChain-finalizeBundleWithProof}.
    function finalizeBundle(
        bytes calldata _batchHeader,
        bytes32 _postStateRoot,
        bytes32 _withdrawRoot
    ) external OnlyProver whenNotPaused {
        if (_postStateRoot == bytes32(0)) revert ErrorStateRootIsZero();

        // compute pending batch hash and verify
        (, bytes32 _batchHash, uint256 _batchIndex, uint256 _totalL1MessagesPoppedOverall) = _loadBatchHeader(
            _batchHeader
        );
        if (_batchIndex <= lastFinalizedBatchIndex) revert ErrorBatchIsAlreadyVerified();

        // store in state
        // @note we do not store intermediate finalized roots
        lastFinalizedBatchIndex = _batchIndex;
        finalizedStateRoots[_batchIndex] = _postStateRoot;
        withdrawRoots[_batchIndex] = _withdrawRoot;

        // Pop finalized and non-skipped message from L1MessageQueue.
        _finalizePoppedL1Messages(_totalL1MessagesPoppedOverall);

        emit FinalizeBatch(_batchIndex, _batchHash, _postStateRoot, _withdrawRoot);
    }
}
