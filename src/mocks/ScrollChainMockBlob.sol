// SPDX-License-Identifier: MIT

pragma solidity =0.8.24;

import {ScrollChain} from "../L1/rollup/ScrollChain.sol";

contract ScrollChainMockFinalize is ScrollChain {
    bytes32 blobVersionedHash;

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

    function _getBlobVersionedHash() internal virtual override returns (bytes32 _blobVersionedHash) {
        _blobVersionedHash = blobVersionedHash;
    }
}
