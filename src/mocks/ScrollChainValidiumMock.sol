// SPDX-License-Identifier: MIT

pragma solidity =0.8.24;

import {IL1MessageQueueV2} from "../L1/rollup/IL1MessageQueueV2.sol";

import {ScrollChainValidium} from "../validium/ScrollChainValidium.sol";

contract ScrollChainValidiumMock is ScrollChainValidium {
    constructor(
        uint64 _chainId,
        address _messageQueueV2,
        address _verifier
    ) ScrollChainValidium(_chainId, _messageQueueV2, _verifier) {}

    /// @dev Internal function to finalize a bundle.
    /// @param batchHeader The header of the last batch in this bundle.
    /// @param totalL1MessagesPoppedOverall The number of messages processed after this bundle.
    function _finalizeBundle(
        bytes calldata batchHeader,
        uint256 totalL1MessagesPoppedOverall,
        bytes calldata
    ) internal virtual override {
        // actions before verification
        (, bytes32 batchHash, uint256 batchIndex, ) = _beforeFinalizeBatch(batchHeader);

        bytes32 postStateRoot = stateRoots[batchIndex];
        bytes32 withdrawRoot = withdrawRoots[batchIndex];

        // actions after verification
        _afterFinalizeBatch(batchIndex, batchHash, totalL1MessagesPoppedOverall, postStateRoot, withdrawRoot);
    }
}
