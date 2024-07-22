// SPDX-License-Identifier: MIT

pragma solidity =0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {IL1ERC20Gateway} from "../L1/gateways/IL1ERC20Gateway.sol";
import {IWETH} from "../interfaces/IWETH.sol";

contract L1WrappedTokenGateway {
    using SafeERC20 for IERC20;

    uint256 public constant SAFE_GAS_LIMIT = 200000;

    address public immutable WETH;

    address public immutable gateway;

    constructor(address _weth, address _gateway) {
        WETH = _weth;
        gateway = _gateway;
    }

    function deposit(address _to, uint256 _amount) external payable {
        IWETH(WETH).deposit{value: _amount}();

        IERC20(WETH).safeApprove(gateway, 0);
        IERC20(WETH).safeApprove(gateway, _amount);
        IL1ERC20Gateway(gateway).depositERC20{value: msg.value - _amount}(WETH, _to, _amount, SAFE_GAS_LIMIT);
    }
}
