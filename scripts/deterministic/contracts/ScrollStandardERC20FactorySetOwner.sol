// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.24;

import {ScrollStandardERC20Factory} from "../../../src/libraries/token/ScrollStandardERC20Factory.sol";

contract ScrollStandardERC20FactorySetOwner is ScrollStandardERC20Factory {
    /// @dev allow setting the owner in the constructor, otherwise
    ///      DeterministicDeploymentProxy would become the owner.
    constructor(address owner, address _implementation) ScrollStandardERC20Factory(_implementation) {
        _transferOwnership(owner);
    }
}
