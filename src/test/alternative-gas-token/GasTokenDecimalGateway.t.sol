// SPDX-License-Identifier: MIT

pragma solidity =0.8.24;

import {MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";

import {ITransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import {L1GasTokenGateway} from "../../alternative-gas-token/L1GasTokenGateway.sol";
import {IL1ScrollMessenger} from "../../L1/IL1ScrollMessenger.sol";
import {IL2ETHGateway} from "../../L2/gateways/IL2ETHGateway.sol";
import {AddressAliasHelper} from "../../libraries/common/AddressAliasHelper.sol";
import {ScrollConstants} from "../../libraries/constants/ScrollConstants.sol";
import {IScrollGateway} from "../../libraries/gateway/IScrollGateway.sol";

import {AlternativeGasTokenTestBase} from "./AlternativeGasTokenTestBase.t.sol";

import {MockGatewayRecipient} from "../mocks/MockGatewayRecipient.sol";
import {MockScrollMessenger} from "../mocks/MockScrollMessenger.sol";

contract L1GasTokenGatewayForTest is L1GasTokenGateway {
    constructor(
        address _gasToken,
        address _counterpart,
        address _router,
        address _messenger
    ) L1GasTokenGateway(_gasToken, _counterpart, _router, _messenger) {}

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

abstract contract GasTokenGatewayTest is AlternativeGasTokenTestBase {
    // from L1GasTokenGateway
    event DepositETH(address indexed from, address indexed to, uint256 amount, bytes data);
    event FinalizeWithdrawETH(address indexed from, address indexed to, uint256 amount, bytes data);
    event RefundETH(address indexed recipient, uint256 amount);

    uint256 private constant NONZERO_TIMESTAMP = 123456;

    MockERC20 private gasToken;
    uint256 private tokenScale;

    struct DepositParams {
        uint256 methodType;
        uint256 amount;
        address recipient;
        bytes dataToCall;
        uint256 gasLimit;
        uint256 feeToPay;
        uint256 exceedValue;
    }

    receive() external payable {}

    function __GasTokenGatewayTest_setUp(uint8 decimals) internal {
        gasToken = new MockERC20("X", "Y", decimals);

        __AlternativeGasTokenTestBase_setUp(1234, address(gasToken));

        admin.upgrade(
            ITransparentUpgradeableProxy(address(l1GasTokenGateway)),
            address(
                new L1GasTokenGatewayForTest(
                    address(gasToken),
                    address(l2ETHGateway),
                    address(l1Router),
                    address(l1Messenger)
                )
            )
        );

        gasToken.mint(address(this), type(uint128).max);
        vm.warp(NONZERO_TIMESTAMP);

        gasToken.approve(address(l1GasTokenGateway), type(uint256).max);
        tokenScale = 10**(18 - decimals);
    }

    function testDepositETH(DepositParams memory params) external {
        params.methodType = 0;
        params.recipient = address(this);
        params.dataToCall = new bytes(0);
        _depositETH(false, params);
    }

    function testDepositETHWithRecipient(DepositParams memory params) external {
        params.methodType = 1;
        params.dataToCall = new bytes(0);
        _depositETH(false, params);
    }

    function testDepositETHAndCall(DepositParams memory params) external {
        params.methodType = 2;
        _depositETH(false, params);
    }

    function testDepositETHWithRouter(DepositParams memory params) external {
        params.methodType = 0;
        params.recipient = address(this);
        params.dataToCall = new bytes(0);
        _depositETH(true, params);
    }

    function testDepositETHWithRecipientWithRouter(DepositParams memory params) external {
        params.methodType = 1;
        params.dataToCall = new bytes(0);
        _depositETH(true, params);
    }

    function testDepositETHAndCallWithRouter(DepositParams memory params) external {
        params.methodType = 2;
        _depositETH(true, params);
    }

    function testFinalizeWithdrawETH(
        address sender,
        address target,
        uint256 amount,
        bytes memory dataToCall
    ) external {
        vm.assume(target != address(0));
        amount = bound(amount, 1, type(uint128).max);

        // revert when ErrorCallerIsNotMessenger
        vm.expectRevert(IScrollGateway.ErrorCallerIsNotMessenger.selector);
        l1GasTokenGateway.finalizeWithdrawETH(sender, target, amount, dataToCall);

        MockScrollMessenger mockMessenger = new MockScrollMessenger();
        admin.upgrade(
            ITransparentUpgradeableProxy(address(l1GasTokenGateway)),
            address(
                new L1GasTokenGatewayForTest(
                    address(gasToken),
                    address(l2ETHGateway),
                    address(l1Router),
                    address(mockMessenger)
                )
            )
        );

        bytes memory message = abi.encodeCall(
            L1GasTokenGateway.finalizeWithdrawETH,
            (sender, target, amount, dataToCall)
        );
        // revert when ErrorCallerIsNotCounterpartGateway
        vm.expectRevert(IScrollGateway.ErrorCallerIsNotCounterpartGateway.selector);
        mockMessenger.callTarget(address(l1GasTokenGateway), message);

        // revert when reentrant
        mockMessenger.setXDomainMessageSender(address(l2ETHGateway));
        vm.expectRevert("ReentrancyGuard: reentrant call");
        L1GasTokenGatewayForTest(address(l1GasTokenGateway)).reentrantCall(
            address(mockMessenger),
            abi.encodeCall(mockMessenger.callTarget, (address(l1GasTokenGateway), message))
        );

        // revert when ErrorNonZeroMsgValue
        vm.expectRevert(L1GasTokenGateway.ErrorNonZeroMsgValue.selector);
        mockMessenger.callTarget{value: 1}(address(l1GasTokenGateway), message);

        admin.upgrade(
            ITransparentUpgradeableProxy(address(l1GasTokenGateway)),
            address(
                new L1GasTokenGatewayForTest(
                    address(gasToken),
                    address(l2ETHGateway),
                    address(l1Router),
                    address(l1Messenger)
                )
            )
        );

        // succeed when finalize
        uint256 scaledAmount = amount / tokenScale;
        gasToken.mint(address(l1GasTokenGateway), type(uint128).max);
        MockGatewayRecipient recipient = new MockGatewayRecipient();
        message = abi.encodeCall(
            L1GasTokenGateway.finalizeWithdrawETH,
            (sender, address(recipient), amount, dataToCall)
        );
        bytes32 messageHash = keccak256(
            encodeXDomainCalldata(address(l2ETHGateway), address(l1GasTokenGateway), 0, 0, message)
        );
        prepareFinalizedBatch(messageHash);
        IL1ScrollMessenger.L2MessageProof memory proof;
        proof.batchIndex = rollup.lastFinalizedBatchIndex();

        // should emit FinalizeWithdrawETH from L1GasTokenGateway
        {
            vm.expectEmit(true, true, true, true);
            emit FinalizeWithdrawETH(sender, address(recipient), scaledAmount, dataToCall);
        }
        // should emit RelayedMessage from L1ScrollMessenger
        {
            vm.expectEmit(true, false, false, true);
            emit RelayedMessage(messageHash);
        }

        uint256 gatewayBalance = gasToken.balanceOf(address(l1GasTokenGateway));
        uint256 recipientBalance = gasToken.balanceOf(address(recipient));
        assertEq(false, l1Messenger.isL2MessageExecuted(messageHash));
        l1Messenger.relayMessageWithProof(address(l2ETHGateway), address(l1GasTokenGateway), 0, 0, message, proof);
        assertEq(true, l1Messenger.isL2MessageExecuted(messageHash));
        assertEq(recipientBalance + scaledAmount, gasToken.balanceOf(address(recipient)));
        assertEq(gatewayBalance - scaledAmount, gasToken.balanceOf(address(l1GasTokenGateway)));
    }

    function testDropMessage(uint256 amount, address recipient) external {
        vm.assume(recipient != address(0));

        amount = bound(amount, 1, gasToken.balanceOf(address(this)));
        uint256 scaledAmount = amount * tokenScale;
        bytes memory message = abi.encodeCall(
            IL2ETHGateway.finalizeDepositETH,
            (address(this), recipient, scaledAmount, new bytes(0))
        );
        l1GasTokenGateway.depositETH(recipient, amount, 1000000);

        // revert when ErrorCallerIsNotMessenger
        vm.expectRevert(IScrollGateway.ErrorCallerIsNotMessenger.selector);
        l1GasTokenGateway.onDropMessage(message);

        MockScrollMessenger mockMessenger = new MockScrollMessenger();
        admin.upgrade(
            ITransparentUpgradeableProxy(address(l1GasTokenGateway)),
            address(
                new L1GasTokenGatewayForTest(
                    address(gasToken),
                    address(l2ETHGateway),
                    address(l1Router),
                    address(mockMessenger)
                )
            )
        );

        // revert not in drop context
        vm.expectRevert(IScrollGateway.ErrorNotInDropMessageContext.selector);
        mockMessenger.callTarget(
            address(l1GasTokenGateway),
            abi.encodeCall(l1GasTokenGateway.onDropMessage, (message))
        );

        // revert when reentrant
        mockMessenger.setXDomainMessageSender(ScrollConstants.DROP_XDOMAIN_MESSAGE_SENDER);
        vm.expectRevert("ReentrancyGuard: reentrant call");
        L1GasTokenGatewayForTest(address(l1GasTokenGateway)).reentrantCall(
            address(mockMessenger),
            abi.encodeCall(
                mockMessenger.callTarget,
                (address(l1GasTokenGateway), abi.encodeCall(l1GasTokenGateway.onDropMessage, (message)))
            )
        );

        // revert when invalid selector
        vm.expectRevert(L1GasTokenGateway.ErrorInvalidSelector.selector);
        mockMessenger.callTarget(
            address(l1GasTokenGateway),
            abi.encodeCall(l1GasTokenGateway.onDropMessage, (new bytes(4)))
        );

        admin.upgrade(
            ITransparentUpgradeableProxy(address(l1GasTokenGateway)),
            address(
                new L1GasTokenGatewayForTest(
                    address(gasToken),
                    address(l2ETHGateway),
                    address(l1Router),
                    address(l1Messenger)
                )
            )
        );

        // succeed on drop
        // skip message 0
        vm.startPrank(address(rollup));
        l1MessageQueue.popCrossDomainMessage(0, 1, 0x1);
        assertEq(l1MessageQueue.pendingQueueIndex(), 1);
        vm.stopPrank();

        // should emit RefundERC20
        vm.expectEmit(true, true, false, true);
        emit RefundETH(address(this), amount);

        uint256 balance = gasToken.balanceOf(address(this));
        uint256 gatewayBalance = gasToken.balanceOf(address(l1GasTokenGateway));
        l1Messenger.dropMessage(address(l1GasTokenGateway), address(l2ETHGateway), scaledAmount, 0, message);
        assertEq(gatewayBalance - amount, gasToken.balanceOf(address(l1GasTokenGateway)));
        assertEq(balance + amount, gasToken.balanceOf(address(this)));
    }

    function testRelayFromL1ToL2(uint256 l1Amount, address recipient) external {
        vm.assume(recipient.code.length == 0); // only refund to EOA to avoid revert
        vm.assume(uint256(uint160(recipient)) > 2**152); // ignore some precompile contracts
        vm.recordLogs();

        l1Amount = bound(l1Amount, 1, gasToken.balanceOf(address(this)));
        uint256 l2Amount = l1Amount * tokenScale;

        l1GasTokenGateway.depositETH(recipient, l1Amount, 1000000);

        uint256 recipientBalance = recipient.balance;
        uint256 l2MessengerBalance = address(l2Messenger).balance;
        relayFromL1();
        assertEq(recipientBalance + l2Amount, recipient.balance);
        assertEq(l2MessengerBalance - l2Amount, address(l2Messenger).balance);
    }

    function testRelayFromL2ToL1(uint256 l2Amount, address recipient) external {
        vm.assume(recipient != address(0));
        vm.recordLogs();

        l2Amount = bound(l2Amount, 1, address(this).balance);
        uint256 l1Amount = l2Amount / tokenScale;

        gasToken.mint(address(l1GasTokenGateway), type(uint128).max);
        l2ETHGateway.withdrawETH{value: l2Amount}(recipient, l2Amount, 1000000);

        uint256 recipientBalance = gasToken.balanceOf(recipient);
        uint256 gatewayBalance = gasToken.balanceOf(address(l1GasTokenGateway));
        relayFromL2();
        assertEq(recipientBalance + l1Amount, gasToken.balanceOf(recipient));
        assertEq(gatewayBalance - l1Amount, gasToken.balanceOf(address(l1GasTokenGateway)));
    }

    function _depositETH(bool useRouter, DepositParams memory params) private {
        vm.assume(params.recipient != address(0));

        params.amount = bound(params.amount, 1, gasToken.balanceOf(address(this)));
        uint256 scaledAmount = params.amount * tokenScale;

        bytes memory message = abi.encodeCall(
            IL2ETHGateway.finalizeDepositETH,
            (address(this), params.recipient, scaledAmount, params.dataToCall)
        );
        bytes memory xDomainCalldata = encodeXDomainCalldata(
            address(l1GasTokenGateway),
            address(l2ETHGateway),
            scaledAmount,
            0,
            message
        );

        params.gasLimit = bound(params.gasLimit, xDomainCalldata.length * 16 + 21000, 1000000);
        params.feeToPay = bound(params.feeToPay, 0, 1 ether);
        params.exceedValue = bound(params.exceedValue, 0, 1 ether);

        l1MessageQueue.setL2BaseFee(params.feeToPay);
        params.feeToPay = params.feeToPay * params.gasLimit;

        // revert when reentrant
        {
            bytes memory reentrantData;
            if (params.methodType == 0) {
                reentrantData = abi.encodeWithSignature("depositETH(uint256,uint256)", params.amount, params.gasLimit);
            } else if (params.methodType == 1) {
                reentrantData = abi.encodeWithSignature(
                    "depositETH(address,uint256,uint256)",
                    params.recipient,
                    params.amount,
                    params.gasLimit
                );
            } else if (params.methodType == 2) {
                reentrantData = abi.encodeCall(
                    l1GasTokenGateway.depositETHAndCall,
                    (params.recipient, params.amount, params.dataToCall, params.gasLimit)
                );
            }
            vm.expectRevert("ReentrancyGuard: reentrant call");
            L1GasTokenGatewayForTest(address(l1GasTokenGateway)).reentrantCall(
                useRouter ? address(l1Router) : address(l1GasTokenGateway),
                reentrantData
            );
        }

        // revert when ErrorDepositZeroGasToken
        {
            uint256 amount = params.amount;
            params.amount = 0;
            vm.expectRevert(L1GasTokenGateway.ErrorDepositZeroGasToken.selector);
            _invokeDepositETHCall(useRouter, params);
            params.amount = amount;
        }

        // succeed to deposit
        // should emit QueueTransaction from L1MessageQueue
        {
            vm.expectEmit(true, true, false, true);
            address sender = AddressAliasHelper.applyL1ToL2Alias(address(l1Messenger));
            emit QueueTransaction(sender, address(l2Messenger), 0, 0, params.gasLimit, xDomainCalldata);
        }
        // should emit SentMessage from L1ScrollMessenger
        {
            vm.expectEmit(true, true, false, true);
            emit SentMessage(
                address(l1GasTokenGateway),
                address(l2ETHGateway),
                scaledAmount,
                0,
                params.gasLimit,
                message
            );
        }
        // should emit DepositERC20 from L1CustomERC20Gateway
        {
            vm.expectEmit(true, true, false, true);
            emit DepositETH(address(this), params.recipient, params.amount, params.dataToCall);
        }

        uint256 gatewayBalance = gasToken.balanceOf(address(l1GasTokenGateway));
        uint256 feeVaultBalance = l1FeeVault.balance;
        uint256 thisBalance = gasToken.balanceOf(address(this));
        assertEq(l1Messenger.messageSendTimestamp(keccak256(xDomainCalldata)), 0);
        uint256 balance = address(this).balance;
        _invokeDepositETHCall(useRouter, params);
        assertEq(balance - params.feeToPay, address(this).balance); // extra value is transferred back
        assertEq(l1Messenger.messageSendTimestamp(keccak256(xDomainCalldata)), NONZERO_TIMESTAMP);
        assertEq(thisBalance - params.amount, gasToken.balanceOf(address(this)));
        assertEq(feeVaultBalance + params.feeToPay, l1FeeVault.balance);
        assertEq(gatewayBalance + params.amount, gasToken.balanceOf(address(l1GasTokenGateway)));
    }

    function _invokeDepositETHCall(bool useRouter, DepositParams memory params) private {
        uint256 value = params.feeToPay + params.exceedValue;
        if (useRouter) {
            if (params.methodType == 0) {
                l1Router.depositETH{value: value}(params.amount, params.gasLimit);
            } else if (params.methodType == 1) {
                l1Router.depositETH{value: value}(params.recipient, params.amount, params.gasLimit);
            } else if (params.methodType == 2) {
                l1Router.depositETHAndCall{value: value}(
                    params.recipient,
                    params.amount,
                    params.dataToCall,
                    params.gasLimit
                );
            }
        } else {
            if (params.methodType == 0) {
                l1GasTokenGateway.depositETH{value: value}(params.amount, params.gasLimit);
            } else if (params.methodType == 1) {
                l1GasTokenGateway.depositETH{value: value}(params.recipient, params.amount, params.gasLimit);
            } else if (params.methodType == 2) {
                l1GasTokenGateway.depositETHAndCall{value: value}(
                    params.recipient,
                    params.amount,
                    params.dataToCall,
                    params.gasLimit
                );
            }
        }
    }
}

contract GasTokenDecimal18GatewayTest is GasTokenGatewayTest {
    function setUp() external {
        __GasTokenGatewayTest_setUp(18);
    }
}

contract GasTokenDecimal8GatewayTest is GasTokenGatewayTest {
    function setUp() external {
        __GasTokenGatewayTest_setUp(8);
    }
}

contract GasTokenDecimal6GatewayTest is GasTokenGatewayTest {
    function setUp() external {
        __GasTokenGatewayTest_setUp(6);
    }
}
