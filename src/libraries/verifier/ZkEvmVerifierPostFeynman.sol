// SPDX-License-Identifier: MIT

pragma solidity =0.8.24;

import {IZkEvmVerifierV2} from "./IZkEvmVerifier.sol";
import {IOpenVmHalo2Verifier} from "./IOpenVmHalo2Verifier.sol";

// solhint-disable no-empty-blocks

contract ZkEvmVerifierPostFeynman is IZkEvmVerifierV2 {
    /**********
     * Errors *
     **********/

    /// @dev Thrown when bundle recursion zk proof verification is failed.
    error VerificationFailed();

    /// @dev Thrown when a verifier digest is not an element of the BN254 scalar field.
    error InvalidVerifierDigest();

    /// @dev Thrown when the plonk verifier address has no code.
    error InvalidPlonkVerifier();

    /*************
     * Constants *
     *************/

    /// @dev The BN254 scalar field modulus. The wrapper rejects commitments at or above it.
    uint256 private constant BN254_SCALAR_MODULUS = 0x30644e72e131a029b85045b68181585d2833e84879b9709143e1f593f0000001;

    /// @notice The address of highly optimized plonk verifier contract.
    address public immutable plonkVerifier;

    /// @notice A predetermined digest for the `plonkVerifier`.
    bytes32 public immutable verifierDigest1;

    /// @notice A predetermined digest for the `plonkVerifier`.
    bytes32 public immutable verifierDigest2;

    /// @notice The version of the protocol.
    /// @dev The protocol version for Validium@v1 onwards encodes `domain` and `version` such that
    /// @dev protocolVersion = (domain << 6) + version.
    uint256 public immutable protocolVersion;

    /***************
     * Constructor *
     ***************/

    constructor(
        address _verifier,
        bytes32 _verifierDigest1,
        bytes32 _verifierDigest2,
        uint256 _protocolVersion
    ) {
        if (_verifier.code.length == 0) revert InvalidPlonkVerifier();
        if (uint256(_verifierDigest1) >= BN254_SCALAR_MODULUS) revert InvalidVerifierDigest();
        if (uint256(_verifierDigest2) >= BN254_SCALAR_MODULUS) revert InvalidVerifierDigest();

        plonkVerifier = _verifier;
        verifierDigest1 = _verifierDigest1;
        verifierDigest2 = _verifierDigest2;
        protocolVersion = _protocolVersion;
    }

    /*************************
     * Public View Functions *
     *************************/

    /// @inheritdoc IZkEvmVerifierV2
    ///
    /// @dev Encoding for `publicInput`. And this is exactly the same as `ZkEvmVerifierV2`.
    /// ```text
    /// | layer2ChainId | msgQueueHash | numBatches | prevStateRoot | prevBatchHash | postStateRoot | batchHash | withdrawRoot | validium ? encryptionKey |
    /// |    8 bytes    |   32  bytes  |  4  bytes  |   32  bytes   |   32  bytes   |   32  bytes   | 32  bytes |   32 bytes   |       33 bytes           |
    /// ```
    function verify(bytes calldata bundleProof, bytes calldata publicInput) external view override {
        bytes32 publicInputHash = keccak256(abi.encodePacked(protocolVersion, publicInput));

        // Use the wrapper's typed entry point, never a raw call: the wrapper has a function
        // dispatcher, so raw calldata led by `bundleProof` could select `verify` itself with
        // attacker-chosen public values. The wrapper lays out the same payload for its
        // Halo2 fallback that this contract used to build by hand.
        try
            IOpenVmHalo2Verifier(plonkVerifier).verify(
                abi.encodePacked(publicInputHash),
                bundleProof,
                verifierDigest1,
                verifierDigest2
            )
        {} catch {
            revert VerificationFailed();
        }
    }
}
