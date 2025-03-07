// SPDX-License-Identifier: MIT

pragma solidity =0.8.24;

import {ScrollChain} from "../L1/rollup/ScrollChain.sol";

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
        _afterFinalizeBatch(batchIndex, batchHash, totalL1MessagesPoppedOverall, postStateRoot, withdrawRoot);
    }
}
