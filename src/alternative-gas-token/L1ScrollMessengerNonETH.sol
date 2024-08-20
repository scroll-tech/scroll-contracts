// SPDX-License-Identifier: MIT

pragma solidity =0.8.24;

import {AddressUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/AddressUpgradeable.sol";

import {IL1MessageQueue} from "../L1/rollup/IL1MessageQueue.sol";
import {IScrollChain} from "../L1/rollup/IScrollChain.sol";
import {L1ScrollMessenger} from "../L1/L1ScrollMessenger.sol";
import {IMessageDropCallback} from "../libraries/callbacks/IMessageDropCallback.sol";
import {ScrollConstants} from "../libraries/constants/ScrollConstants.sol";
import {WithdrawTrieVerifier} from "../libraries/verifier/WithdrawTrieVerifier.sol";

contract L1ScrollMessengerNonETH is L1ScrollMessenger {
    /**********
     * Errors *
     **********/

    /// @dev Thrown when the message is duplicated.
    error ErrorDuplicatedMessage();

    /// @dev Thrown when caller pass non-zero value in `sendMessage`.
    error ErrorNonZeroValueFromCaller();

    /// @dev Thrown when caller pass non-zero value in `relayMessageWithProof`.
    error ErrorNonZeroValueFromCrossDomainCaller();

    /// @dev Thrown when the `msg.value` cannot cover cross domain fee.
    error ErrorInsufficientMsgValue();

    /// @dev Thrown when the message is executed before.
    error ErrorMessageExecuted();

    /// @dev Thrown when the message has not enqueued before.
    error ErrorMessageNotEnqueued();

    /// @dev Thrown when the message is dropped before.
    error ErrorMessageDropped();

    /// @dev Thrown when relay a message belonging to an unfinalized batch.
    error ErrorBatchNotFinalized();

    /// @dev Thrown when the provided merkle proof is invalid.
    error ErrorInvalidMerkleProof();

    /// @dev Thrown when call to message queue.
    error ErrorForbidToCallMessageQueue();

    /// @dev Thrown when the message sender is invalid.
    error ErrorInvalidMessageSender();

    /*************
     * Constants *
     *************/

    /// @notice The address of `L1NativeTokenGateway` contract.
    address public immutable nativeTokenGateway;

    /***************
     * Constructor *
     ***************/

    constructor(
        address _nativeTokenGateway,
        address _counterpart,
        address _rollup,
        address _messageQueue
    ) L1ScrollMessenger(_counterpart, _rollup, _messageQueue) {
        nativeTokenGateway = _nativeTokenGateway;
    }

    /**********************
     * Internal Functions *
     **********************/

    /// @inheritdoc L1ScrollMessenger
    function _sendMessage(
        address _to,
        uint256 _l2GasTokenValue,
        bytes memory _message,
        uint256 _gasLimit,
        address _refundAddress
    ) internal override {
        // if we want to pass value to L2, must call from `L1NativeTokenGateway`.
        if (_l2GasTokenValue > 0 && _msgSender() != nativeTokenGateway) {
            revert ErrorNonZeroValueFromCaller();
        }

        // compute the actual cross domain message calldata.
        uint256 _messageNonce = IL1MessageQueue(messageQueue).nextCrossDomainMessageIndex();
        bytes memory _xDomainCalldata = _encodeXDomainCalldata(
            _msgSender(),
            _to,
            _l2GasTokenValue,
            _messageNonce,
            _message
        );

        // compute and deduct the messaging fee to fee vault.
        uint256 _fee = IL1MessageQueue(messageQueue).estimateCrossDomainMessageFee(_gasLimit);
        if (msg.value < _fee) {
            revert ErrorInsufficientMsgValue();
        }
        if (_fee > 0) {
            AddressUpgradeable.sendValue(payable(feeVault), _fee);
        }

        // append message to L1MessageQueue
        IL1MessageQueue(messageQueue).appendCrossDomainMessage(counterpart, _gasLimit, _xDomainCalldata);

        // record the message hash for future use.
        bytes32 _xDomainCalldataHash = keccak256(_xDomainCalldata);

        // normally this won't happen, since each message has different nonce, but just in case.
        if (messageSendTimestamp[_xDomainCalldataHash] != 0) {
            revert ErrorDuplicatedMessage();
        }
        messageSendTimestamp[_xDomainCalldataHash] = block.timestamp;

        emit SentMessage(_msgSender(), _to, _l2GasTokenValue, _messageNonce, _gasLimit, _message);

        // refund fee to `_refundAddress`
        unchecked {
            uint256 _refund = msg.value - _fee;
            if (_refund > 0) {
                AddressUpgradeable.sendValue(payable(_refundAddress), _refund);
            }
        }
    }

    /// @inheritdoc L1ScrollMessenger
    function _relayMessageWithProof(
        address _from,
        address _to,
        uint256 _l2GasTokenValue,
        uint256 _nonce,
        bytes memory _message,
        L2MessageProof memory _proof
    ) internal virtual override {
        // if we want to pass value to L1, must call to `L1NativeTokenGateway`.
        if (_l2GasTokenValue > 0 && _to != nativeTokenGateway) {
            revert ErrorNonZeroValueFromCrossDomainCaller();
        }

        bytes32 _xDomainCalldataHash = keccak256(
            _encodeXDomainCalldata(_from, _to, _l2GasTokenValue, _nonce, _message)
        );
        if (isL2MessageExecuted[_xDomainCalldataHash]) {
            revert ErrorMessageExecuted();
        }

        {
            if (!IScrollChain(rollup).isBatchFinalized(_proof.batchIndex)) {
                revert ErrorBatchNotFinalized();
            }
            bytes32 _messageRoot = IScrollChain(rollup).withdrawRoots(_proof.batchIndex);
            if (
                !WithdrawTrieVerifier.verifyMerkleProof(_messageRoot, _xDomainCalldataHash, _nonce, _proof.merkleProof)
            ) {
                revert ErrorInvalidMerkleProof();
            }
        }

        // @note check more `_to` address to avoid attack in the future when we add more gateways.
        if (_to == messageQueue) {
            revert ErrorForbidToCallMessageQueue();
        }
        _validateTargetAddress(_to);

        // @note This usually will never happen, just in case.
        if (_from == xDomainMessageSender) {
            revert ErrorInvalidMessageSender();
        }

        xDomainMessageSender = _from;
        (bool success, ) = _to.call(_message);
        // reset value to refund gas.
        xDomainMessageSender = ScrollConstants.DEFAULT_XDOMAIN_MESSAGE_SENDER;

        if (success) {
            isL2MessageExecuted[_xDomainCalldataHash] = true;
            emit RelayedMessage(_xDomainCalldataHash);
        } else {
            emit FailedRelayedMessage(_xDomainCalldataHash);
        }
    }

    /// @inheritdoc L1ScrollMessenger
    function _dropMessage(
        address _from,
        address _to,
        uint256 _l2GasTokenValue,
        uint256 _messageNonce,
        bytes memory _message
    ) internal virtual override {
        // The criteria for dropping a message:
        // 1. The message is a L1 message.
        // 2. The message has not been dropped before.
        // 3. the message and all of its replacement are finalized in L1.
        // 4. the message and all of its replacement are skipped.
        //
        // Possible denial of service attack:
        // + replayMessage is called every time someone want to drop the message.
        // + replayMessage is called so many times for a skipped message, thus results a long list.
        //
        // We limit the number of `replayMessage` calls of each message, which may solve the above problem.

        // check message exists
        bytes memory _xDomainCalldata = _encodeXDomainCalldata(_from, _to, _l2GasTokenValue, _messageNonce, _message);
        bytes32 _xDomainCalldataHash = keccak256(_xDomainCalldata);
        if (messageSendTimestamp[_xDomainCalldataHash] == 0) {
            revert ErrorMessageNotEnqueued();
        }

        // check message not dropped
        if (isL1MessageDropped[_xDomainCalldataHash]) {
            revert ErrorMessageDropped();
        }

        // check message is finalized
        uint256 _lastIndex = replayStates[_xDomainCalldataHash].lastIndex;
        if (_lastIndex == 0) _lastIndex = _messageNonce;

        // check message is skipped and drop it.
        // @note If the list is very long, the message may never be dropped.
        while (true) {
            IL1MessageQueue(messageQueue).dropCrossDomainMessage(_lastIndex);
            _lastIndex = prevReplayIndex[_lastIndex];
            if (_lastIndex == 0) break;
            unchecked {
                _lastIndex = _lastIndex - 1;
            }
        }

        isL1MessageDropped[_xDomainCalldataHash] = true;

        // set execution context
        xDomainMessageSender = ScrollConstants.DROP_XDOMAIN_MESSAGE_SENDER;
        IMessageDropCallback(_from).onDropMessage(_message);
        // clear execution context
        xDomainMessageSender = ScrollConstants.DEFAULT_XDOMAIN_MESSAGE_SENDER;
    }
}
