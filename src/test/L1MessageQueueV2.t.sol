// SPDX-License-Identifier: MIT

pragma solidity =0.8.24;

import {DSTestPlus} from "solmate/test/utils/DSTestPlus.sol";

import {ITransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import {IL1MessageQueueV1} from "../L1/rollup/IL1MessageQueueV1.sol";
import {L1MessageQueueV1} from "../L1/rollup/L1MessageQueueV1.sol";
import {L1MessageQueueV2} from "../L1/rollup/L1MessageQueueV2.sol";
import {L2GasPriceOracle} from "../L1/rollup/L2GasPriceOracle.sol";
import {SystemConfig} from "../L1/system-contract/SystemConfig.sol";
import {Whitelist} from "../L2/predeploys/Whitelist.sol";

import {ScrollTestBase} from "./ScrollTestBase.t.sol";

contract L1MessageQueueV2Test is ScrollTestBase {
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
    event FinalizedDequeuedTransaction(uint256 finalizedIndex);

    address private FakeScrollChain = 0x1000000000000000000000000000000000000001;
    address private FakeMessenger = 0x1000000000000000000000000000000000000002;
    address private FakeGateway = 0x1000000000000000000000000000000000000003;
    address private FakeSigner = 0x1000000000000000000000000000000000000004;

    SystemConfig private system;
    L1MessageQueueV1 private queueV1;
    L1MessageQueueV2 private queueV2;

    function setUp() public {
        __ScrollTestBase_setUp();

        system = SystemConfig(_deployProxy(address(0)));
        queueV1 = L1MessageQueueV1(_deployProxy(address(0)));
        queueV2 = L1MessageQueueV2(_deployProxy(address(0)));

        // Upgrade the SystemConfig implementation and initialize
        admin.upgrade(ITransparentUpgradeableProxy(address(system)), address(new SystemConfig()));
        system.initialize(
            address(this),
            address(uint160(1)),
            SystemConfig.MessageQueueParameters({maxGasLimit: 1, baseFeeOverhead: 2, baseFeeScalar: 3}),
            SystemConfig.EnforcedBatchParameters({maxDelayEnterEnforcedMode: 4, maxDelayMessageQueue: 5})
        );

        // Upgrade the L1MessageQueueV1 implementation and initialize
        admin.upgrade(
            ITransparentUpgradeableProxy(address(queueV1)),
            address(new L1MessageQueueV1(FakeMessenger, FakeScrollChain, FakeGateway))
        );
        queueV1.initialize(address(1), address(1), address(1), address(0), 10000000);

        // push 100 messages into queueV1
        hevm.startPrank(FakeMessenger);
        for (uint256 i = 0; i < 100; ++i) {
            queueV1.appendCrossDomainMessage(address(0), 1000000, "0x");
        }
        hevm.stopPrank();

        // Upgrade the L1MessageQueueV2 implementation and initialize
        admin.upgrade(
            ITransparentUpgradeableProxy(address(queueV2)),
            address(
                new L1MessageQueueV2(FakeMessenger, FakeScrollChain, FakeGateway, address(queueV1), address(system))
            )
        );
        queueV2.initialize();
    }

    function testInitialize() external {
        assertEq(queueV2.owner(), address(this));
        assertEq(queueV2.messenger(), FakeMessenger);
        assertEq(queueV2.scrollChain(), FakeScrollChain);
        assertEq(queueV2.enforcedTxGateway(), FakeGateway);
        assertEq(queueV2.firstCrossDomainMessageIndex(), 100);
        assertEq(queueV2.nextCrossDomainMessageIndex(), 100);
        assertEq(queueV2.nextUnfinalizedQueueIndex(), 100);

        hevm.expectRevert("Initializable: contract is already initialized");
        queueV2.initialize();
    }

    function testEstimatedL2BaseFee(
        uint256 basefee,
        uint256 overhead,
        uint256 scalar
    ) external {
        basefee = bound(basefee, 0, 1 ether);
        overhead = bound(overhead, 0, 1 ether);
        scalar = bound(scalar, 0, 1 ether);

        hevm.fee(basefee);
        system.updateMessageQueueParameters(
            SystemConfig.MessageQueueParameters({
                maxGasLimit: 1,
                baseFeeOverhead: uint112(overhead),
                baseFeeScalar: uint112(scalar)
            })
        );

        assertEq(queueV2.estimateL2BaseFee(), (basefee * scalar) / 1e18 + overhead);
    }

    function testEstimateCrossDomainMessageFee(
        uint256 gaslimit,
        uint256 basefee,
        uint256 overhead,
        uint256 scalar
    ) external {
        gaslimit = bound(gaslimit, 0, 30000000);
        basefee = bound(basefee, 0, 1 ether);
        overhead = bound(overhead, 0, 1 ether);
        scalar = bound(scalar, 0, 1 ether);

        hevm.fee(basefee);
        system.updateMessageQueueParameters(
            SystemConfig.MessageQueueParameters({
                maxGasLimit: 1,
                baseFeeOverhead: uint112(overhead),
                baseFeeScalar: uint112(scalar)
            })
        );

        assertEq(queueV2.estimateCrossDomainMessageFee(gaslimit), gaslimit * ((basefee * scalar) / 1e18 + overhead));
    }

    function testCalculateIntrinsicGasFee(bytes calldata data) external {
        assertEq(queueV2.calculateIntrinsicGasFee(data), 21000 + data.length * 40);
    }

    function testAppendCrossDomainMessage(
        uint256 gasLimit,
        bytes memory data,
        uint256 timestamp
    ) external {
        gasLimit = bound(gasLimit, 21000 + data.length * 40, 10000000);
        timestamp = bound(timestamp, 1, 2**31 - 1);

        // should revert, when non-messenger call
        hevm.expectRevert(L1MessageQueueV2.ErrorCallerIsNotMessenger.selector);
        queueV2.appendCrossDomainMessage(address(0), 0, "0x");

        system.updateMessageQueueParameters(
            SystemConfig.MessageQueueParameters({maxGasLimit: 10000000, baseFeeOverhead: 0, baseFeeScalar: 0})
        );

        hevm.startPrank(FakeMessenger);
        // should revert, when exceed maxGasLimit
        hevm.expectRevert(L1MessageQueueV2.ErrorGasLimitExceeded.selector);
        queueV2.appendCrossDomainMessage(address(0), 10000001, "0x");

        // should revert, when below intrinsic gas
        hevm.expectRevert(L1MessageQueueV2.ErrorGasLimitBelowIntrinsicGas.selector);
        queueV2.appendCrossDomainMessage(address(0), 0, "0x");

        // should succeed
        hevm.warp(timestamp);
        assertEq(queueV2.nextCrossDomainMessageIndex(), 100);
        address sender = address(uint160(FakeMessenger) + uint160(0x1111000000000000000000000000000000001111));
        bytes32 hash0 = queueV2.computeTransactionHash(sender, 100, 0, FakeSigner, gasLimit, data);
        bytes32 rhash0 = encodeHash(bytes32(0), hash0);
        hevm.expectEmit(true, true, false, true);
        emit QueueTransaction(sender, FakeSigner, 0, 100, gasLimit, data);
        queueV2.appendCrossDomainMessage(FakeSigner, gasLimit, data);
        assertEq(queueV2.nextCrossDomainMessageIndex(), 101);
        assertEq(queueV2.getMessageRollingHash(100), rhash0);
        assertEq(queueV2.getMessageEnqueueTimestamp(100), timestamp);

        hevm.warp(timestamp + 100);
        bytes32 hash1 = queueV2.computeTransactionHash(sender, 101, 0, FakeSigner, gasLimit, data);
        bytes32 rhash1 = encodeHash(rhash0, hash1);
        hevm.expectEmit(true, true, false, true);
        emit QueueTransaction(sender, FakeSigner, 0, 101, gasLimit, data);
        queueV2.appendCrossDomainMessage(FakeSigner, gasLimit, data);
        assertEq(queueV2.nextCrossDomainMessageIndex(), 102);
        assertEq(queueV2.getMessageRollingHash(100), rhash0);
        assertEq(queueV2.getMessageEnqueueTimestamp(100), timestamp);
        assertEq(queueV2.getMessageRollingHash(101), rhash1);
        assertEq(queueV2.getMessageEnqueueTimestamp(101), timestamp + 100);

        hevm.stopPrank();
    }

    function testAppendEnforcedTransaction(
        uint256 value,
        uint256 gasLimit,
        bytes memory data,
        uint256 timestamp
    ) external {
        gasLimit = bound(gasLimit, 21000 + data.length * 40, 10000000);
        timestamp = bound(timestamp, 1, 2**31 - 1);

        // should revert, when non-gateway call
        hevm.expectRevert(L1MessageQueueV2.ErrorCallerIsNotEnforcedTxGateway.selector);
        queueV2.appendEnforcedTransaction(FakeSigner, address(0), 0, 0, "0x");

        system.updateMessageQueueParameters(
            SystemConfig.MessageQueueParameters({maxGasLimit: 10000000, baseFeeOverhead: 0, baseFeeScalar: 0})
        );
        hevm.startPrank(FakeGateway);

        // should revert, when exceed maxGasLimit
        hevm.expectRevert(L1MessageQueueV2.ErrorGasLimitExceeded.selector);
        queueV2.appendEnforcedTransaction(FakeSigner, address(0), 0, 10000001, "0x");

        // should revert, when below intrinsic gas
        hevm.expectRevert(L1MessageQueueV2.ErrorGasLimitBelowIntrinsicGas.selector);
        queueV2.appendEnforcedTransaction(FakeSigner, address(0), 0, 0, "0x");

        // should succeed
        hevm.warp(timestamp);
        assertEq(queueV2.nextCrossDomainMessageIndex(), 100);
        address sender = address(uint160(FakeMessenger) + uint160(0x1111000000000000000000000000000000001111));
        bytes32 hash0 = queueV2.computeTransactionHash(sender, 100, value, FakeSigner, gasLimit, data);
        bytes32 rhash0 = encodeHash(bytes32(0), hash0);
        hevm.expectEmit(true, true, false, true);
        emit QueueTransaction(sender, FakeSigner, value, 100, gasLimit, data);
        queueV2.appendEnforcedTransaction(sender, FakeSigner, value, gasLimit, data);
        assertEq(queueV2.nextCrossDomainMessageIndex(), 101);
        assertEq(queueV2.getMessageRollingHash(100), rhash0);
        assertEq(queueV2.getMessageEnqueueTimestamp(100), timestamp);

        hevm.warp(timestamp + 100);
        bytes32 hash1 = queueV2.computeTransactionHash(sender, 101, value, FakeSigner, gasLimit, data);
        bytes32 rhash1 = encodeHash(rhash0, hash1);
        hevm.expectEmit(true, true, false, true);
        emit QueueTransaction(sender, FakeSigner, value, 101, gasLimit, data);
        queueV2.appendEnforcedTransaction(sender, FakeSigner, value, gasLimit, data);
        assertEq(queueV2.nextCrossDomainMessageIndex(), 102);
        assertEq(queueV2.getMessageRollingHash(100), rhash0);
        assertEq(queueV2.getMessageEnqueueTimestamp(100), timestamp);
        assertEq(queueV2.getMessageRollingHash(101), rhash1);
        assertEq(queueV2.getMessageEnqueueTimestamp(101), timestamp + 100);

        hevm.stopPrank();
    }

    function testFinalizePoppedCrossDomainMessage() external {
        system.updateMessageQueueParameters(
            SystemConfig.MessageQueueParameters({maxGasLimit: 10000000, baseFeeOverhead: 0, baseFeeScalar: 0})
        );

        // should revert, when non-scrollChain call
        hevm.expectRevert(L1MessageQueueV2.ErrorCallerIsNotScrollChain.selector);
        queueV2.finalizePoppedCrossDomainMessage(0);

        // append 10 messages
        hevm.startPrank(FakeMessenger);
        for (uint256 i = 0; i < 10; i++) {
            queueV2.appendCrossDomainMessage(address(0), 1000000, "0x");
        }
        hevm.stopPrank();
        assertEq(queueV2.nextCrossDomainMessageIndex(), 110);
        assertEq(queueV2.nextUnfinalizedQueueIndex(), 100);

        // should revert, when finalized index too small
        hevm.startPrank(FakeScrollChain);
        hevm.expectRevert(L1MessageQueueV2.ErrorFinalizedIndexTooSmall.selector);
        queueV2.finalizePoppedCrossDomainMessage(99);
        hevm.stopPrank();

        // should revert, when finalized index too large
        hevm.startPrank(FakeScrollChain);
        hevm.expectRevert(L1MessageQueueV2.ErrorFinalizedIndexTooLarge.selector);
        queueV2.finalizePoppedCrossDomainMessage(111);
        hevm.stopPrank();

        // should succeed
        hevm.startPrank(FakeScrollChain);
        hevm.expectEmit(false, false, false, true);
        emit FinalizedDequeuedTransaction(100);
        queueV2.finalizePoppedCrossDomainMessage(101);
        assertEq(queueV2.nextCrossDomainMessageIndex(), 110);
        assertEq(queueV2.nextUnfinalizedQueueIndex(), 101);

        hevm.expectEmit(false, false, false, true);
        emit FinalizedDequeuedTransaction(109);
        queueV2.finalizePoppedCrossDomainMessage(110);
        assertEq(queueV2.nextCrossDomainMessageIndex(), 110);
        assertEq(queueV2.nextUnfinalizedQueueIndex(), 110);
        hevm.stopPrank();

        // should do nothing
        hevm.startPrank(FakeScrollChain);
        queueV2.finalizePoppedCrossDomainMessage(110);
        assertEq(queueV2.nextUnfinalizedQueueIndex(), 110);
        assertEq(queueV2.nextCrossDomainMessageIndex(), 110);
        assertEq(queueV2.nextUnfinalizedQueueIndex(), 110);
        hevm.stopPrank();
    }

    function encodeHash(bytes32 a, bytes32 b) internal pure returns (bytes32 value) {
        // solhint-disable-next-line no-inline-assembly
        assembly {
            mstore(0x00, a)
            mstore(0x20, b)
            value := keccak256(0x00, 0x40)
            value := shl(32, shr(32, value))
        }
    }
}
