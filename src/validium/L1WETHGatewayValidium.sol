// SPDX-License-Identifier: MIT

pragma solidity =0.8.24;

import {IERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import {SafeERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";

import {IWETH} from "../interfaces/IWETH.sol";
import {IL1ERC20GatewayValidium} from "./IL1ERC20GatewayValidium.sol";

contract L1WETHGatewayValidium {
    using SafeERC20Upgradeable for IERC20Upgradeable;

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
    function deposit(bytes32 _to) external payable {
        IWETH(WETH).deposit{value: msg.value}();
        IERC20Upgradeable(WETH).safeTransfer(gateway, msg.value);
        IL1ERC20GatewayValidium(gateway).depositERC20(WETH, _to, msg.value, GAS_LIMIT);
    }
}
