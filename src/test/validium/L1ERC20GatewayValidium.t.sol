// SPDX-License-Identifier: MIT

pragma solidity =0.8.24;

import {MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";

import {ITransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import {IL1ScrollMessenger} from "../../L1/IL1ScrollMessenger.sol";
import {L2StandardERC20Gateway} from "../../L2/gateways/L2StandardERC20Gateway.sol";
import {ScrollStandardERC20} from "../../libraries/token/ScrollStandardERC20.sol";
import {ScrollStandardERC20Factory} from "../../libraries/token/ScrollStandardERC20Factory.sol";
import {AddressAliasHelper} from "../../libraries/common/AddressAliasHelper.sol";
import {IL1ERC20GatewayValidium} from "../../validium/IL1ERC20GatewayValidium.sol";
import {IL2ERC20GatewayValidium} from "../../validium/IL2ERC20GatewayValidium.sol";
import {L1ERC20GatewayValidium} from "../../validium/L1ERC20GatewayValidium.sol";
import {ScrollChainValidium} from "../../validium/ScrollChainValidium.sol";

import {TransferReentrantToken} from "../mocks/tokens/TransferReentrantToken.sol";
import {FeeOnTransferToken} from "../mocks/tokens/FeeOnTransferToken.sol";
import {MockScrollMessenger} from "../mocks/MockScrollMessenger.sol";
import {MockGatewayRecipient} from "../mocks/MockGatewayRecipient.sol";

import {ValidiumTestBase} from "./ValidiumTestBase.t.sol";

contract L1ERC20GatewayValidiumTest is ValidiumTestBase {
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

    L1ERC20GatewayValidium private gateway;

    ScrollStandardERC20 private template;
    ScrollStandardERC20Factory private factory;
    L2StandardERC20Gateway private counterpartGateway;

    MockERC20 private l1Token;
    MockERC20 private l2Token;
    TransferReentrantToken private reentrantToken;
    FeeOnTransferToken private feeToken;

    function setUp() public {
        __ValidiumTestBase_setUp(1233);

        // Deploy tokens
        l1Token = new MockERC20("Mock", "M", 18);
        reentrantToken = new TransferReentrantToken("Reentrant", "R", 18);
        feeToken = new FeeOnTransferToken("Fee", "F", 18);

        // Deploy L2 contracts
        template = new ScrollStandardERC20();
        factory = new ScrollStandardERC20Factory(address(template));
        counterpartGateway = new L2StandardERC20Gateway(address(1), address(1), address(1), address(factory));

        // Deploy L1 contracts
        gateway = _deployGateway(address(l1Messenger));

        // Initialize L1 contracts
        gateway.initialize();

        address[] memory addresses = new address[](1);
        addresses[0] = address(gateway);
        gatewayWhitelist.updateWhitelistStatus(addresses, true);

        // Prepare token balances
        l2Token = MockERC20(gateway.getL2ERC20Address(address(l1Token)));
        l1Token.mint(address(this), type(uint128).max);
        l1Token.approve(address(gateway), type(uint256).max);

        reentrantToken.mint(address(this), type(uint128).max);
        reentrantToken.approve(address(gateway), type(uint256).max);

        feeToken.mint(address(this), type(uint128).max);
        feeToken.approve(address(gateway), type(uint256).max);
    }

    function testInitialized() public {
        // state in OwnableUpgradeable
        assertEq(address(this), gateway.owner());

        // state in ScrollGatewayBase
        assertEq(address(l1Messenger), gateway.messenger());
        assertEq(address(0), gateway.router());
        assertEq(address(counterpartGateway), gateway.counterpart());

        // state in L1ERC20GatewayValidium
        assertEq(address(template), gateway.l2TokenImplementation());
        assertEq(address(factory), gateway.l2TokenFactory());

        // revert when initializing again
        hevm.expectRevert("Initializable: contract is already initialized");
        gateway.initialize();
    }

    function testGetL2ERC20Address(address l1Address) public {
        assertEq(
            gateway.getL2ERC20Address(l1Address),
            factory.computeL2TokenAddress(address(counterpartGateway), l1Address)
        );
    }

    function testDepositERC20(
        uint256 amount,
        bytes memory recipient,
        uint256 gasLimit
    ) public {
        _deposit(address(this), amount, recipient, gasLimit);
    }

    function testDepositERC20WithSender(
        address sender,
        uint256 amount,
        bytes memory recipient,
        uint256 gasLimit
    ) public {
        _deposit(sender, amount, recipient, gasLimit);
    }

    function testDepositERC20WrongKey(
        uint256 amount,
        bytes memory recipient,
        uint256 gasLimit
    ) public {
        (uint256 keyId, ) = rollup.getLatestEncryptionKey();
        hevm.expectRevert(ScrollChainValidium.ErrorUnknownEncryptionKey.selector);
        gateway.depositERC20(address(l1Token), recipient, amount, gasLimit, keyId + 1);
    }

    function testDepositReentrantToken(uint256 amount) public {
        (uint256 keyId, ) = rollup.getLatestEncryptionKey();

        // should revert, reentrant before transfer
        reentrantToken.setReentrantCall(
            address(gateway),
            0,
            abi.encodeWithSignature(
                "depositERC20(address,bytes,uint256,uint256,uint256)",
                address(reentrantToken),
                new bytes(0),
                amount,
                defaultGasLimit,
                keyId
            ),
            true
        );
        amount = bound(amount, 1, reentrantToken.balanceOf(address(this)));
        hevm.expectRevert("ReentrancyGuard: reentrant call");

        gateway.depositERC20(address(reentrantToken), new bytes(0), amount, defaultGasLimit, keyId);

        // should revert, reentrant after transfer
        reentrantToken.setReentrantCall(
            address(gateway),
            0,
            abi.encodeWithSignature(
                "depositERC20(address,bytes,uint256,uint256,uint256)",
                address(reentrantToken),
                new bytes(0),
                amount,
                defaultGasLimit,
                keyId
            ),
            false
        );
        amount = bound(amount, 1, reentrantToken.balanceOf(address(this)));
        hevm.expectRevert("ReentrancyGuard: reentrant call");
        gateway.depositERC20(address(reentrantToken), new bytes(0), amount, defaultGasLimit, keyId);
    }

    function testFeeOnTransferTokenFailed(uint256 amount) public {
        feeToken.setFeeRate(1e9);
        amount = bound(amount, 1, feeToken.balanceOf(address(this)));
        (uint256 keyId, ) = rollup.getLatestEncryptionKey();
        hevm.expectRevert(L1ERC20GatewayValidium.ErrorAmountIsZero.selector);
        gateway.depositERC20(address(feeToken), new bytes(0), amount, defaultGasLimit, keyId);
    }

    function testFeeOnTransferTokenSucceed(uint256 amount, uint256 feeRate) public {
        feeRate = bound(feeRate, 0, 1e9 - 1);
        amount = bound(amount, 1e9, feeToken.balanceOf(address(this)));
        feeToken.setFeeRate(feeRate);

        // should succeed, for valid amount
        uint256 balanceBefore = feeToken.balanceOf(address(gateway));
        uint256 fee = (amount * feeRate) / 1e9;
        (uint256 keyId, ) = rollup.getLatestEncryptionKey();
        gateway.depositERC20(address(feeToken), new bytes(0), amount, defaultGasLimit, keyId);
        uint256 balanceAfter = feeToken.balanceOf(address(gateway));
        assertEq(balanceBefore + amount - fee, balanceAfter);
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
        gateway.initialize();

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
        hevm.expectRevert(L1ERC20GatewayValidium.ErrorMsgValueNotZero.selector);
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
    }

    function testFinalizeWithdrawERC20Failed(
        address sender,
        address recipient,
        uint256 amount,
        bytes memory dataToCall
    ) public {
        // blacklist some addresses
        hevm.assume(recipient != address(0));

        amount = bound(amount, 1, l1Token.balanceOf(address(this)));

        // deposit some token to L1ERC20GatewayValidium
        (uint256 keyId, ) = rollup.getLatestEncryptionKey();
        gateway.depositERC20(address(l1Token), new bytes(0), amount, defaultGasLimit, keyId);

        // do finalize withdraw token
        bytes memory message = abi.encodeWithSelector(
            IL1ERC20GatewayValidium.finalizeWithdrawERC20.selector,
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

        amount = bound(amount, 1, l1Token.balanceOf(address(this)));

        // deposit some token to L1ERC20GatewayValidium
        (uint256 keyId, ) = rollup.getLatestEncryptionKey();
        gateway.depositERC20(address(l1Token), new bytes(0), amount, defaultGasLimit, keyId);

        // do finalize withdraw token
        bytes memory message = abi.encodeWithSelector(
            IL1ERC20GatewayValidium.finalizeWithdrawERC20.selector,
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

        // emit FinalizeWithdrawERC20 from L1ERC20GatewayValidium
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

    function _deposit(
        address from,
        uint256 amount,
        bytes memory recipient,
        uint256 gasLimit
    ) private {
        amount = bound(amount, 0, l1Token.balanceOf(address(this)));
        gasLimit = bound(gasLimit, defaultGasLimit / 2, defaultGasLimit);
        setL2BaseFee(0);

        bytes memory message = abi.encodeWithSelector(
            IL2ERC20GatewayValidium.finalizeDepositERC20Encrypted.selector,
            address(l1Token),
            address(l2Token),
            from,
            recipient,
            amount,
            abi.encode(true, abi.encode(new bytes(0), abi.encode(l1Token.symbol(), l1Token.name(), l1Token.decimals())))
        );
        bytes memory xDomainCalldata = abi.encodeWithSignature(
            "relayMessage(address,address,uint256,uint256,bytes)",
            address(gateway),
            address(counterpartGateway),
            0,
            0,
            message
        );

        if (amount == 0) {
            (uint256 keyId, ) = rollup.getLatestEncryptionKey();
            hevm.expectRevert(L1ERC20GatewayValidium.ErrorAmountIsZero.selector);
            if (from == address(this)) {
                gateway.depositERC20(address(l1Token), recipient, amount, gasLimit, keyId);
            } else {
                gateway.depositERC20(address(l1Token), from, recipient, amount, gasLimit, keyId);
            }
        } else {
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
            emit DepositERC20(address(l1Token), address(l2Token), from, recipient, amount, new bytes(0));

            uint256 gatewayBalance = l1Token.balanceOf(address(gateway));
            uint256 feeVaultBalance = address(feeVault).balance;
            assertEq(l1Messenger.messageSendTimestamp(keccak256(xDomainCalldata)), 0);
            (uint256 keyId, ) = rollup.getLatestEncryptionKey();
            if (from == address(this)) {
                gateway.depositERC20(address(l1Token), recipient, amount, gasLimit, keyId);
            } else {
                gateway.depositERC20(address(l1Token), from, recipient, amount, gasLimit, keyId);
            }
            assertEq(amount + gatewayBalance, l1Token.balanceOf(address(gateway)));
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
