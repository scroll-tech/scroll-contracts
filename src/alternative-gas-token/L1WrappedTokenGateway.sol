// SPDX-License-Identifier: MIT

pragma solidity =0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";

import {IL1ERC20Gateway} from "../L1/gateways/IL1ERC20Gateway.sol";
import {IWETH} from "../interfaces/IWETH.sol";

contract L1WrappedTokenGateway {
    using SafeERC20 for IERC20;

    /**********
     * Events *
     **********/

    /// @notice Emitted when someone wrap ETH to WETH and then deposit WETH from L1 to L2.
    /// @param from The address of sender in L1.
    /// @param to The address of recipient in L2.
    /// @param amount The amount of ETH will be deposited from L1 to L2.
    event DepositWrappedToken(address indexed from, address indexed to, uint256 amount);

    /*********
     * Error *
     *********/

    /// @dev Thrown when someone try to send ETH to this contract.
    error ErrorCallNotFromFeeRefund();

    /*************
     * Constants *
     *************/

    /// @dev The safe gas limit used to bridge WETH to L2.
    uint256 private constant SAFE_GAS_LIMIT = 450000;

    /// @dev The default value of `sender`.
    address private constant DEFAULT_SENDER = address(1);

    /// @notice The address of Wrapped Ether.
    address public immutable WETH;

    /// @notice The address of ERC20 gateway used to bridge WETH.
    address public immutable gateway;

    /*************
     * Variables *
     *************/

    /// @notice The address of caller who called `deposit`.
    /// @dev This will be reset after call `gateway.depositERC20`, which is used to
    /// prevent malicious user sending ETH to this contract.
    address public sender;

    /***************
     * Constructor *
     ***************/

    constructor(address _weth, address _gateway) {
        WETH = _weth;
        gateway = _gateway;

        sender = DEFAULT_SENDER;
    }

    /*****************************
     * Public Mutating Functions *
     *****************************/

    /// @dev Only receive cross domain fee refund
    receive() external payable {
        if (sender == DEFAULT_SENDER) {
            revert ErrorCallNotFromFeeRefund();
        }
    }

    /// @notice Deposit ETH.
    /// @dev This will wrap ETH to WETH first and then deposit as WETH.
    /// @param _to The address of recipient in L2.
    /// @param _amount The amount of ETH to deposit.
    function deposit(address _to, uint256 _amount) external payable {
        IWETH(WETH).deposit{value: _amount}();

        IERC20(WETH).safeApprove(gateway, 0);
        IERC20(WETH).safeApprove(gateway, _amount);
        sender = msg.sender;
        IL1ERC20Gateway(gateway).depositERC20{value: msg.value - _amount}(WETH, _to, _amount, SAFE_GAS_LIMIT);
        sender = DEFAULT_SENDER;

        emit DepositWrappedToken(msg.sender, _to, _amount);

        // refund exceed fee
        uint256 balance = address(this).balance;
        if (balance > 0) {
            Address.sendValue(payable(msg.sender), balance);
        }
    }
}
