// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

/// @title IRollupVerifier
/// @notice The interface for rollup verifier.
interface IRollupVerifier {
    /// @notice Compute the verifier should be used for specific batch.
    /// @param _version The version of verifier to query.
    /// @param _batchIndex The batch index to query.
    /// @return The address of verifier.
    function getVerifier(uint256 _version, uint256 _batchIndex) external view returns (address);

    /// @notice Verify aggregate zk proof.
    /// @param batchIndex The batch index to verify.
    /// @param aggrProof The aggregated proof.
    /// @param publicInputHash The public input hash.
    function verifyAggregateProof(
        uint256 batchIndex,
        bytes calldata aggrProof,
        bytes32 publicInputHash
    ) external view;

    /// @notice Verify aggregate zk proof.
    /// @param version The version of verifier to use.
    /// @param batchIndex The batch index to verify.
    /// @param aggrProof The aggregated proof.
    /// @param publicInputHash The public input hash.
    function verifyAggregateProof(
        uint256 version,
        uint256 batchIndex,
        bytes calldata aggrProof,
        bytes32 publicInputHash
    ) external view;

    /// @notice Verify bundle zk proof.
    /// @param version The version of verifier to use.
    /// @param batchIndex The batch index used to select verifier.
    /// @param bundleProof The aggregated proof.
    /// @param publicInput The public input.
    function verifyBundleProof(
        uint256 version,
        uint256 batchIndex,
        bytes calldata bundleProof,
        bytes calldata publicInput
    ) external view;
}
