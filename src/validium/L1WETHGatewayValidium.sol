// SPDX-License-Identifier: MIT

pragma solidity =0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {IWETH} from "../interfaces/IWETH.sol";
import {IL1ERC20GatewayValidium} from "./IL1ERC20GatewayValidium.sol";

contract L1WETHGatewayValidium {
    using SafeERC20 for IERC20;

    /**********
     * Errors *
     **********/

    /// @notice The error thrown when the value is insufficient.
    error ErrorInsufficientValue();

    /*************
     * Constants *
     *************/

    /// @dev The gas limit for the deposit.
    uint256 private constant GAS_LIMIT = 1000000;

    /***********************
     * Immutable Variables *
     ***********************/

    /// @notice The address of `WETH` token.
    address public immutable WETH;

    /// @notice The address of `L1ERC20GatewayValidium` contract.
    address public immutable gateway;

    /***************
     * Constructor *
     ***************/

    constructor(address _WETH, address _gateway) {
        WETH = _WETH;
        gateway = _gateway;
    }

    /*****************************
     * Public Mutating Functions *
     *****************************/

    /// @notice Deposit ETH to L2 through the  `L1ERC20GatewayValidium` contract.
    /// @param _to The encrypted address of recipient in L2 to receive the token.
    function deposit(
        bytes memory _to,
        uint256 _amount,
        uint256 _keyId
    ) external payable {
        if (msg.value < _amount) revert ErrorInsufficientValue();

        // WETH deposit is safe.
        // slither-disable-next-line arbitrary-send-eth
        IWETH(WETH).deposit{value: _amount}();
        IERC20(WETH).safeApprove(gateway, _amount);
        IL1ERC20GatewayValidium(gateway).depositERC20{value: msg.value - _amount}(
            WETH,
            msg.sender,
            _to,
            _amount,
            GAS_LIMIT,
            _keyId
        );
    }
}
