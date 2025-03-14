// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.24;

import {Script} from "forge-std/Script.sol";

import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {ITransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import {L1CustomERC20Gateway} from "../../src/L1/gateways/L1CustomERC20Gateway.sol";
import {L1ERC1155Gateway} from "../../src/L1/gateways/L1ERC1155Gateway.sol";
import {L1ERC721Gateway} from "../../src/L1/gateways/L1ERC721Gateway.sol";
import {L1ETHGateway} from "../../src/L1/gateways/L1ETHGateway.sol";
import {L1GatewayRouter} from "../../src/L1/gateways/L1GatewayRouter.sol";
import {L1ScrollMessenger} from "../../src/L1/L1ScrollMessenger.sol";
import {L1StandardERC20Gateway} from "../../src/L1/gateways/L1StandardERC20Gateway.sol";
import {L1WETHGateway} from "../../src/L1/gateways/L1WETHGateway.sol";
import {MultipleVersionRollupVerifier} from "../../src/L1/rollup/MultipleVersionRollupVerifier.sol";
import {ScrollChain} from "../../src/L1/rollup/ScrollChain.sol";
import {L1MessageQueueV1} from "../../src/L1/rollup/L1MessageQueueV1.sol";
import {L1MessageQueueV1WithGasPriceOracle} from "../../src/L1/rollup/L1MessageQueueV1WithGasPriceOracle.sol";
import {L1MessageQueueV2} from "../../src/L1/rollup/L1MessageQueueV2.sol";
import {SystemConfig} from "../../src/L1/system-contract/SystemConfig.sol";
import {L2GasPriceOracle} from "../../src/L1/rollup/L2GasPriceOracle.sol";
import {EnforcedTxGateway} from "../../src/L1/gateways/EnforcedTxGateway.sol";

// solhint-disable max-states-count
// solhint-disable state-visibility
// solhint-disable var-name-mixedcase

contract InitializeL1BridgeContracts is Script {
    uint256 L1_DEPLOYER_PRIVATE_KEY = vm.envUint("L1_DEPLOYER_PRIVATE_KEY");

    uint256 CHAIN_ID_L2 = vm.envUint("CHAIN_ID_L2");
    uint256 MAX_TX_IN_CHUNK = vm.envUint("MAX_TX_IN_CHUNK");
    uint256 MAX_L1_MESSAGE_GAS_LIMIT = vm.envUint("MAX_L1_MESSAGE_GAS_LIMIT");
    uint256 FINALIZE_BATCH_DEADLINE_SEC = vm.envUint("FINALIZE_BATCH_DEADLINE_SEC");
    uint256 RELAY_MESSAGE_DEADLINE_SEC = vm.envUint("RELAY_MESSAGE_DEADLINE_SEC");
    address L2GETH_SIGNER_ADDRESS = vm.envAddress("L2GETH_SIGNER_ADDRESS");
    address L1_COMMIT_SENDER_ADDRESS = vm.envAddress("L1_COMMIT_SENDER_ADDRESS");
    address L1_FINALIZE_SENDER_ADDRESS = vm.envAddress("L1_FINALIZE_SENDER_ADDRESS");
    address L1_FEE_VAULT_ADDR = vm.envAddress("L1_FEE_VAULT_ADDR");
    address L1_WETH_ADDR = vm.envAddress("L1_WETH_ADDR");

    address L1_PROXY_ADMIN_ADDR = vm.envAddress("L1_PROXY_ADMIN_ADDR");

    address L1_WHITELIST_ADDR = vm.envAddress("L1_WHITELIST_ADDR");
    address L1_SCROLL_CHAIN_PROXY_ADDR = vm.envAddress("L1_SCROLL_CHAIN_PROXY_ADDR");
    address L1_SCROLL_CHAIN_IMPLEMENTATION_ADDR = vm.envAddress("L1_SCROLL_CHAIN_IMPLEMENTATION_ADDR");
    address L1_MESSAGE_QUEUE_V1_PROXY_ADDR = vm.envAddress("L1_MESSAGE_QUEUE_V1_PROXY_ADDR");
    address L1_MESSAGE_QUEUE_V1_IMPLEMENTATION_ADDR = vm.envAddress("L1_MESSAGE_QUEUE_V1_IMPLEMENTATION_ADDR");
    address L1_MESSAGE_QUEUE_V2_PROXY_ADDR = vm.envAddress("L1_MESSAGE_QUEUE_V2_PROXY_ADDR");
    address L1_MESSAGE_QUEUE_V2_IMPLEMENTATION_ADDR = vm.envAddress("L1_MESSAGE_QUEUE_V2_IMPLEMENTATION_ADDR");
    address L1_SYSTEM_CONFIG_PROXY_ADDR = vm.envAddress("L1_SYSTEM_CONFIG_PROXY_ADDR");
    address L1_SYSTEM_CONFIG_IMPLEMENTATION_ADDR = vm.envAddress("L1_SYSTEM_CONFIG_IMPLEMENTATION_ADDR");
    address L2_GAS_PRICE_ORACLE_PROXY_ADDR = vm.envAddress("L2_GAS_PRICE_ORACLE_PROXY_ADDR");
    address L1_SCROLL_MESSENGER_PROXY_ADDR = vm.envAddress("L1_SCROLL_MESSENGER_PROXY_ADDR");
    address L1_SCROLL_MESSENGER_IMPLEMENTATION_ADDR = vm.envAddress("L1_SCROLL_MESSENGER_IMPLEMENTATION_ADDR");
    address L1_GATEWAY_ROUTER_PROXY_ADDR = vm.envAddress("L1_GATEWAY_ROUTER_PROXY_ADDR");
    address L1_CUSTOM_ERC20_GATEWAY_PROXY_ADDR = vm.envAddress("L1_CUSTOM_ERC20_GATEWAY_PROXY_ADDR");
    address L1_CUSTOM_ERC20_GATEWAY_IMPLEMENTATION_ADDR = vm.envAddress("L1_CUSTOM_ERC20_GATEWAY_IMPLEMENTATION_ADDR");
    address L1_ERC721_GATEWAY_PROXY_ADDR = vm.envAddress("L1_ERC721_GATEWAY_PROXY_ADDR");
    address L1_ERC721_GATEWAY_IMPLEMENTATION_ADDR = vm.envAddress("L1_ERC721_GATEWAY_IMPLEMENTATION_ADDR");
    address L1_ERC1155_GATEWAY_PROXY_ADDR = vm.envAddress("L1_ERC1155_GATEWAY_PROXY_ADDR");
    address L1_ERC1155_GATEWAY_IMPLEMENTATION_ADDR = vm.envAddress("L1_ERC1155_GATEWAY_IMPLEMENTATION_ADDR");
    address L1_ETH_GATEWAY_PROXY_ADDR = vm.envAddress("L1_ETH_GATEWAY_PROXY_ADDR");
    address L1_ETH_GATEWAY_IMPLEMENTATION_ADDR = vm.envAddress("L1_ETH_GATEWAY_IMPLEMENTATION_ADDR");
    address L1_STANDARD_ERC20_GATEWAY_PROXY_ADDR = vm.envAddress("L1_STANDARD_ERC20_GATEWAY_PROXY_ADDR");
    address L1_STANDARD_ERC20_GATEWAY_IMPLEMENTATION_ADDR =
        vm.envAddress("L1_STANDARD_ERC20_GATEWAY_IMPLEMENTATION_ADDR");
    address L1_WETH_GATEWAY_PROXY_ADDR = vm.envAddress("L1_WETH_GATEWAY_PROXY_ADDR");
    address L1_WETH_GATEWAY_IMPLEMENTATION_ADDR = vm.envAddress("L1_WETH_GATEWAY_IMPLEMENTATION_ADDR");
    address L1_MULTIPLE_VERSION_ROLLUP_VERIFIER_ADDR = vm.envAddress("L1_MULTIPLE_VERSION_ROLLUP_VERIFIER_ADDR");
    address L1_ENFORCED_TX_GATEWAY_PROXY_ADDR = vm.envAddress("L1_ENFORCED_TX_GATEWAY_PROXY_ADDR");

    address L2_SCROLL_MESSENGER_PROXY_ADDR = vm.envAddress("L2_SCROLL_MESSENGER_PROXY_ADDR");
    address L2_CUSTOM_ERC20_GATEWAY_PROXY_ADDR = vm.envAddress("L2_CUSTOM_ERC20_GATEWAY_PROXY_ADDR");
    address L2_ERC721_GATEWAY_PROXY_ADDR = vm.envAddress("L2_ERC721_GATEWAY_PROXY_ADDR");
    address L2_ERC1155_GATEWAY_PROXY_ADDR = vm.envAddress("L2_ERC1155_GATEWAY_PROXY_ADDR");
    address L2_ETH_GATEWAY_PROXY_ADDR = vm.envAddress("L2_ETH_GATEWAY_PROXY_ADDR");
    address L2_STANDARD_ERC20_GATEWAY_PROXY_ADDR = vm.envAddress("L2_STANDARD_ERC20_GATEWAY_PROXY_ADDR");
    address L2_WETH_GATEWAY_PROXY_ADDR = vm.envAddress("L2_WETH_GATEWAY_PROXY_ADDR");
    address L2_SCROLL_STANDARD_ERC20_ADDR = vm.envAddress("L2_SCROLL_STANDARD_ERC20_ADDR");
    address L2_SCROLL_STANDARD_ERC20_FACTORY_ADDR = vm.envAddress("L2_SCROLL_STANDARD_ERC20_FACTORY_ADDR");

    function run() external {
        ProxyAdmin proxyAdmin = ProxyAdmin(L1_PROXY_ADMIN_ADDR);

        vm.startBroadcast(L1_DEPLOYER_PRIVATE_KEY);

        // note: we use call upgrade(...) and initialize(...) instead of upgradeAndCall(...),
        // otherwise the contract owner would become ProxyAdmin.

        // initialize system config
        proxyAdmin.upgrade(
            ITransparentUpgradeableProxy(L1_SYSTEM_CONFIG_PROXY_ADDR),
            L1_SYSTEM_CONFIG_IMPLEMENTATION_ADDR
        );

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

        // initialize ScrollChain
        proxyAdmin.upgrade(
            ITransparentUpgradeableProxy(L1_SCROLL_CHAIN_PROXY_ADDR),
            L1_SCROLL_CHAIN_IMPLEMENTATION_ADDR
        );

        ScrollChain(L1_SCROLL_CHAIN_PROXY_ADDR).initialize(
            L1_MESSAGE_QUEUE_V1_PROXY_ADDR, // not used
            L1_MULTIPLE_VERSION_ROLLUP_VERIFIER_ADDR,
            MAX_TX_IN_CHUNK
        );

        ScrollChain(L1_SCROLL_CHAIN_PROXY_ADDR).initializeV2();

        ScrollChain(L1_SCROLL_CHAIN_PROXY_ADDR).addSequencer(L1_COMMIT_SENDER_ADDRESS);
        ScrollChain(L1_SCROLL_CHAIN_PROXY_ADDR).addProver(L1_FINALIZE_SENDER_ADDRESS);

        // initialize L2GasPriceOracle
        L2GasPriceOracle(L2_GAS_PRICE_ORACLE_PROXY_ADDR).initialize(
            21000, // _txGas
            53000, // _txGasContractCreation
            4, // _zeroGas
            16 // _nonZeroGas
        );
        L2GasPriceOracle(L2_GAS_PRICE_ORACLE_PROXY_ADDR).updateWhitelist(L1_WHITELIST_ADDR);

        // initialize L1MessageQueueV1WithGasPriceOracle
        proxyAdmin.upgrade(
            ITransparentUpgradeableProxy(L1_MESSAGE_QUEUE_V1_PROXY_ADDR),
            L1_MESSAGE_QUEUE_V1_IMPLEMENTATION_ADDR
        );

        L1MessageQueueV1WithGasPriceOracle(L1_MESSAGE_QUEUE_V1_PROXY_ADDR).initialize(
            L1_SCROLL_MESSENGER_PROXY_ADDR,
            L1_SCROLL_CHAIN_PROXY_ADDR,
            L1_ENFORCED_TX_GATEWAY_PROXY_ADDR,
            L2_GAS_PRICE_ORACLE_PROXY_ADDR,
            MAX_L1_MESSAGE_GAS_LIMIT
        );

        // initialize L1MessageQueueV2
        proxyAdmin.upgrade(
            ITransparentUpgradeableProxy(L1_MESSAGE_QUEUE_V2_PROXY_ADDR),
            L1_MESSAGE_QUEUE_V2_IMPLEMENTATION_ADDR
        );

        L1MessageQueueV2(L1_MESSAGE_QUEUE_V2_PROXY_ADDR).initialize();

        // initialize L1ScrollMessenger
        proxyAdmin.upgrade(
            ITransparentUpgradeableProxy(L1_SCROLL_MESSENGER_PROXY_ADDR),
            L1_SCROLL_MESSENGER_IMPLEMENTATION_ADDR
        );

        L1ScrollMessenger(payable(L1_SCROLL_MESSENGER_PROXY_ADDR)).initialize(
            L2_SCROLL_MESSENGER_PROXY_ADDR,
            L1_FEE_VAULT_ADDR,
            L1_SCROLL_CHAIN_PROXY_ADDR,
            L1_MESSAGE_QUEUE_V1_PROXY_ADDR // not used anymore
        );

        // initialize EnforcedTxGateway
        EnforcedTxGateway(payable(L1_ENFORCED_TX_GATEWAY_PROXY_ADDR)).initialize();

        // initialize L1GatewayRouter
        L1GatewayRouter(L1_GATEWAY_ROUTER_PROXY_ADDR).initialize(
            L1_ETH_GATEWAY_PROXY_ADDR,
            L1_STANDARD_ERC20_GATEWAY_PROXY_ADDR
        );

        // initialize L1CustomERC20Gateway
        proxyAdmin.upgrade(
            ITransparentUpgradeableProxy(L1_CUSTOM_ERC20_GATEWAY_PROXY_ADDR),
            L1_CUSTOM_ERC20_GATEWAY_IMPLEMENTATION_ADDR
        );

        L1CustomERC20Gateway(L1_CUSTOM_ERC20_GATEWAY_PROXY_ADDR).initialize(
            L2_CUSTOM_ERC20_GATEWAY_PROXY_ADDR,
            L1_GATEWAY_ROUTER_PROXY_ADDR,
            L1_SCROLL_MESSENGER_PROXY_ADDR
        );

        // initialize L1ERC1155Gateway
        proxyAdmin.upgrade(
            ITransparentUpgradeableProxy(L1_ERC1155_GATEWAY_PROXY_ADDR),
            L1_ERC1155_GATEWAY_IMPLEMENTATION_ADDR
        );

        L1ERC1155Gateway(L1_ERC1155_GATEWAY_PROXY_ADDR).initialize(
            L2_ERC1155_GATEWAY_PROXY_ADDR,
            L1_SCROLL_MESSENGER_PROXY_ADDR
        );

        // initialize L1ERC721Gateway
        proxyAdmin.upgrade(
            ITransparentUpgradeableProxy(L1_ERC721_GATEWAY_PROXY_ADDR),
            L1_ERC721_GATEWAY_IMPLEMENTATION_ADDR
        );

        L1ERC721Gateway(L1_ERC721_GATEWAY_PROXY_ADDR).initialize(
            L2_ERC721_GATEWAY_PROXY_ADDR,
            L1_SCROLL_MESSENGER_PROXY_ADDR
        );

        // initialize L1ETHGateway
        proxyAdmin.upgrade(ITransparentUpgradeableProxy(L1_ETH_GATEWAY_PROXY_ADDR), L1_ETH_GATEWAY_IMPLEMENTATION_ADDR);

        L1ETHGateway(L1_ETH_GATEWAY_PROXY_ADDR).initialize(
            L2_ETH_GATEWAY_PROXY_ADDR,
            L1_GATEWAY_ROUTER_PROXY_ADDR,
            L1_SCROLL_MESSENGER_PROXY_ADDR
        );

        // initialize L1StandardERC20Gateway
        proxyAdmin.upgrade(
            ITransparentUpgradeableProxy(L1_STANDARD_ERC20_GATEWAY_PROXY_ADDR),
            L1_STANDARD_ERC20_GATEWAY_IMPLEMENTATION_ADDR
        );

        L1StandardERC20Gateway(L1_STANDARD_ERC20_GATEWAY_PROXY_ADDR).initialize(
            L2_STANDARD_ERC20_GATEWAY_PROXY_ADDR,
            L1_GATEWAY_ROUTER_PROXY_ADDR,
            L1_SCROLL_MESSENGER_PROXY_ADDR,
            L2_SCROLL_STANDARD_ERC20_ADDR,
            L2_SCROLL_STANDARD_ERC20_FACTORY_ADDR
        );

        // initialize L1WETHGateway
        proxyAdmin.upgrade(
            ITransparentUpgradeableProxy(L1_WETH_GATEWAY_PROXY_ADDR),
            L1_WETH_GATEWAY_IMPLEMENTATION_ADDR
        );

        L1WETHGateway(payable(L1_WETH_GATEWAY_PROXY_ADDR)).initialize(
            L2_WETH_GATEWAY_PROXY_ADDR,
            L1_GATEWAY_ROUTER_PROXY_ADDR,
            L1_SCROLL_MESSENGER_PROXY_ADDR
        );

        // set WETH gateway in router
        {
            address[] memory _tokens = new address[](1);
            _tokens[0] = L1_WETH_ADDR;
            address[] memory _gateways = new address[](1);
            _gateways[0] = L1_WETH_GATEWAY_PROXY_ADDR;
            L1GatewayRouter(L1_GATEWAY_ROUTER_PROXY_ADDR).setERC20Gateway(_tokens, _gateways);
        }

        vm.stopBroadcast();
    }
}
