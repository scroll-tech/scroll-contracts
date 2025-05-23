// SPDX-License-Identifier: MIT

pragma solidity =0.8.24;

import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

contract L2SystemContract is OwnableUpgradeable {
    /*************
     * Constants *
     *************/

    uint256 private constant PRECISION = 1e18;

    /*********************
     * Storage Variables *
     *********************/

    /// @notice The base fee overhead. This is part of the L2 base fee calculation.
    uint256 public baseFeeOverhead;

    /// @notice The base fee scalar. This is part of the L2 base fee calculation.
    uint256 public baseFeeScalar;

    /***************
     * Constructor *
     ***************/

    constructor() {
        _disableInitializers();
    }

    function initialize(address _owner) external initializer {
        __Ownable_init();
        transferOwnership(_owner);
    }

    /*************************
     * Public View Functions *
     *************************/

    /// @notice Calculates the L2 base fee based on the L1 base fee.
    /// @param l1BaseFee The L1 base fee.
    /// @return l2BaseFee The L2 base fee.
    function getL2BaseFee(uint256 l1BaseFee) public view returns (uint256 l2BaseFee) {
        l2BaseFee = (l1BaseFee * baseFeeScalar) / PRECISION + baseFeeOverhead;
    }

    /************************
     * Restricted Functions *
     ************************/

    /// @notice Updates the base fee overhead.
    /// @param _baseFeeOverhead The new base fee overhead.
    function updateBaseFeeOverhead(uint256 _baseFeeOverhead) external onlyOwner {
        baseFeeOverhead = _baseFeeOverhead;
    }

    /// @notice Updates the base fee scalar.
    /// @param _baseFeeScalar The new base fee scalar.
    function updateBaseFeeScalar(uint256 _baseFeeScalar) external onlyOwner {
        baseFeeScalar = _baseFeeScalar;
    }
}
