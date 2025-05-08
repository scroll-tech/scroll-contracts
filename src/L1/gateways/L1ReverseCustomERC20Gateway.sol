// SPDX-License-Identifier: MIT

pragma solidity =0.8.24;

import {IL2ERC20Gateway} from "../../L2/gateways/IL2ERC20Gateway.sol";
import {IScrollERC20Upgradeable} from "../../libraries/token/IScrollERC20Upgradeable.sol";
import {IL1ScrollMessenger} from "../IL1ScrollMessenger.sol";
import {L1CustomERC20Gateway} from "./L1CustomERC20Gateway.sol";
import {L1ERC20Gateway} from "./L1ERC20Gateway.sol";

/// @title L1ReverseCustomERC20Gateway
/// @notice The `L1ReverseCustomERC20Gateway` is used to deposit layer 2 native ERC20 tokens on layer 1 and
/// finalize withdraw the tokens from layer 2.
/// @dev The deposited tokens are transferred to this gateway and then burned. On finalizing withdraw, the corresponding
/// tokens will be minted and transfer to the recipient.
contract L1ReverseCustomERC20Gateway is L1CustomERC20Gateway {
    /**********
     * Errors *
     **********/

    /// @dev Thrown when no l2 token exists.
    error ErrorNoCorrespondingL2Token();

    /***************
     * Constructor *
     ***************/

    /// @notice Constructor for `L1ReverseCustomERC20Gateway` implementation contract.
    ///
    /// @param _counterpart The address of `L2ReverseCustomERC20Gateway` contract in L2.
    /// @param _router The address of `L1GatewayRouter` contract in L1.
    /// @param _messenger The address of `L1ScrollMessenger` contract L1.
    constructor(
        address _counterpart,
        address _router,
        address _messenger
    ) L1CustomERC20Gateway(_counterpart, _router, _messenger) {
        _disableInitializers();
    }

    /**********************
     * Internal Functions *
     **********************/

    /// @inheritdoc L1ERC20Gateway
    function _beforeFinalizeWithdrawERC20(
        address _l1Token,
        address _l2Token,
        address _from,
        address _to,
        uint256 _amount,
        bytes calldata _data
    ) internal virtual override {
        super._beforeFinalizeWithdrawERC20(_l1Token, _l2Token, _from, _to, _amount, _data);

        IScrollERC20Upgradeable(_l1Token).mint(address(this), _amount);
    }

    /// @inheritdoc L1ERC20Gateway
    function _beforeDropMessage(
        address _token,
        address _receiver,
        uint256 _amount
    ) internal virtual override {
        super._beforeDropMessage(_token, _receiver, _amount);

        IScrollERC20Upgradeable(_token).mint(address(this), _amount);
    }

    /// @inheritdoc L1ERC20Gateway
    function _deposit(
        address _token,
        address _to,
        uint256 _amount,
        bytes memory _data,
        uint256 _gasLimit
    ) internal virtual override {
        super._deposit(_token, _to, _amount, _data, _gasLimit);

        IScrollERC20Upgradeable(_token).burn(address(this), _amount);
    }
}
