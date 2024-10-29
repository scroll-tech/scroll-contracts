// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

interface IAttestationVerifier {
    /**********
     * Events *
     **********/

    event UpdateMrSigner(bytes32 indexed mrSigner, bool status);

    event UpdateMrEnclave(bytes32 indexed mrEnclave, bool status);

    /*************************
     * Public View Functions *
     *************************/

    function isTrustedMrSigner(bytes32 mrSigner) external view returns (bool);

    function isTrustedMrEnclave(bytes32 mrEnclave) external view returns (bool);

    function getTrustedMrSigner() external view returns (bytes32[] memory signers);

    function getTrustedMrEnclave() external view returns (bytes32[] memory enclaves);

    function verifyAttestation(bytes calldata report, bytes32 userData) external view;
}
