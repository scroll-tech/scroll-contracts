// SPDX-License-Identifier: MIT

pragma solidity =0.8.24;

import {MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";

import {ITransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import {IL1ERC20Gateway, L1CustomERC20Gateway} from "../L1/gateways/L1CustomERC20Gateway.sol";
import {L1GatewayRouter} from "../L1/gateways/L1GatewayRouter.sol";
import {IL1ScrollMessenger} from "../L1/IL1ScrollMessenger.sol";
import {L1ScrollMessenger} from "../L1/L1ScrollMessenger.sol";
import {IL2ERC20Gateway, L2CustomERC20Gateway} from "../L2/gateways/L2CustomERC20Gateway.sol";
import {AddressAliasHelper} from "../libraries/common/AddressAliasHelper.sol";
import {ScrollConstants} from "../libraries/constants/ScrollConstants.sol";

import {L1GatewayTestBase} from "./L1GatewayTestBase.t.sol";
import {MockScrollMessenger} from "./mocks/MockScrollMessenger.sol";
import {MockGatewayRecipient} from "./mocks/MockGatewayRecipient.sol";

contract L1CustomERC20GatewayTest is L1GatewayTestBase {
    // from L1CustomERC20Gateway
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

    L1CustomERC20Gateway private gateway;
    L1GatewayRouter private router;

    L2CustomERC20Gateway private counterpartGateway;

    MockERC20 private l1Token;
    MockERC20 private l2Token;

    function setUp() public {
        __L1GatewayTestBase_setUp();

        // Deploy tokens
        l1Token = new MockERC20("Mock L1", "ML1", 18);
        l2Token = new MockERC20("Mock L2", "ML2", 18);

        // Deploy L2 contracts
        counterpartGateway = new L2CustomERC20Gateway(address(1), address(1), address(1));

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

    function testInitialized() public {
        assertEq(address(this), gateway.owner());
        assertEq(address(counterpartGateway), gateway.counterpart());
        assertEq(address(router), gateway.router());
        assertEq(address(l1Messenger), gateway.messenger());

        assertEq(address(0), gateway.getL2ERC20Address(address(l1Token)));

        hevm.expectRevert("Initializable: contract is already initialized");
        gateway.initialize(address(counterpartGateway), address(router), address(l1Messenger));
    }

    function testUpdateTokenMappingFailed(address token1) public {
        // call by non-owner, should revert
        hevm.startPrank(address(1));
        hevm.expectRevert("Ownable: caller is not the owner");
        gateway.updateTokenMapping(token1, token1);
        hevm.stopPrank();

        // l2 token is zero, should revert
        hevm.expectRevert("token address cannot be 0");
        gateway.updateTokenMapping(token1, address(0));
    }

    function testUpdateTokenMappingSuccess(address token1, address token2) public {
        hevm.assume(token2 != address(0));
        hevm.assume(token1 != address(l1Token));

        assertEq(gateway.getL2ERC20Address(token1), address(0));
        gateway.updateTokenMapping{value: 1 ether}(token1, token2);
        assertEq(gateway.getL2ERC20Address(token1), token2);
    }

    function testDepositERC20(
        uint256 amount,
        uint256 gasLimit,
        uint256 feePerGas
    ) public {
        _depositERC20(false, amount, gasLimit, feePerGas);
    }

    function testDepositERC20WithRecipient(
        uint256 amount,
        address recipient,
        uint256 gasLimit,
        uint256 feePerGas
    ) public {
        _depositERC20WithRecipient(false, amount, recipient, gasLimit, feePerGas);
    }

    function testDepositERC20WithRecipientAndCalldata(
        uint256 amount,
        address recipient,
        bytes memory dataToCall,
        uint256 gasLimit,
        uint256 feePerGas
    ) public {
        _depositERC20WithRecipientAndCalldata(false, amount, recipient, dataToCall, gasLimit, feePerGas);
    }

    function testFinalizeWithdrawERC20FailedMocking(
        address sender,
        address recipient,
        uint256 amount,
        bytes memory dataToCall
    ) public {
        amount = bound(amount, 1, 100000);

        // revert when caller is not messenger
        hevm.expectRevert(ErrorCallerIsNotMessenger.selector);
        gateway.finalizeWithdrawERC20(address(l1Token), address(l2Token), sender, recipient, amount, dataToCall);

        MockScrollMessenger mockMessenger = new MockScrollMessenger();
        gateway = _deployGateway(address(mockMessenger));
        gateway.initialize(address(counterpartGateway), address(router), address(mockMessenger));

        // only call by counterpart
        hevm.expectRevert(ErrorCallerIsNotCounterpartGateway.selector);
        mockMessenger.callTarget(
            address(gateway),
            abi.encodeWithSelector(
                gateway.finalizeWithdrawERC20.selector,
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
        hevm.expectRevert("nonzero msg.value");
        mockMessenger.callTarget{value: 1}(
            address(gateway),
            abi.encodeWithSelector(
                gateway.finalizeWithdrawERC20.selector,
                address(l1Token),
                address(l2Token),
                sender,
                recipient,
                amount,
                dataToCall
            )
        );

        // msg.value mismatch
        hevm.expectRevert("l2 token mismatch");
        mockMessenger.callTarget(
            address(gateway),
            abi.encodeWithSelector(
                gateway.finalizeWithdrawERC20.selector,
                address(l1Token),
                address(l2Token),
                sender,
                recipient,
                amount,
                dataToCall
            )
        );
    }

    function testFinalizeWithdrawERC20Failed(
        address sender,
        address recipient,
        uint256 amount,
        bytes memory dataToCall
    ) public {
        // blacklist some addresses
        hevm.assume(recipient != address(0));
        hevm.assume(recipient != address(gateway));

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

        prepareL2MessageRoot(keccak256(xDomainCalldata));

        IL1ScrollMessenger.L2MessageProof memory proof;
        proof.batchIndex = rollup.lastFinalizedBatchIndex();

        // counterpart is not L2WETHGateway
        // emit FailedRelayedMessage from L1ScrollMessenger
        hevm.expectEmit(true, false, false, true);
        emit FailedRelayedMessage(keccak256(xDomainCalldata));

        uint256 gatewayBalance = l1Token.balanceOf(address(gateway));
        uint256 recipientBalance = l1Token.balanceOf(recipient);
        assertBoolEq(false, l1Messenger.isL2MessageExecuted(keccak256(xDomainCalldata)));
        l1Messenger.relayMessageWithProof(
            address(uint160(address(counterpartGateway)) + 1),
            address(gateway),
            0,
            0,
            message,
            proof
        );
        assertEq(gatewayBalance, l1Token.balanceOf(address(gateway)));
        assertEq(recipientBalance, l1Token.balanceOf(recipient));
        assertBoolEq(false, l1Messenger.isL2MessageExecuted(keccak256(xDomainCalldata)));
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
        assertEq(gatewayBalance - amount, l1Token.balanceOf(address(gateway)));
        assertEq(recipientBalance + amount, l1Token.balanceOf(address(recipient)));
        assertBoolEq(true, l1Messenger.isL2MessageExecuted(keccak256(xDomainCalldata)));
    }

    function _depositERC20(
        bool useRouter,
        uint256 amount,
        uint256 gasLimit,
        uint256 feePerGas
    ) private {
        uint64 nonce = 1;
        amount = bound(amount, 0, l1Token.balanceOf(address(this)));
        gasLimit = bound(gasLimit, defaultGasLimit / 2, defaultGasLimit);
        feePerGas = bound(feePerGas, 0, 1000);

        setL2BaseFee(feePerGas);

        uint256 feeToPay = feePerGas * gasLimit;
        bytes memory message = abi.encodeWithSelector(
            IL2ERC20Gateway.finalizeDepositERC20.selector,
            address(l1Token),
            address(l2Token),
            address(this),
            address(this),
            amount,
            new bytes(0)
        );
        bytes memory xDomainCalldata = abi.encodeWithSignature(
            "relayMessage(address,address,uint256,uint256,bytes)",
            address(gateway),
            address(counterpartGateway),
            0,
            nonce,
            message
        );

        hevm.expectRevert("no corresponding l2 token");
        if (useRouter) {
            router.depositERC20{value: feeToPay + extraValue}(address(l1Token), amount, gasLimit);
        } else {
            gateway.depositERC20{value: feeToPay + extraValue}(address(l1Token), amount, gasLimit);
        }

        gateway.updateTokenMapping{value: 1 ether}(address(l1Token), address(l2Token));
        if (amount == 0) {
            hevm.expectRevert("deposit zero amount");
            if (useRouter) {
                router.depositERC20{value: feeToPay + extraValue}(address(l1Token), amount, gasLimit);
            } else {
                gateway.depositERC20{value: feeToPay + extraValue}(address(l1Token), amount, gasLimit);
            }
        } else {
            // emit QueueTransaction from L1MessageQueue
            {
                hevm.expectEmit(true, true, false, true);
                address sender = AddressAliasHelper.applyL1ToL2Alias(address(l1Messenger));
                emit QueueTransaction(sender, address(l2Messenger), 0, nonce, gasLimit, xDomainCalldata);
            }

            // emit SentMessage from L1ScrollMessenger
            {
                hevm.expectEmit(true, true, false, true);
                emit SentMessage(address(gateway), address(counterpartGateway), 0, nonce, gasLimit, message);
            }

            // emit DepositERC20 from L1CustomERC20Gateway
            hevm.expectEmit(true, true, true, true);
            emit DepositERC20(address(l1Token), address(l2Token), address(this), address(this), amount, new bytes(0));

            uint256 gatewayBalance = l1Token.balanceOf(address(gateway));
            uint256 feeVaultBalance = address(feeVault).balance;
            assertEq(l1Messenger.messageSendTimestamp(keccak256(xDomainCalldata)), 0);
            if (useRouter) {
                router.depositERC20{value: feeToPay + extraValue}(address(l1Token), amount, gasLimit);
            } else {
                gateway.depositERC20{value: feeToPay + extraValue}(address(l1Token), amount, gasLimit);
            }
            assertEq(amount + gatewayBalance, l1Token.balanceOf(address(gateway)));
            assertEq(feeToPay + feeVaultBalance, address(feeVault).balance);
            assertGt(l1Messenger.messageSendTimestamp(keccak256(xDomainCalldata)), 0);
        }
    }

    function _depositERC20WithRecipient(
        bool useRouter,
        uint256 amount,
        address recipient,
        uint256 gasLimit,
        uint256 feePerGas
    ) private {
        uint64 nonce = 1;
        amount = bound(amount, 0, l1Token.balanceOf(address(this)));
        gasLimit = bound(gasLimit, defaultGasLimit / 2, defaultGasLimit);
        feePerGas = bound(feePerGas, 0, 1000);

        setL2BaseFee(feePerGas);

        uint256 feeToPay = feePerGas * gasLimit;
        bytes memory message = abi.encodeWithSelector(
            IL2ERC20Gateway.finalizeDepositERC20.selector,
            address(l1Token),
            address(l2Token),
            address(this),
            recipient,
            amount,
            new bytes(0)
        );
        bytes memory xDomainCalldata = abi.encodeWithSignature(
            "relayMessage(address,address,uint256,uint256,bytes)",
            address(gateway),
            address(counterpartGateway),
            0,
            nonce,
            message
        );

        hevm.expectRevert("no corresponding l2 token");
        if (useRouter) {
            router.depositERC20{value: feeToPay + extraValue}(address(l1Token), amount, gasLimit);
        } else {
            gateway.depositERC20{value: feeToPay + extraValue}(address(l1Token), amount, gasLimit);
        }

        gateway.updateTokenMapping{value: 1 ether}(address(l1Token), address(l2Token));
        if (amount == 0) {
            hevm.expectRevert("deposit zero amount");
            if (useRouter) {
                router.depositERC20{value: feeToPay + extraValue}(address(l1Token), recipient, amount, gasLimit);
            } else {
                gateway.depositERC20{value: feeToPay + extraValue}(address(l1Token), recipient, amount, gasLimit);
            }
        } else {
            // emit QueueTransaction from L1MessageQueue
            {
                hevm.expectEmit(true, true, false, true);
                address sender = AddressAliasHelper.applyL1ToL2Alias(address(l1Messenger));
                emit QueueTransaction(sender, address(l2Messenger), 0, nonce, gasLimit, xDomainCalldata);
            }

            // emit SentMessage from L1ScrollMessenger
            {
                hevm.expectEmit(true, true, false, true);
                emit SentMessage(address(gateway), address(counterpartGateway), 0, nonce, gasLimit, message);
            }

            // emit DepositERC20 from L1CustomERC20Gateway
            hevm.expectEmit(true, true, true, true);
            emit DepositERC20(address(l1Token), address(l2Token), address(this), recipient, amount, new bytes(0));

            uint256 gatewayBalance = l1Token.balanceOf(address(gateway));
            uint256 feeVaultBalance = address(feeVault).balance;
            assertEq(l1Messenger.messageSendTimestamp(keccak256(xDomainCalldata)), 0);
            if (useRouter) {
                router.depositERC20{value: feeToPay + extraValue}(address(l1Token), recipient, amount, gasLimit);
            } else {
                gateway.depositERC20{value: feeToPay + extraValue}(address(l1Token), recipient, amount, gasLimit);
            }
            assertEq(amount + gatewayBalance, l1Token.balanceOf(address(gateway)));
            assertEq(feeToPay + feeVaultBalance, address(feeVault).balance);
            assertGt(l1Messenger.messageSendTimestamp(keccak256(xDomainCalldata)), 0);
        }
    }

    function _depositERC20WithRecipientAndCalldata(
        bool useRouter,
        uint256 amount,
        address recipient,
        bytes memory dataToCall,
        uint256 gasLimit,
        uint256 feePerGas
    ) private {
        uint64 nonce = 1;
        amount = bound(amount, 0, l1Token.balanceOf(address(this)));
        gasLimit = bound(gasLimit, defaultGasLimit / 2, defaultGasLimit);
        feePerGas = bound(feePerGas, 0, 1000);

        setL2BaseFee(feePerGas);

        uint256 feeToPay = feePerGas * gasLimit;
        bytes memory message = abi.encodeWithSelector(
            IL2ERC20Gateway.finalizeDepositERC20.selector,
            address(l1Token),
            address(l2Token),
            address(this),
            recipient,
            amount,
            dataToCall
        );
        bytes memory xDomainCalldata = abi.encodeWithSignature(
            "relayMessage(address,address,uint256,uint256,bytes)",
            address(gateway),
            address(counterpartGateway),
            0,
            nonce,
            message
        );

        hevm.expectRevert("no corresponding l2 token");
        if (useRouter) {
            router.depositERC20{value: feeToPay + extraValue}(address(l1Token), amount, gasLimit);
        } else {
            gateway.depositERC20{value: feeToPay + extraValue}(address(l1Token), amount, gasLimit);
        }

        gateway.updateTokenMapping{value: 1 ether}(address(l1Token), address(l2Token));
        if (amount == 0) {
            hevm.expectRevert("deposit zero amount");
            if (useRouter) {
                router.depositERC20AndCall{value: feeToPay + extraValue}(
                    address(l1Token),
                    recipient,
                    amount,
                    dataToCall,
                    gasLimit
                );
            } else {
                gateway.depositERC20AndCall{value: feeToPay + extraValue}(
                    address(l1Token),
                    recipient,
                    amount,
                    dataToCall,
                    gasLimit
                );
            }
        } else {
            // emit QueueTransaction from L1MessageQueue
            {
                hevm.expectEmit(true, true, false, true);
                address sender = AddressAliasHelper.applyL1ToL2Alias(address(l1Messenger));
                emit QueueTransaction(sender, address(l2Messenger), 0, nonce, gasLimit, xDomainCalldata);
            }

            // emit SentMessage from L1ScrollMessenger
            {
                hevm.expectEmit(true, true, false, true);
                emit SentMessage(address(gateway), address(counterpartGateway), 0, nonce, gasLimit, message);
            }

            // emit DepositERC20 from L1CustomERC20Gateway
            hevm.expectEmit(true, true, true, true);
            emit DepositERC20(address(l1Token), address(l2Token), address(this), recipient, amount, dataToCall);

            uint256 gatewayBalance = l1Token.balanceOf(address(gateway));
            uint256 feeVaultBalance = address(feeVault).balance;
            assertEq(l1Messenger.messageSendTimestamp(keccak256(xDomainCalldata)), 0);
            if (useRouter) {
                router.depositERC20AndCall{value: feeToPay + extraValue}(
                    address(l1Token),
                    recipient,
                    amount,
                    dataToCall,
                    gasLimit
                );
            } else {
                gateway.depositERC20AndCall{value: feeToPay + extraValue}(
                    address(l1Token),
                    recipient,
                    amount,
                    dataToCall,
                    gasLimit
                );
            }
            assertEq(amount + gatewayBalance, l1Token.balanceOf(address(gateway)));
            assertEq(feeToPay + feeVaultBalance, address(feeVault).balance);
            assertGt(l1Messenger.messageSendTimestamp(keccak256(xDomainCalldata)), 0);
        }
    }

    function _deployGateway(address messenger) internal returns (L1CustomERC20Gateway _gateway) {
        _gateway = L1CustomERC20Gateway(_deployProxy(address(0)));

        admin.upgrade(
            ITransparentUpgradeableProxy(address(_gateway)),
            address(new L1CustomERC20Gateway(address(counterpartGateway), address(router), messenger))
        );
    }
}
