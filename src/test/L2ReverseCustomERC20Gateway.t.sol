// SPDX-License-Identifier: MIT

pragma solidity =0.8.24;

import {MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";

import {ITransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import {IL1ERC20Gateway} from "../L1/gateways/IL1ERC20Gateway.sol";
import {L1ReverseCustomERC20Gateway} from "../L1/gateways/L1ReverseCustomERC20Gateway.sol";
import {IL2ERC20Gateway} from "../L2/gateways/IL2ERC20Gateway.sol";
import {L2ReverseCustomERC20Gateway} from "../L2/gateways/L2ReverseCustomERC20Gateway.sol";
import {L2GatewayRouter} from "../L2/gateways/L2GatewayRouter.sol";

import {AddressAliasHelper} from "../libraries/common/AddressAliasHelper.sol";

import {L2GatewayTestBase} from "./L2GatewayTestBase.t.sol";
import {MockScrollMessenger} from "./mocks/MockScrollMessenger.sol";
import {MockGatewayRecipient} from "./mocks/MockGatewayRecipient.sol";

contract MockL2ReverseCustomERC20Gateway is L2ReverseCustomERC20Gateway {
    constructor(
        address _counterpart,
        address _router,
        address _messenger
    ) L2ReverseCustomERC20Gateway(_counterpart, _router, _messenger) {}

    function reentrantCall(address target, bytes calldata data) external payable nonReentrant {
        (bool success, ) = target.call{value: msg.value}(data);
        if (!success) {
            // solhint-disable-next-line no-inline-assembly
            assembly {
                let ptr := mload(0x40)
                let size := returndatasize()
                returndatacopy(ptr, 0, size)
                revert(ptr, size)
            }
        }
    }
}

contract L2ReverseCustomERC20GatewayTest is L2GatewayTestBase {
    // from L2ReverseCustomERC20Gateway
    event WithdrawERC20(
        address indexed _l1Token,
        address indexed _l2Token,
        address indexed _from,
        address _to,
        uint256 _amount,
        bytes _data
    );
    event FinalizeDepositERC20(
        address indexed _l1Token,
        address indexed _l2Token,
        address indexed _from,
        address _to,
        uint256 _amount,
        bytes _data
    );

    MockL2ReverseCustomERC20Gateway private gateway;
    L2GatewayRouter private router;

    L1ReverseCustomERC20Gateway private counterpartGateway;

    MockERC20 private l1Token;
    MockERC20 private l2Token;

    function setUp() public {
        setUpBase();
        // Deploy tokens
        l1Token = new MockERC20("Mock L1", "ML1", 18);
        l2Token = new MockERC20("Mock L2", "ML2", 18);

        // Deploy L1 contracts
        counterpartGateway = new L1ReverseCustomERC20Gateway(address(1), address(1), address(1));

        // Deploy L2 contracts
        router = L2GatewayRouter(_deployProxy(address(new L2GatewayRouter())));
        gateway = _deployGateway(address(l2Messenger));

        // Initialize L2 contracts
        gateway.initialize(address(counterpartGateway), address(router), address(l2Messenger));
        router.initialize(address(0), address(gateway));

        // Prepare token balances
        l2Token.mint(address(this), type(uint128).max);
        l2Token.approve(address(gateway), type(uint256).max);
    }

    function testWithdrawERC20(uint256 amount, uint256 gasLimit) external {
        _withdrawERC20(false, 0, amount, address(this), new bytes(0), gasLimit);
    }

    function testWithdrawERC20WithRecipient(
        uint256 amount,
        address recipient,
        uint256 gasLimit
    ) external {
        _withdrawERC20(false, 1, amount, recipient, new bytes(0), gasLimit);
    }

    function testWithdrawERC20WithRecipientAndCalldata(
        uint256 amount,
        address recipient,
        bytes memory dataToCall,
        uint256 gasLimit
    ) external {
        _withdrawERC20(false, 2, amount, recipient, dataToCall, gasLimit);
    }

    function testWithdrawERC20ByRouter(uint256 amount, uint256 gasLimit) external {
        _withdrawERC20(true, 0, amount, address(this), new bytes(0), gasLimit);
    }

    function testWithdrawERC20WithRecipientByRouter(
        uint256 amount,
        address recipient,
        uint256 gasLimit
    ) external {
        _withdrawERC20(true, 1, amount, recipient, new bytes(0), gasLimit);
    }

    function testWithdrawERC20WithRecipientAndCalldataByRouter(
        uint256 amount,
        address recipient,
        bytes memory dataToCall,
        uint256 gasLimit
    ) external {
        _withdrawERC20(true, 2, amount, recipient, dataToCall, gasLimit);
    }

    function testFinalizeDepositERC20FailedMocking(
        address sender,
        address recipient,
        uint256 amount,
        bytes memory dataToCall
    ) public {
        amount = bound(amount, 1, 100000);

        // revert when caller is not messenger
        hevm.expectRevert(ErrorCallerIsNotMessenger.selector);
        gateway.finalizeDepositERC20(address(l1Token), address(l2Token), sender, recipient, amount, dataToCall);

        MockScrollMessenger mockMessenger = new MockScrollMessenger();
        gateway = _deployGateway(address(mockMessenger));
        gateway.initialize(address(counterpartGateway), address(router), address(mockMessenger));

        // only call by counterpart
        hevm.expectRevert(ErrorCallerIsNotCounterpartGateway.selector);
        mockMessenger.callTarget(
            address(gateway),
            abi.encodeWithSelector(
                gateway.finalizeDepositERC20.selector,
                address(l1Token),
                address(l2Token),
                sender,
                recipient,
                amount,
                dataToCall
            )
        );

        mockMessenger.setXDomainMessageSender(address(counterpartGateway));

        // msg.value mismatch
        hevm.expectRevert(L2ReverseCustomERC20Gateway.ErrorNonzeroMsgValue.selector);
        mockMessenger.callTarget{value: 1}(
            address(gateway),
            abi.encodeWithSelector(
                gateway.finalizeDepositERC20.selector,
                address(l1Token),
                address(l2Token),
                sender,
                recipient,
                amount,
                dataToCall
            )
        );

        // l1 token iszero
        hevm.expectRevert(L2ReverseCustomERC20Gateway.ErrorL1TokenAddressIsZero.selector);
        mockMessenger.callTarget(
            address(gateway),
            abi.encodeWithSelector(
                gateway.finalizeDepositERC20.selector,
                address(0),
                address(l2Token),
                sender,
                recipient,
                amount,
                dataToCall
            )
        );

        // l1 token mismatch
        hevm.expectRevert(L2ReverseCustomERC20Gateway.ErrorL1TokenAddressMismatch.selector);
        mockMessenger.callTarget(
            address(gateway),
            abi.encodeWithSelector(
                gateway.finalizeDepositERC20.selector,
                address(l1Token),
                address(l2Token),
                sender,
                recipient,
                amount,
                dataToCall
            )
        );
    }

    function testFinalizeDepositERC20Failed(
        address sender,
        address recipient,
        uint256 amount,
        bytes memory dataToCall
    ) public {
        // blacklist some addresses
        hevm.assume(recipient != address(0));

        _updateTokenMapping(address(l1Token), address(l2Token));

        amount = bound(amount, 1, l2Token.balanceOf(address(this)));

        // do finalize deposit token
        bytes memory message = abi.encodeWithSelector(
            IL2ERC20Gateway.finalizeDepositERC20.selector,
            address(l1Token),
            address(l2Token),
            sender,
            recipient,
            amount,
            dataToCall
        );
        bytes memory xDomainCalldata = abi.encodeWithSignature(
            "relayMessage(address,address,uint256,uint256,bytes)",
            address(uint160(address(counterpartGateway)) + 1),
            address(gateway),
            0,
            0,
            message
        );

        // counterpart is not L1ReverseCustomERC20Gateway
        // emit FailedRelayedMessage from L2ScrollMessenger
        hevm.expectEmit(true, false, false, true);
        emit FailedRelayedMessage(keccak256(xDomainCalldata));

        uint256 gatewayBalance = l2Token.balanceOf(address(gateway));
        uint256 recipientBalance = l2Token.balanceOf(recipient);
        assertBoolEq(false, l2Messenger.isL1MessageExecuted(keccak256(xDomainCalldata)));
        hevm.startPrank(AddressAliasHelper.applyL1ToL2Alias(address(l1Messenger)));
        l2Messenger.relayMessage(address(uint160(address(counterpartGateway)) + 1), address(gateway), 0, 0, message);
        hevm.stopPrank();
        assertEq(gatewayBalance, l2Token.balanceOf(address(gateway)));
        assertEq(recipientBalance, l2Token.balanceOf(recipient));
        assertBoolEq(false, l2Messenger.isL1MessageExecuted(keccak256(xDomainCalldata)));
    }

    function testFinalizeDepositERC20(
        address sender,
        uint256 amount,
        bytes memory dataToCall
    ) public {
        MockGatewayRecipient recipient = new MockGatewayRecipient();

        _updateTokenMapping(address(l1Token), address(l2Token));

        amount = bound(amount, 1, l2Token.balanceOf(address(this)));

        // deposit some token to L2ReverseCustomERC20Gateway
        gateway.withdrawERC20(address(l2Token), amount, 0);

        // do finalize deposit token
        bytes memory message = abi.encodeWithSelector(
            IL2ERC20Gateway.finalizeDepositERC20.selector,
            address(l1Token),
            address(l2Token),
            sender,
            address(recipient),
            amount,
            dataToCall
        );
        bytes memory xDomainCalldata = abi.encodeWithSignature(
            "relayMessage(address,address,uint256,uint256,bytes)",
            address(counterpartGateway),
            address(gateway),
            0,
            0,
            message
        );

        // emit FinalizeDepositERC20 from L2ReverseCustomERC20Gateway
        {
            hevm.expectEmit(true, true, true, true);
            emit FinalizeDepositERC20(
                address(l1Token),
                address(l2Token),
                sender,
                address(recipient),
                amount,
                dataToCall
            );
        }

        // emit RelayedMessage from L2ScrollMessenger
        {
            hevm.expectEmit(true, false, false, true);
            emit RelayedMessage(keccak256(xDomainCalldata));
        }

        uint256 gatewayBalance = l2Token.balanceOf(address(gateway));
        uint256 recipientBalance = l2Token.balanceOf(address(recipient));
        assertBoolEq(false, l2Messenger.isL1MessageExecuted(keccak256(xDomainCalldata)));
        hevm.startPrank(AddressAliasHelper.applyL1ToL2Alias(address(l1Messenger)));
        l2Messenger.relayMessage(address(counterpartGateway), address(gateway), 0, 0, message);
        hevm.stopPrank();
        assertEq(gatewayBalance - amount, l2Token.balanceOf(address(gateway)));
        assertEq(recipientBalance + amount, l2Token.balanceOf(address(recipient)));
        assertBoolEq(true, l2Messenger.isL1MessageExecuted(keccak256(xDomainCalldata)));
    }

    function _withdrawERC20(
        bool useRouter,
        uint256 methodType,
        uint256 amount,
        address recipient,
        bytes memory dataToCall,
        uint256 gasLimit
    ) private {
        hevm.assume(recipient != address(0));
        amount = bound(amount, 1, l2Token.balanceOf(address(this)));

        // revert when reentrant
        hevm.expectRevert("ReentrancyGuard: reentrant call");
        bytes memory reentrantData;
        if (methodType == 0) {
            reentrantData = abi.encodeWithSignature(
                "withdrawERC20(address,uint256,uint256)",
                address(l2Token),
                amount,
                gasLimit
            );
        } else if (methodType == 1) {
            reentrantData = abi.encodeWithSignature(
                "withdrawERC20(address,address,uint256,uint256)",
                address(l2Token),
                recipient,
                amount,
                gasLimit
            );
        } else if (methodType == 2) {
            reentrantData = abi.encodeCall(
                IL2ERC20Gateway.withdrawERC20AndCall,
                (address(l2Token), recipient, amount, dataToCall, gasLimit)
            );
        }
        gateway.reentrantCall(useRouter ? address(router) : address(gateway), reentrantData);

        // revert when l2 token not support
        hevm.expectRevert(L2ReverseCustomERC20Gateway.ErrorNoCorrespondingL1Token.selector);
        _invokeWithdrawERC20Call(useRouter, methodType, address(l1Token), amount, recipient, dataToCall, gasLimit);

        _updateTokenMapping(address(l1Token), address(l2Token));

        // revert when withdraw zero amount
        hevm.expectRevert(L2ReverseCustomERC20Gateway.ErrorWithdrawZeroAmount.selector);
        _invokeWithdrawERC20Call(useRouter, methodType, address(l2Token), 0, recipient, dataToCall, gasLimit);

        // succeed to withdraw
        bytes memory message = abi.encodeCall(
            IL1ERC20Gateway.finalizeWithdrawERC20,
            (address(l1Token), address(l2Token), address(this), recipient, amount, dataToCall)
        );
        bytes memory xDomainCalldata = abi.encodeCall(
            l2Messenger.relayMessage,
            (address(gateway), address(counterpartGateway), 0, 0, message)
        );
        // should emit AppendMessage from L2MessageQueue
        hevm.expectEmit(false, false, false, true);
        emit AppendMessage(0, keccak256(xDomainCalldata));

        // should emit SentMessage from L2ScrollMessenger
        hevm.expectEmit(true, true, false, true);
        emit SentMessage(address(gateway), address(counterpartGateway), 0, 0, gasLimit, message);

        // should emit WithdrawERC20 from L2LidoGateway
        hevm.expectEmit(true, true, true, true);
        emit WithdrawERC20(address(l1Token), address(l2Token), address(this), recipient, amount, dataToCall);

        uint256 gatewayBalance = l2Token.balanceOf(address(gateway));
        uint256 thisBalance = l2Token.balanceOf(address(this));
        assertEq(l2Messenger.messageSendTimestamp(keccak256(xDomainCalldata)), 0);
        _invokeWithdrawERC20Call(useRouter, methodType, address(l2Token), amount, recipient, dataToCall, gasLimit);
        assertGt(l2Messenger.messageSendTimestamp(keccak256(xDomainCalldata)), 0);
        assertEq(thisBalance - amount, l2Token.balanceOf(address(this)));
        assertEq(gatewayBalance + amount, l2Token.balanceOf(address(gateway)));
    }

    function _invokeWithdrawERC20Call(
        bool useRouter,
        uint256 methodType,
        address token,
        uint256 amount,
        address recipient,
        bytes memory dataToCall,
        uint256 gasLimit
    ) private {
        if (useRouter) {
            if (methodType == 0) {
                router.withdrawERC20(token, amount, gasLimit);
            } else if (methodType == 1) {
                router.withdrawERC20(token, recipient, amount, gasLimit);
            } else if (methodType == 2) {
                router.withdrawERC20AndCall(token, recipient, amount, dataToCall, gasLimit);
            }
        } else {
            if (methodType == 0) {
                gateway.withdrawERC20(token, amount, gasLimit);
            } else if (methodType == 1) {
                gateway.withdrawERC20(token, recipient, amount, gasLimit);
            } else if (methodType == 2) {
                gateway.withdrawERC20AndCall(token, recipient, amount, dataToCall, gasLimit);
            }
        }
    }

    function _deployGateway(address messenger) internal returns (MockL2ReverseCustomERC20Gateway _gateway) {
        _gateway = MockL2ReverseCustomERC20Gateway(_deployProxy(address(0)));

        admin.upgrade(
            ITransparentUpgradeableProxy(address(_gateway)),
            address(
                new MockL2ReverseCustomERC20Gateway(address(counterpartGateway), address(router), address(messenger))
            )
        );
    }

    function _updateTokenMapping(address _l1Token, address _l2Token) internal {
        hevm.startPrank(AddressAliasHelper.applyL1ToL2Alias(address(l1Messenger)));
        l2Messenger.relayMessage(
            address(counterpartGateway),
            address(gateway),
            0,
            0,
            abi.encodeCall(gateway.updateTokenMapping, (_l2Token, _l1Token))
        );
        hevm.stopPrank();
    }
}
