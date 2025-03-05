// SPDX-License-Identifier: MIT

pragma solidity =0.8.24;

import {DSTestPlus} from "solmate/test/utils/DSTestPlus.sol";

import {ITransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import {IL1MessageQueueV1} from "../L1/rollup/IL1MessageQueueV1.sol";
import {L1MessageQueueV1} from "../L1/rollup/L1MessageQueueV1.sol";
import {L2GasPriceOracle} from "../L1/rollup/L2GasPriceOracle.sol";
import {Whitelist} from "../L2/predeploys/Whitelist.sol";

import {ScrollTestBase} from "./ScrollTestBase.t.sol";

contract L1MessageQueueV1Test is ScrollTestBase {
    // events
    event QueueTransaction(
        address indexed sender,
        address indexed target,
        uint256 value,
        uint64 queueIndex,
        uint256 gasLimit,
        bytes data
    );
    event DequeueTransaction(uint256 startIndex, uint256 count, uint256 skippedBitmap);
    event ResetDequeuedTransaction(uint256 startIndex);
    event FinalizedDequeuedTransaction(uint256 finalizedIndex);
    event DropTransaction(uint256 index);
    event UpdateGasOracle(address indexed _oldGasOracle, address indexed _newGasOracle);
    event UpdateMaxGasLimit(uint256 _oldMaxGasLimit, uint256 _newMaxGasLimit);

    address private FakeScrollChain = 0x1000000000000000000000000000000000000001;
    address private FakeMessenger = 0x1000000000000000000000000000000000000002;
    address private FakeGateway = 0x1000000000000000000000000000000000000003;
    address private FakeSigner = 0x1000000000000000000000000000000000000004;

    L1MessageQueueV1 private queue;
    L2GasPriceOracle private gasOracle;

    function setUp() public {
        __ScrollTestBase_setUp();

        queue = L1MessageQueueV1(_deployProxy(address(0)));
        gasOracle = L2GasPriceOracle(_deployProxy(address(new L2GasPriceOracle())));

        // Upgrade the L1MessageQueueV1 implementation and initialize
        admin.upgrade(
            ITransparentUpgradeableProxy(address(queue)),
            address(new L1MessageQueueV1(FakeMessenger, FakeScrollChain, FakeGateway))
        );
        gasOracle.initialize(21000, 50000, 8, 16);
        queue.initialize(address(1), address(1), address(1), address(gasOracle), 10000000);
    }

    function testInitialize() external {
        assertEq(queue.owner(), address(this));
        assertEq(queue.messenger(), FakeMessenger);
        assertEq(queue.scrollChain(), FakeScrollChain);
        assertEq(queue.enforcedTxGateway(), FakeGateway);
        assertEq(queue.gasOracle(), address(gasOracle));
        assertEq(queue.maxGasLimit(), 10000000);

        hevm.expectRevert("Initializable: contract is already initialized");
        queue.initialize(address(0), address(0), address(0), address(0), 0);
    }

    function testUpdateGasOracle(address newGasOracle) external {
        // call by non-owner, should revert
        hevm.startPrank(address(1));
        hevm.expectRevert("Ownable: caller is not the owner");
        queue.updateGasOracle(newGasOracle);
        hevm.stopPrank();

        // call by owner, should succeed
        assertEq(queue.gasOracle(), address(gasOracle));
        hevm.expectEmit(true, true, false, true);
        emit UpdateGasOracle(address(gasOracle), newGasOracle);
        queue.updateGasOracle(newGasOracle);
        assertEq(queue.gasOracle(), newGasOracle);
    }

    function testUpdateMaxGasLimit(uint256 newMaxGasLimit) external {
        // call by non-owner, should revert
        hevm.startPrank(address(1));
        hevm.expectRevert("Ownable: caller is not the owner");
        queue.updateMaxGasLimit(newMaxGasLimit);
        hevm.stopPrank();

        // call by owner, should succeed
        assertEq(queue.maxGasLimit(), 10000000);
        hevm.expectEmit(true, true, false, true);
        emit UpdateMaxGasLimit(10000000, newMaxGasLimit);
        queue.updateMaxGasLimit(newMaxGasLimit);
        assertEq(queue.maxGasLimit(), newMaxGasLimit);
    }

    function testAppendCrossDomainMessage(uint256 gasLimit, bytes memory data) external {
        gasLimit = bound(gasLimit, 21000 + data.length * 16, 10000000);

        // should revert, when non-messenger call
        hevm.expectRevert("Only callable by the L1ScrollMessenger");
        queue.appendCrossDomainMessage(address(0), 0, "0x");

        hevm.startPrank(FakeMessenger);

        // should revert, when exceed maxGasLimit
        hevm.expectRevert("Gas limit must not exceed maxGasLimit");
        queue.appendCrossDomainMessage(address(0), 10000001, "0x");

        // should revert, when below intrinsic gas
        hevm.expectRevert("Insufficient gas limit, must be above intrinsic gas");
        queue.appendCrossDomainMessage(address(0), 0, "0x");

        // should succeed
        assertEq(queue.nextCrossDomainMessageIndex(), 0);
        address sender = address(uint160(FakeMessenger) + uint160(0x1111000000000000000000000000000000001111));
        bytes32 hash0 = queue.computeTransactionHash(sender, 0, 0, FakeSigner, gasLimit, data);
        hevm.expectEmit(true, true, false, true);
        emit QueueTransaction(sender, FakeSigner, 0, 0, gasLimit, data);
        queue.appendCrossDomainMessage(FakeSigner, gasLimit, data);
        assertEq(queue.nextCrossDomainMessageIndex(), 1);
        assertEq(queue.getCrossDomainMessage(0), hash0);

        bytes32 hash1 = queue.computeTransactionHash(sender, 1, 0, FakeSigner, gasLimit, data);
        hevm.expectEmit(true, true, false, true);
        emit QueueTransaction(sender, FakeSigner, 0, 1, gasLimit, data);
        queue.appendCrossDomainMessage(FakeSigner, gasLimit, data);
        assertEq(queue.nextCrossDomainMessageIndex(), 2);
        assertEq(queue.getCrossDomainMessage(0), hash0);
        assertEq(queue.getCrossDomainMessage(1), hash1);

        hevm.stopPrank();
    }

    function testAppendEnforcedTransaction(
        uint256 value,
        uint256 gasLimit,
        bytes memory data
    ) external {
        gasLimit = bound(gasLimit, 21000 + data.length * 16, 10000000);

        // should revert, when non-gateway call
        hevm.expectRevert("Only callable by the EnforcedTxGateway");
        queue.appendEnforcedTransaction(FakeSigner, address(0), 0, 0, "0x");

        hevm.startPrank(FakeGateway);

        // should revert, when sender is not EOA
        hevm.expectRevert("only EOA");
        queue.appendEnforcedTransaction(address(this), address(0), 0, 0, "0x");

        // should revert, when exceed maxGasLimit
        hevm.expectRevert("Gas limit must not exceed maxGasLimit");
        queue.appendEnforcedTransaction(FakeSigner, address(0), 0, 10000001, "0x");

        // should revert, when below intrinsic gas
        hevm.expectRevert("Insufficient gas limit, must be above intrinsic gas");
        queue.appendEnforcedTransaction(FakeSigner, address(0), 0, 0, "0x");

        // should succeed
        assertEq(queue.nextCrossDomainMessageIndex(), 0);
        address sender = address(uint160(FakeMessenger) + uint160(0x1111000000000000000000000000000000001111));
        bytes32 hash0 = queue.computeTransactionHash(sender, 0, value, FakeSigner, gasLimit, data);
        hevm.expectEmit(true, true, false, true);
        emit QueueTransaction(sender, FakeSigner, value, 0, gasLimit, data);
        queue.appendEnforcedTransaction(sender, FakeSigner, value, gasLimit, data);
        assertEq(queue.nextCrossDomainMessageIndex(), 1);
        assertEq(queue.getCrossDomainMessage(0), hash0);

        bytes32 hash1 = queue.computeTransactionHash(sender, 1, value, FakeSigner, gasLimit, data);
        hevm.expectEmit(true, true, false, true);
        emit QueueTransaction(sender, FakeSigner, value, 1, gasLimit, data);
        queue.appendEnforcedTransaction(sender, FakeSigner, value, gasLimit, data);
        assertEq(queue.nextCrossDomainMessageIndex(), 2);
        assertEq(queue.getCrossDomainMessage(0), hash0);
        assertEq(queue.getCrossDomainMessage(1), hash1);

        hevm.stopPrank();
    }

    function testPopCrossDomainMessage(uint256 bitmap) external {
        // should revert, when non-scrollChain call
        hevm.expectRevert("Only callable by the ScrollChain");
        queue.popCrossDomainMessage(0, 0, 0);

        // should revert, when pop too many messages
        hevm.startPrank(FakeScrollChain);
        hevm.expectRevert("pop too many messages");
        queue.popCrossDomainMessage(0, 257, 0);
        hevm.stopPrank();

        // should revert, when start index mismatch
        hevm.startPrank(FakeScrollChain);
        hevm.expectRevert("start index mismatch");
        queue.popCrossDomainMessage(1, 256, 0);
        hevm.stopPrank();

        // should succeed
        // append 512 messages
        hevm.startPrank(FakeMessenger);
        for (uint256 i = 0; i < 512; ++i) {
            queue.appendCrossDomainMessage(address(0), 1000000, "0x");
        }
        hevm.stopPrank();

        // pop 50 messages with no skip
        hevm.startPrank(FakeScrollChain);
        hevm.expectEmit(false, false, false, true);
        emit DequeueTransaction(0, 50, 0);
        queue.popCrossDomainMessage(0, 50, 0);
        assertEq(queue.pendingQueueIndex(), 50);
        assertEq(queue.nextUnfinalizedQueueIndex(), 0);
        for (uint256 i = 0; i < 50; i++) {
            assertBoolEq(queue.isMessageSkipped(i), false);
            assertBoolEq(queue.isMessageDropped(i), false);
        }

        // pop 10 messages all skip
        hevm.expectEmit(false, false, false, true);
        emit DequeueTransaction(50, 10, 1023);
        queue.popCrossDomainMessage(50, 10, 1023);
        assertEq(queue.pendingQueueIndex(), 60);
        assertEq(queue.nextUnfinalizedQueueIndex(), 0);
        for (uint256 i = 50; i < 60; i++) {
            assertBoolEq(queue.isMessageSkipped(i), true);
            assertBoolEq(queue.isMessageDropped(i), false);
        }
        assertBoolEq(queue.isMessageSkipped(60), false);

        // pop 20 messages, skip first 5
        hevm.expectEmit(false, false, false, true);
        emit DequeueTransaction(60, 20, 31);
        queue.popCrossDomainMessage(60, 20, 31);
        assertEq(queue.pendingQueueIndex(), 80);
        assertEq(queue.nextUnfinalizedQueueIndex(), 0);
        for (uint256 i = 60; i < 65; i++) {
            assertBoolEq(queue.isMessageSkipped(i), true);
            assertBoolEq(queue.isMessageDropped(i), false);
        }
        for (uint256 i = 65; i < 80; i++) {
            assertBoolEq(queue.isMessageSkipped(i), false);
            assertBoolEq(queue.isMessageDropped(i), false);
        }

        // pop 256 messages with random skip
        hevm.expectEmit(false, false, false, true);
        emit DequeueTransaction(80, 256, bitmap);
        queue.popCrossDomainMessage(80, 256, bitmap);
        assertEq(queue.pendingQueueIndex(), 336);
        for (uint256 i = 80; i < 80 + 256; i++) {
            assertBoolEq(queue.isMessageSkipped(i), ((bitmap >> (i - 80)) & 1) == 1);
            assertBoolEq(queue.isMessageDropped(i), false);
        }

        hevm.stopPrank();
    }

    function testPopCrossDomainMessageRandom(
        uint256 count1,
        uint256 count2,
        uint256 count3,
        uint256 bitmap1,
        uint256 bitmap2,
        uint256 bitmap3
    ) external {
        count1 = bound(count1, 1, 256);
        count2 = bound(count2, 1, 256);
        count3 = bound(count3, 1, 256);
        // append count1 + count2 + count3 messages
        hevm.startPrank(FakeMessenger);
        for (uint256 i = 0; i < count1 + count2 + count3; i++) {
            queue.appendCrossDomainMessage(address(0), 1000000, "0x");
        }
        hevm.stopPrank();

        hevm.startPrank(FakeScrollChain);
        // first pop `count1` messages
        hevm.expectEmit(false, false, false, true);
        if (count1 == 256) {
            emit DequeueTransaction(0, count1, bitmap1);
        } else {
            emit DequeueTransaction(0, count1, bitmap1 & ((1 << count1) - 1));
        }
        queue.popCrossDomainMessage(0, count1, bitmap1);
        assertEq(queue.pendingQueueIndex(), count1);
        for (uint256 i = 0; i < count1; i++) {
            assertBoolEq(queue.isMessageSkipped(i), ((bitmap1 >> i) & 1) == 1);
            assertBoolEq(queue.isMessageDropped(i), false);
        }

        // then pop `count2` messages
        hevm.expectEmit(false, false, false, true);
        if (count2 == 256) {
            emit DequeueTransaction(count1, count2, bitmap2);
        } else {
            emit DequeueTransaction(count1, count2, bitmap2 & ((1 << count2) - 1));
        }
        queue.popCrossDomainMessage(count1, count2, bitmap2);
        assertEq(queue.pendingQueueIndex(), count1 + count2);
        for (uint256 i = 0; i < count2; i++) {
            assertBoolEq(queue.isMessageSkipped(i + count1), ((bitmap2 >> i) & 1) == 1);
            assertBoolEq(queue.isMessageDropped(i + count1), false);
        }

        // last pop `count3` messages
        hevm.expectEmit(false, false, false, true);
        if (count3 == 256) {
            emit DequeueTransaction(count1 + count2, count3, bitmap3);
        } else {
            emit DequeueTransaction(count1 + count2, count3, bitmap3 & ((1 << count3) - 1));
        }
        queue.popCrossDomainMessage(count1 + count2, count3, bitmap3);
        assertEq(queue.pendingQueueIndex(), count1 + count2 + count3);
        for (uint256 i = 0; i < count3; i++) {
            assertBoolEq(queue.isMessageSkipped(i + count1 + count2), ((bitmap3 >> i) & 1) == 1);
            assertBoolEq(queue.isMessageDropped(i + count1 + count2), false);
        }
        hevm.stopPrank();
    }

    function testResetPoppedCrossDomainMessage(uint256 startIndex) external {
        // should revert, when non-scrollChain call
        hevm.expectRevert("Only callable by the ScrollChain");
        queue.resetPoppedCrossDomainMessage(0);

        // should do nothing
        hevm.startPrank(FakeScrollChain);
        queue.resetPoppedCrossDomainMessage(0);
        hevm.stopPrank();

        // append 512 messages
        hevm.startPrank(FakeMessenger);
        for (uint256 i = 0; i < 512; i++) {
            queue.appendCrossDomainMessage(address(0), 1000000, "0x");
        }
        hevm.stopPrank();

        // pop 256 messages with no skip
        hevm.startPrank(FakeScrollChain);
        hevm.expectEmit(false, false, false, true);
        emit DequeueTransaction(0, 256, 0);
        queue.popCrossDomainMessage(0, 256, 0);
        assertEq(queue.pendingQueueIndex(), 256);
        assertEq(queue.nextUnfinalizedQueueIndex(), 0);
        hevm.stopPrank();

        // finalize 128 messages
        hevm.startPrank(FakeScrollChain);
        hevm.expectEmit(false, false, false, true);
        emit FinalizedDequeuedTransaction(127);
        queue.finalizePoppedCrossDomainMessage(128);
        assertEq(queue.nextUnfinalizedQueueIndex(), 128);
        hevm.stopPrank();

        // should revert, when reset finalized messages
        hevm.startPrank(FakeScrollChain);
        hevm.expectRevert("reset finalized messages");
        queue.resetPoppedCrossDomainMessage(127);
        hevm.stopPrank();

        // should revert, when reset pending messages
        hevm.startPrank(FakeScrollChain);
        hevm.expectRevert("reset pending messages");
        queue.resetPoppedCrossDomainMessage(257);
        hevm.stopPrank();

        // should succeed
        startIndex = bound(startIndex, 128, 256);
        hevm.startPrank(FakeScrollChain);
        if (startIndex < 256) {
            hevm.expectEmit(false, false, false, true);
            emit ResetDequeuedTransaction(startIndex);
        }
        queue.resetPoppedCrossDomainMessage(startIndex);
        assertEq(queue.pendingQueueIndex(), startIndex);
        assertEq(queue.nextUnfinalizedQueueIndex(), 128);
        hevm.stopPrank();
    }

    // pop, reset, pop, reset, pop
    function testResetPoppedCrossDomainMessageRandom(
        uint256 bitmap1,
        uint256 bitmap2,
        uint256 startIndex1,
        uint256 startIndex2
    ) external {
        // append 1024 messages
        hevm.startPrank(FakeMessenger);
        for (uint256 i = 0; i < 512; i++) {
            queue.appendCrossDomainMessage(address(0), 1000000, "0x");
        }
        hevm.stopPrank();

        // first pop 512 messages
        hevm.startPrank(FakeScrollChain);
        queue.popCrossDomainMessage(0, 256, bitmap1);
        assertEq(queue.pendingQueueIndex(), 256);
        queue.popCrossDomainMessage(256, 256, bitmap2);
        assertEq(queue.pendingQueueIndex(), 512);
        hevm.stopPrank();

        for (uint256 i = 0; i < 512; ++i) {
            if (i < 256) {
                assertBoolEq(queue.isMessageSkipped(i), ((bitmap1) >> i) & 1 == 1);
            } else {
                assertBoolEq(queue.isMessageSkipped(i), ((bitmap2) >> (i - 256)) & 1 == 1);
            }
        }

        // first reset
        startIndex1 = bound(startIndex1, 0, 512);
        hevm.startPrank(FakeScrollChain);
        queue.resetPoppedCrossDomainMessage(startIndex1);
        hevm.stopPrank();
        assertEq(queue.pendingQueueIndex(), startIndex1);
        for (uint256 i = 0; i < 512; ++i) {
            if (i >= startIndex1) {
                assertBoolEq(queue.isMessageSkipped(i), false);
                continue;
            }
            if (i < 256) {
                assertBoolEq(queue.isMessageSkipped(i), ((bitmap1) >> i) & 1 == 1);
            } else {
                assertBoolEq(queue.isMessageSkipped(i), ((bitmap2) >> (i - 256)) & 1 == 1);
            }
        }

        // next pop 512 messages
        hevm.startPrank(FakeScrollChain);
        queue.popCrossDomainMessage(startIndex1, 256, bitmap1);
        assertEq(queue.pendingQueueIndex(), startIndex1 + 256);
        queue.popCrossDomainMessage(startIndex1 + 256, 256, bitmap2);
        assertEq(queue.pendingQueueIndex(), startIndex1 + 512);
        hevm.stopPrank();

        for (uint256 i = 0; i < startIndex1 + 512; ++i) {
            if (i < startIndex1) {
                if (i < 256) {
                    assertBoolEq(queue.isMessageSkipped(i), ((bitmap1) >> i) & 1 == 1);
                } else {
                    assertBoolEq(queue.isMessageSkipped(i), ((bitmap2) >> (i - 256)) & 1 == 1);
                }
            } else {
                uint256 offset = i - startIndex1;
                if (offset < 256) {
                    assertBoolEq(queue.isMessageSkipped(i), ((bitmap1) >> offset) & 1 == 1);
                } else {
                    assertBoolEq(queue.isMessageSkipped(i), ((bitmap2) >> (offset - 256)) & 1 == 1);
                }
            }
        }

        // second reset
        startIndex2 = bound(startIndex2, 0, startIndex1 + 512);
        hevm.startPrank(FakeScrollChain);
        queue.resetPoppedCrossDomainMessage(startIndex2);
        hevm.stopPrank();
        assertEq(queue.pendingQueueIndex(), startIndex2);
        for (uint256 i = 0; i < startIndex1 + 512; ++i) {
            if (i >= startIndex2) {
                assertBoolEq(queue.isMessageSkipped(i), false);
                continue;
            }
            if (i < startIndex1) {
                if (i < 256) {
                    assertBoolEq(queue.isMessageSkipped(i), ((bitmap1) >> i) & 1 == 1);
                } else {
                    assertBoolEq(queue.isMessageSkipped(i), ((bitmap2) >> (i - 256)) & 1 == 1);
                }
            } else {
                uint256 offset = i - startIndex1;
                if (offset < 256) {
                    assertBoolEq(queue.isMessageSkipped(i), ((bitmap1) >> offset) & 1 == 1);
                } else {
                    assertBoolEq(queue.isMessageSkipped(i), ((bitmap2) >> (offset - 256)) & 1 == 1);
                }
            }
        }
    }

    function testFinalizePoppedCrossDomainMessage() external {
        // should revert, when non-scrollChain call
        hevm.expectRevert("Only callable by the ScrollChain");
        queue.finalizePoppedCrossDomainMessage(0);

        // append 10 messages
        hevm.startPrank(FakeMessenger);
        for (uint256 i = 0; i < 10; i++) {
            queue.appendCrossDomainMessage(address(0), 1000000, "0x");
        }
        hevm.stopPrank();

        // pop 5 messages with no skip
        hevm.startPrank(FakeScrollChain);
        hevm.expectEmit(false, false, false, true);
        emit DequeueTransaction(0, 5, 0);
        queue.popCrossDomainMessage(0, 5, 0);
        assertEq(queue.pendingQueueIndex(), 5);
        assertEq(queue.nextUnfinalizedQueueIndex(), 0);
        hevm.stopPrank();

        // should revert, when finalized index too large
        hevm.startPrank(FakeScrollChain);
        hevm.expectRevert("finalized index too large");
        queue.finalizePoppedCrossDomainMessage(6);
        hevm.stopPrank();

        // should succeed
        hevm.startPrank(FakeScrollChain);
        hevm.expectEmit(false, false, false, true);
        emit FinalizedDequeuedTransaction(4);
        queue.finalizePoppedCrossDomainMessage(5);
        assertEq(queue.nextUnfinalizedQueueIndex(), 5);
        hevm.stopPrank();

        // should revert, finalized index too small
        hevm.startPrank(FakeScrollChain);
        hevm.expectRevert("finalized index too small");
        queue.finalizePoppedCrossDomainMessage(4);
        hevm.stopPrank();

        // should do nothing
        hevm.startPrank(FakeScrollChain);
        queue.finalizePoppedCrossDomainMessage(5);
        assertEq(queue.nextUnfinalizedQueueIndex(), 5);
        hevm.stopPrank();
    }

    function testDropCrossDomainMessageFailed() external {
        // should revert, when non-messenger call
        hevm.expectRevert("Only callable by the L1ScrollMessenger");
        queue.dropCrossDomainMessage(0);

        // should revert, when drop non-skipped message
        // append 10 messages
        hevm.startPrank(FakeMessenger);
        for (uint256 i = 0; i < 10; i++) {
            queue.appendCrossDomainMessage(address(0), 1000000, "0x");
        }
        hevm.stopPrank();

        // pop 5 messages with no skip
        hevm.startPrank(FakeScrollChain);
        hevm.expectEmit(false, false, false, true);
        emit DequeueTransaction(0, 5, 0);
        queue.popCrossDomainMessage(0, 5, 0);
        assertEq(queue.pendingQueueIndex(), 5);
        assertEq(queue.nextUnfinalizedQueueIndex(), 0);
        hevm.stopPrank();

        // drop pending message
        hevm.startPrank(FakeMessenger);
        for (uint256 i = 0; i < 5; i++) {
            hevm.expectRevert("cannot drop pending message");
            queue.dropCrossDomainMessage(i);
        }
        hevm.stopPrank();

        hevm.startPrank(FakeScrollChain);
        queue.finalizePoppedCrossDomainMessage(5);
        hevm.stopPrank();
        assertEq(queue.pendingQueueIndex(), 5);
        assertEq(queue.nextUnfinalizedQueueIndex(), 5);

        // drop non-skipped message
        hevm.startPrank(FakeMessenger);
        for (uint256 i = 0; i < 5; i++) {
            hevm.expectRevert("drop non-skipped message");
            queue.dropCrossDomainMessage(i);
        }
        hevm.stopPrank();

        // drop pending message
        hevm.startPrank(FakeMessenger);
        for (uint256 i = 5; i < 10; i++) {
            hevm.expectRevert("cannot drop pending message");
            queue.dropCrossDomainMessage(i);
        }
        hevm.stopPrank();
    }

    function testDropCrossDomainMessageSucceed() external {
        // append 10 messages
        hevm.startPrank(FakeMessenger);
        for (uint256 i = 0; i < 10; i++) {
            queue.appendCrossDomainMessage(address(0), 1000000, "0x");
        }
        hevm.stopPrank();

        // pop 10 messages, all skipped
        hevm.startPrank(FakeScrollChain);
        hevm.expectEmit(false, false, false, true);
        emit DequeueTransaction(0, 10, 0x3ff);
        queue.popCrossDomainMessage(0, 10, 0x3ff);
        assertEq(queue.pendingQueueIndex(), 10);
        assertEq(queue.nextUnfinalizedQueueIndex(), 0);
        queue.finalizePoppedCrossDomainMessage(5);
        assertEq(queue.pendingQueueIndex(), 10);
        assertEq(queue.nextUnfinalizedQueueIndex(), 5);
        hevm.stopPrank();

        for (uint256 i = 0; i < 5; i++) {
            assertBoolEq(queue.isMessageSkipped(i), true);
            assertBoolEq(queue.isMessageDropped(i), false);
            hevm.startPrank(FakeMessenger);
            hevm.expectEmit(false, false, false, true);
            emit DropTransaction(i);
            queue.dropCrossDomainMessage(i);

            hevm.expectRevert("message already dropped");
            queue.dropCrossDomainMessage(i);
            hevm.stopPrank();

            assertBoolEq(queue.isMessageSkipped(i), true);
            assertBoolEq(queue.isMessageDropped(i), true);
        }
        for (uint256 i = 5; i < 10; i++) {
            assertBoolEq(queue.isMessageSkipped(i), true);
            assertBoolEq(queue.isMessageDropped(i), false);

            hevm.startPrank(FakeMessenger);
            hevm.expectRevert("cannot drop pending message");
            queue.dropCrossDomainMessage(i);
            hevm.stopPrank();
        }
    }
}
