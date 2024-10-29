// SPDX-License-Identifier: MIT

pragma solidity =0.8.24;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

import {IAttestationVerifier} from "./IAttestationVerifier.sol";
import {IDcapAttestation} from "./IDcapAttestation.sol";

import {BELE} from "./utils/BELE.sol";
import {BytesUtils} from "./utils/BytesUtils.sol";

contract AttestationVerifier is Ownable, IAttestationVerifier {
    using BytesUtils for bytes;
    using EnumerableSet for EnumerableSet.Bytes32Set;

    /**********
     * Errors *
     **********/

    error ErrorInvalidReport();

    error ErrorInvalidReportData();

    error ErrorReportDataMismatch();

    error ErrorInvalidMrSigner();

    error ErrorInvalidMrEnclave();

    /***********************
     * Immutable Variables *
     ***********************/

    IDcapAttestation public immutable attestationVerifier;

    /***********
     * Structs *
     ***********/

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

    /*********************
     * Storage Variables *
     *********************/

    EnumerableSet.Bytes32Set private trustedUserMrEnclave;

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

        EnclaveReport memory report = extractEnclaveReport(output);
        bytes32 reportUserData = report.reportData.readBytes32(32);
        if (reportUserData != _userData) {
            revert ErrorReportDataMismatch();
        }

        // check local enclave report
        if (!isTrustedMrEnclave(report.mrEnclave)) {
            revert ErrorInvalidMrEnclave();
        }
        if (!isTrustedMrSigner(report.mrSigner)) {
            revert ErrorInvalidMrSigner();
        }
    }

    /************************
     * Restricted Functions *
     ************************/

    function updateMrSigner(bytes32 _mrSigner, bool _status) external onlyOwner {
        if (_status) {
            trustedUserMrSigner.add(_mrSigner);
        } else {
            trustedUserMrSigner.remove(_mrSigner);
        }

        emit UpdateMrSigner(_mrSigner, _status);
    }

    function updateMrEnclave(bytes32 _mrEnclave, bool _status) external onlyOwner {
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

    function extractEnclaveReport(bytes memory output) internal pure returns (EnclaveReport memory) {
        uint256 offset = 13;
        uint256 len = output.length - offset;
        return parseEnclaveReport(output.substring(13, len));
    }

    // todo: optimize with assembly
    function parseEnclaveReport(bytes memory rawEnclaveReport)
        internal
        pure
        returns (EnclaveReport memory enclaveReport)
    {
        if (rawEnclaveReport.length != 384) {
            revert ErrorInvalidReportData();
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
}
