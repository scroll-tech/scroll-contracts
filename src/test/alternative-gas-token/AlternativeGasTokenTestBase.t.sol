// SPDX-License-Identifier: MIT

pragma solidity =0.8.24;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";

import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {ITransparentUpgradeableProxy, TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import {L1GasTokenGateway} from "../../alternative-gas-token/L1GasTokenGateway.sol";
import {L1ScrollMessengerNonETH} from "../../alternative-gas-token/L1ScrollMessengerNonETH.sol";
import {L1GatewayRouter} from "../../L1/gateways/L1GatewayRouter.sol";
import {EnforcedTxGateway} from "../../L1/gateways/EnforcedTxGateway.sol";
import {L1MessageQueueWithGasPriceOracle} from "../../L1/rollup/L1MessageQueueWithGasPriceOracle.sol";
import {L2GasPriceOracle} from "../../L1/rollup/L2GasPriceOracle.sol";
import {ScrollChain, IScrollChain} from "../../L1/rollup/ScrollChain.sol";
import {L2GatewayRouter} from "../../L2/gateways/L2GatewayRouter.sol";
import {L2ETHGateway} from "../../L2/gateways/L2ETHGateway.sol";
import {L2MessageQueue} from "../../L2/predeploys/L2MessageQueue.sol";
import {Whitelist} from "../../L2/predeploys/Whitelist.sol";
import {L2ScrollMessenger, IL2ScrollMessenger} from "../../L2/L2ScrollMessenger.sol";
import {AddressAliasHelper} from "../../libraries/common/AddressAliasHelper.sol";
import {EmptyContract} from "../../misc/EmptyContract.sol";

import {MockRollupVerifier} from "../mocks/MockRollupVerifier.sol";

abstract contract AlternativeGasTokenTestBase is Test {
    // from L1MessageQueue
    event QueueTransaction(
        address indexed sender,
        address indexed target,
        uint256 value,
        uint64 queueIndex,
        uint256 gasLimit,
        bytes data
    );

    // from L1ScrollMessengerNonETH
    event SentMessage(
        address indexed sender,
        address indexed target,
        uint256 value,
        uint256 messageNonce,
        uint256 gasLimit,
        bytes message
    );
    event RelayedMessage(bytes32 indexed messageHash);
    event FailedRelayedMessage(bytes32 indexed messageHash);

    bytes32 private constant SENT_MESSAGE_TOPIC =
        keccak256("SentMessage(address,address,uint256,uint256,uint256,bytes)");

    ProxyAdmin internal admin;
    EmptyContract private placeholder;

    // L1 contracts
    L1ScrollMessengerNonETH internal l1Messenger;
    L1MessageQueueWithGasPriceOracle internal l1MessageQueue;
    ScrollChain internal rollup;
    L1GasTokenGateway internal l1GasTokenGateway;
    L1GatewayRouter internal l1Router;
    address internal l1FeeVault;

    // L2 contracts
    L2ScrollMessenger internal l2Messenger;
    L2MessageQueue internal l2MessageQueue;
    L2ETHGateway internal l2ETHGateway;
    L2GatewayRouter internal l2Router;

    uint256 private lastFromL2LogIndex;
    uint256 private lastFromL1LogIndex;

    function __AlternativeGasTokenTestBase_setUp(uint64 l2ChainId, address gasToken) internal {
        admin = new ProxyAdmin();
        placeholder = new EmptyContract();

        // deploy proxy and contracts in L1
        l1FeeVault = address(uint160(address(this)) - 1);
        l1MessageQueue = L1MessageQueueWithGasPriceOracle(_deployProxy(address(0)));
        rollup = ScrollChain(_deployProxy(address(0)));
        l1Messenger = L1ScrollMessengerNonETH(payable(_deployProxy(address(0))));
        l1GasTokenGateway = L1GasTokenGateway(_deployProxy(address(0)));
        l1Router = L1GatewayRouter(_deployProxy(address(0)));
        L2GasPriceOracle gasOracle = L2GasPriceOracle(_deployProxy(address(new L2GasPriceOracle())));
        Whitelist whitelist = new Whitelist(address(this));
        MockRollupVerifier verifier = new MockRollupVerifier();

        // deploy proxy and contracts in L2
        l2MessageQueue = new L2MessageQueue(address(this));
        l2Messenger = L2ScrollMessenger(payable(_deployProxy(address(0))));
        l2ETHGateway = L2ETHGateway(payable(_deployProxy(address(0))));
        l2Router = L2GatewayRouter(_deployProxy(address(0)));

        // Upgrade the L1ScrollMessengerNonETH implementation and initialize
        admin.upgrade(
            ITransparentUpgradeableProxy(address(l1Messenger)),
            address(
                new L1ScrollMessengerNonETH(
                    address(l1GasTokenGateway),
                    address(l2Messenger),
                    address(rollup),
                    address(l1MessageQueue)
                )
            )
        );
        l1Messenger.initialize(address(l2Messenger), l1FeeVault, address(rollup), address(l1MessageQueue));

        // initialize L2GasPriceOracle
        gasOracle.initialize(1, 2, 1, 1);
        gasOracle.updateWhitelist(address(whitelist));

        // Upgrade the L1MessageQueueWithGasPriceOracle implementation and initialize
        admin.upgrade(
            ITransparentUpgradeableProxy(address(l1MessageQueue)),
            address(new L1MessageQueueWithGasPriceOracle(address(l1Messenger), address(rollup), address(1)))
        );
        l1MessageQueue.initialize(address(l1Messenger), address(rollup), address(this), address(gasOracle), 10000000);
        l1MessageQueue.initializeV2();

        // Upgrade the ScrollChain implementation and initialize
        admin.upgrade(
            ITransparentUpgradeableProxy(address(rollup)),
            address(new ScrollChain(l2ChainId, address(l1MessageQueue), address(verifier)))
        );
        rollup.initialize(address(l1MessageQueue), address(verifier), 44);

        // Upgrade the L1GasTokenGateway implementation and initialize
        admin.upgrade(
            ITransparentUpgradeableProxy(address(l1GasTokenGateway)),
            address(new L1GasTokenGateway(gasToken, address(l2ETHGateway), address(l1Router), address(l1Messenger)))
        );
        l1GasTokenGateway.initialize();

        // Upgrade the L1GatewayRouter implementation and initialize
        admin.upgrade(ITransparentUpgradeableProxy(address(l1Router)), address(new L1GatewayRouter()));
        l1Router.initialize(address(l1GasTokenGateway), address(0));

        // L2ScrollMessenger
        admin.upgrade(
            ITransparentUpgradeableProxy(address(l2Messenger)),
            address(new L2ScrollMessenger(address(l1Messenger), address(l2MessageQueue)))
        );
        l2Messenger.initialize(address(0));
        l2MessageQueue.initialize(address(l2Messenger));

        // L2ETHGateway
        admin.upgrade(
            ITransparentUpgradeableProxy(address(l2ETHGateway)),
            address(new L2ETHGateway(address(l1GasTokenGateway), address(l2Router), address(l2Messenger)))
        );
        l2ETHGateway.initialize(address(l1GasTokenGateway), address(l2Router), address(l2Messenger));

        // L2GatewayRouter
        admin.upgrade(ITransparentUpgradeableProxy(address(l2Router)), address(new L2GatewayRouter()));
        l2Router.initialize(address(l2ETHGateway), address(0));

        // Setup whitelist in L1
        address[] memory _accounts = new address[](1);
        _accounts[0] = address(this);
        whitelist.updateWhitelistStatus(_accounts, true);

        // Make nonzero block.timestamp
        vm.warp(1);

        // Allocate balance to l2Messenger
        vm.deal(address(l2Messenger), type(uint256).max / 2);
    }

    function _deployProxy(address _logic) internal returns (address) {
        if (_logic == address(0)) _logic = address(placeholder);
        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(_logic, address(admin), new bytes(0));
        return address(proxy);
    }

    function relayFromL1() internal {
        address malias = AddressAliasHelper.applyL1ToL2Alias(address(l1Messenger));

        // Read all L1 -> L2 messages and relay them
        Vm.Log[] memory allLogs = vm.getRecordedLogs();
        for (; lastFromL1LogIndex < allLogs.length; lastFromL1LogIndex++) {
            Vm.Log memory _log = allLogs[lastFromL1LogIndex];
            if (_log.topics[0] == SENT_MESSAGE_TOPIC && _log.emitter == address(l1Messenger)) {
                address sender = address(uint160(uint256(_log.topics[1])));
                address target = address(uint160(uint256(_log.topics[2])));
                (uint256 value, uint256 nonce, uint256 gasLimit, bytes memory message) = abi.decode(
                    _log.data,
                    (uint256, uint256, uint256, bytes)
                );
                vm.prank(malias);
                IL2ScrollMessenger(l2Messenger).relayMessage{gas: gasLimit}(sender, target, value, nonce, message);
            }
        }
    }

    function relayFromL2() internal {
        // Read all L2 -> L1 messages and relay them
        // Note: We bypass the L1 messenger relay here because it's easier to not have to generate valid state roots / merkle proofs
        Vm.Log[] memory allLogs = vm.getRecordedLogs();
        for (; lastFromL2LogIndex < allLogs.length; lastFromL2LogIndex++) {
            Vm.Log memory _log = allLogs[lastFromL2LogIndex];
            if (_log.topics[0] == SENT_MESSAGE_TOPIC && _log.emitter == address(l2Messenger)) {
                address sender = address(uint160(uint256(_log.topics[1])));
                address target = address(uint160(uint256(_log.topics[2])));
                (, , , bytes memory message) = abi.decode(_log.data, (uint256, uint256, uint256, bytes));
                // Set xDomainMessageSender
                vm.store(address(l1Messenger), bytes32(uint256(201)), bytes32(uint256(uint160(sender))));
                vm.startPrank(address(l1Messenger));
                (bool success, bytes memory response) = target.call(message);
                vm.stopPrank();
                vm.store(address(l1Messenger), bytes32(uint256(201)), bytes32(uint256(1)));
                if (!success) {
                    assembly {
                        revert(add(response, 32), mload(response))
                    }
                }
            }
        }
    }

    function encodeXDomainCalldata(
        address _sender,
        address _target,
        uint256 _value,
        uint256 _messageNonce,
        bytes memory _message
    ) internal pure returns (bytes memory) {
        return abi.encodeCall(IL2ScrollMessenger.relayMessage, (_sender, _target, _value, _messageNonce, _message));
    }

    function prepareFinalizedBatch(bytes32 messageHash) internal {
        rollup.addSequencer(address(0));
        rollup.addProver(address(0));

        // import genesis batch
        bytes memory batchHeader0 = new bytes(89);
        assembly {
            mstore(add(batchHeader0, add(0x20, 25)), 1)
        }
        rollup.importGenesisBatch(batchHeader0, bytes32(uint256(1)));
        bytes32 batchHash0 = rollup.committedBatches(0);

        // commit one batch
        bytes[] memory chunks = new bytes[](1);
        bytes memory chunk0 = new bytes(1 + 60);
        chunk0[0] = bytes1(uint8(1)); // one block in this chunk
        chunks[0] = chunk0;
        vm.startPrank(address(0));
        rollup.commitBatch(0, batchHeader0, chunks, new bytes(0));
        vm.stopPrank();

        bytes memory batchHeader1 = new bytes(89);
        assembly {
            mstore(add(batchHeader1, 0x20), 0) // version
            mstore(add(batchHeader1, add(0x20, 1)), shl(192, 1)) // batchIndex
            mstore(add(batchHeader1, add(0x20, 9)), 0) // l1MessagePopped
            mstore(add(batchHeader1, add(0x20, 17)), 0) // totalL1MessagePopped
            mstore(add(batchHeader1, add(0x20, 25)), 0x246394445f4fe64ed5598554d55d1682d6fb3fe04bf58eb54ef81d1189fafb51) // dataHash
            mstore(add(batchHeader1, add(0x20, 57)), batchHash0) // parentBatchHash
        }

        vm.startPrank(address(0));
        rollup.finalizeBatchWithProof(
            batchHeader1,
            bytes32(uint256(1)),
            bytes32(uint256(2)),
            messageHash,
            new bytes(0)
        );
        vm.stopPrank();
    }
}
