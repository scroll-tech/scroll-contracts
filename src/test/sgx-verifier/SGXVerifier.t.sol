// SPDX-License-Identifier: MIT

pragma solidity =0.8.24;

import {DSTestPlus} from "solmate/test/utils/DSTestPlus.sol";

import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

import {AttestationVerifier} from "../../sgx-verifier/AttestationVerifier.sol";
import {SGXVerifier, ISGXVerifier} from "../../sgx-verifier/SGXVerifier.sol";

contract SGXVerifierTest is DSTestPlus {
    event ProverRegistered(address indexed prover, uint256 validUntil);

    AttestationVerifier private attestationVerifier;
    SGXVerifier private sgxVerifier;

    function setUp() public {
        hevm.warp(1);
        attestationVerifier = new AttestationVerifier(address(0));
        sgxVerifier = new SGXVerifier(address(attestationVerifier), 86400 * 7, 60);

        sgxVerifier.grantRole(sgxVerifier.PROVER_REGISTER_ROLE(), address(this));
    }

    function testRegister() external {
        // revert when no PROVER_REGISTER_ROLE
        hevm.startPrank(address(1));
        hevm.expectRevert(
            abi.encodePacked(
                "AccessControl: account ",
                Strings.toHexString(address(1)),
                " is missing role ",
                Strings.toHexString(uint256(sgxVerifier.PROVER_REGISTER_ROLE()), 32)
            )
        );
        sgxVerifier.register(new bytes(0), ISGXVerifier.ReportData(address(0), 0, bytes32(0)));
        hevm.stopPrank();

        // revert when ErrorInvalidBlockNumber
        hevm.expectRevert(SGXVerifier.ErrorInvalidBlockNumber.selector);
        sgxVerifier.register(new bytes(0), ISGXVerifier.ReportData(address(0), block.number, bytes32(0)));

        hevm.roll(100);

        // revert when ErrorBlockNumberOutOfDate
        hevm.expectRevert(SGXVerifier.ErrorBlockNumberOutOfDate.selector);
        sgxVerifier.register(new bytes(0), ISGXVerifier.ReportData(address(0), block.number - 60, bytes32(0)));

        // revert when ErrorBlockHashMismatch
        hevm.expectRevert(SGXVerifier.ErrorBlockHashMismatch.selector);
        sgxVerifier.register(new bytes(0), ISGXVerifier.ReportData(address(0), block.number - 59, bytes32(0)));

        // todo: add rest tests

        // revert when ErrorReportUsed

        // succeed
    }
}
