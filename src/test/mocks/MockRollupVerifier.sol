// SPDX-License-Identifier: MIT

pragma solidity =0.8.24;

import {IRollupVerifier} from "../../libraries/verifier/IRollupVerifier.sol";

contract MockRollupVerifier is IRollupVerifier {
    /// @inheritdoc IRollupVerifier
    function getVerifier(uint256 _version, uint256 _batchIndex) external view returns (address) {
        return address(this);
    }

    /// @inheritdoc IRollupVerifier
    function verifyAggregateProof(
        uint256,
        bytes calldata,
        bytes32
    ) external view {}

    /// @inheritdoc IRollupVerifier
    function verifyAggregateProof(
        uint256,
        uint256,
        bytes calldata,
        bytes32
    ) external view {}

    /// @inheritdoc IRollupVerifier
    function verifyBundleProof(
        uint256,
        uint256,
        bytes calldata,
        bytes calldata
    ) external view {}

    function randomSelectNextProver() external returns (address) {}
}
