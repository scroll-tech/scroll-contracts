// SPDX-License-Identifier: MIT

pragma solidity =0.8.24;

import {DSTestPlus} from "solmate/test/utils/DSTestPlus.sol";

import {ITransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import {L1MessageQueueV2} from "../../L1/rollup/L1MessageQueueV2.sol";
import {SystemConfig} from "../../L1/system-contract/SystemConfig.sol";
import {Whitelist} from "../../L2/predeploys/Whitelist.sol";
import {L2ScrollMessenger} from "../../L2/L2ScrollMessenger.sol";

import {EmptyL1MessageQueueV1} from "../../validium/EmptyL1MessageQueueV1.sol";
import {L1ScrollMessengerValidium} from "../../validium/L1ScrollMessengerValidium.sol";
import {ScrollChainValidium} from "../../validium/ScrollChainValidium.sol";

import {ScrollChainValidiumMock} from "../../mocks/ScrollChainValidiumMock.sol";
import {MockRollupVerifier} from "../mocks/MockRollupVerifier.sol";
import {ScrollTestBase} from "../ScrollTestBase.t.sol";

// solhint-disable no-inline-assembly

abstract contract ValidiumTestBase is ScrollTestBase {
    // from L1MessageQueueV2
    event QueueTransaction(
        address indexed sender,
        address indexed target,
        uint256 value,
        uint64 queueIndex,
        uint256 gasLimit,
        bytes data
    );

    // from L1ScrollMessenger
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

    /**********
     * Errors *
     **********/

    // from IScrollGateway
    error ErrorZeroAddress();
    error ErrorCallerIsNotMessenger();
    error ErrorCallerIsNotCounterpartGateway();
    error ErrorNotInDropMessageContext();

    uint32 internal constant defaultGasLimit = 1000000;

    SystemConfig internal systemConfig;
    Whitelist internal gatewayWhitelist;
    L1ScrollMessengerValidium internal l1Messenger;
    EmptyL1MessageQueueV1 internal messageQueueV1;
    L1MessageQueueV2 internal messageQueueV2;
    ScrollChainValidium internal rollup;

    MockRollupVerifier internal verifier;

    address internal feeVault;

    L2ScrollMessenger internal l2Messenger;

    function __ValidiumTestBase_setUp(uint32 _chainId) internal {
        __ScrollTestBase_setUp();

        feeVault = address(uint160(address(this)) - 1);

        // deploy proxy and contracts in L1
        systemConfig = SystemConfig(_deployProxy(address(0)));
        l1Messenger = L1ScrollMessengerValidium(payable(_deployProxy(address(0))));
        messageQueueV1 = new EmptyL1MessageQueueV1();
        messageQueueV2 = L1MessageQueueV2(_deployProxy(address(0)));
        rollup = ScrollChainValidiumMock(_deployProxy(address(0)));
        gatewayWhitelist = new Whitelist(address(this));
        verifier = new MockRollupVerifier();

        // deploy proxy and contracts in L2
        l2Messenger = L2ScrollMessenger(payable(_deployProxy(address(0))));

        // Upgrade the SystemConfig implementation and initialize
        admin.upgrade(ITransparentUpgradeableProxy(address(systemConfig)), address(new SystemConfig()));
        systemConfig.initialize(
            address(this),
            address(uint160(1)),
            SystemConfig.MessageQueueParameters({maxGasLimit: 1000000, baseFeeOverhead: 0, baseFeeScalar: 0}),
            SystemConfig.EnforcedBatchParameters({maxDelayEnterEnforcedMode: 0, maxDelayMessageQueue: 0})
        );

        // Upgrade the L1ScrollMessengerValidium implementation and initialize
        admin.upgrade(
            ITransparentUpgradeableProxy(address(l1Messenger)),
            address(
                new L1ScrollMessengerValidium(
                    address(l2Messenger),
                    address(rollup),
                    address(messageQueueV2),
                    address(gatewayWhitelist)
                )
            )
        );
        l1Messenger.initialize(address(0), feeVault, address(0), address(0));

        // Upgrade the L1MessageQueueV2 implementation and initialize
        admin.upgrade(
            ITransparentUpgradeableProxy(address(messageQueueV2)),
            address(
                new L1MessageQueueV2(
                    address(l1Messenger),
                    address(rollup),
                    address(0),
                    address(messageQueueV1),
                    address(systemConfig)
                )
            )
        );
        messageQueueV2.initialize();

        // Upgrade the ScrollChain implementation and initialize
        admin.upgrade(
            ITransparentUpgradeableProxy(address(rollup)),
            address(new ScrollChainValidium(_chainId, address(messageQueueV2), address(verifier)))
        );
        rollup.initialize(address(this));
        rollup.grantRole(rollup.KEY_MANAGER_ROLE(), address(this));
        rollup.registerNewEncryptionKey(hex"123456789012345678901234567890123456789012345678901234567890123456");

        // Make nonzero block.timestamp
        hevm.warp(1);
    }

    function prepareL2MessageRoot(bytes32 messageHash) internal {
        rollup.grantRole(rollup.SEQUENCER_ROLE(), address(0));
        rollup.grantRole(rollup.PROVER_ROLE(), address(0));

        // import genesis batch
        bytes memory batchHeader0 = abi.encodePacked(
            bytes1(uint8(0)), // version
            uint64(0), // batchIndex
            bytes32(0), // parentBatchHash
            keccak256("0"), // postStateRoot
            bytes32(0), // withdrawRoot
            bytes32(0) // commitment
        );
        rollup.grantRole(rollup.GENESIS_IMPORTER_ROLE(), address(this));
        rollup.importGenesisBatch(batchHeader0);
        bytes32 batchHash0 = rollup.committedBatches(0);

        // commit one batch
        bytes[] memory chunks = new bytes[](1);
        bytes memory chunk0 = new bytes(1 + 60);
        chunk0[0] = bytes1(uint8(1)); // one block in this chunk
        chunks[0] = chunk0;
        hevm.startPrank(address(0));
        rollup.commitBatch(4, batchHash0, keccak256("1"), messageHash, new bytes(32));
        hevm.stopPrank();

        bytes memory batchHeader1 = abi.encodePacked(
            bytes1(uint8(4)), // version
            uint64(1), // batchIndex
            batchHash0, // parentBatchHash
            keccak256("1"), // postStateRoot
            messageHash, // withdrawRoot
            bytes32(0) // commitment
        );
        hevm.startPrank(address(0));
        rollup.finalizeBundle(batchHeader1, 0, new bytes(0));
        hevm.stopPrank();

        rollup.lastFinalizedBatchIndex();
    }

    function setL2BaseFee(uint256 feePerGas) internal {
        setL2BaseFee(feePerGas, 1000000);
    }

    function setL2BaseFee(uint256 feePerGas, uint256 gasLimit) internal {
        systemConfig.updateMessageQueueParameters(
            SystemConfig.MessageQueueParameters({
                maxGasLimit: uint32(gasLimit),
                baseFeeOverhead: uint112(0),
                baseFeeScalar: uint112(1 ether)
            })
        );
        hevm.fee(feePerGas);
        assertEq(messageQueueV2.estimateL2BaseFee(), feePerGas);
    }
}
