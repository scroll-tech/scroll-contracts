// SPDX-License-Identifier: MIT

pragma solidity =0.8.24;

import {IERC20MetadataUpgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/IERC20MetadataUpgradeable.sol";

import {L1ScrollMessenger} from "./L1ScrollMessenger.sol";
import {IL2ERC20Gateway} from "../L2/gateways/IL2ERC20Gateway.sol";
import {ScrollMessengerBase} from "../libraries/ScrollMessengerBase.sol";

contract L1ScrollMessengerWithGasToken is L1ScrollMessenger {
    /*************
     * Constants *
     *************/

    /// @notice The L1 ERC20 token address that serves as gas token on L2.
    address public immutable gasToken;

    /// @notice The decimals of the gas token token on L1.
    uint8 public immutable gasTokenDecimals;

    /// @notice The address of wrapped ETH ERC20 token on L2.
    address public immutable l2Weth = address(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE);

    /// @notice The address of the L2 ETH gateway.
    address public immutable l2EthGateway;

    /***************
     * Constructor *
     ***************/

    constructor(
        address _counterpart,
        address _rollup,
        address _messageQueue,
        address _gasToken,
        address _l2EthGateway
    ) L1ScrollMessenger(_counterpart, _rollup, _messageQueue) {
        gasToken = _gasToken;
        l2EthGateway = _l2EthGateway;

        // retrieve gas token decimals
        gasTokenDecimals = IERC20MetadataUpgradeable(_gasToken).decimals();
        require(gasTokenDecimals <= 18 && gasTokenDecimals > 0, "Invalid gas token decimals");
    }

    /// @inheritdoc L1ScrollMessenger
    function initialize(
        address _counterpart,
        address _feeVault,
        address _rollup,
        address _messageQueue
    ) public virtual override initializer {
        ScrollMessengerBase.__ScrollMessengerBase_init(_counterpart, _feeVault);

        // __rollup = _rollup;
        // __messageQueue = _messageQueue;

        maxReplayTimes = 3;
        emit UpdateMaxReplayTimes(0, 3);
    }

    /**********************
     * Internal Functions *
     **********************/

    /// @inheritdoc ScrollMessengerBase
    function _encodeL1L2XDomainCalldata(
        address _sender,
        address _target,
        uint256 _value,
        uint256 _messageNonce,
        bytes calldata _message
    ) internal view virtual override returns (bytes memory) {
        bytes memory newMessage;
        (_target, _value, newMessage) = _translate(_target, _value, _message);

        return
            abi.encodeWithSignature(
                "relayMessage(address,address,uint256,uint256,bytes)",
                _sender,
                _target,
                _value,
                _messageNonce,
                newMessage
            );
    }

    function _translate(
        address _originalTo,
        uint256 _originalETHValue,
        bytes calldata _originalMessage
    )
        internal
        view
        returns (
            address,
            uint256,
            bytes memory
        )
    {
        // decode
        address decodedL1Token;
        address decodedFrom;
        address decodedTo;
        uint256 decodedAmount;

        if (bytes4(_originalMessage[0:4]) == IL2ERC20Gateway.finalizeDepositERC20.selector) {
            (
                decodedL1Token, /*decodedL2Token*/
                ,
                decodedFrom,
                decodedTo,
                decodedAmount, /*decodedData*/

            ) = abi.decode(_originalMessage[4:], (address, address, address, address, uint256, bytes));
        }

        // decide what kind of deposit this is
        bool isETHDeposit = _originalETHValue != 0;
        bool isGasTokenDeposit = decodedL1Token == gasToken;
        bool isERC20TokenDeposit = !isGasTokenDeposit && decodedL1Token != address(0);

        // we deposit gas token and ETH at the same time
        if (isETHDeposit && isGasTokenDeposit) {
            // construct deposit message for L2 wETH
            bytes memory erc20DepositMessage = abi.encodeCall(
                IL2ERC20Gateway.finalizeDepositERC20,
                (address(0), l2Weth, decodedFrom, decodedTo, _originalETHValue, "")
            );

            // send it to L2 gateway that processes ETH deposits
            uint256 l2Amount = _convertGasTokenAmount(decodedAmount);
            return (l2EthGateway, l2Amount, erc20DepositMessage);
        }
        // only gas token deposit
        else if (isGasTokenDeposit) {
            // translate into a simple deposit message
            uint256 l2Amount = _convertGasTokenAmount(decodedAmount);
            return (decodedTo, l2Amount, "");
        }
        // plain old ETH deposit, or ETH-carrying custom message
        else if (isETHDeposit) {
            if (isERC20TokenDeposit) {
                revert("Cannot deposit ETH together with other token");
            }

            // construct deposit message for L2 wETH
            bytes memory erc20DepositMessage = abi.encodeCall(
                IL2ERC20Gateway.finalizeDepositERC20,
                (address(0), l2Weth, _msgSender(), _originalTo, _originalETHValue, _originalMessage)
            );

            // send it to L2 gateway that processes ETH deposits
            return (l2EthGateway, 0, erc20DepositMessage);
        }
        // other ERC20 deposit or custom message
        else {
            return (_originalTo, _originalETHValue, _originalMessage);
        }
    }

    function _convertGasTokenAmount(uint256 amount) public view returns (uint256) {
        uint256 exponent = 18 - gasTokenDecimals;
        return amount * 10**exponent;
    }
}
