// SPDX-License-Identifier: MIT
pragma solidity =0.8.24;

import {IScrollMessenger} from "../libraries/IScrollMessenger.sol";
import {IWhitelist} from "../libraries/common/IWhitelist.sol";

import {L1ScrollMessenger} from "../L1/L1ScrollMessenger.sol";

// solhint-disable avoid-low-level-calls
// solhint-disable not-rely-on-time
// solhint-disable reason-string

/// @title L1ScrollMessengerValidium
contract L1ScrollMessengerValidium is L1ScrollMessenger {
    /**********
     * Errors *
     **********/

    /// @dev Thrown when the sender is not allowed to send message.
    error ErrorSenderNotAllowed();

    /*************
     * Constants *
     *************/

    /// @notice The address of whitelist contract.
    address public immutable whitelist;

    /***************
     * Constructor *
     ***************/

    constructor(
        address _counterpart,
        address _rollup,
        address _messageQueueV2,
        address _whitelist
    ) L1ScrollMessenger(_counterpart, _rollup, address(0), _messageQueueV2, address(0)) {
        _disableInitializers();
        whitelist = _whitelist;
    }

    /**********************
     * Internal Functions *
     **********************/

    /// @inheritdoc L1ScrollMessenger
    function _sendMessage(
        address _to,
        uint256 _value,
        bytes memory _message,
        uint256 _gasLimit,
        address _refundAddress
    ) internal virtual override {
        if (!IWhitelist(whitelist).isSenderAllowed(_msgSender())) revert ErrorSenderNotAllowed();

        super._sendMessage(_to, _value, _message, _gasLimit, _refundAddress);
    }
}
