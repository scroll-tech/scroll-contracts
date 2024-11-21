// SPDX-License-Identifier: MIT

pragma solidity =0.8.24;

import {DSTestPlus} from "solmate/test/utils/DSTestPlus.sol";

import {AttestationVerifier} from "../../sgx-verifier/AttestationVerifier.sol";
import {ISGXVerifier} from "../../sgx-verifier/ISGXVerifier.sol";

import {MockDcapAttestation} from "../mocks/MockDcapAttestation.sol";

contract AttestationVerifierTest is DSTestPlus {
    event UpdateMrSigner(bytes32 indexed mrSigner, bool status);
    event UpdateMrEnclave(bytes32 indexed mrEnclave, bool status);

    MockDcapAttestation private dcap;
    AttestationVerifier private attestationVerifier;

    function setUp() public {
        hevm.warp(1);
        dcap = new MockDcapAttestation();
        attestationVerifier = new AttestationVerifier(address(dcap));
    }

    function testUpdateMrSigner(bytes32[] memory signers) external {
        hevm.assume(signers.length > 0);
        for (uint256 i = 0; i < signers.length; i++) {
            for (uint256 j = 0; j < i; ++j) {
                hevm.assume(signers[i] != signers[j]);
            }
        }

        // not owner, revert
        hevm.startPrank(address(1));
        hevm.expectRevert("Ownable: caller is not the owner");
        attestationVerifier.updateMrSigner(signers[0], true);
        hevm.stopPrank();

        for (uint256 i = 0; i < signers.length; i++) {
            assertBoolEq(false, attestationVerifier.isTrustedMrSigner(signers[i]));
            hevm.expectEmit(true, false, false, true);
            emit UpdateMrSigner(signers[i], true);
            attestationVerifier.updateMrSigner(signers[i], true);
            assertBoolEq(true, attestationVerifier.isTrustedMrSigner(signers[i]));

            bytes32[] memory lists = attestationVerifier.getTrustedMrSigners();
            assertEq(lists.length, i + 1);
            for (uint256 j = 0; j <= i; ++j) {
                assertEq(lists[j], signers[j]);
            }
        }
        for (uint256 i = 0; i < signers.length; i++) {
            assertBoolEq(true, attestationVerifier.isTrustedMrSigner(signers[signers.length - 1 - i]));
            hevm.expectEmit(true, false, false, true);
            emit UpdateMrSigner(signers[signers.length - 1 - i], false);
            attestationVerifier.updateMrSigner(signers[signers.length - 1 - i], false);
            assertBoolEq(false, attestationVerifier.isTrustedMrSigner(signers[signers.length - 1 - i]));

            bytes32[] memory lists = attestationVerifier.getTrustedMrSigners();
            assertEq(lists.length, signers.length - 1 - i);
            for (uint256 j = 0; j < signers.length - 1 - i; ++j) {
                assertEq(lists[j], signers[j]);
            }
        }
    }

    function testUpdateMrEnclave(bytes32[] memory enclaves) external {
        hevm.assume(enclaves.length > 0);
        for (uint256 i = 0; i < enclaves.length; i++) {
            for (uint256 j = 0; j < i; ++j) {
                hevm.assume(enclaves[i] != enclaves[j]);
            }
        }

        // not owner, revert
        hevm.startPrank(address(1));
        hevm.expectRevert("Ownable: caller is not the owner");
        attestationVerifier.updateMrEnclave(enclaves[0], true);
        hevm.stopPrank();

        for (uint256 i = 0; i < enclaves.length; i++) {
            assertBoolEq(false, attestationVerifier.isTrustedMrEnclave(enclaves[i]));
            hevm.expectEmit(true, false, false, true);
            emit UpdateMrEnclave(enclaves[i], true);
            attestationVerifier.updateMrEnclave(enclaves[i], true);
            assertBoolEq(true, attestationVerifier.isTrustedMrEnclave(enclaves[i]));

            bytes32[] memory lists = attestationVerifier.getTrustedMrEnclaves();
            assertEq(lists.length, i + 1);
            for (uint256 j = 0; j <= i; ++j) {
                assertEq(lists[j], enclaves[j]);
            }
        }
        for (uint256 i = 0; i < enclaves.length; i++) {
            assertBoolEq(true, attestationVerifier.isTrustedMrEnclave(enclaves[enclaves.length - 1 - i]));
            hevm.expectEmit(true, false, false, true);
            emit UpdateMrEnclave(enclaves[enclaves.length - 1 - i], false);
            attestationVerifier.updateMrEnclave(enclaves[enclaves.length - 1 - i], false);
            assertBoolEq(false, attestationVerifier.isTrustedMrEnclave(enclaves[enclaves.length - 1 - i]));

            bytes32[] memory lists = attestationVerifier.getTrustedMrEnclaves();
            assertEq(lists.length, enclaves.length - 1 - i);
            for (uint256 j = 0; j < enclaves.length - 1 - i; ++j) {
                assertEq(lists[j], enclaves[j]);
            }
        }
    }

    function testVerifyAttestation() external {
        bytes32 hash = 0x1d541a57a16735fca3a2ef49ce5711705a71c26119b5043aeaab70adfcb3868d;

        // revert ErrorInvalidReport
        dcap.setValue(false, new bytes(0));
        hevm.expectRevert(AttestationVerifier.ErrorInvalidReport.selector);
        attestationVerifier.verifyAttestation(new bytes(0), hash);
        dcap.setValue(true, new bytes(0));
        hevm.expectRevert(AttestationVerifier.ErrorInvalidReport.selector);
        attestationVerifier.verifyAttestation(new bytes(0), hash);

        // the value comes from 0x76A3657F2d6c5C66733e9b69ACaDadCd0B68788b.verifyAndAttestOnChain
        dcap.setValue(
            true,
            hex"0003000000000100606a0000000e0e100fffff0100000000000000000000000000000000000000000000000000000000000000000000000000000000000500000000000000e700000000000000de424a88451579c00ad51d75c8f938b3f0bcb42fbb6840ac542f81a90a12dbcf00000000000000000000000000000000000000000000000000000000000000001d7b598f382a365d445d477f0df30bbe13a9a2276c75c9b002dba6a9a925c7030000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001d541a57a16735fca3a2ef49ce5711705a71c26119b5043aeaab70adfcb3868d"
        );

        // revert ErrorReportDataMismatch
        hevm.expectRevert(AttestationVerifier.ErrorReportDataMismatch.selector);
        attestationVerifier.verifyAttestation(new bytes(0), bytes32(0));

        // MrEnclave = 0xde424a88451579c00ad51d75c8f938b3f0bcb42fbb6840ac542f81a90a12dbcf
        // revert ErrorInvalidMrEnclave
        hevm.expectRevert(AttestationVerifier.ErrorInvalidMrEnclave.selector);
        attestationVerifier.verifyAttestation(new bytes(0), hash);

        attestationVerifier.updateMrEnclave(0xde424a88451579c00ad51d75c8f938b3f0bcb42fbb6840ac542f81a90a12dbcf, true);

        // MrSigner = 0x1d7b598f382a365d445d477f0df30bbe13a9a2276c75c9b002dba6a9a925c703
        // revert ErrorInvalidMrSigner
        hevm.expectRevert(AttestationVerifier.ErrorInvalidMrSigner.selector);
        attestationVerifier.verifyAttestation(new bytes(0), hash);

        attestationVerifier.updateMrSigner(0x1d7b598f382a365d445d477f0df30bbe13a9a2276c75c9b002dba6a9a925c703, true);

        // succeed
        attestationVerifier.verifyAttestation(new bytes(0), hash);
    }
}
