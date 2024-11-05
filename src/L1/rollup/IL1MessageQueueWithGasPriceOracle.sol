// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import {IL1MessageQueue} from "./IL1MessageQueue.sol";

interface IL1MessageQueueWithGasPriceOracle is IL1MessageQueue {
    /**********
     * Events *
     **********/

    /// @notice Emitted when current l2 base fee parameters are updated.
    /// @param overhead The value of overhead.
    /// @param scalar The value of scalar to `block.basefee`.
    event UpdateL2BaseFeeParameters(uint256 overhead, uint256 scalar);

    /*************************
     * Public View Functions *
     *************************/

    /// @notice Return the latest known l2 base fee.
    function l2BaseFee() external view returns (uint256);
}
