// SPDX-License-Identifier: MIT

pragma solidity =0.8.24;

import {DSTestPlus} from "solmate/test/utils/DSTestPlus.sol";

import {AttestationVerifier} from "../../sgx-verifier/AttestationVerifier.sol";

contract AttestationVerifierTest is DSTestPlus {
    event UpdateMrSigner(bytes32 indexed mrSigner, bool status);
    event UpdateMrEnclave(bytes32 indexed mrEnclave, bool status);

    AttestationVerifier private attestationVerifier;

    function setUp() public {
        hevm.warp(1);
        attestationVerifier = new AttestationVerifier(address(0));
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
        // todo
    }
}
