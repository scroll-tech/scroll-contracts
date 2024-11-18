// SPDX-License-Identifier: MIT

pragma solidity =0.8.24;

import {DSTestPlus} from "solmate/test/utils/DSTestPlus.sol";

import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

import {AttestationVerifier} from "../../sgx-verifier/AttestationVerifier.sol";
import {SGXVerifier, ISGXVerifier} from "../../sgx-verifier/SGXVerifier.sol";

import {MockAttestationVerifier} from "../mocks/MockAttestationVerifier.sol";

contract SGXVerifierTest is DSTestPlus {
    event ProverRegistered(address indexed prover, uint256 validUntil);

    MockAttestationVerifier private attestationVerifier;
    SGXVerifier private sgxVerifier;

    function setUp() public {
        hevm.warp(1);
        attestationVerifier = new MockAttestationVerifier();
        sgxVerifier = new SGXVerifier(address(attestationVerifier), 86400 * 7, 60, 86400);

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

        // first register, succeed
        (address nextProver, uint256 expireTime) = sgxVerifier.nextProver();
        assertEq(sgxVerifier.proverQueueHead(), 0);
        assertEq(sgxVerifier.proverQueueTail(), 0);
        assertEq(nextProver, address(0));
        assertEq(expireTime, 0);
        sgxVerifier.register(
            new bytes(0),
            ISGXVerifier.ReportData(address(1), block.number - 59, blockhash(block.number - 59))
        );
        assertEq(sgxVerifier.proverQueueHead(), 0);
        assertEq(sgxVerifier.proverQueueTail(), 1);
        assertEq(sgxVerifier.proverQueue(0), address(1));
        assertEq(sgxVerifier.attestedProverExpireTime(address(1)), block.timestamp + 86400 * 7);
        (nextProver, expireTime) = sgxVerifier.nextProver();
        assertEq(nextProver, address(1));
        assertEq(expireTime, block.timestamp + 86400);

        // revert when ErrorReportUsed
        hevm.expectRevert(SGXVerifier.ErrorReportUsed.selector);
        sgxVerifier.register(
            new bytes(0),
            ISGXVerifier.ReportData(address(1), block.number - 59, blockhash(block.number - 59))
        );

        // second register, succeed
        sgxVerifier.register(
            new bytes(1),
            ISGXVerifier.ReportData(address(2), block.number - 59, blockhash(block.number - 59))
        );
        assertEq(sgxVerifier.proverQueueHead(), 0);
        assertEq(sgxVerifier.proverQueueTail(), 2);
        assertEq(sgxVerifier.proverQueue(0), address(1));
        assertEq(sgxVerifier.proverQueue(1), address(2));
        assertEq(sgxVerifier.attestedProverExpireTime(address(2)), block.timestamp + 86400 * 7);
        (nextProver, expireTime) = sgxVerifier.nextProver();
        assertEq(nextProver, address(1));
        assertEq(expireTime, block.timestamp + 86400);

        // third register, succeed
        sgxVerifier.register(
            new bytes(2),
            ISGXVerifier.ReportData(address(3), block.number - 59, blockhash(block.number - 59))
        );
        assertEq(sgxVerifier.proverQueueHead(), 0);
        assertEq(sgxVerifier.proverQueueTail(), 3);
        assertEq(sgxVerifier.proverQueue(0), address(1));
        assertEq(sgxVerifier.proverQueue(1), address(2));
        assertEq(sgxVerifier.proverQueue(2), address(3));
        assertEq(sgxVerifier.attestedProverExpireTime(address(3)), block.timestamp + 86400 * 7);
        (nextProver, expireTime) = sgxVerifier.nextProver();
        assertEq(nextProver, address(1));
        assertEq(expireTime, block.timestamp + 86400);

        // all expired
        sgxVerifier.grantRole(sgxVerifier.PROVER_SELECTION_ROLE(), address(this));
        hevm.warp(block.timestamp + 86400 * 10);
        assertEq(address(0), sgxVerifier.randomSelectNextProver());
        assertEq(sgxVerifier.proverQueueHead(), 3);
        assertEq(sgxVerifier.proverQueueTail(), 3);

        // forth register, succeed
        sgxVerifier.register(
            new bytes(3),
            ISGXVerifier.ReportData(address(4), block.number - 59, blockhash(block.number - 59))
        );
        assertEq(sgxVerifier.proverQueueHead(), 3);
        assertEq(sgxVerifier.proverQueueTail(), 4);
        assertEq(sgxVerifier.attestedProverExpireTime(address(4)), block.timestamp + 86400 * 7);
        (nextProver, expireTime) = sgxVerifier.nextProver();
        assertEq(nextProver, address(4));
        assertEq(expireTime, block.timestamp + 86400);
    }

    function testVerify(
        uint64 layer2ChainId,
        uint32 numBatches,
        bytes32 prevStateRoot,
        bytes32 prevBatchHash,
        bytes32 postStateRoot,
        bytes32 batchHash,
        bytes32 postWithdrawRoot
    ) external {
        bytes memory publicInput = abi.encodePacked(
            layer2ChainId,
            numBatches,
            prevStateRoot,
            prevBatchHash,
            postStateRoot,
            batchHash,
            postWithdrawRoot
        );
        bytes32 hash = sgxVerifier.getProveBundleSignatureDataHash(
            layer2ChainId,
            numBatches,
            prevStateRoot,
            prevBatchHash,
            postStateRoot,
            batchHash,
            postWithdrawRoot
        );
        bytes memory signature;
        {
            (uint8 v, bytes32 r, bytes32 s) = hevm.sign(1, hash);
            signature = abi.encodePacked(r, s, v);
        }

        // register
        hevm.roll(100);
        sgxVerifier.register(
            new bytes(0),
            ISGXVerifier.ReportData(hevm.addr(1), block.number - 1, blockhash(block.number - 1))
        );
        sgxVerifier.register(
            new bytes(1),
            ISGXVerifier.ReportData(hevm.addr(2), block.number - 1, blockhash(block.number - 1))
        );

        // verify ok
        sgxVerifier.verify(signature, publicInput);

        // revert `ErrorNotSelectedProver`
        {
            (uint8 v, bytes32 r, bytes32 s) = hevm.sign(2, hash);
            signature = abi.encodePacked(r, s, v);
        }
        hevm.expectRevert(SGXVerifier.ErrorNotSelectedProver.selector);
        sgxVerifier.verify(signature, publicInput);

        // verify ok, when selected prover not submit in time
        (, uint256 expireTime) = sgxVerifier.nextProver();
        hevm.warp(expireTime + 1);
        sgxVerifier.verify(signature, publicInput);

        // revert `ErrorProverOutOfDate`
        {
            (uint8 v, bytes32 r, bytes32 s) = hevm.sign(1, hash);
            signature = abi.encodePacked(r, s, v);
        }
        hevm.warp(sgxVerifier.attestedProverExpireTime(hevm.addr(1)) + 1);
        hevm.expectRevert(SGXVerifier.ErrorProverOutOfDate.selector);
        sgxVerifier.verify(signature, publicInput);
    }

    function testRandomSelectNextProver() external {
        hevm.roll(100);

        // revert when no PROVER_SELECTION_ROLE
        hevm.startPrank(address(1));
        hevm.expectRevert(
            abi.encodePacked(
                "AccessControl: account ",
                Strings.toHexString(address(1)),
                " is missing role ",
                Strings.toHexString(uint256(sgxVerifier.PROVER_SELECTION_ROLE()), 32)
            )
        );
        sgxVerifier.randomSelectNextProver();
        hevm.stopPrank();

        // empty queue return address(0)
        sgxVerifier.grantRole(sgxVerifier.PROVER_SELECTION_ROLE(), address(this));
        assertEq(address(0), sgxVerifier.randomSelectNextProver());

        uint256 startTime = block.timestamp;
        // register 3 prover, selected is first one
        sgxVerifier.register(
            new bytes(0),
            ISGXVerifier.ReportData(address(1), block.number - 1, blockhash(block.number - 1))
        );
        hevm.warp(startTime + 86400);
        sgxVerifier.register(
            new bytes(1),
            ISGXVerifier.ReportData(address(2), block.number - 1, blockhash(block.number - 1))
        );
        hevm.warp(startTime + 86400 * 2);
        sgxVerifier.register(
            new bytes(2),
            ISGXVerifier.ReportData(address(3), block.number - 1, blockhash(block.number - 1))
        );
        (address nextProver, uint256 expireTime) = sgxVerifier.nextProver();
        assertEq(nextProver, address(1));
        assertEq(expireTime, startTime + 86400);

        // first expired
        hevm.warp(startTime + 86400 * 6);
        for (uint256 i = 0; i < 10; ++i) {
            sgxVerifier.randomSelectNextProver();
        }
        assertEq(sgxVerifier.proverQueueHead(), 1);
        (nextProver, expireTime) = sgxVerifier.nextProver();
        assertTrue(nextProver != address(1));
        assertEq(expireTime, block.timestamp + 86400);
    }
}
