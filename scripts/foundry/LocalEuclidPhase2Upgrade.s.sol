// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.24;

// solhint-disable no-console

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";

import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {ITransparentUpgradeableProxy, TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import {EnforcedTxGateway} from "../../src/L1/gateways/EnforcedTxGateway.sol";
import {L1MessageQueueV2} from "../../src/L1/rollup/L1MessageQueueV2.sol";
import {L1ScrollMessenger} from "../../src/L1/L1ScrollMessenger.sol";
import {ScrollChainMockFinalize} from "../../src/mocks/ScrollChainMockFinalize.sol";
import {SystemConfig} from "../../src/L1/system-contract/SystemConfig.sol";

// solhint-disable max-states-count
// solhint-disable state-visibility
// solhint-disable var-name-mixedcase

contract LocalEuclidPhase2Upgrade is Script {
    uint256 L1_DEPLOYER_PRIVATE_KEY = vm.envUint("L1_DEPLOYER_PRIVATE_KEY");

    uint64 CHAIN_ID_L2 = uint64(vm.envUint("CHAIN_ID_L2"));
    uint256 MAX_L1_MESSAGE_GAS_LIMIT = vm.envUint("MAX_L1_MESSAGE_GAS_LIMIT");
    uint256 FINALIZE_BATCH_DEADLINE_SEC = vm.envUint("FINALIZE_BATCH_DEADLINE_SEC");
    uint256 RELAY_MESSAGE_DEADLINE_SEC = vm.envUint("RELAY_MESSAGE_DEADLINE_SEC");

    address L1_PROXY_ADMIN_ADDR = vm.envAddress("L1_PROXY_ADMIN_ADDR");
    address L1_SCROLL_CHAIN_PROXY_ADDR = vm.envAddress("L1_SCROLL_CHAIN_PROXY_ADDR");
    address L1_MESSAGE_QUEUE_V1_PROXY_ADDR = vm.envAddress("L1_MESSAGE_QUEUE_V1_PROXY_ADDR");
    address L1_SCROLL_MESSENGER_PROXY_ADDR = vm.envAddress("L1_SCROLL_MESSENGER_PROXY_ADDR");
    address L1_MULTIPLE_VERSION_ROLLUP_VERIFIER_ADDR = vm.envAddress("L1_MULTIPLE_VERSION_ROLLUP_VERIFIER_ADDR");
    address L1_FEE_VAULT_ADDR = vm.envAddress("L1_FEE_VAULT_ADDR");
    address L1_ENFORCED_TX_GATEWAY_PROXY_ADDR = vm.envAddress("L1_ENFORCED_TX_GATEWAY_PROXY_ADDR");

    address L2GETH_SIGNER_ADDRESS = vm.envAddress("L2GETH_SIGNER_ADDRESS");
    address L2_SCROLL_MESSENGER_PROXY_ADDR = vm.envAddress("L2_SCROLL_MESSENGER_PROXY_ADDR");

    ProxyAdmin proxyAdmin;

    address L1_SYSTEM_CONFIG_PROXY_ADDR;
    address L1_MESSAGE_QUEUE_V2_PROXY_ADDR;
    address L1_MESSAGE_QUEUE_V2_IMPLEMENTATION_ADDR;
    address L1_SCROLL_CHAIN_IMPLEMENTATION_ADDR;
    address L1_SCROLL_MESSENGER_IMPLEMENTATION_ADDR;
    address L1_ENFORCED_TX_GATEWAY_IMPLEMENTATION_ADDR;

    function run() external {
        console.log("Deployer:", vm.addr(L1_DEPLOYER_PRIVATE_KEY));
        vm.startBroadcast(L1_DEPLOYER_PRIVATE_KEY);

        proxyAdmin = ProxyAdmin(L1_PROXY_ADMIN_ADDR);

        deploySystemConfig();
        deployL1MessageQueueV2();
        deployScrollChainImpl();
        deployL1ScrollMessengerImpl();
        deployEnforcedTxGatewayImpl();

        upgradeAndInitialize();

        vm.stopBroadcast();
    }

    function upgradeAndInitialize() internal {
        // upgrade SystemConfig and initialize
        SystemConfig(L1_SYSTEM_CONFIG_PROXY_ADDR).initialize(
            vm.addr(L1_DEPLOYER_PRIVATE_KEY),
            L2GETH_SIGNER_ADDRESS,
            SystemConfig.MessageQueueParameters({
                maxGasLimit: uint32(MAX_L1_MESSAGE_GAS_LIMIT),
                baseFeeOverhead: 1000000000,
                baseFeeScalar: 1000000000
            }),
            SystemConfig.EnforcedBatchParameters({
                maxDelayEnterEnforcedMode: uint24(FINALIZE_BATCH_DEADLINE_SEC),
                maxDelayMessageQueue: uint24(RELAY_MESSAGE_DEADLINE_SEC)
            })
        );

        // upgrade L1MessageQueueV2 and initialize
        proxyAdmin.upgrade(
            ITransparentUpgradeableProxy(L1_MESSAGE_QUEUE_V2_PROXY_ADDR),
            L1_MESSAGE_QUEUE_V2_IMPLEMENTATION_ADDR
        );
        L1MessageQueueV2(L1_MESSAGE_QUEUE_V2_PROXY_ADDR).initialize();

        // upgrade ScrollChain and initializeV2
        proxyAdmin.upgrade(
            ITransparentUpgradeableProxy(L1_SCROLL_CHAIN_PROXY_ADDR),
            L1_SCROLL_CHAIN_IMPLEMENTATION_ADDR
        );
        ScrollChainMockFinalize(L1_SCROLL_CHAIN_PROXY_ADDR).initializeV2();

        // upgrade L1ScrollMessenger
        proxyAdmin.upgrade(
            ITransparentUpgradeableProxy(L1_SCROLL_MESSENGER_PROXY_ADDR),
            L1_SCROLL_MESSENGER_IMPLEMENTATION_ADDR
        );

        // upgrade EnforcedTxGateway
        proxyAdmin.upgrade(
            ITransparentUpgradeableProxy(L1_ENFORCED_TX_GATEWAY_PROXY_ADDR),
            L1_ENFORCED_TX_GATEWAY_IMPLEMENTATION_ADDR
        );
    }

    function deploySystemConfig() internal {
        SystemConfig impl = new SystemConfig();
        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(
            address(impl),
            address(proxyAdmin),
            new bytes(0)
        );

        L1_SYSTEM_CONFIG_PROXY_ADDR = address(proxy);
        logAddress("L1_SYSTEM_CONFIG_IMPLEMENTATION_ADDR", address(impl));
        logAddress("L1_SYSTEM_CONFIG_PROXY_ADDR", address(proxy));
    }

    function deployL1MessageQueueV2() internal {
        L1MessageQueueV2 v2_impl = new L1MessageQueueV2(
            L1_SCROLL_MESSENGER_PROXY_ADDR,
            L1_SCROLL_CHAIN_PROXY_ADDR,
            L1_ENFORCED_TX_GATEWAY_PROXY_ADDR,
            L1_MESSAGE_QUEUE_V1_PROXY_ADDR,
            L1_SYSTEM_CONFIG_PROXY_ADDR
        );
        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(
            address(v2_impl),
            address(proxyAdmin),
            new bytes(0)
        );
        L1_MESSAGE_QUEUE_V2_PROXY_ADDR = address(proxy);
        L1_MESSAGE_QUEUE_V2_IMPLEMENTATION_ADDR = address(v2_impl);
        logAddress("L1_MESSAGE_QUEUE_V2_PROXY_ADDR", address(proxy));
        logAddress("L1_MESSAGE_QUEUE_V2_IMPLEMENTATION_ADDR", address(v2_impl));
    }

    function deployScrollChainImpl() internal {
        ScrollChainMockFinalize impl = new ScrollChainMockFinalize(
            CHAIN_ID_L2,
            L1_MESSAGE_QUEUE_V1_PROXY_ADDR,
            L1_MESSAGE_QUEUE_V2_PROXY_ADDR,
            L1_MULTIPLE_VERSION_ROLLUP_VERIFIER_ADDR,
            L1_SYSTEM_CONFIG_PROXY_ADDR
        );
        L1_SCROLL_CHAIN_IMPLEMENTATION_ADDR = address(impl);
        logAddress("L1_SCROLL_CHAIN_IMPLEMENTATION_ADDR", address(impl));
    }

    function deployL1ScrollMessengerImpl() internal {
        L1ScrollMessenger impl = new L1ScrollMessenger(
            L2_SCROLL_MESSENGER_PROXY_ADDR,
            L1_SCROLL_CHAIN_PROXY_ADDR,
            L1_MESSAGE_QUEUE_V1_PROXY_ADDR,
            L1_MESSAGE_QUEUE_V2_PROXY_ADDR
        );

        L1_SCROLL_MESSENGER_IMPLEMENTATION_ADDR = address(impl);
        logAddress("L1_SCROLL_MESSENGER_IMPLEMENTATION_ADDR", address(impl));
    }

    function deployEnforcedTxGatewayImpl() internal {
        EnforcedTxGateway impl = new EnforcedTxGateway(L1_MESSAGE_QUEUE_V2_PROXY_ADDR, L1_FEE_VAULT_ADDR);

        L1_ENFORCED_TX_GATEWAY_IMPLEMENTATION_ADDR = address(impl);
        logAddress("L1_ENFORCED_TX_GATEWAY_IMPLEMENTATION_ADDR", address(impl));
    }

    function logAddress(string memory name, address addr) internal view {
        console.log(string(abi.encodePacked(name, "=", vm.toString(address(addr)))));
    }
}
