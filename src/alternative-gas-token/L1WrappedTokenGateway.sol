// SPDX-License-Identifier: MIT

pragma solidity =0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {IL1ERC20Gateway} from "../L1/gateways/IL1ERC20Gateway.sol";
import {IWETH} from "../interfaces/IWETH.sol";

contract L1WrappedTokenGateway {
    using SafeERC20 for IERC20;

    /*************
     * Constants *
     *************/

    /// @dev The safe gas limit used to bridge WETH to L2.
    uint256 private constant SAFE_GAS_LIMIT = 200000;

    /// @notice The address of Wrapped Ether.
    address public immutable WETH;

    /// @notice The address of ERC20 gateway used to bridge WETH.
    address public immutable gateway;

    /***************
     * Constructor *
     ***************/

    constructor(address _weth, address _gateway) {
        WETH = _weth;
        gateway = _gateway;
    }

    /*****************************
     * Public Mutating Functions *
     *****************************/

    /// @notice Deposit ETH.
    /// @dev This will wrap ETH to WETH first and then deposit as WETH.
    /// @param _to The address of recipient in L2.
    /// @param _amount The amount of ETH to deposit.
    function deposit(address _to, uint256 _amount) external payable {
        IWETH(WETH).deposit{value: _amount}();

        IERC20(WETH).safeApprove(gateway, 0);
        IERC20(WETH).safeApprove(gateway, _amount);
        IL1ERC20Gateway(gateway).depositERC20{value: msg.value - _amount}(WETH, _to, _amount, SAFE_GAS_LIMIT);
    }
}
