// SPDX-License-Identifier: MIT

pragma solidity =0.8.24;

import {MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";

import {ITransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import {IL1ScrollMessenger} from "../../L1/IL1ScrollMessenger.sol";
import {L2StandardERC20Gateway} from "../../L2/gateways/L2StandardERC20Gateway.sol";
import {WrappedEther} from "../../L2/predeploys/WrappedEther.sol";
import {ScrollStandardERC20} from "../../libraries/token/ScrollStandardERC20.sol";
import {ScrollStandardERC20Factory} from "../../libraries/token/ScrollStandardERC20Factory.sol";
import {AddressAliasHelper} from "../../libraries/common/AddressAliasHelper.sol";
import {IL1ERC20GatewayValidium} from "../../validium/IL1ERC20GatewayValidium.sol";
import {IL2ERC20GatewayValidium} from "../../validium/IL2ERC20GatewayValidium.sol";
import {L1ERC20GatewayValidium} from "../../validium/L1ERC20GatewayValidium.sol";
import {L1WETHGatewayValidium} from "../../validium/L1WETHGatewayValidium.sol";

import {TransferReentrantToken} from "../mocks/tokens/TransferReentrantToken.sol";
import {FeeOnTransferToken} from "../mocks/tokens/FeeOnTransferToken.sol";
import {MockScrollMessenger} from "../mocks/MockScrollMessenger.sol";
import {MockGatewayRecipient} from "../mocks/MockGatewayRecipient.sol";

import {ValidiumTestBase} from "./ValidiumTestBase.t.sol";

contract L1WETHGatewayValidiumTest is ValidiumTestBase {
    event FinalizeWithdrawERC20(
        address indexed _l1Token,
        address indexed _l2Token,
        address indexed _from,
        address _to,
        uint256 _amount,
        bytes _data
    );
    event DepositERC20(
        address indexed l1Token,
        address indexed l2Token,
        address indexed from,
        bytes to,
        uint256 amount,
        bytes data
    );

    L1WETHGatewayValidium private wethGateway;
    L1ERC20GatewayValidium private gateway;

    ScrollStandardERC20 private template;
    ScrollStandardERC20Factory private factory;
    L2StandardERC20Gateway private counterpartGateway;

    WrappedEther private weth;
    MockERC20 private l2Token;

    function setUp() public {
        __ValidiumTestBase_setUp(1233);

        // Deploy tokens
        weth = new WrappedEther();

        // Deploy L2 contracts
        template = new ScrollStandardERC20();
        factory = new ScrollStandardERC20Factory(address(template));
        counterpartGateway = new L2StandardERC20Gateway(address(1), address(1), address(1), address(factory));

        // Deploy L1 contracts
        gateway = _deployGateway(address(l1Messenger));
        wethGateway = new L1WETHGatewayValidium(address(weth), address(gateway));

        // Initialize L1 contracts
        gateway.initialize();

        address[] memory addresses = new address[](1);
        addresses[0] = address(gateway);
        gatewayWhitelist.updateWhitelistStatus(addresses, true);

        l2Token = MockERC20(gateway.getL2ERC20Address(address(weth)));
    }

    function testDeposit(uint256 amount, bytes memory recipient) public {
        _deposit(address(this), amount, recipient, 1000000);
    }

    function _deposit(
        address from,
        uint256 amount,
        bytes memory recipient,
        uint256 gasLimit
    ) private {
        amount = bound(amount, 0, address(this).balance / 2);
        setL2BaseFee(0);

        bytes memory message = abi.encodeWithSelector(
            IL2ERC20GatewayValidium.finalizeDepositERC20Encrypted.selector,
            address(weth),
            address(l2Token),
            from,
            recipient,
            amount,
            abi.encode(true, abi.encode(new bytes(0), abi.encode(weth.symbol(), weth.name(), weth.decimals())))
        );
        bytes memory xDomainCalldata = abi.encodeWithSignature(
            "relayMessage(address,address,uint256,uint256,bytes)",
            address(gateway),
            address(counterpartGateway),
            0,
            0,
            message
        );

        (uint256 keyId, ) = rollup.getLatestEncryptionKey();

        if (amount == 0) {
            hevm.expectRevert(L1ERC20GatewayValidium.ErrorAmountIsZero.selector);
            wethGateway.deposit(recipient, amount, keyId);
        } else {
            // revert when ErrorInsufficientValue
            hevm.expectRevert(L1WETHGatewayValidium.ErrorInsufficientValue.selector);
            wethGateway.deposit{value: amount - 1}(recipient, amount, keyId);

            // emit QueueTransaction from L1MessageQueueV2
            {
                hevm.expectEmit(true, true, false, true);
                address sender = AddressAliasHelper.applyL1ToL2Alias(address(l1Messenger));
                emit QueueTransaction(sender, address(l2Messenger), 0, 0, gasLimit, xDomainCalldata);
            }

            // emit SentMessage from L1ScrollMessenger
            {
                hevm.expectEmit(true, true, false, true);
                emit SentMessage(address(gateway), address(counterpartGateway), 0, 0, gasLimit, message);
            }

            // emit DepositERC20 from L1ERC20GatewayValidium
            hevm.expectEmit(true, true, true, true);
            emit DepositERC20(address(weth), address(l2Token), from, recipient, amount, new bytes(0));

            uint256 ethBalance = address(this).balance;
            uint256 gatewayBalance = weth.balanceOf(address(gateway));
            uint256 feeVaultBalance = address(feeVault).balance;
            assertEq(l1Messenger.messageSendTimestamp(keccak256(xDomainCalldata)), 0);
            wethGateway.deposit{value: amount}(recipient, amount, keyId);
            assertEq(ethBalance - amount, address(this).balance);
            assertEq(amount + gatewayBalance, weth.balanceOf(address(gateway)));
            assertEq(feeVaultBalance, address(feeVault).balance);
            assertGt(l1Messenger.messageSendTimestamp(keccak256(xDomainCalldata)), 0);
        }
    }

    function _deployGateway(address messenger) internal returns (L1ERC20GatewayValidium _gateway) {
        _gateway = L1ERC20GatewayValidium(_deployProxy(address(0)));

        admin.upgrade(
            ITransparentUpgradeableProxy(address(_gateway)),
            address(
                new L1ERC20GatewayValidium(
                    address(counterpartGateway),
                    address(messenger),
                    address(template),
                    address(factory),
                    address(rollup)
                )
            )
        );
    }
}
