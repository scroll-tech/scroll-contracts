// SPDX-License-Identifier: MIT

pragma solidity =0.8.24;

import {MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";

import {ITransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import {L1ScrollMessengerNonETH} from "../../alternative-gas-token/L1ScrollMessengerNonETH.sol";
import {IL1ScrollMessenger} from "../../L1/IL1ScrollMessenger.sol";
import {AddressAliasHelper} from "../../libraries/common/AddressAliasHelper.sol";
import {ScrollConstants} from "../../libraries/constants/ScrollConstants.sol";

import {AlternativeGasTokenTestBase} from "./AlternativeGasTokenTestBase.t.sol";

contract L1ScrollMessengerNonETHForTest is L1ScrollMessengerNonETH {
    constructor(
        address _nativeTokenGateway,
        address _counterpart,
        address _rollup,
        address _messageQueue
    ) L1ScrollMessengerNonETH(_nativeTokenGateway, _counterpart, _rollup, _messageQueue) {}

    function setMessageSendTimestamp(bytes32 hash, uint256 value) external {
        messageSendTimestamp[hash] = value;
    }
}

contract L1ScrollMessengerNonETHTest is AlternativeGasTokenTestBase {
    event OnDropMessageCalled(uint256, bytes);

    event OnRelayMessageWithProof(uint256, bytes);

    MockERC20 private gasToken;

    receive() external payable {}

    function setUp() external {
        gasToken = new MockERC20("X", "Y", 18);

        __AlternativeGasTokenTestBase_setUp(1234, address(gasToken));
    }

    function testInitialization() external view {
        assertEq(l1Messenger.nativeTokenGateway(), address(l1GasTokenGateway));
        assertEq(l1Messenger.messageQueue(), address(l1MessageQueue));
        assertEq(l1Messenger.rollup(), address(rollup));
    }

    function testSendMessageRevertOnErrorNonZeroValueFromCaller(uint256 value) external {
        vm.assume(value > 0);
        // revert ErrorNonZeroValueFromCaller
        vm.expectRevert(L1ScrollMessengerNonETH.ErrorNonZeroValueFromCaller.selector);
        l1Messenger.sendMessage(address(0), value, new bytes(0), 0);
    }

    function testSendMessageRevertOnErrorInsufficientMsgValue(
        uint256 l2BaseFee,
        uint256 gasLimit,
        bytes memory message
    ) external {
        bytes memory encoded = encodeXDomainCalldata(address(this), address(0), 0, 0, message);
        vm.assume(encoded.length < 60000);
        gasLimit = bound(gasLimit, encoded.length * 16 + 21000, 1000000);
        l2BaseFee = bound(l2BaseFee, 1, 1 ether);

        l1MessageQueue.setL2BaseFee(l2BaseFee);

        // revert ErrorInsufficientMsgValue
        vm.expectRevert(L1ScrollMessengerNonETH.ErrorInsufficientMsgValue.selector);
        l1Messenger.sendMessage{value: gasLimit * l2BaseFee - 1}(address(0), 0, message, gasLimit);
    }

    function testSendMessageRevertOnErrorDuplicatedMessage(
        address target,
        uint256 gasLimit,
        bytes memory message
    ) external {
        bytes memory encoded = encodeXDomainCalldata(address(this), target, 0, 0, message);
        vm.assume(encoded.length < 60000);
        gasLimit = bound(gasLimit, encoded.length * 16 + 21000, 1000000);

        admin.upgrade(
            ITransparentUpgradeableProxy(address(l1Messenger)),
            address(
                new L1ScrollMessengerNonETHForTest(
                    address(l1GasTokenGateway),
                    address(l2Messenger),
                    address(rollup),
                    address(l1MessageQueue)
                )
            )
        );
        L1ScrollMessengerNonETHForTest(payable(address(l1Messenger))).setMessageSendTimestamp(keccak256(encoded), 1);
        l1MessageQueue.setL2BaseFee(0);

        // revert ErrorDuplicatedMessage
        vm.expectRevert(L1ScrollMessengerNonETH.ErrorDuplicatedMessage.selector);
        l1Messenger.sendMessage(target, 0, message, gasLimit);
    }

    function testSendMessage(
        uint256 l2BaseFee,
        address target,
        uint256 gasLimit,
        bytes memory message,
        uint256 exceedValue,
        address refundAddress
    ) external {
        vm.assume(refundAddress.code.length == 0); // only refund to EOA to avoid revert
        vm.assume(uint256(uint160(refundAddress)) > 2**152); // ignore some precompile contracts
        vm.assume(refundAddress != l1FeeVault);

        uint256 NONZERO_TIMESTAMP = 123456;
        vm.warp(NONZERO_TIMESTAMP);

        bytes memory encoded0 = encodeXDomainCalldata(address(this), target, 0, 0, message);
        bytes memory encoded1 = encodeXDomainCalldata(address(this), target, 0, 1, message);
        bytes memory encoded2 = encodeXDomainCalldata(address(this), target, 0, 2, message);
        vm.assume(encoded0.length < 60000);

        gasLimit = bound(gasLimit, encoded0.length * 16 + 21000, 1000000);
        exceedValue = bound(exceedValue, 1, address(this).balance / 2);
        l2BaseFee = bound(l2BaseFee, 1, 1 ether);

        l1MessageQueue.setL2BaseFee(l2BaseFee);

        assertEq(l1MessageQueue.nextCrossDomainMessageIndex(), 0);

        // send message 0, exact fee
        // emit QueueTransaction from L1MessageQueue
        {
            vm.expectEmit(true, true, false, true);
            address sender = AddressAliasHelper.applyL1ToL2Alias(address(l1Messenger));
            emit QueueTransaction(sender, address(l2Messenger), 0, 0, gasLimit, encoded0);
        }
        // emit SentMessage from L1ScrollMessengerNonETH
        {
            vm.expectEmit(true, true, false, true);
            emit SentMessage(address(this), target, 0, 0, gasLimit, message);
        }
        uint256 thisBalance = address(this).balance;
        assertEq(l1Messenger.messageSendTimestamp(keccak256(encoded0)), 0);
        l1Messenger.sendMessage{value: gasLimit * l2BaseFee}(target, 0, message, gasLimit);
        assertEq(address(this).balance, thisBalance - gasLimit * l2BaseFee);
        assertEq(l1MessageQueue.nextCrossDomainMessageIndex(), 1);
        assertEq(l1Messenger.messageSendTimestamp(keccak256(encoded0)), NONZERO_TIMESTAMP);

        // send message 1, over fee, refund to self
        // emit QueueTransaction from L1MessageQueue
        {
            vm.expectEmit(true, true, false, true);
            address sender = AddressAliasHelper.applyL1ToL2Alias(address(l1Messenger));
            emit QueueTransaction(sender, address(l2Messenger), 0, 1, gasLimit, encoded1);
        }
        // emit SentMessage from L1ScrollMessengerNonETH
        {
            vm.expectEmit(true, true, false, true);
            emit SentMessage(address(this), target, 0, 1, gasLimit, message);
        }
        thisBalance = address(this).balance;
        assertEq(l1Messenger.messageSendTimestamp(keccak256(encoded1)), 0);
        l1Messenger.sendMessage{value: gasLimit * l2BaseFee + exceedValue}(target, 0, message, gasLimit);
        assertEq(address(this).balance, thisBalance - gasLimit * l2BaseFee);
        assertEq(l1MessageQueue.nextCrossDomainMessageIndex(), 2);
        assertEq(l1Messenger.messageSendTimestamp(keccak256(encoded1)), NONZERO_TIMESTAMP);

        // send message 2, over fee, refund to other
        // emit QueueTransaction from L1MessageQueue
        {
            vm.expectEmit(true, true, false, true);
            address sender = AddressAliasHelper.applyL1ToL2Alias(address(l1Messenger));
            emit QueueTransaction(sender, address(l2Messenger), 0, 2, gasLimit, encoded2);
        }
        // emit SentMessage from L1ScrollMessengerNonETH
        {
            vm.expectEmit(true, true, false, true);
            emit SentMessage(address(this), target, 0, 2, gasLimit, message);
        }
        thisBalance = address(this).balance;
        uint256 refundBalance = refundAddress.balance;
        assertEq(l1Messenger.messageSendTimestamp(keccak256(encoded2)), 0);
        l1Messenger.sendMessage{value: gasLimit * l2BaseFee + exceedValue}(target, 0, message, gasLimit, refundAddress);
        assertEq(address(this).balance, thisBalance - gasLimit * l2BaseFee - exceedValue);
        assertEq(refundAddress.balance, refundBalance + exceedValue);
        assertEq(l1MessageQueue.nextCrossDomainMessageIndex(), 3);
        assertEq(l1Messenger.messageSendTimestamp(keccak256(encoded2)), NONZERO_TIMESTAMP);
    }

    function testRelayMessageWithProofRevertOnErrorNonZeroValueFromCrossDomainCaller(
        address sender,
        address target,
        uint256 value,
        uint256 nonce,
        bytes memory message,
        IL1ScrollMessenger.L2MessageProof memory proof
    ) external {
        vm.assume(value > 0);
        vm.assume(target != address(l1GasTokenGateway));

        // revert ErrorNonZeroValueFromCrossDomainCaller
        vm.expectRevert(L1ScrollMessengerNonETH.ErrorNonZeroValueFromCrossDomainCaller.selector);
        l1Messenger.relayMessageWithProof(sender, target, value, nonce, message, proof);
    }

    function testRelayMessageWithProofRevertOnErrorMessageExecuted(
        address sender,
        address target,
        uint256 nonce,
        bytes memory message
    ) external {
        vm.assume(target.code.length == 0); // only refund to EOA to avoid revert
        vm.assume(uint256(uint160(target)) > 2**152); // ignore some precompile contracts
        vm.assume(uint256(uint160(sender)) > 2**152); // ignore some precompile contracts

        prepareFinalizedBatch(keccak256(encodeXDomainCalldata(sender, target, 0, nonce, message)));
        IL1ScrollMessenger.L2MessageProof memory proof;
        proof.batchIndex = rollup.lastFinalizedBatchIndex();

        l1Messenger.relayMessageWithProof(sender, target, 0, nonce, message, proof);

        // revert ErrorMessageExecuted
        vm.expectRevert(L1ScrollMessengerNonETH.ErrorMessageExecuted.selector);
        l1Messenger.relayMessageWithProof(sender, target, 0, nonce, message, proof);
    }

    function testRelayMessageWithProofRevertOnErrorBatchNotFinalized(
        address sender,
        address target,
        uint256 nonce,
        bytes memory message
    ) external {
        vm.assume(target.code.length == 0); // only refund to EOA to avoid revert
        vm.assume(uint256(uint160(target)) > 2**152); // ignore some precompile contracts

        prepareFinalizedBatch(keccak256(encodeXDomainCalldata(sender, target, 0, nonce, message)));
        IL1ScrollMessenger.L2MessageProof memory proof;
        proof.batchIndex = rollup.lastFinalizedBatchIndex() + 1;

        // revert ErrorBatchNotFinalized
        vm.expectRevert(L1ScrollMessengerNonETH.ErrorBatchNotFinalized.selector);
        l1Messenger.relayMessageWithProof(sender, target, 0, nonce, message, proof);
    }

    function testRelayMessageWithProofRevertOnErrorInvalidMerkleProof(
        address sender,
        address target,
        uint256 nonce,
        bytes memory message,
        IL1ScrollMessenger.L2MessageProof memory proof
    ) external {
        vm.assume(target.code.length == 0); // only refund to EOA to avoid revert
        vm.assume(uint256(uint160(target)) > 2**152); // ignore some precompile contracts
        vm.assume(proof.merkleProof.length > 0);
        vm.assume(proof.merkleProof.length % 32 == 0);

        prepareFinalizedBatch(keccak256(encodeXDomainCalldata(sender, target, 0, nonce, message)));
        proof.batchIndex = rollup.lastFinalizedBatchIndex();

        // revert ErrorInvalidMerkleProof
        vm.expectRevert(L1ScrollMessengerNonETH.ErrorInvalidMerkleProof.selector);
        l1Messenger.relayMessageWithProof(sender, target, 0, nonce, message, proof);
    }

    function testRelayMessageWithProofRevertOnErrorForbidToCallMessageQueue(
        address sender,
        uint256 nonce,
        bytes memory message
    ) external {
        address target = address(l1MessageQueue);

        prepareFinalizedBatch(keccak256(encodeXDomainCalldata(sender, target, 0, nonce, message)));
        IL1ScrollMessenger.L2MessageProof memory proof;
        proof.batchIndex = rollup.lastFinalizedBatchIndex();

        // revert ErrorForbidToCallMessageQueue
        vm.expectRevert(L1ScrollMessengerNonETH.ErrorForbidToCallMessageQueue.selector);
        l1Messenger.relayMessageWithProof(sender, target, 0, nonce, message, proof);
    }

    function testRelayMessageWithProofRevertOnCallSelfFromL2(
        address sender,
        uint256 nonce,
        bytes memory message
    ) external {
        address target = address(l1Messenger);

        prepareFinalizedBatch(keccak256(encodeXDomainCalldata(sender, target, 0, nonce, message)));
        IL1ScrollMessenger.L2MessageProof memory proof;
        proof.batchIndex = rollup.lastFinalizedBatchIndex();

        // revert when call self
        vm.expectRevert("Forbid to call self");
        l1Messenger.relayMessageWithProof(sender, target, 0, nonce, message, proof);
    }

    function testRelayMessageWithProofRevertOnErrorInvalidMessageSender(
        address target,
        uint256 nonce,
        bytes memory message
    ) external {
        vm.assume(target.code.length == 0); // only refund to EOA to avoid revert
        vm.assume(uint256(uint160(target)) > 2**152); // ignore some precompile contracts
        address sender = ScrollConstants.DEFAULT_XDOMAIN_MESSAGE_SENDER;

        prepareFinalizedBatch(keccak256(encodeXDomainCalldata(sender, target, 0, nonce, message)));
        IL1ScrollMessenger.L2MessageProof memory proof;
        proof.batchIndex = rollup.lastFinalizedBatchIndex();

        // revert ErrorInvalidMessageSender
        vm.expectRevert(L1ScrollMessengerNonETH.ErrorInvalidMessageSender.selector);
        l1Messenger.relayMessageWithProof(sender, target, 0, nonce, message, proof);
    }

    bool revertOnRelayMessageWithProof;

    function onRelayMessageWithProof(bytes memory message) external payable {
        emit OnRelayMessageWithProof(msg.value, message);

        if (revertOnRelayMessageWithProof) revert();
    }

    function testRelayMessageWithProofFailed(
        address sender,
        uint256 nonce,
        bytes memory message
    ) external {
        vm.assume(sender != ScrollConstants.DEFAULT_XDOMAIN_MESSAGE_SENDER);

        revertOnRelayMessageWithProof = true;
        bytes memory encoded = abi.encodeCall(L1ScrollMessengerNonETHTest.onRelayMessageWithProof, (message));
        address target = address(this);

        bytes32 hash = keccak256(encodeXDomainCalldata(sender, target, 0, nonce, encoded));
        prepareFinalizedBatch(hash);
        IL1ScrollMessenger.L2MessageProof memory proof;
        proof.batchIndex = rollup.lastFinalizedBatchIndex();

        assertEq(l1Messenger.isL2MessageExecuted(hash), false);
        vm.expectEmit(true, false, false, true);
        emit FailedRelayedMessage(hash);
        l1Messenger.relayMessageWithProof(sender, target, 0, nonce, encoded, proof);
        assertEq(l1Messenger.isL2MessageExecuted(hash), false);
    }

    function testRelayMessageWithProofSucceed(
        address sender,
        uint256 nonce,
        bytes memory message
    ) external {
        vm.assume(sender != ScrollConstants.DEFAULT_XDOMAIN_MESSAGE_SENDER);

        revertOnRelayMessageWithProof = false;
        bytes memory encoded = abi.encodeCall(L1ScrollMessengerNonETHTest.onRelayMessageWithProof, (message));
        address target = address(this);

        bytes32 hash = keccak256(encodeXDomainCalldata(sender, target, 0, nonce, encoded));
        prepareFinalizedBatch(hash);
        IL1ScrollMessenger.L2MessageProof memory proof;
        proof.batchIndex = rollup.lastFinalizedBatchIndex();

        assertEq(l1Messenger.isL2MessageExecuted(hash), false);
        vm.expectEmit(false, false, false, true);
        emit OnRelayMessageWithProof(0, message);
        vm.expectEmit(true, false, false, true);
        emit RelayedMessage(hash);
        l1Messenger.relayMessageWithProof(sender, target, 0, nonce, encoded, proof);
        assertEq(l1Messenger.isL2MessageExecuted(hash), true);
    }

    function onDropMessage(bytes memory message) external payable {
        emit OnDropMessageCalled(msg.value, message);
    }

    function testDropMessageRevertOnErrorMessageNotEnqueued(
        address sender,
        address target,
        uint256 value,
        uint256 messageNonce,
        bytes memory message
    ) external {
        // revert on ErrorMessageNotEnqueued
        vm.expectRevert(L1ScrollMessengerNonETH.ErrorMessageNotEnqueued.selector);
        l1Messenger.dropMessage(sender, target, value, messageNonce, message);
    }

    function testDropMessage(
        address target,
        bytes memory message,
        uint32 gasLimit
    ) external {
        bytes memory encoded = encodeXDomainCalldata(address(this), target, 0, 0, message);
        vm.assume(encoded.length < 60000);
        gasLimit = uint32(bound(gasLimit, encoded.length * 16 + 21000, 1000000));

        l1MessageQueue.setL2BaseFee(0);

        // send one message with nonce 0
        l1Messenger.sendMessage(target, 0, message, gasLimit);
        assertEq(l1MessageQueue.nextCrossDomainMessageIndex(), 1);

        // drop pending message, revert
        vm.expectRevert("cannot drop pending message");
        l1Messenger.dropMessage(address(this), target, 0, 0, message);

        l1Messenger.updateMaxReplayTimes(10);

        // replay 1 time
        l1Messenger.replayMessage(address(this), target, 0, 0, message, gasLimit, address(0));
        assertEq(l1MessageQueue.nextCrossDomainMessageIndex(), 2);

        // skip all 2 messages
        vm.startPrank(address(rollup));
        l1MessageQueue.popCrossDomainMessage(0, 2, 0x3);
        l1MessageQueue.finalizePoppedCrossDomainMessage(2);
        assertEq(l1MessageQueue.nextUnfinalizedQueueIndex(), 2);
        assertEq(l1MessageQueue.pendingQueueIndex(), 2);
        vm.stopPrank();
        for (uint256 i = 0; i < 2; ++i) {
            assertEq(l1MessageQueue.isMessageSkipped(i), true);
            assertEq(l1MessageQueue.isMessageDropped(i), false);
        }
        vm.expectEmit(false, false, false, true);
        emit OnDropMessageCalled(0, message);
        l1Messenger.dropMessage(address(this), target, 0, 0, message);
        for (uint256 i = 0; i < 2; ++i) {
            assertEq(l1MessageQueue.isMessageSkipped(i), true);
            assertEq(l1MessageQueue.isMessageDropped(i), true);
        }

        // send one message with nonce 2 and replay 3 times
        l1Messenger.sendMessage(target, 0, message, gasLimit);
        assertEq(l1MessageQueue.nextCrossDomainMessageIndex(), 3);
        for (uint256 i = 0; i < 3; i++) {
            l1Messenger.replayMessage(address(this), target, 0, 2, message, gasLimit, address(0));
        }
        assertEq(l1MessageQueue.nextCrossDomainMessageIndex(), 6);

        // only first 3 are skipped
        vm.startPrank(address(rollup));
        l1MessageQueue.popCrossDomainMessage(2, 4, 0x7);
        l1MessageQueue.finalizePoppedCrossDomainMessage(6);
        assertEq(l1MessageQueue.nextUnfinalizedQueueIndex(), 6);
        assertEq(l1MessageQueue.pendingQueueIndex(), 6);
        vm.stopPrank();
        for (uint256 i = 2; i < 6; i++) {
            assertEq(l1MessageQueue.isMessageSkipped(i), i < 5);
            assertEq(l1MessageQueue.isMessageDropped(i), false);
        }

        // drop non-skipped message, revert
        vm.expectRevert("drop non-skipped message");
        l1Messenger.dropMessage(address(this), target, 0, 2, message);

        // send one message with nonce 6 and replay 4 times
        l1Messenger.sendMessage(target, 0, message, gasLimit);
        for (uint256 i = 0; i < 4; i++) {
            l1Messenger.replayMessage(address(this), target, 0, 6, message, gasLimit, address(0));
        }
        assertEq(l1MessageQueue.nextCrossDomainMessageIndex(), 11);

        // skip all 5 messages
        vm.startPrank(address(rollup));
        l1MessageQueue.popCrossDomainMessage(6, 5, 0x1f);
        l1MessageQueue.finalizePoppedCrossDomainMessage(11);
        assertEq(l1MessageQueue.nextUnfinalizedQueueIndex(), 11);
        assertEq(l1MessageQueue.pendingQueueIndex(), 11);
        vm.stopPrank();
        for (uint256 i = 6; i < 11; ++i) {
            assertEq(l1MessageQueue.isMessageSkipped(i), true);
            assertEq(l1MessageQueue.isMessageDropped(i), false);
        }
        vm.expectEmit(false, false, false, true);
        emit OnDropMessageCalled(0, message);
        l1Messenger.dropMessage(address(this), target, 0, 6, message);
        for (uint256 i = 6; i < 11; ++i) {
            assertEq(l1MessageQueue.isMessageSkipped(i), true);
            assertEq(l1MessageQueue.isMessageDropped(i), true);
        }

        // Message already dropped, revert
        vm.expectRevert(L1ScrollMessengerNonETH.ErrorMessageDropped.selector);
        l1Messenger.dropMessage(address(this), target, 0, 0, message);
        vm.expectRevert(L1ScrollMessengerNonETH.ErrorMessageDropped.selector);
        l1Messenger.dropMessage(address(this), target, 0, 6, message);

        // replay dropped message, revert
        vm.expectRevert("Message already dropped");
        l1Messenger.replayMessage(address(this), target, 0, 0, message, gasLimit, address(0));
        vm.expectRevert("Message already dropped");
        l1Messenger.replayMessage(address(this), target, 0, 6, message, gasLimit, address(0));
    }
}
