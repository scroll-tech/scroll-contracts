// SPDX-License-Identifier: MIT

pragma solidity =0.8.24;

import {DSTestPlus} from "solmate/test/utils/DSTestPlus.sol";

import {ITransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import {EnforcedTxGateway} from "../L1/gateways/EnforcedTxGateway.sol";
import {L1MessageQueueWithGasPriceOracle} from "../L1/rollup/L1MessageQueueWithGasPriceOracle.sol";
import {L2GasPriceOracle} from "../L1/rollup/L2GasPriceOracle.sol";
import {Whitelist} from "../L2/predeploys/Whitelist.sol";
import {L1ScrollMessenger} from "../L1/L1ScrollMessenger.sol";
import {L2ScrollMessenger} from "../L2/L2ScrollMessenger.sol";
import {EmptyContract} from "../misc/EmptyContract.sol";

import {ScrollChainMockBlob} from "../mocks/ScrollChainMockBlob.sol";
import {MockRollupVerifier} from "./mocks/MockRollupVerifier.sol";
import {ScrollTestBase} from "./ScrollTestBase.t.sol";

// solhint-disable no-inline-assembly

abstract contract L1GatewayTestBase is ScrollTestBase {
    // from L1MessageQueue
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

    // pay 0.1 extra ETH to test refund
    uint256 internal constant extraValue = 1e17;

    uint32 internal constant defaultGasLimit = 1000000;

    L1ScrollMessenger internal l1Messenger;
    L1MessageQueueWithGasPriceOracle internal messageQueue;
    L2GasPriceOracle internal gasOracle;
    EnforcedTxGateway internal enforcedTxGateway;
    ScrollChainMockBlob internal rollup;

    MockRollupVerifier internal verifier;

    address internal feeVault;
    Whitelist private whitelist;

    L2ScrollMessenger internal l2Messenger;

    bool internal revertOnReceive;

    receive() external payable {
        if (revertOnReceive) {
            revert("RevertOnReceive");
        }
    }

    function __L1GatewayTestBase_setUp() internal {
        __ScrollTestBase_setUp();

        feeVault = address(uint160(address(this)) - 1);

        // deploy proxy and contracts in L1
        l1Messenger = L1ScrollMessenger(payable(_deployProxy(address(0))));
        messageQueue = L1MessageQueueWithGasPriceOracle(_deployProxy(address(0)));
        rollup = ScrollChainMockBlob(_deployProxy(address(0)));
        enforcedTxGateway = EnforcedTxGateway(_deployProxy(address(new EnforcedTxGateway())));
        gasOracle = L2GasPriceOracle(_deployProxy(address(new L2GasPriceOracle())));
        whitelist = new Whitelist(address(this));
        verifier = new MockRollupVerifier();

        // deploy proxy and contracts in L2
        l2Messenger = L2ScrollMessenger(payable(_deployProxy(address(0))));

        // Upgrade the L1ScrollMessenger implementation and initialize
        admin.upgrade(
            ITransparentUpgradeableProxy(address(l1Messenger)),
            address(new L1ScrollMessenger(address(l2Messenger), address(rollup), address(messageQueue)))
        );
        l1Messenger.initialize(address(l2Messenger), feeVault, address(rollup), address(messageQueue));

        // initialize L2GasPriceOracle
        gasOracle.initialize(1, 2, 1, 1);
        gasOracle.updateWhitelist(address(whitelist));

        // Upgrade the L1MessageQueueWithGasPriceOracle implementation and initialize
        admin.upgrade(
            ITransparentUpgradeableProxy(address(messageQueue)),
            address(new L1MessageQueueWithGasPriceOracle(address(l1Messenger), address(rollup), address(1)))
        );
        messageQueue.initialize(
            address(l1Messenger),
            address(rollup),
            address(enforcedTxGateway),
            address(gasOracle),
            10000000
        );
        messageQueue.initializeV2();

        // Upgrade the ScrollChain implementation and initialize
        admin.upgrade(
            ITransparentUpgradeableProxy(address(rollup)),
            address(new ScrollChainMockBlob(1233, address(messageQueue), address(verifier)))
        );
        rollup.initialize(address(messageQueue), address(0), 44);

        // Setup whitelist
        address[] memory _accounts = new address[](1);
        _accounts[0] = address(this);
        whitelist.updateWhitelistStatus(_accounts, true);

        // Make nonzero block.timestamp
        hevm.warp(1);
    }

    function prepareL2MessageRoot(bytes32 messageHash) internal {
        rollup.addSequencer(address(0));
        rollup.addProver(address(0));

        // import genesis batch
        bytes memory batchHeader0 = new bytes(89);
        assembly {
            mstore(add(batchHeader0, add(0x20, 25)), 1)
        }
        rollup.importGenesisBatch(batchHeader0, bytes32(uint256(1)));
        bytes32 batchHash0 = rollup.committedBatches(0);

        // from https://etherscan.io/blob/0x013590dc3544d56629ba81bb14d4d31248f825001653aa575eb8e3a719046757?bid=740652
        bytes32 blobVersionedHash = 0x013590dc3544d56629ba81bb14d4d31248f825001653aa575eb8e3a719046757;
        bytes
            memory blobDataProof = hex"2c9d777660f14ad49803a6442935c0d24a0d83551de5995890bf70a17d24e68753ab0fe6807c7081f0885fe7da741554d658a03730b1fa006f8319f8b993bcb0a5a0c9e8a145c5ef6e415c245690effa2914ec9393f58a7251d30c0657da1453d9ad906eae8b97dd60c9a216f81b4df7af34d01e214e1ec5865f0133ecc16d7459e49dab66087340677751e82097fbdd20551d66076f425775d1758a9dfd186b";
        rollup.setBlobVersionedHash(blobVersionedHash);

        // commit one batch
        bytes[] memory chunks = new bytes[](1);
        bytes memory chunk0 = new bytes(1 + 60);
        chunk0[0] = bytes1(uint8(1)); // one block in this chunk
        chunks[0] = chunk0;
        hevm.startPrank(address(0));
        rollup.commitBatch(1, batchHeader0, chunks, new bytes(0));
        hevm.stopPrank();

        bytes memory batchHeader1 = new bytes(121);
        assembly {
            mstore8(add(batchHeader1, 0x20), 1) // version
            mstore(add(batchHeader1, add(0x20, 1)), shl(192, 1)) // batchIndex
            mstore(add(batchHeader1, add(0x20, 9)), 0) // l1MessagePopped
            mstore(add(batchHeader1, add(0x20, 17)), 0) // totalL1MessagePopped
            mstore(add(batchHeader1, add(0x20, 25)), 0x246394445f4fe64ed5598554d55d1682d6fb3fe04bf58eb54ef81d1189fafb51) // dataHash
            mstore(add(batchHeader1, add(0x20, 57)), blobVersionedHash) // blobVersionedHash
            mstore(add(batchHeader1, add(0x20, 89)), batchHash0) // parentBatchHash
        }

        hevm.startPrank(address(0));
        rollup.finalizeBatchWithProof4844(
            batchHeader1,
            bytes32(uint256(1)),
            bytes32(uint256(2)),
            messageHash,
            blobDataProof,
            new bytes(0)
        );
        hevm.stopPrank();
    }
}
