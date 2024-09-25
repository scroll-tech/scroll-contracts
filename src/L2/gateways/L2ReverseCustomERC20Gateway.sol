// SPDX-License-Identifier: MIT

pragma solidity =0.8.24;

import {IERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import {SafeERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import {AddressUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/AddressUpgradeable.sol";

import {IL1ERC20Gateway} from "../../L1/gateways/IL1ERC20Gateway.sol";
import {IL2ScrollMessenger} from "../IL2ScrollMessenger.sol";
import {IL2ERC20Gateway, L2ERC20Gateway} from "./L2ERC20Gateway.sol";
import {L2CustomERC20Gateway} from "./L2CustomERC20Gateway.sol";

/// @title L2ReverseCustomERC20Gateway
/// @notice The `L2ReverseCustomERC20Gateway` is used to withdraw native ERC20 tokens on layer 2 and
/// finalize deposit the tokens from layer 1.
/// @dev The withdrawn ERC20 tokens are holed in this contract. On finalizing deposit, the corresponding
/// token will be transferred to the recipient.
contract L2ReverseCustomERC20Gateway is L2CustomERC20Gateway {
    using SafeERC20Upgradeable for IERC20Upgradeable;

    /**********
     * Errors *
     **********/

    /// @dev Thrown when the message value is not zero.
    error ErrorNonzeroMsgValue();

    /// @dev Thrown when the given l1 token address is zero.
    error ErrorL1TokenAddressIsZero();

    /// @dev Thrown when the given l1 token address not match stored one.
    error ErrorL1TokenAddressMismatch();

    /// @dev Thrown when no l1 token exists.
    error ErrorNoCorrespondingL1Token();

    /// @dev Thrown when withdraw zero amount token.
    error ErrorWithdrawZeroAmount();

    /***************
     * Constructor *
     ***************/

    /// @notice Constructor for `L2ReverseCustomERC20Gateway` implementation contract.
    ///
    /// @param _counterpart The address of `L1ReverseCustomERC20Gateway` contract in L1.
    /// @param _router The address of `L2GatewayRouter` contract in L2.
    /// @param _messenger The address of `L2ScrollMessenger` contract in L2.
    constructor(
        address _counterpart,
        address _router,
        address _messenger
    ) L2CustomERC20Gateway(_counterpart, _router, _messenger) {
        _disableInitializers();
    }

    /*****************************
     * Public Mutating Functions *
     *****************************/

    /// @inheritdoc IL2ERC20Gateway
    function finalizeDepositERC20(
        address _l1Token,
        address _l2Token,
        address _from,
        address _to,
        uint256 _amount,
        bytes calldata _data
    ) external payable override onlyCallByCounterpart nonReentrant {
        if (msg.value != 0) revert ErrorNonzeroMsgValue();
        if (_l1Token == address(0)) revert ErrorL1TokenAddressIsZero();
        if (_l1Token != tokenMapping[_l2Token]) revert ErrorL1TokenAddressMismatch();

        IERC20Upgradeable(_l2Token).safeTransfer(_to, _amount);

        _doCallback(_to, _data);

        emit FinalizeDepositERC20(_l1Token, _l2Token, _from, _to, _amount, _data);
    }

    /**********************
     * Internal Functions *
     **********************/

    /// @inheritdoc L2ERC20Gateway
    function _withdraw(
        address _token,
        address _to,
        uint256 _amount,
        bytes memory _data,
        uint256 _gasLimit
    ) internal virtual override nonReentrant {
        address _l1Token = tokenMapping[_token];
        if (_l1Token == address(0)) revert ErrorNoCorrespondingL1Token();
        if (_amount == 0) revert ErrorWithdrawZeroAmount();

        // 1. Extract real sender if this call is from L2GatewayRouter.
        address _from = _msgSender();
        if (router == _from) {
            (_from, _data) = abi.decode(_data, (address, bytes));
        }

        // 2. transfer token to this contract
        uint256 balance = IERC20Upgradeable(_token).balanceOf(address(this));
        IERC20Upgradeable(_token).safeTransferFrom(_from, address(this), _amount);
        _amount = IERC20Upgradeable(_token).balanceOf(address(this)) - balance;

        // 3. Generate message passed to L1ReverseCustomERC20Gateway.
        bytes memory _message = abi.encodeCall(
            IL1ERC20Gateway.finalizeWithdrawERC20,
            (_l1Token, _token, _from, _to, _amount, _data)
        );

        // 4. send message to L2ScrollMessenger
        IL2ScrollMessenger(messenger).sendMessage{value: msg.value}(counterpart, 0, _message, _gasLimit);

        emit WithdrawERC20(_l1Token, _token, _from, _to, _amount, _data);
    }
}
