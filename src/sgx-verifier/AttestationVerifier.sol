// SPDX-License-Identifier: MIT

pragma solidity =0.8.24;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

import {IAttestationVerifier} from "./IAttestationVerifier.sol";
import {IDcapAttestation} from "./IDcapAttestation.sol";

import {BytesUtils} from "./utils/BytesUtils.sol";

/// @dev This contract is modified from https://github.com/automata-network/scroll-prover/blob/demo/contracts/src/core/AttestationVerifier.sol
contract AttestationVerifier is Ownable, IAttestationVerifier {
    using BytesUtils for bytes;
    using EnumerableSet for EnumerableSet.Bytes32Set;

    /**********
     * Errors *
     **********/

    /// @dev Thrown when the given attestation report is invalid.
    error ErrorInvalidReport();

    /// @dev Thrown when the user data from the attestation report mismatch.
    error ErrorReportDataMismatch();

    /// @dev Thrown when the MrSigner from the attestation report is invalid.
    error ErrorInvalidMrSigner();

    /// @dev Thrown when the MrSigner from the attestation report is invalid.
    error ErrorInvalidMrEnclave();

    /***********************
     * Immutable Variables *
     ***********************/

    /// @notice The address of automata's DCAP Attestation contract.
    IDcapAttestation public immutable attestationVerifier;

    /*********************
     * Storage Variables *
     *********************/

    /// @dev The list of trusted enclaves.
    EnumerableSet.Bytes32Set private trustedUserMrEnclave;

    /// @dev The list of trusted signers.
    EnumerableSet.Bytes32Set private trustedUserMrSigner;

    /***************
     * Constructor *
     ***************/

    constructor(address _attestationVerifierAddr) {
        attestationVerifier = IDcapAttestation(_attestationVerifierAddr);
    }

    /*************************
     * Public View Functions *
     *************************/

    /// @inheritdoc IAttestationVerifier
    function isTrustedMrSigner(bytes32 mrSigner) public view returns (bool) {
        return trustedUserMrSigner.contains(mrSigner);
    }

    /// @inheritdoc IAttestationVerifier
    function isTrustedMrEnclave(bytes32 mrEnclave) public view returns (bool) {
        return trustedUserMrEnclave.contains(mrEnclave);
    }

    /// @inheritdoc IAttestationVerifier
    function getTrustedMrSigner() external view returns (bytes32[] memory signers) {
        uint256 length = trustedUserMrSigner.length();
        signers = new bytes32[](length);
        for (uint256 i = 0; i < length; i++) {
            signers[i] = trustedUserMrSigner.at(i);
        }
    }

    /// @inheritdoc IAttestationVerifier
    function getTrustedMrEnclave() external view returns (bytes32[] memory enclaves) {
        uint256 length = trustedUserMrEnclave.length();
        enclaves = new bytes32[](length);
        for (uint256 i = 0; i < length; i++) {
            enclaves[i] = trustedUserMrEnclave.at(i);
        }
    }

    /// @inheritdoc IAttestationVerifier
    function verifyAttestation(bytes calldata _report, bytes32 _userData) external view {
        (bool success, bytes memory output) = attestationVerifier.verifyAndAttestOnChain(_report);
        if (!success) {
            revert ErrorInvalidReport();
        }

        (bytes32 reportUserData, bytes32 mrEnclave, bytes32 mrSigner) = extractEnclaveReport(output);
        if (reportUserData != _userData) {
            revert ErrorReportDataMismatch();
        }
        // check local enclave report
        if (!isTrustedMrEnclave(mrEnclave)) {
            revert ErrorInvalidMrEnclave();
        }
        if (!isTrustedMrSigner(mrSigner)) {
            revert ErrorInvalidMrSigner();
        }
    }

    /************************
     * Restricted Functions *
     ************************/

    /// @notice Update the status of a signer.
    /// @param _mrSigner The signer to update.
    /// @param _status The new status to update. If it is `true`, the signer is trusted.
    function updateMrSigner(bytes32 _mrSigner, bool _status) external onlyOwner {
        // @note No need to check the previous status, offline owner will make sure this tx is meaningful.
        if (_status) {
            trustedUserMrSigner.add(_mrSigner);
        } else {
            trustedUserMrSigner.remove(_mrSigner);
        }

        emit UpdateMrSigner(_mrSigner, _status);
    }

    /// @notice Update the status of an enclave.
    /// @param _mrEnclave The enclave to update.
    /// @param _status The new status to update. If it is `true`, the enclave is trusted.
    function updateMrEnclave(bytes32 _mrEnclave, bool _status) external onlyOwner {
        // @note No need to check the previous status, offline owner will make sure this tx is meaningful.
        if (_status) {
            trustedUserMrEnclave.add(_mrEnclave);
        } else {
            trustedUserMrEnclave.remove(_mrEnclave);
        }

        emit UpdateMrEnclave(_mrEnclave, _status);
    }

    /**********************
     * Internal Functions *
     **********************/

    /// @dev Internal function to extract `reportUserData`, `mrEnclave` and `mrSigner` from report.
    function extractEnclaveReport(bytes memory rawEnclaveReport)
        internal
        pure
        returns (
            bytes32 reportUserData,
            bytes32 mrEnclave,
            bytes32 mrSigner
        )
    {
        // @note the actual length is 384, but we have extra 13 bytes at the beginning.
        if (rawEnclaveReport.length != 397) {
            revert ErrorInvalidReport();
        }

        // @dev Below codes can be further optimized with assembly codes, but not necessary.
        // @note The actual offsets are `64`, `128` and `320`, but we have extra 13 bytes at the beginning.
        // The offsets used here become `77`, `141` and `333`.
        mrEnclave = bytes32(rawEnclaveReport.substring(77, 32));
        mrSigner = bytes32(rawEnclaveReport.substring(141, 32));
        reportUserData = rawEnclaveReport.substring(333, 64).readBytes32(32);
    }

    /* for reference
    struct EnclaveReport {
        bytes16 cpuSvn;
        bytes4 miscSelect;
        bytes28 reserved1;
        bytes16 attributes;
        bytes32 mrEnclave;
        bytes32 reserved2;
        bytes32 mrSigner;
        bytes reserved3; // 96 bytes
        uint16 isvProdId;
        uint16 isvSvn;
        bytes reserved4; // 60 bytes
        bytes reportData; // 64 bytes - For QEReports, this contains the hash of the concatenation of attestation key and QEAuthData
    }

    function parseEnclaveReport(
        bytes memory rawEnclaveReport
    ) internal pure returns (EnclaveReport memory enclaveReport) {
        if (rawEnclaveReport.length != 384) {
            revert ErrorInvalidReport();
        }

        enclaveReport.cpuSvn = bytes16(rawEnclaveReport.substring(0, 16));
        enclaveReport.miscSelect = bytes4(rawEnclaveReport.substring(16, 4));
        enclaveReport.reserved1 = bytes28(rawEnclaveReport.substring(20, 28));
        enclaveReport.attributes = bytes16(rawEnclaveReport.substring(48, 16));
        enclaveReport.mrEnclave = bytes32(rawEnclaveReport.substring(64, 32));
        enclaveReport.reserved2 = bytes32(rawEnclaveReport.substring(96, 32));
        enclaveReport.mrSigner = bytes32(rawEnclaveReport.substring(128, 32));
        enclaveReport.reserved3 = rawEnclaveReport.substring(160, 96);
        enclaveReport.isvProdId = uint16(BELE.leBytesToBeUint(rawEnclaveReport.substring(256, 2)));
        enclaveReport.isvSvn = uint16(BELE.leBytesToBeUint(rawEnclaveReport.substring(258, 2)));
        enclaveReport.reserved4 = rawEnclaveReport.substring(260, 60);
        enclaveReport.reportData = rawEnclaveReport.substring(320, 64);
    }
    */
}
