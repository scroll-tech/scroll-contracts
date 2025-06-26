// SPDX-License-Identifier: MIT

pragma solidity =0.8.24;

import {MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";

import {ITransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import {IL1ERC20Gateway} from "../L1/gateways/IL1ERC20Gateway.sol";
import {L1ReverseCustomERC20Gateway} from "../L1/gateways/L1ReverseCustomERC20Gateway.sol";
import {L1GatewayRouter} from "../L1/gateways/L1GatewayRouter.sol";
import {IL1ScrollMessenger} from "../L1/IL1ScrollMessenger.sol";
import {L1ScrollMessenger} from "../L1/L1ScrollMessenger.sol";
import {IL2ERC20Gateway} from "../L2/gateways/IL2ERC20Gateway.sol";
import {L2ReverseCustomERC20Gateway} from "../L2/gateways/L2ReverseCustomERC20Gateway.sol";
import {AddressAliasHelper} from "../libraries/common/AddressAliasHelper.sol";
import {ScrollConstants} from "../libraries/constants/ScrollConstants.sol";

import {L1GatewayTestBase} from "./L1GatewayTestBase.t.sol";
import {MockScrollMessenger} from "./mocks/MockScrollMessenger.sol";
import {MockGatewayRecipient} from "./mocks/MockGatewayRecipient.sol";

contract MockL1ReverseCustomERC20Gateway is L1ReverseCustomERC20Gateway {
    constructor(
        address _counterpart,
        address _router,
        address _messenger
    ) L1ReverseCustomERC20Gateway(_counterpart, _router, _messenger) {}

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

contract L1ReverseCustomERC20GatewayTest is L1GatewayTestBase {
    // from L1ReverseCustomERC20Gateway
    event FinalizeWithdrawERC20(
        address indexed _l1Token,
        address indexed _l2Token,
        address indexed _from,
        address _to,
        uint256 _amount,
        bytes _data
    );
    event DepositERC20(
        address indexed _l1Token,
        address indexed _l2Token,
        address indexed _from,
        address _to,
        uint256 _amount,
        bytes _data
    );
    event RefundERC20(address indexed token, address indexed recipient, uint256 amount);

    MockL1ReverseCustomERC20Gateway private gateway;
    L1GatewayRouter private router;

    L2ReverseCustomERC20Gateway private counterpartGateway;

    MockERC20 private l1Token;
    MockERC20 private l2Token;

    function setUp() public {
        __L1GatewayTestBase_setUp();

        // Deploy tokens
        l1Token = new MockERC20("Mock L1", "ML1", 18);
        l2Token = new MockERC20("Mock L2", "ML2", 18);

        // Deploy L2 contracts
        counterpartGateway = new L2ReverseCustomERC20Gateway(address(1), address(1), address(1));

        // Deploy L1 contracts
        router = L1GatewayRouter(_deployProxy(address(new L1GatewayRouter())));
        gateway = _deployGateway(address(l1Messenger));

        // Initialize L1 contracts
        gateway.initialize(address(counterpartGateway), address(router), address(l1Messenger));
        router.initialize(address(0), address(gateway));

        // Prepare token balances
        l1Token.mint(address(this), type(uint128).max);
        l1Token.approve(address(gateway), type(uint256).max);
        l1Token.approve(address(router), type(uint256).max);
    }

    function testDepositERC20(
        uint256 amount,
        uint256 gasLimit,
        uint256 feePerGas
    ) external {
        _depositERC20(false, 0, amount, address(this), new bytes(0), gasLimit, feePerGas);
    }

    function testDepositERC20WithRecipient(
        uint256 amount,
        address recipient,
        uint256 gasLimit,
        uint256 feePerGas
    ) external {
        _depositERC20(false, 1, amount, recipient, new bytes(0), gasLimit, feePerGas);
    }

    function testDepositERC20WithRecipientAndCalldata(
        uint256 amount,
        address recipient,
        bytes memory dataToCall,
        uint256 gasLimit,
        uint256 feePerGas
    ) external {
        _depositERC20(false, 2, amount, recipient, dataToCall, gasLimit, feePerGas);
    }

    function testDepositERC20ByRouter(
        uint256 amount,
        uint256 gasLimit,
        uint256 feePerGas
    ) external {
        _depositERC20(true, 0, amount, address(this), new bytes(0), gasLimit, feePerGas);
    }

    function testDepositERC20WithRecipientByRouter(
        uint256 amount,
        address recipient,
        uint256 gasLimit,
        uint256 feePerGas
    ) external {
        _depositERC20(true, 1, amount, recipient, new bytes(0), gasLimit, feePerGas);
    }

    function testDepositERC20WithRecipientAndCalldataByRouter(
        uint256 amount,
        address recipient,
        bytes memory dataToCall,
        uint256 gasLimit,
        uint256 feePerGas
    ) external {
        _depositERC20(true, 2, amount, recipient, dataToCall, gasLimit, feePerGas);
    }

    function testFinalizeWithdrawERC20(
        address sender,
        uint256 amount,
        bytes memory dataToCall
    ) public {
        MockGatewayRecipient recipient = new MockGatewayRecipient();

        gateway.updateTokenMapping{value: 1 ether}(address(l1Token), address(l2Token));

        amount = bound(amount, 1, l1Token.balanceOf(address(this)));

        // deposit some token to L1StandardERC20Gateway
        gateway.depositERC20(address(l1Token), amount, defaultGasLimit);

        // do finalize withdraw token
        bytes memory message = abi.encodeWithSelector(
            IL1ERC20Gateway.finalizeWithdrawERC20.selector,
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

        prepareL2MessageRoot(keccak256(xDomainCalldata));

        IL1ScrollMessenger.L2MessageProof memory proof;
        proof.batchIndex = rollup.lastFinalizedBatchIndex();

        // emit FinalizeWithdrawERC20 from L1StandardERC20Gateway
        {
            hevm.expectEmit(true, true, true, true);
            emit FinalizeWithdrawERC20(
                address(l1Token),
                address(l2Token),
                sender,
                address(recipient),
                amount,
                dataToCall
            );
        }

        // emit RelayedMessage from L1ScrollMessenger
        {
            hevm.expectEmit(true, false, false, true);
            emit RelayedMessage(keccak256(xDomainCalldata));
        }

        uint256 gatewayBalance = l1Token.balanceOf(address(gateway));
        uint256 recipientBalance = l1Token.balanceOf(address(recipient));
        assertBoolEq(false, l1Messenger.isL2MessageExecuted(keccak256(xDomainCalldata)));
        l1Messenger.relayMessageWithProof(address(counterpartGateway), address(gateway), 0, 0, message, proof);
        assertEq(gatewayBalance, l1Token.balanceOf(address(gateway)));
        assertEq(recipientBalance + amount, l1Token.balanceOf(address(recipient)));
        assertBoolEq(true, l1Messenger.isL2MessageExecuted(keccak256(xDomainCalldata)));
    }

    function _depositERC20(
        bool useRouter,
        uint256 methodType,
        uint256 amount,
        address recipient,
        bytes memory dataToCall,
        uint256 gasLimit,
        uint256 feePerGas
    ) private {
        hevm.assume(recipient != address(0));
        amount = bound(amount, 1, l1Token.balanceOf(address(this)));
        gasLimit = bound(gasLimit, defaultGasLimit / 2, defaultGasLimit);
        feePerGas = bound(feePerGas, 0, 1000);
        setL2BaseFee(feePerGas);
        feePerGas = feePerGas * gasLimit;

        // revert when reentrant
        hevm.expectRevert("ReentrancyGuard: reentrant call");
        {
            bytes memory reentrantData;
            if (methodType == 0) {
                reentrantData = abi.encodeWithSignature(
                    "depositERC20(address,uint256,uint256)",
                    address(l1Token),
                    amount,
                    gasLimit
                );
            } else if (methodType == 1) {
                reentrantData = abi.encodeWithSignature(
                    "depositERC20(address,address,uint256,uint256)",
                    address(l1Token),
                    recipient,
                    amount,
                    gasLimit
                );
            } else if (methodType == 2) {
                reentrantData = abi.encodeCall(
                    IL1ERC20Gateway.depositERC20AndCall,
                    (address(l1Token), recipient, amount, dataToCall, gasLimit)
                );
            }
            gateway.reentrantCall(useRouter ? address(router) : address(gateway), reentrantData);
        }

        // revert when l1 token not support
        hevm.expectRevert("no corresponding l2 token");
        _invokeDepositERC20Call(
            useRouter,
            methodType,
            address(l2Token),
            amount,
            recipient,
            dataToCall,
            gasLimit,
            feePerGas
        );

        gateway.updateTokenMapping{value: 1 ether}(address(l1Token), address(l2Token));
        uint64 nonce = uint64(messageQueueV2.nextCrossDomainMessageIndex());

        // revert when deposit zero amount
        hevm.expectRevert("deposit zero amount");
        _invokeDepositERC20Call(useRouter, methodType, address(l1Token), 0, recipient, dataToCall, gasLimit, feePerGas);

        // succeed to deposit
        bytes memory message = abi.encodeCall(
            IL2ERC20Gateway.finalizeDepositERC20,
            (address(l1Token), address(l2Token), address(this), recipient, amount, dataToCall)
        );
        bytes memory xDomainCalldata = abi.encodeCall(
            l2Messenger.relayMessage,
            (address(gateway), address(counterpartGateway), 0, nonce, message)
        );
        // should emit QueueTransaction from L1MessageQueue
        {
            hevm.expectEmit(true, true, false, true);
            address sender = AddressAliasHelper.applyL1ToL2Alias(address(l1Messenger));
            emit QueueTransaction(sender, address(l2Messenger), 0, nonce, gasLimit, xDomainCalldata);
        }
        // should emit SentMessage from L1ScrollMessenger
        {
            hevm.expectEmit(true, true, false, true);
            emit SentMessage(address(gateway), address(counterpartGateway), 0, nonce, gasLimit, message);
        }
        // should emit DepositERC20 from L1CustomERC20Gateway
        {
            hevm.expectEmit(true, true, true, true);
            emit DepositERC20(address(l1Token), address(l2Token), address(this), recipient, amount, dataToCall);
        }

        uint256 gatewayBalance = l1Token.balanceOf(address(gateway));
        uint256 feeVaultBalance = address(feeVault).balance;
        uint256 thisBalance = l1Token.balanceOf(address(this));
        assertEq(l1Messenger.messageSendTimestamp(keccak256(xDomainCalldata)), 0);
        uint256 balance = address(this).balance;
        _invokeDepositERC20Call(
            useRouter,
            methodType,
            address(l1Token),
            amount,
            recipient,
            dataToCall,
            gasLimit,
            feePerGas
        );
        assertEq(balance - feePerGas, address(this).balance); // extra value is transferred back
        assertGt(l1Messenger.messageSendTimestamp(keccak256(xDomainCalldata)), 0);
        assertEq(thisBalance - amount, l1Token.balanceOf(address(this)));
        assertEq(feeVaultBalance + feePerGas, address(feeVault).balance);
        assertEq(gatewayBalance, l1Token.balanceOf(address(gateway)));
    }

    function _invokeDepositERC20Call(
        bool useRouter,
        uint256 methodType,
        address token,
        uint256 amount,
        address recipient,
        bytes memory dataToCall,
        uint256 gasLimit,
        uint256 feeToPay
    ) private {
        uint256 value = feeToPay + extraValue;
        if (useRouter) {
            if (methodType == 0) {
                router.depositERC20{value: value}(token, amount, gasLimit);
            } else if (methodType == 1) {
                router.depositERC20{value: value}(token, recipient, amount, gasLimit);
            } else if (methodType == 2) {
                router.depositERC20AndCall{value: value}(token, recipient, amount, dataToCall, gasLimit);
            }
        } else {
            if (methodType == 0) {
                gateway.depositERC20{value: value}(token, amount, gasLimit);
            } else if (methodType == 1) {
                gateway.depositERC20{value: value}(token, recipient, amount, gasLimit);
            } else if (methodType == 2) {
                gateway.depositERC20AndCall{value: value}(token, recipient, amount, dataToCall, gasLimit);
            }
        }
    }

    function _deployGateway(address messenger) internal returns (MockL1ReverseCustomERC20Gateway _gateway) {
        _gateway = MockL1ReverseCustomERC20Gateway(_deployProxy(address(0)));

        admin.upgrade(
            ITransparentUpgradeableProxy(address(_gateway)),
            address(new MockL1ReverseCustomERC20Gateway(address(counterpartGateway), address(router), messenger))
        );
    }
}
