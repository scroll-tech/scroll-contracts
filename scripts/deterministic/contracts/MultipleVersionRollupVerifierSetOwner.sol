// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.24;

import {MultipleVersionRollupVerifier} from "../../../src/L1/rollup/MultipleVersionRollupVerifier.sol";

contract MultipleVersionRollupVerifierSetOwner is MultipleVersionRollupVerifier {
    /// @dev allow setting the owner in the constructor, otherwise
    ///      DeterministicDeploymentProxy would become the owner.
    constructor(
        address owner,
        uint256[] memory _versions,
        address[] memory _verifiers
    ) MultipleVersionRollupVerifier(_versions, _verifiers) {
        _transferOwnership(owner);
    }
}
