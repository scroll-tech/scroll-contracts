// SPDX-License-Identifier: MIT

pragma solidity =0.8.24;

import {ScrollChain} from "../L1/rollup/ScrollChain.sol";

contract ScrollChainMockFinalize is ScrollChain {
    /***************
     * Constructor *
     ***************/

    constructor(
        uint64 _chainId,
        address _messageQueueV1,
        address _messageQueueV2,
        address _verifier,
        address _system
    ) ScrollChain(_chainId, _messageQueueV1, _messageQueueV2, _verifier, _system) {}

    /*****************************
     * Public Mutating Functions *
     *****************************/

    /// @notice Finalize bundle without proof, See the comments of {ScrollChain-finalizeBundleWithProof}.
    function finalizeBundle(
        bytes calldata batchHeader,
        bytes32 postStateRoot,
        bytes32 withdrawRoot
    ) external OnlyProver whenNotPaused {
        // actions before verification
        (, bytes32 batchHash, uint256 batchIndex, uint256 totalL1MessagesPoppedOverall, ) = _beforeFinalizeBatch(
            batchHeader,
            postStateRoot
        );

        // actions after verification
        _afterFinalizeBatch(batchIndex, batchHash, totalL1MessagesPoppedOverall, postStateRoot, withdrawRoot, true);
    }

    function finalizeBundlePostEuclidV2NoProof(
        bytes calldata batchHeader,
        uint256 totalL1MessagesPoppedOverall,
        bytes32 postStateRoot,
        bytes32 withdrawRoot,
        bytes32 prevBlockHash,
        bytes32 postBlockHash,
        uint64,
        uint64
    ) external {
        // actions before verification
        (, bytes32 batchHash, uint256 batchIndex, , uint256 prevBatchIndex) = _beforeFinalizeBatch(
            batchHeader,
            postStateRoot
        );

        // anchor the first block's parent hash to the previously finalized L2 block hash
        if (prevBatchIndex == 0) {
            if (prevBlockHash != bytes32(0)) revert ErrorIncorrectPrevBlockHash();
        } else {
            if (prevBlockHash != finalizedL2BlockHashes[prevBatchIndex]) revert ErrorIncorrectPrevBlockHash();
        }

        // actions after verification
        _afterFinalizeBatch(batchIndex, batchHash, totalL1MessagesPoppedOverall, postStateRoot, withdrawRoot, false);

        // store the last L2 block hash of this bundle to anchor the next bundle
        finalizedL2BlockHashes[batchIndex] = postBlockHash;
    }
}
