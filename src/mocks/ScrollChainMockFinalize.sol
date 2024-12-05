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
