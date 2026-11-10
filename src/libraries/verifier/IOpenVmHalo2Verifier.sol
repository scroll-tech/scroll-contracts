// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

/// @notice Typed entry point of the OpenVM Halo2 verifier wrapper
/// (`OpenVmHalo2Verifier`, selector `0x24270d54`).
/// @dev The wrapper formats the payload and self-calls its inherited
/// `Halo2Verifier` fallback. Reaching it through this typed function means the
/// call selector is fixed by the compiler, never taken from caller bytes.
interface IOpenVmHalo2Verifier {
    /// @param publicValues The public values revealed by the guest program. For
    /// Scroll this is the 32-byte `publicInputHash`.
    /// @param proofData `abi.encodePacked(kzgAccumulator, proofSuffix)`, i.e. the
    /// bundle proof exactly as `ScrollChain` forwards it.
    /// @param appExeCommit Commitment to the application executable. For Scroll
    /// this is the fixed `verifierDigest1`.
    /// @param appVmCommit Commitment to the VM configuration. For Scroll this is
    /// the fixed `verifierDigest2`.
    function verify(
        bytes calldata publicValues,
        bytes calldata proofData,
        bytes32 appExeCommit,
        bytes32 appVmCommit
    ) external view;
}
