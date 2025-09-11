// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.24;

import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {ProxyAdminSetOwner} from "../contracts/ProxyAdminSetOwner.sol";
import {TransparentUpgradeableProxy, ITransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

import {EmptyContract} from "../../../src/misc/EmptyContract.sol";

import {EnforcedTxGateway} from "../../../src/L1/gateways/EnforcedTxGateway.sol";
import {L1CustomERC20Gateway} from "../../../src/L1/gateways/L1CustomERC20Gateway.sol";
import {L1ERC1155Gateway} from "../../../src/L1/gateways/L1ERC1155Gateway.sol";
import {L1ERC721Gateway} from "../../../src/L1/gateways/L1ERC721Gateway.sol";
import {L1ETHGateway} from "../../../src/L1/gateways/L1ETHGateway.sol";
import {L1GatewayRouter} from "../../../src/L1/gateways/L1GatewayRouter.sol";
import {L1MessageQueueV1WithGasPriceOracle} from "../../../src/L1/rollup/L1MessageQueueV1WithGasPriceOracle.sol";
import {L1MessageQueueV2} from "../../../src/L1/rollup/L1MessageQueueV2.sol";
import {SystemConfig} from "../../../src/L1/system-contract/SystemConfig.sol";
import {L1ScrollMessenger} from "../../../src/L1/L1ScrollMessenger.sol";
import {L1StandardERC20Gateway} from "../../../src/L1/gateways/L1StandardERC20Gateway.sol";
import {L1WETHGateway} from "../../../src/L1/gateways/L1WETHGateway.sol";
import {L2GasPriceOracle} from "../../../src/L1/rollup/L2GasPriceOracle.sol";
import {ScrollChain} from "../../../src/L1/rollup/ScrollChain.sol";
import {ZkEvmVerifierV2} from "../../../src/libraries/verifier/ZkEvmVerifierV2.sol";
import {L2CustomERC20Gateway} from "../../../src/L2/gateways/L2CustomERC20Gateway.sol";
import {L2ERC1155Gateway} from "../../../src/L2/gateways/L2ERC1155Gateway.sol";
import {L2ERC721Gateway} from "../../../src/L2/gateways/L2ERC721Gateway.sol";
import {L2ETHGateway} from "../../../src/L2/gateways/L2ETHGateway.sol";
import {L2GatewayRouter} from "../../../src/L2/gateways/L2GatewayRouter.sol";
import {L2ScrollMessenger} from "../../../src/L2/L2ScrollMessenger.sol";
import {L2StandardERC20Gateway} from "../../../src/L2/gateways/L2StandardERC20Gateway.sol";
import {L2WETHGateway} from "../../../src/L2/gateways/L2WETHGateway.sol";
import {L1GasPriceOracle} from "../../../src/L2/predeploys/L1GasPriceOracle.sol";
import {L2MessageQueue} from "../../../src/L2/predeploys/L2MessageQueue.sol";
import {L2TxFeeVault} from "../../../src/L2/predeploys/L2TxFeeVault.sol";
import {Whitelist} from "../../../src/L2/predeploys/Whitelist.sol";
import {WrappedEther} from "../../../src/L2/predeploys/WrappedEther.sol";
import {ScrollStandardERC20} from "../../../src/libraries/token/ScrollStandardERC20.sol";

import {MultipleVersionRollupVerifierSetOwner} from "../contracts/MultipleVersionRollupVerifierSetOwner.sol";
import {ScrollStandardERC20FactorySetOwner} from "../contracts/ScrollStandardERC20FactorySetOwner.sol";

import {ScrollChainMockFinalize} from "../../../src/mocks/ScrollChainMockFinalize.sol";

import "./Constants.sol";
import {ScrollConfiguration} from "./ScrollConfiguration.sol";
import "../DeterministicDeployment.sol";

/// @dev The minimum deployer account balance.
uint256 constant MINIMUM_DEPLOYER_BALANCE = 0.1 ether;

contract DeployScroll is DeterministicDeployment, ScrollConfiguration {
    using stdToml for string;

    /*********
     * Types *
     *********/

    enum Layer {
        None,
        L1,
        L2
    }

    /*******************
     * State variables *
     *******************/

    // general configurations
    Layer private broadcastLayer = Layer.None;

    /***********************
     * Contracts to deploy *
     ***********************/

    // L1 addresses
    address internal L1_CUSTOM_ERC20_GATEWAY_IMPLEMENTATION_ADDR;
    address internal L1_CUSTOM_ERC20_GATEWAY_PROXY_ADDR;
    address internal L1_ENFORCED_TX_GATEWAY_IMPLEMENTATION_ADDR;
    address internal L1_ENFORCED_TX_GATEWAY_PROXY_ADDR;
    address internal L1_ERC1155_GATEWAY_IMPLEMENTATION_ADDR;
    address internal L1_ERC1155_GATEWAY_PROXY_ADDR;
    address internal L1_ERC721_GATEWAY_IMPLEMENTATION_ADDR;
    address internal L1_ERC721_GATEWAY_PROXY_ADDR;
    address internal L1_ETH_GATEWAY_IMPLEMENTATION_ADDR;
    address internal L1_ETH_GATEWAY_PROXY_ADDR;
    address internal L1_GATEWAY_ROUTER_IMPLEMENTATION_ADDR;
    address internal L1_GATEWAY_ROUTER_PROXY_ADDR;
    address internal L1_MESSAGE_QUEUE_V1_IMPLEMENTATION_ADDR;
    address internal L1_MESSAGE_QUEUE_V1_PROXY_ADDR;
    address internal L1_MESSAGE_QUEUE_V2_IMPLEMENTATION_ADDR;
    address internal L1_MESSAGE_QUEUE_V2_PROXY_ADDR;
    address internal L1_MULTIPLE_VERSION_ROLLUP_VERIFIER_ADDR;
    address internal L1_PROXY_ADMIN_ADDR;
    address internal L1_PROXY_IMPLEMENTATION_PLACEHOLDER_ADDR;
    address internal L1_SCROLL_CHAIN_IMPLEMENTATION_ADDR;
    address internal L1_SCROLL_CHAIN_PROXY_ADDR;
    address internal L1_SCROLL_MESSENGER_IMPLEMENTATION_ADDR;
    address internal L1_SCROLL_MESSENGER_PROXY_ADDR;
    address internal L1_STANDARD_ERC20_GATEWAY_IMPLEMENTATION_ADDR;
    address internal L1_STANDARD_ERC20_GATEWAY_PROXY_ADDR;
    address internal L1_WETH_ADDR;
    address internal L1_WETH_GATEWAY_IMPLEMENTATION_ADDR;
    address internal L1_WETH_GATEWAY_PROXY_ADDR;
    address internal L1_WHITELIST_ADDR;
    address internal L1_PLONK_VERIFIER_ADDR;
    address internal L1_ZKEVM_VERIFIER_V2_ADDR;
    address internal L1_WRAPPED_TOKEN_GATEWAY_ADDR;
    address internal SYSTEM_CONFIG_IMPLEMENTATION_ADDR;
    address internal SYSTEM_CONFIG_PROXY_ADDR;

    // L2 addresses
    address internal L1_GAS_PRICE_ORACLE_ADDR;
    address internal L2_CUSTOM_ERC20_GATEWAY_IMPLEMENTATION_ADDR;
    address internal L2_CUSTOM_ERC20_GATEWAY_PROXY_ADDR;
    address internal L2_ERC1155_GATEWAY_IMPLEMENTATION_ADDR;
    address internal L2_ERC1155_GATEWAY_PROXY_ADDR;
    address internal L2_ERC721_GATEWAY_IMPLEMENTATION_ADDR;
    address internal L2_ERC721_GATEWAY_PROXY_ADDR;
    address internal L2_ETH_GATEWAY_IMPLEMENTATION_ADDR;
    address internal L2_ETH_GATEWAY_PROXY_ADDR;
    address internal L2_GATEWAY_ROUTER_IMPLEMENTATION_ADDR;
    address internal L2_GATEWAY_ROUTER_PROXY_ADDR;
    address internal L2_MESSAGE_QUEUE_ADDR;
    address internal L2_PROXY_ADMIN_ADDR;
    address internal L2_PROXY_IMPLEMENTATION_PLACEHOLDER_ADDR;
    address internal L2_SCROLL_MESSENGER_IMPLEMENTATION_ADDR;
    address internal L2_SCROLL_MESSENGER_PROXY_ADDR;
    address internal L2_SCROLL_STANDARD_ERC20_ADDR;
    address internal L2_SCROLL_STANDARD_ERC20_FACTORY_ADDR;
    address internal L2_STANDARD_ERC20_GATEWAY_IMPLEMENTATION_ADDR;
    address internal L2_STANDARD_ERC20_GATEWAY_PROXY_ADDR;
    address internal L2_TX_FEE_VAULT_ADDR;
    address internal L2_WETH_ADDR;
    address internal L2_WETH_GATEWAY_IMPLEMENTATION_ADDR;
    address internal L2_WETH_GATEWAY_PROXY_ADDR;
    address internal L2_WHITELIST_ADDR;

    /*************
     * Utilities *
     *************/

    /// @dev Only broadcast code block if we run the script on the specified layer.
    modifier broadcast(Layer layer) {
        if (broadcastLayer == layer) {
            vm.startBroadcast(DEPLOYER_PRIVATE_KEY);
        } else {
            // make sure we use the correct sender in simulation
            vm.startPrank(DEPLOYER_ADDR);
        }

        _;

        if (broadcastLayer == layer) {
            vm.stopBroadcast();
        } else {
            vm.stopPrank();
        }
    }

    /// @dev Only execute block if we run the script on the specified layer.
    modifier only(Layer layer) {
        if (broadcastLayer != layer) {
            return;
        }
        _;
    }

    /// @dev Do not execute block if we run the script on the specified layer.
    modifier skip(Layer layer) {
        if (broadcastLayer == layer) {
            return;
        }
        _;
    }

    /***************
     * Entry point *
     ***************/

    function run(
        string memory workdir,
        string memory layer,
        string memory scriptMode
    ) public {
        broadcastLayer = parseLayer(layer);
        ScriptMode mode = parseScriptMode(scriptMode);

        DeterministicDeployment.initialize(mode, workdir);

        checkDeployerBalance();
        deployAllContracts();
        initializeL1Contracts();
        initializeL2Contracts();
    }

    /**********************
     * Internal interface *
     **********************/

    function predictAllContracts() internal {
        skipDeployment();
        deployAllContracts();
    }

    /*********************
     * Private functions *
     *********************/

    function parseLayer(string memory raw) private pure returns (Layer) {
        if (keccak256(bytes(raw)) == keccak256(bytes("L1"))) {
            return Layer.L1;
        } else if (keccak256(bytes(raw)) == keccak256(bytes("L2"))) {
            return Layer.L2;
        } else {
            return Layer.None;
        }
    }

    function checkDeployerBalance() private {
        // ignore balance during simulation
        if (broadcastLayer == Layer.None) {
            return;
        }

        // check funds for deployment (L1 & L2)
        if (DEPLOYER_ADDR.balance < MINIMUM_DEPLOYER_BALANCE) {
            revert(
                string(
                    abi.encodePacked(
                        "[ERROR] insufficient funds on deployer account for contract deployment (",
                        vm.toString(DEPLOYER_ADDR),
                        ") minimum ETH balance (in wei): ",
                        vm.toString(MINIMUM_DEPLOYER_BALANCE)
                    )
                )
            );
        }

        // check funds for initial deposit (L1, ETH as gas token)
        if (broadcastLayer == Layer.L1) {
            // note: L1_SCROLL_MESSENGER_PROXY_ADDR is not known at this point,
            // so we read it directly from the generated configuration file.
            address l1MessengerProxyAddr = notnull(contractsCfg.readAddress(".L1_SCROLL_MESSENGER_PROXY_ADDR"));

            uint256 l1MessengerBalance = l1MessengerProxyAddr.balance;
            uint256 amountToLock = L2_DEPLOYER_INITIAL_BALANCE;

            uint256 amountToSend = 0;
            if (l1MessengerBalance < amountToLock) {
                amountToSend = amountToLock - l1MessengerBalance;
            }

            uint256 minBalance = MINIMUM_DEPLOYER_BALANCE + amountToSend;

            if (DEPLOYER_ADDR.balance < minBalance) {
                revert(
                    string(
                        abi.encodePacked(
                            "[ERROR] insufficient funds on deployer account for initial deposit (",
                            vm.toString(DEPLOYER_ADDR),
                            ") minimum ETH balance (in wei): ",
                            vm.toString(minBalance)
                        )
                    )
                );
            }
        }
    }

    function transferOwnership(address addr, address newOwner) private {
        if (Ownable(addr).owner() != newOwner) {
            Ownable(addr).transferOwnership(newOwner);
        }
    }

    function deployAllContracts() private {
        deployL1Contracts1stPass();
        deployL2Contracts1stPass();
        deployL1Contracts2ndPass();
        deployL2Contracts2ndPass();
    }

    // @notice deployL1Contracts1stPass deploys L1 contracts whose initialization does not depend on any L2 addresses.
    function deployL1Contracts1stPass() private broadcast(Layer.L1) {
        deployL1Weth();
        deployL1ProxyAdmin();
        deployL1PlaceHolder();
        deployL1Whitelist();
        deployL1ScrollChainProxy();
        deployL1ScrollMessengerProxy();
        deployL1EnforcedTxGatewayProxy();
        deployL1PlonkVerifier();
        deployL1ZkEvmVerifier();
        deployL1MultipleVersionRollupVerifier();
        deploySystemConfig();
        deployL1MessageQueue();
        deployL1ScrollChain();
        deployL1GatewayRouter();
        deployL1ETHGatewayProxy();
        deployL1WETHGatewayProxy();
        deployL1StandardERC20GatewayProxy();
        deployL1CustomERC20GatewayProxy();
        deployL1ERC721GatewayProxy();
        deployL1ERC1155GatewayProxy();
    }

    // @notice deployL2Contracts1stPass deploys L2 contracts whose initialization does not depend on any L1 addresses.
    function deployL2Contracts1stPass() private broadcast(Layer.L2) {
        deployL2MessageQueue();
        deployL1GasPriceOracle();
        deployL2Whitelist();
        deployL2Weth();
        deployTxFeeVault();
        deployL2ProxyAdmin();
        deployL2PlaceHolder();
        deployL2ScrollMessengerProxy();
        deployL2ETHGatewayProxy();
        deployL2WETHGatewayProxy();
        deployL2StandardERC20GatewayProxy();
        deployL2CustomERC20GatewayProxy();
        deployL2ERC721GatewayProxy();
        deployL2ERC1155GatewayProxy();
        deployScrollStandardERC20Factory();
    }

    // @notice deployL1Contracts2ndPass deploys L1 contracts whose initialization depends on some L2 addresses.
    function deployL1Contracts2ndPass() private broadcast(Layer.L1) {
        deployL1EnforcedTxGateway();
        deployL1ScrollMessenger();
        deployL1StandardERC20Gateway();
        deployL1ETHGateway();
        deployL1WETHGateway();
        deployL1CustomERC20Gateway();
        deployL1ERC721Gateway();
        deployL1ERC1155Gateway();
    }

    // @notice deployL2Contracts2ndPass deploys L2 contracts whose initialization depends on some L1 addresses.
    function deployL2Contracts2ndPass() private broadcast(Layer.L2) {
        // upgradable
        deployL2ScrollMessenger();
        deployL2GatewayRouter();
        deployL2StandardERC20Gateway();
        deployL2ETHGateway();
        deployL2WETHGateway();
        deployL2CustomERC20Gateway();
        deployL2ERC721Gateway();
        deployL2ERC1155Gateway();
    }

    // @notice initializeL1Contracts initializes contracts deployed on L1.
    function initializeL1Contracts() private broadcast(Layer.L1) only(Layer.L1) {
        initializeScrollChain();
        initializeSystemConfig();
        initializeL1MessageQueue();
        initializeL1ScrollMessenger();
        initializeEnforcedTxGateway();
        initializeL1GatewayRouter();
        initializeL1CustomERC20Gateway();
        initializeL1ERC1155Gateway();
        initializeL1ERC721Gateway();
        initializeL1ETHGateway();
        initializeL1StandardERC20Gateway();
        initializeL1WETHGateway();
        initializeL1Whitelist();

        // lock tokens on L1 to ensure bridge parity,
        // we lock ETH in L1ScrollMessenger
        // note: this can only be done before transferring ownership
        lockTokensOnL1();

        transferL1ContractOwnership();
    }

    // @notice initializeL2Contracts initializes contracts deployed on L2.
    function initializeL2Contracts() private broadcast(Layer.L2) only(Layer.L2) {
        initializeL2MessageQueue();
        initializeL2TxFeeVault();
        initializeL1GasPriceOracle();
        initializeL2ScrollMessenger();
        initializeL2GatewayRouter();
        initializeL2CustomERC20Gateway();
        initializeL2ERC1155Gateway();
        initializeL2ERC721Gateway();
        initializeL2ETHGateway();
        initializeL2StandardERC20Gateway();
        initializeL2WETHGateway();
        initializeScrollStandardERC20Factory();
        initializeL2Whitelist();

        transferL2ContractOwnership();
    }

    /***************************
     * L1: 1st pass deployment *
     ***************************/

    function deployL1Weth() private {
        L1_WETH_ADDR = deploy("L1_WETH", type(WrappedEther).creationCode);
    }

    function deployL1ProxyAdmin() private {
        bytes memory args = abi.encode(DEPLOYER_ADDR);
        L1_PROXY_ADMIN_ADDR = deploy("L1_PROXY_ADMIN", type(ProxyAdminSetOwner).creationCode, args);
    }

    function deployL1PlaceHolder() private {
        L1_PROXY_IMPLEMENTATION_PLACEHOLDER_ADDR = deploy(
            "L1_PROXY_IMPLEMENTATION_PLACEHOLDER",
            type(EmptyContract).creationCode
        );
    }

    function deployL1Whitelist() private {
        bytes memory args = abi.encode(DEPLOYER_ADDR);
        L1_WHITELIST_ADDR = deploy("L1_WHITELIST", type(Whitelist).creationCode, args);
    }

    function deployL1ScrollChainProxy() private {
        bytes memory args = abi.encode(
            notnull(L1_PROXY_IMPLEMENTATION_PLACEHOLDER_ADDR),
            notnull(L1_PROXY_ADMIN_ADDR),
            new bytes(0)
        );

        L1_SCROLL_CHAIN_PROXY_ADDR = deploy(
            "L1_SCROLL_CHAIN_PROXY",
            type(TransparentUpgradeableProxy).creationCode,
            args
        );
    }

    function deployL1ScrollMessengerProxy() private {
        bytes memory args = abi.encode(
            notnull(L1_PROXY_IMPLEMENTATION_PLACEHOLDER_ADDR),
            notnull(L1_PROXY_ADMIN_ADDR),
            new bytes(0)
        );

        L1_SCROLL_MESSENGER_PROXY_ADDR = deploy(
            "L1_SCROLL_MESSENGER_PROXY",
            type(TransparentUpgradeableProxy).creationCode,
            args
        );
    }

    function deployL1EnforcedTxGatewayProxy() private {
        bytes memory args = abi.encode(
            notnull(L1_PROXY_IMPLEMENTATION_PLACEHOLDER_ADDR),
            notnull(L1_PROXY_ADMIN_ADDR),
            new bytes(0)
        );

        L1_ENFORCED_TX_GATEWAY_PROXY_ADDR = deploy(
            "L1_ENFORCED_TX_GATEWAY_PROXY",
            type(TransparentUpgradeableProxy).creationCode,
            args
        );
    }

    function deployL1EnforcedTxGateway() private {
        bytes memory args = abi.encode(notnull(L1_MESSAGE_QUEUE_V2_PROXY_ADDR), notnull(L1_FEE_VAULT_ADDR));

        L1_ENFORCED_TX_GATEWAY_IMPLEMENTATION_ADDR = deploy(
            "L1_ENFORCED_TX_GATEWAY_IMPLEMENTATION",
            type(EnforcedTxGateway).creationCode,
            args
        );

        upgrade(L1_PROXY_ADMIN_ADDR, L1_ENFORCED_TX_GATEWAY_PROXY_ADDR, L1_ENFORCED_TX_GATEWAY_IMPLEMENTATION_ADDR);
    }

    function deployL1PlonkVerifier() private {
        L1_PLONK_VERIFIER_ADDR = deploy("L1_PLONK_VERIFIER", PLONK_VERIFIER_CREATION_CODE);
    }

    function deployL1ZkEvmVerifier() private {
        bytes memory args = abi.encode(notnull(L1_PLONK_VERIFIER_ADDR), VERIFIER_DIGEST);
        L1_ZKEVM_VERIFIER_V2_ADDR = deploy("L1_ZKEVM_VERIFIER_V2", type(ZkEvmVerifierV2).creationCode, args);
    }

    function deployL1MultipleVersionRollupVerifier() private {
        uint256[] memory _versions = new uint256[](1);
        address[] memory _verifiers = new address[](1);

        // register V4 verifier: DarwinV2 upgrade, plonk verifier v0.13.1
        _versions[0] = 4;
        _verifiers[0] = notnull(L1_ZKEVM_VERIFIER_V2_ADDR);

        bytes memory args = abi.encode(DEPLOYER_ADDR, _versions, _verifiers);

        L1_MULTIPLE_VERSION_ROLLUP_VERIFIER_ADDR = deploy(
            "L1_MULTIPLE_VERSION_ROLLUP_VERIFIER",
            type(MultipleVersionRollupVerifierSetOwner).creationCode,
            args
        );
    }

    function deploySystemConfig() private {
        SYSTEM_CONFIG_IMPLEMENTATION_ADDR = deploy("SYSTEM_CONFIG_IMPLEMENTATION", type(SystemConfig).creationCode);

        bytes memory args = abi.encode(
            notnull(SYSTEM_CONFIG_IMPLEMENTATION_ADDR),
            notnull(L1_PROXY_ADMIN_ADDR),
            new bytes(0)
        );

        SYSTEM_CONFIG_PROXY_ADDR = deploy("SYSTEM_CONFIG_PROXY", type(TransparentUpgradeableProxy).creationCode, args);
    }

    function deployL1MessageQueue() private {
        // deploy L1MessageQueueV1
        bytes memory args = abi.encode(
            notnull(L1_SCROLL_MESSENGER_PROXY_ADDR),
            notnull(L1_SCROLL_CHAIN_PROXY_ADDR),
            notnull(L1_ENFORCED_TX_GATEWAY_PROXY_ADDR)
        );

        L1_MESSAGE_QUEUE_V1_IMPLEMENTATION_ADDR = deploy(
            "L1_MESSAGE_QUEUE_V1_IMPLEMENTATION",
            type(L1MessageQueueV1WithGasPriceOracle).creationCode,
            args
        );

        bytes memory args2 = abi.encode(
            notnull(L1_MESSAGE_QUEUE_V1_IMPLEMENTATION_ADDR),
            notnull(L1_PROXY_ADMIN_ADDR),
            new bytes(0)
        );

        L1_MESSAGE_QUEUE_V1_PROXY_ADDR = deploy(
            "L1_MESSAGE_QUEUE_V1_PROXY",
            type(TransparentUpgradeableProxy).creationCode,
            args2
        );

        // deploy L1MessageQueueV2
        bytes memory args3 = abi.encode(
            notnull(L1_SCROLL_MESSENGER_PROXY_ADDR),
            notnull(L1_SCROLL_CHAIN_PROXY_ADDR),
            notnull(L1_ENFORCED_TX_GATEWAY_PROXY_ADDR),
            notnull(L1_MESSAGE_QUEUE_V1_PROXY_ADDR),
            notnull(SYSTEM_CONFIG_PROXY_ADDR)
        );

        L1_MESSAGE_QUEUE_V2_IMPLEMENTATION_ADDR = deploy(
            "L1_MESSAGE_QUEUE_V2_IMPLEMENTATION",
            type(L1MessageQueueV2).creationCode,
            args3
        );

        bytes memory args4 = abi.encode(
            notnull(L1_MESSAGE_QUEUE_V2_IMPLEMENTATION_ADDR),
            notnull(L1_PROXY_ADMIN_ADDR),
            new bytes(0)
        );

        L1_MESSAGE_QUEUE_V2_PROXY_ADDR = deploy(
            "L1_MESSAGE_QUEUE_V2_PROXY",
            type(TransparentUpgradeableProxy).creationCode,
            args4
        );
    }

    function deployL1ScrollChain() private {
        bytes memory args = abi.encode(
            CHAIN_ID_L2,
            notnull(L1_MESSAGE_QUEUE_V1_PROXY_ADDR),
            notnull(L1_MESSAGE_QUEUE_V2_PROXY_ADDR),
            notnull(L1_MULTIPLE_VERSION_ROLLUP_VERIFIER_ADDR),
            notnull(SYSTEM_CONFIG_PROXY_ADDR)
        );

        bytes memory creationCode = type(ScrollChain).creationCode;

        if (TEST_ENV_MOCK_FINALIZE_ENABLED) {
            creationCode = type(ScrollChainMockFinalize).creationCode;
        }

        L1_SCROLL_CHAIN_IMPLEMENTATION_ADDR = deploy("L1_SCROLL_CHAIN_IMPLEMENTATION", creationCode, args);

        upgrade(L1_PROXY_ADMIN_ADDR, L1_SCROLL_CHAIN_PROXY_ADDR, L1_SCROLL_CHAIN_IMPLEMENTATION_ADDR);
    }

    function deployL1GatewayRouter() private {
        L1_GATEWAY_ROUTER_IMPLEMENTATION_ADDR = deploy(
            "L1_GATEWAY_ROUTER_IMPLEMENTATION",
            type(L1GatewayRouter).creationCode
        );

        bytes memory args = abi.encode(
            notnull(L1_GATEWAY_ROUTER_IMPLEMENTATION_ADDR),
            notnull(L1_PROXY_ADMIN_ADDR),
            new bytes(0)
        );

        L1_GATEWAY_ROUTER_PROXY_ADDR = deploy(
            "L1_GATEWAY_ROUTER_PROXY",
            type(TransparentUpgradeableProxy).creationCode,
            args
        );
    }

    function deployL1ETHGatewayProxy() private {
        bytes memory args = abi.encode(
            notnull(L1_PROXY_IMPLEMENTATION_PLACEHOLDER_ADDR),
            notnull(L1_PROXY_ADMIN_ADDR),
            new bytes(0)
        );

        L1_ETH_GATEWAY_PROXY_ADDR = deploy(
            "L1_ETH_GATEWAY_PROXY",
            type(TransparentUpgradeableProxy).creationCode,
            args
        );
    }

    function deployL1WETHGatewayProxy() private {
        bytes memory args = abi.encode(
            notnull(L1_PROXY_IMPLEMENTATION_PLACEHOLDER_ADDR),
            notnull(L1_PROXY_ADMIN_ADDR),
            new bytes(0)
        );

        L1_WETH_GATEWAY_PROXY_ADDR = deploy(
            "L1_WETH_GATEWAY_PROXY",
            type(TransparentUpgradeableProxy).creationCode,
            args
        );
    }

    function deployL1StandardERC20GatewayProxy() private {
        bytes memory args = abi.encode(
            notnull(L1_PROXY_IMPLEMENTATION_PLACEHOLDER_ADDR),
            notnull(L1_PROXY_ADMIN_ADDR),
            new bytes(0)
        );

        L1_STANDARD_ERC20_GATEWAY_PROXY_ADDR = deploy(
            "L1_STANDARD_ERC20_GATEWAY_PROXY",
            type(TransparentUpgradeableProxy).creationCode,
            args
        );
    }

    function deployL1CustomERC20GatewayProxy() private {
        bytes memory args = abi.encode(
            notnull(L1_PROXY_IMPLEMENTATION_PLACEHOLDER_ADDR),
            notnull(L1_PROXY_ADMIN_ADDR),
            new bytes(0)
        );

        L1_CUSTOM_ERC20_GATEWAY_PROXY_ADDR = deploy(
            "L1_CUSTOM_ERC20_GATEWAY_PROXY",
            type(TransparentUpgradeableProxy).creationCode,
            args
        );
    }

    function deployL1ERC721GatewayProxy() private {
        bytes memory args = abi.encode(
            notnull(L1_PROXY_IMPLEMENTATION_PLACEHOLDER_ADDR),
            notnull(L1_PROXY_ADMIN_ADDR),
            new bytes(0)
        );

        L1_ERC721_GATEWAY_PROXY_ADDR = deploy(
            "L1_ERC721_GATEWAY_PROXY",
            type(TransparentUpgradeableProxy).creationCode,
            args
        );
    }

    function deployL1ERC1155GatewayProxy() private {
        bytes memory args = abi.encode(
            notnull(L1_PROXY_IMPLEMENTATION_PLACEHOLDER_ADDR),
            notnull(L1_PROXY_ADMIN_ADDR),
            new bytes(0)
        );

        L1_ERC1155_GATEWAY_PROXY_ADDR = deploy(
            "L1_ERC1155_GATEWAY_PROXY",
            type(TransparentUpgradeableProxy).creationCode,
            args
        );
    }

    /***************************
     * L2: 1st pass deployment *
     ***************************/

    function deployL2MessageQueue() private {
        bytes memory args = abi.encode(DEPLOYER_ADDR);
        L2_MESSAGE_QUEUE_ADDR = deploy("L2_MESSAGE_QUEUE", type(L2MessageQueue).creationCode, args);
    }

    function deployL1GasPriceOracle() private {
        bytes memory args = abi.encode(DEPLOYER_ADDR, true);
        L1_GAS_PRICE_ORACLE_ADDR = deploy("L1_GAS_PRICE_ORACLE", type(L1GasPriceOracle).creationCode, args);
    }

    function deployL2Whitelist() private {
        bytes memory args = abi.encode(DEPLOYER_ADDR);
        L2_WHITELIST_ADDR = deploy("L2_WHITELIST", type(Whitelist).creationCode, args);
    }

    function deployL2Weth() private {
        L2_WETH_ADDR = deploy("L2_WETH", type(WrappedEther).creationCode);
    }

    function deployTxFeeVault() private {
        bytes memory args = abi.encode(DEPLOYER_ADDR, L1_FEE_VAULT_ADDR, FEE_VAULT_MIN_WITHDRAW_AMOUNT);
        L2_TX_FEE_VAULT_ADDR = deploy("L2_TX_FEE_VAULT", type(L2TxFeeVault).creationCode, args);
    }

    function deployL2ProxyAdmin() private {
        bytes memory args = abi.encode(DEPLOYER_ADDR);
        L2_PROXY_ADMIN_ADDR = deploy("L2_PROXY_ADMIN", type(ProxyAdminSetOwner).creationCode, args);
    }

    function deployL2PlaceHolder() private {
        L2_PROXY_IMPLEMENTATION_PLACEHOLDER_ADDR = deploy(
            "L2_PROXY_IMPLEMENTATION_PLACEHOLDER",
            type(EmptyContract).creationCode
        );
    }

    function deployL2ScrollMessengerProxy() private {
        bytes memory args = abi.encode(
            notnull(L2_PROXY_IMPLEMENTATION_PLACEHOLDER_ADDR),
            notnull(L2_PROXY_ADMIN_ADDR),
            new bytes(0)
        );

        L2_SCROLL_MESSENGER_PROXY_ADDR = deploy(
            "L2_SCROLL_MESSENGER_PROXY",
            type(TransparentUpgradeableProxy).creationCode,
            args
        );
    }

    function deployL2StandardERC20GatewayProxy() private {
        bytes memory args = abi.encode(
            notnull(L2_PROXY_IMPLEMENTATION_PLACEHOLDER_ADDR),
            notnull(L2_PROXY_ADMIN_ADDR),
            new bytes(0)
        );

        L2_STANDARD_ERC20_GATEWAY_PROXY_ADDR = deploy(
            "L2_STANDARD_ERC20_GATEWAY_PROXY",
            type(TransparentUpgradeableProxy).creationCode,
            args
        );
    }

    function deployL2ETHGatewayProxy() private {
        bytes memory args = abi.encode(
            notnull(L2_PROXY_IMPLEMENTATION_PLACEHOLDER_ADDR),
            notnull(L2_PROXY_ADMIN_ADDR),
            new bytes(0)
        );

        L2_ETH_GATEWAY_PROXY_ADDR = deploy(
            "L2_ETH_GATEWAY_PROXY",
            type(TransparentUpgradeableProxy).creationCode,
            args
        );
    }

    function deployL2WETHGatewayProxy() private {
        bytes memory args = abi.encode(
            notnull(L2_PROXY_IMPLEMENTATION_PLACEHOLDER_ADDR),
            notnull(L2_PROXY_ADMIN_ADDR),
            new bytes(0)
        );

        L2_WETH_GATEWAY_PROXY_ADDR = deploy(
            "L2_WETH_GATEWAY_PROXY",
            type(TransparentUpgradeableProxy).creationCode,
            args
        );
    }

    function deployL2CustomERC20GatewayProxy() private {
        bytes memory args = abi.encode(
            notnull(L2_PROXY_IMPLEMENTATION_PLACEHOLDER_ADDR),
            notnull(L2_PROXY_ADMIN_ADDR),
            new bytes(0)
        );

        L2_CUSTOM_ERC20_GATEWAY_PROXY_ADDR = deploy(
            "L2_CUSTOM_ERC20_GATEWAY_PROXY",
            type(TransparentUpgradeableProxy).creationCode,
            args
        );
    }

    function deployL2ERC721GatewayProxy() private {
        bytes memory args = abi.encode(
            notnull(L2_PROXY_IMPLEMENTATION_PLACEHOLDER_ADDR),
            notnull(L2_PROXY_ADMIN_ADDR),
            new bytes(0)
        );

        L2_ERC721_GATEWAY_PROXY_ADDR = deploy(
            "L2_ERC721_GATEWAY_PROXY",
            type(TransparentUpgradeableProxy).creationCode,
            args
        );
    }

    function deployL2ERC1155GatewayProxy() private {
        bytes memory args = abi.encode(
            notnull(L2_PROXY_IMPLEMENTATION_PLACEHOLDER_ADDR),
            notnull(L2_PROXY_ADMIN_ADDR),
            new bytes(0)
        );

        L2_ERC1155_GATEWAY_PROXY_ADDR = deploy(
            "L2_ERC1155_GATEWAY_PROXY",
            type(TransparentUpgradeableProxy).creationCode,
            args
        );
    }

    function deployScrollStandardERC20Factory() private {
        L2_SCROLL_STANDARD_ERC20_ADDR = deploy("L2_SCROLL_STANDARD_ERC20", type(ScrollStandardERC20).creationCode);
        bytes memory args = abi.encode(DEPLOYER_ADDR, notnull(L2_SCROLL_STANDARD_ERC20_ADDR));

        L2_SCROLL_STANDARD_ERC20_FACTORY_ADDR = deploy(
            "L2_SCROLL_STANDARD_ERC20_FACTORY",
            type(ScrollStandardERC20FactorySetOwner).creationCode,
            args
        );
    }

    /***************************
     * L1: 2nd pass deployment *
     ***************************/

    function deployL1ScrollMessenger() private {
        bytes memory args = abi.encode(
            notnull(L2_SCROLL_MESSENGER_PROXY_ADDR),
            notnull(L1_SCROLL_CHAIN_PROXY_ADDR),
            notnull(L1_MESSAGE_QUEUE_V1_PROXY_ADDR),
            notnull(L1_MESSAGE_QUEUE_V2_PROXY_ADDR)
        );

        L1_SCROLL_MESSENGER_IMPLEMENTATION_ADDR = deploy(
            "L1_SCROLL_MESSENGER_IMPLEMENTATION",
            type(L1ScrollMessenger).creationCode,
            args
        );

        upgrade(L1_PROXY_ADMIN_ADDR, L1_SCROLL_MESSENGER_PROXY_ADDR, L1_SCROLL_MESSENGER_IMPLEMENTATION_ADDR);
    }

    function deployL1ETHGateway() private {
        bytes memory args = abi.encode(
            notnull(L2_ETH_GATEWAY_PROXY_ADDR),
            notnull(L1_GATEWAY_ROUTER_PROXY_ADDR),
            notnull(L1_SCROLL_MESSENGER_PROXY_ADDR)
        );

        L1_ETH_GATEWAY_IMPLEMENTATION_ADDR = deploy(
            "L1_ETH_GATEWAY_IMPLEMENTATION",
            type(L1ETHGateway).creationCode,
            args
        );

        upgrade(L1_PROXY_ADMIN_ADDR, L1_ETH_GATEWAY_PROXY_ADDR, L1_ETH_GATEWAY_IMPLEMENTATION_ADDR);
    }

    function deployL1WETHGateway() private {
        bytes memory args = abi.encode(
            notnull(L1_WETH_ADDR),
            notnull(L2_WETH_ADDR),
            notnull(L2_WETH_GATEWAY_PROXY_ADDR),
            notnull(L1_GATEWAY_ROUTER_PROXY_ADDR),
            notnull(L1_SCROLL_MESSENGER_PROXY_ADDR)
        );

        L1_WETH_GATEWAY_IMPLEMENTATION_ADDR = deploy(
            "L1_WETH_GATEWAY_IMPLEMENTATION",
            type(L1WETHGateway).creationCode,
            args
        );

        upgrade(L1_PROXY_ADMIN_ADDR, L1_WETH_GATEWAY_PROXY_ADDR, L1_WETH_GATEWAY_IMPLEMENTATION_ADDR);
    }

    function deployL1StandardERC20Gateway() private {
        bytes memory args = abi.encode(
            notnull(L2_STANDARD_ERC20_GATEWAY_PROXY_ADDR),
            notnull(L1_GATEWAY_ROUTER_PROXY_ADDR),
            notnull(L1_SCROLL_MESSENGER_PROXY_ADDR),
            notnull(L2_SCROLL_STANDARD_ERC20_ADDR),
            notnull(L2_SCROLL_STANDARD_ERC20_FACTORY_ADDR)
        );

        L1_STANDARD_ERC20_GATEWAY_IMPLEMENTATION_ADDR = deploy(
            "L1_STANDARD_ERC20_GATEWAY_IMPLEMENTATION",
            type(L1StandardERC20Gateway).creationCode,
            args
        );

        upgrade(
            L1_PROXY_ADMIN_ADDR,
            L1_STANDARD_ERC20_GATEWAY_PROXY_ADDR,
            L1_STANDARD_ERC20_GATEWAY_IMPLEMENTATION_ADDR
        );
    }

    function deployL1CustomERC20Gateway() private {
        bytes memory args = abi.encode(
            notnull(L2_CUSTOM_ERC20_GATEWAY_PROXY_ADDR),
            notnull(L1_GATEWAY_ROUTER_PROXY_ADDR),
            notnull(L1_SCROLL_MESSENGER_PROXY_ADDR)
        );

        L1_CUSTOM_ERC20_GATEWAY_IMPLEMENTATION_ADDR = deploy(
            "L1_CUSTOM_ERC20_GATEWAY_IMPLEMENTATION",
            type(L1CustomERC20Gateway).creationCode,
            args
        );

        upgrade(L1_PROXY_ADMIN_ADDR, L1_CUSTOM_ERC20_GATEWAY_PROXY_ADDR, L1_CUSTOM_ERC20_GATEWAY_IMPLEMENTATION_ADDR);
    }

    function deployL1ERC721Gateway() private {
        bytes memory args = abi.encode(notnull(L2_ERC721_GATEWAY_PROXY_ADDR), notnull(L1_SCROLL_MESSENGER_PROXY_ADDR));

        L1_ERC721_GATEWAY_IMPLEMENTATION_ADDR = deploy(
            "L1_ERC721_GATEWAY_IMPLEMENTATION",
            type(L1ERC721Gateway).creationCode,
            args
        );

        upgrade(L1_PROXY_ADMIN_ADDR, L1_ERC721_GATEWAY_PROXY_ADDR, L1_ERC721_GATEWAY_IMPLEMENTATION_ADDR);
    }

    function deployL1ERC1155Gateway() private {
        bytes memory args = abi.encode(notnull(L2_ERC1155_GATEWAY_PROXY_ADDR), notnull(L1_SCROLL_MESSENGER_PROXY_ADDR));

        L1_ERC1155_GATEWAY_IMPLEMENTATION_ADDR = deploy(
            "L1_ERC1155_GATEWAY_IMPLEMENTATION",
            type(L1ERC1155Gateway).creationCode,
            args
        );

        upgrade(L1_PROXY_ADMIN_ADDR, L1_ERC1155_GATEWAY_PROXY_ADDR, L1_ERC1155_GATEWAY_IMPLEMENTATION_ADDR);
    }

    /***************************
     * L2: 2nd pass deployment *
     ***************************/

    function deployL2ScrollMessenger() private {
        bytes memory args = abi.encode(notnull(L1_SCROLL_MESSENGER_PROXY_ADDR), notnull(L2_MESSAGE_QUEUE_ADDR));

        L2_SCROLL_MESSENGER_IMPLEMENTATION_ADDR = deploy(
            "L2_SCROLL_MESSENGER_IMPLEMENTATION",
            type(L2ScrollMessenger).creationCode,
            args
        );

        upgrade(L2_PROXY_ADMIN_ADDR, L2_SCROLL_MESSENGER_PROXY_ADDR, L2_SCROLL_MESSENGER_IMPLEMENTATION_ADDR);
    }

    function deployL2GatewayRouter() private {
        L2_GATEWAY_ROUTER_IMPLEMENTATION_ADDR = deploy(
            "L2_GATEWAY_ROUTER_IMPLEMENTATION",
            type(L2GatewayRouter).creationCode
        );

        bytes memory args = abi.encode(
            notnull(L2_GATEWAY_ROUTER_IMPLEMENTATION_ADDR),
            notnull(L2_PROXY_ADMIN_ADDR),
            new bytes(0)
        );

        L2_GATEWAY_ROUTER_PROXY_ADDR = deploy(
            "L2_GATEWAY_ROUTER_PROXY",
            type(TransparentUpgradeableProxy).creationCode,
            args
        );
    }

    function deployL2StandardERC20Gateway() private {
        bytes memory args = abi.encode(
            notnull(L1_STANDARD_ERC20_GATEWAY_PROXY_ADDR),
            notnull(L2_GATEWAY_ROUTER_PROXY_ADDR),
            notnull(L2_SCROLL_MESSENGER_PROXY_ADDR),
            notnull(L2_SCROLL_STANDARD_ERC20_FACTORY_ADDR)
        );

        L2_STANDARD_ERC20_GATEWAY_IMPLEMENTATION_ADDR = deploy(
            "L2_STANDARD_ERC20_GATEWAY_IMPLEMENTATION",
            type(L2StandardERC20Gateway).creationCode,
            args
        );

        upgrade(
            L2_PROXY_ADMIN_ADDR,
            L2_STANDARD_ERC20_GATEWAY_PROXY_ADDR,
            L2_STANDARD_ERC20_GATEWAY_IMPLEMENTATION_ADDR
        );
    }

    function deployL2ETHGateway() private {
        address COUNTERPART = L1_ETH_GATEWAY_PROXY_ADDR;
        bytes memory args = abi.encode(
            notnull(COUNTERPART),
            notnull(L2_GATEWAY_ROUTER_PROXY_ADDR),
            notnull(L2_SCROLL_MESSENGER_PROXY_ADDR)
        );

        L2_ETH_GATEWAY_IMPLEMENTATION_ADDR = deploy(
            "L2_ETH_GATEWAY_IMPLEMENTATION",
            type(L2ETHGateway).creationCode,
            args
        );

        upgrade(L2_PROXY_ADMIN_ADDR, L2_ETH_GATEWAY_PROXY_ADDR, L2_ETH_GATEWAY_IMPLEMENTATION_ADDR);
    }

    function deployL2WETHGateway() private {
        bytes memory args = abi.encode(
            notnull(L2_WETH_ADDR),
            notnull(L1_WETH_ADDR),
            notnull(L1_WETH_GATEWAY_PROXY_ADDR),
            notnull(L2_GATEWAY_ROUTER_PROXY_ADDR),
            notnull(L2_SCROLL_MESSENGER_PROXY_ADDR)
        );

        L2_WETH_GATEWAY_IMPLEMENTATION_ADDR = deploy(
            "L2_WETH_GATEWAY_IMPLEMENTATION",
            type(L2WETHGateway).creationCode,
            args
        );

        upgrade(L2_PROXY_ADMIN_ADDR, L2_WETH_GATEWAY_PROXY_ADDR, L2_WETH_GATEWAY_IMPLEMENTATION_ADDR);
    }

    function deployL2CustomERC20Gateway() private {
        bytes memory args = abi.encode(
            notnull(L1_CUSTOM_ERC20_GATEWAY_PROXY_ADDR),
            notnull(L2_GATEWAY_ROUTER_PROXY_ADDR),
            notnull(L2_SCROLL_MESSENGER_PROXY_ADDR)
        );

        L2_CUSTOM_ERC20_GATEWAY_IMPLEMENTATION_ADDR = deploy(
            "L2_CUSTOM_ERC20_GATEWAY_IMPLEMENTATION",
            type(L2CustomERC20Gateway).creationCode,
            args
        );

        upgrade(L2_PROXY_ADMIN_ADDR, L2_CUSTOM_ERC20_GATEWAY_PROXY_ADDR, L2_CUSTOM_ERC20_GATEWAY_IMPLEMENTATION_ADDR);
    }

    function deployL2ERC721Gateway() private {
        bytes memory args = abi.encode(notnull(L1_ERC721_GATEWAY_PROXY_ADDR), notnull(L2_SCROLL_MESSENGER_PROXY_ADDR));

        L2_ERC721_GATEWAY_IMPLEMENTATION_ADDR = deploy(
            "L2_ERC721_GATEWAY_IMPLEMENTATION",
            type(L2ERC721Gateway).creationCode,
            args
        );

        upgrade(L2_PROXY_ADMIN_ADDR, L2_ERC721_GATEWAY_PROXY_ADDR, L2_ERC721_GATEWAY_IMPLEMENTATION_ADDR);
    }

    function deployL2ERC1155Gateway() private {
        bytes memory args = abi.encode(notnull(L1_ERC1155_GATEWAY_PROXY_ADDR), notnull(L2_SCROLL_MESSENGER_PROXY_ADDR));

        L2_ERC1155_GATEWAY_IMPLEMENTATION_ADDR = deploy(
            "L2_ERC1155_GATEWAY_IMPLEMENTATION",
            type(L2ERC1155Gateway).creationCode,
            args
        );

        upgrade(L2_PROXY_ADMIN_ADDR, L2_ERC1155_GATEWAY_PROXY_ADDR, L2_ERC1155_GATEWAY_IMPLEMENTATION_ADDR);
    }

    /**********************
     * L1: initialization *
     **********************/

    function initializeScrollChain() private {
        if (getInitializeCount(L1_SCROLL_CHAIN_PROXY_ADDR) == 0) {
            ScrollChain(L1_SCROLL_CHAIN_PROXY_ADDR).initialize(
                notnull(L1_MESSAGE_QUEUE_V2_PROXY_ADDR),
                notnull(L1_MULTIPLE_VERSION_ROLLUP_VERIFIER_ADDR),
                MAX_TX_IN_CHUNK
            );
        }

        if (!ScrollChain(L1_SCROLL_CHAIN_PROXY_ADDR).isSequencer(L1_COMMIT_SENDER_ADDR)) {
            ScrollChain(L1_SCROLL_CHAIN_PROXY_ADDR).addSequencer(L1_COMMIT_SENDER_ADDR);
        }

        if (!ScrollChain(L1_SCROLL_CHAIN_PROXY_ADDR).isProver(L1_FINALIZE_SENDER_ADDR)) {
            ScrollChain(L1_SCROLL_CHAIN_PROXY_ADDR).addProver(L1_FINALIZE_SENDER_ADDR);
        }
    }

    function initializeSystemConfig() private {
        address owner = L1_PROXY_ADMIN_ADDR;
        address signer = L2GETH_SIGNER_ADDRESS;
        SystemConfig.MessageQueueParameters memory messageQueueParameters = SystemConfig.MessageQueueParameters({
            maxGasLimit: uint32(MAX_L1_MESSAGE_GAS_LIMIT),
            baseFeeOverhead: 1000000000,
            baseFeeScalar: 1000000000
        });
        SystemConfig.EnforcedBatchParameters memory enforcedBatchParameters = SystemConfig.EnforcedBatchParameters({
            maxDelayEnterEnforcedMode: uint24(FINALIZE_BATCH_DEADLINE_SEC),
            maxDelayMessageQueue: uint24(RELAY_MESSAGE_DEADLINE_SEC)
        });

        if (getInitializeCount(SYSTEM_CONFIG_PROXY_ADDR) == 0) {
            SystemConfig(SYSTEM_CONFIG_PROXY_ADDR).initialize(
                owner,
                signer,
                messageQueueParameters,
                enforcedBatchParameters
            );
        }
    }

    function initializeL1MessageQueue() private {
        if (getInitializeCount(L1_MESSAGE_QUEUE_V2_PROXY_ADDR) == 0) {
            L1MessageQueueV2(L1_MESSAGE_QUEUE_V2_PROXY_ADDR).initialize();
        }
    }

    function initializeL1ScrollMessenger() private {
        if (getInitializeCount(L1_SCROLL_MESSENGER_PROXY_ADDR) == 0) {
            L1ScrollMessenger(payable(L1_SCROLL_MESSENGER_PROXY_ADDR)).initialize(
                notnull(L2_SCROLL_MESSENGER_PROXY_ADDR),
                notnull(L1_FEE_VAULT_ADDR),
                notnull(L1_SCROLL_CHAIN_PROXY_ADDR),
                notnull(L1_MESSAGE_QUEUE_V2_PROXY_ADDR)
            );
        }
    }

    function initializeEnforcedTxGateway() private {
        if (getInitializeCount(L1_ENFORCED_TX_GATEWAY_PROXY_ADDR) == 0) {
            EnforcedTxGateway(payable(L1_ENFORCED_TX_GATEWAY_PROXY_ADDR)).initialize();
        }

        // disable gateway
        if (!EnforcedTxGateway(payable(L1_ENFORCED_TX_GATEWAY_PROXY_ADDR)).paused()) {
            EnforcedTxGateway(payable(L1_ENFORCED_TX_GATEWAY_PROXY_ADDR)).setPause(true);
        }
    }

    function initializeL1GatewayRouter() private {
        address L2_ETH_GATEWAY_COUNTERPART = L1_ETH_GATEWAY_PROXY_ADDR;
        if (getInitializeCount(L1_GATEWAY_ROUTER_PROXY_ADDR) == 0) {
            L1GatewayRouter(L1_GATEWAY_ROUTER_PROXY_ADDR).initialize(
                notnull(L2_ETH_GATEWAY_COUNTERPART),
                notnull(L1_STANDARD_ERC20_GATEWAY_PROXY_ADDR)
            );
        }
    }

    function initializeL1CustomERC20Gateway() private {
        if (getInitializeCount(L1_CUSTOM_ERC20_GATEWAY_PROXY_ADDR) == 0) {
            L1CustomERC20Gateway(L1_CUSTOM_ERC20_GATEWAY_PROXY_ADDR).initialize(
                notnull(L2_CUSTOM_ERC20_GATEWAY_PROXY_ADDR),
                notnull(L1_GATEWAY_ROUTER_PROXY_ADDR),
                notnull(L1_SCROLL_MESSENGER_PROXY_ADDR)
            );
        }
    }

    function initializeL1ERC1155Gateway() private {
        if (getInitializeCount(L1_ERC1155_GATEWAY_PROXY_ADDR) == 0) {
            L1ERC1155Gateway(L1_ERC1155_GATEWAY_PROXY_ADDR).initialize(
                notnull(L2_ERC1155_GATEWAY_PROXY_ADDR),
                notnull(L1_SCROLL_MESSENGER_PROXY_ADDR)
            );
        }
    }

    function initializeL1ERC721Gateway() private {
        if (getInitializeCount(L1_ERC721_GATEWAY_PROXY_ADDR) == 0) {
            L1ERC721Gateway(L1_ERC721_GATEWAY_PROXY_ADDR).initialize(
                notnull(L2_ERC721_GATEWAY_PROXY_ADDR),
                notnull(L1_SCROLL_MESSENGER_PROXY_ADDR)
            );
        }
    }

    function initializeL1ETHGateway() private {
        if (getInitializeCount(L1_ETH_GATEWAY_PROXY_ADDR) == 0) {
            L1ETHGateway(L1_ETH_GATEWAY_PROXY_ADDR).initialize(
                notnull(L2_ETH_GATEWAY_PROXY_ADDR),
                notnull(L1_GATEWAY_ROUTER_PROXY_ADDR),
                notnull(L1_SCROLL_MESSENGER_PROXY_ADDR)
            );
        }
    }

    function initializeL1StandardERC20Gateway() private {
        if (getInitializeCount(L1_STANDARD_ERC20_GATEWAY_PROXY_ADDR) == 0) {
            L1StandardERC20Gateway(L1_STANDARD_ERC20_GATEWAY_PROXY_ADDR).initialize(
                notnull(L2_STANDARD_ERC20_GATEWAY_PROXY_ADDR),
                notnull(L1_GATEWAY_ROUTER_PROXY_ADDR),
                notnull(L1_SCROLL_MESSENGER_PROXY_ADDR),
                notnull(L2_SCROLL_STANDARD_ERC20_ADDR),
                notnull(L2_SCROLL_STANDARD_ERC20_FACTORY_ADDR)
            );
        }
    }

    function initializeL1WETHGateway() private {
        if (getInitializeCount(L1_WETH_GATEWAY_PROXY_ADDR) == 0) {
            L1WETHGateway(payable(L1_WETH_GATEWAY_PROXY_ADDR)).initialize(
                notnull(L2_WETH_GATEWAY_PROXY_ADDR),
                notnull(L1_GATEWAY_ROUTER_PROXY_ADDR),
                notnull(L1_SCROLL_MESSENGER_PROXY_ADDR)
            );
        }

        // set WETH gateway in router
        address[] memory _tokens = new address[](1);
        _tokens[0] = notnull(L1_WETH_ADDR);
        address[] memory _gateways = new address[](1);
        _gateways[0] = notnull(L1_WETH_GATEWAY_PROXY_ADDR);

        if (L1GatewayRouter(L1_GATEWAY_ROUTER_PROXY_ADDR).ERC20Gateway(_tokens[0]) != _gateways[0]) {
            L1GatewayRouter(L1_GATEWAY_ROUTER_PROXY_ADDR).setERC20Gateway(_tokens, _gateways);
        }
    }

    function initializeL1Whitelist() private {
        address[] memory accounts = new address[](1);
        accounts[0] = L1_GAS_ORACLE_SENDER_ADDR;

        if (!Whitelist(L1_WHITELIST_ADDR).isSenderAllowed(accounts[0])) {
            Whitelist(L1_WHITELIST_ADDR).updateWhitelistStatus(accounts, true);
        }
    }

    function lockTokensOnL1() private {
        uint256 l1MessengerBalance = address(L1_SCROLL_MESSENGER_PROXY_ADDR).balance;
        uint256 amountToLock = L2_DEPLOYER_INITIAL_BALANCE;

        if (l1MessengerBalance < amountToLock) {
            uint256 amountToSend = amountToLock - l1MessengerBalance;
            (bool sent, bytes memory data) = payable(L1_SCROLL_MESSENGER_PROXY_ADDR).call{value: amountToSend}("");
            require(sent, "[ERROR] failed to lock tokens on layer 1");
        }
    }

    function transferL1ContractOwnership() private {
        transferOwnership(L1_ENFORCED_TX_GATEWAY_PROXY_ADDR, OWNER_ADDR);
        transferOwnership(L1_CUSTOM_ERC20_GATEWAY_PROXY_ADDR, OWNER_ADDR);
        transferOwnership(L1_ERC1155_GATEWAY_PROXY_ADDR, OWNER_ADDR);
        transferOwnership(L1_ERC721_GATEWAY_PROXY_ADDR, OWNER_ADDR);
        transferOwnership(L1_GATEWAY_ROUTER_PROXY_ADDR, OWNER_ADDR);
        transferOwnership(L1_MESSAGE_QUEUE_V2_PROXY_ADDR, OWNER_ADDR);
        transferOwnership(L1_SCROLL_MESSENGER_PROXY_ADDR, OWNER_ADDR);
        transferOwnership(L1_STANDARD_ERC20_GATEWAY_PROXY_ADDR, OWNER_ADDR);
        transferOwnership(L1_MULTIPLE_VERSION_ROLLUP_VERIFIER_ADDR, OWNER_ADDR);
        transferOwnership(L1_PROXY_ADMIN_ADDR, OWNER_ADDR);
        transferOwnership(L1_SCROLL_CHAIN_PROXY_ADDR, OWNER_ADDR);
        transferOwnership(L1_WHITELIST_ADDR, OWNER_ADDR);
        transferOwnership(L1_ETH_GATEWAY_PROXY_ADDR, OWNER_ADDR);
        transferOwnership(L1_WETH_GATEWAY_PROXY_ADDR, OWNER_ADDR);
    }

    /**********************
     * L2: initialization *
     **********************/

    function initializeL2MessageQueue() private {
        if (L2MessageQueue(L2_MESSAGE_QUEUE_ADDR).messenger() != notnull(L2_SCROLL_MESSENGER_PROXY_ADDR)) {
            L2MessageQueue(L2_MESSAGE_QUEUE_ADDR).initialize(L2_SCROLL_MESSENGER_PROXY_ADDR);
        }
    }

    function initializeL2TxFeeVault() private {
        if (L2TxFeeVault(payable(L2_TX_FEE_VAULT_ADDR)).messenger() != notnull(L2_SCROLL_MESSENGER_PROXY_ADDR)) {
            L2TxFeeVault(payable(L2_TX_FEE_VAULT_ADDR)).updateMessenger(L2_SCROLL_MESSENGER_PROXY_ADDR);
        }
    }

    function initializeL1GasPriceOracle() private {
        if (address(L1GasPriceOracle(L1_GAS_PRICE_ORACLE_ADDR).whitelist()) != notnull(L2_WHITELIST_ADDR)) {
            L1GasPriceOracle(L1_GAS_PRICE_ORACLE_ADDR).updateWhitelist(L2_WHITELIST_ADDR);
        }
    }

    function initializeL2ScrollMessenger() private {
        if (getInitializeCount(L2_SCROLL_MESSENGER_PROXY_ADDR) == 0) {
            L2ScrollMessenger(payable(L2_SCROLL_MESSENGER_PROXY_ADDR)).initialize(
                notnull(L1_SCROLL_MESSENGER_PROXY_ADDR)
            );
        }
    }

    function initializeL2GatewayRouter() private {
        if (getInitializeCount(L2_GATEWAY_ROUTER_PROXY_ADDR) == 0) {
            L2GatewayRouter(L2_GATEWAY_ROUTER_PROXY_ADDR).initialize(
                notnull(L2_ETH_GATEWAY_PROXY_ADDR),
                notnull(L2_STANDARD_ERC20_GATEWAY_PROXY_ADDR)
            );
        }
    }

    function initializeL2CustomERC20Gateway() private {
        if (getInitializeCount(L2_CUSTOM_ERC20_GATEWAY_PROXY_ADDR) == 0) {
            L2CustomERC20Gateway(L2_CUSTOM_ERC20_GATEWAY_PROXY_ADDR).initialize(
                notnull(L1_CUSTOM_ERC20_GATEWAY_PROXY_ADDR),
                notnull(L2_GATEWAY_ROUTER_PROXY_ADDR),
                notnull(L2_SCROLL_MESSENGER_PROXY_ADDR)
            );
        }
    }

    function initializeL2ERC1155Gateway() private {
        if (getInitializeCount(L2_ERC1155_GATEWAY_PROXY_ADDR) == 0) {
            L2ERC1155Gateway(L2_ERC1155_GATEWAY_PROXY_ADDR).initialize(
                notnull(L1_ERC1155_GATEWAY_PROXY_ADDR),
                notnull(L2_SCROLL_MESSENGER_PROXY_ADDR)
            );
        }
    }

    function initializeL2ERC721Gateway() private {
        if (getInitializeCount(L2_ERC721_GATEWAY_PROXY_ADDR) == 0) {
            L2ERC721Gateway(L2_ERC721_GATEWAY_PROXY_ADDR).initialize(
                notnull(L1_ERC721_GATEWAY_PROXY_ADDR),
                notnull(L2_SCROLL_MESSENGER_PROXY_ADDR)
            );
        }
    }

    function initializeL2ETHGateway() private {
        address COUNTERPART = L1_ETH_GATEWAY_PROXY_ADDR;
        if (getInitializeCount(L2_ETH_GATEWAY_PROXY_ADDR) == 0) {
            L2ETHGateway(L2_ETH_GATEWAY_PROXY_ADDR).initialize(
                notnull(COUNTERPART),
                notnull(L2_GATEWAY_ROUTER_PROXY_ADDR),
                notnull(L2_SCROLL_MESSENGER_PROXY_ADDR)
            );
        }
    }

    function initializeL2StandardERC20Gateway() private {
        if (getInitializeCount(L2_STANDARD_ERC20_GATEWAY_PROXY_ADDR) == 0) {
            L2StandardERC20Gateway(L2_STANDARD_ERC20_GATEWAY_PROXY_ADDR).initialize(
                notnull(L1_STANDARD_ERC20_GATEWAY_PROXY_ADDR),
                notnull(L2_GATEWAY_ROUTER_PROXY_ADDR),
                notnull(L2_SCROLL_MESSENGER_PROXY_ADDR),
                notnull(L2_SCROLL_STANDARD_ERC20_FACTORY_ADDR)
            );
        }
    }

    function initializeL2WETHGateway() private {
        if (getInitializeCount(L2_WETH_GATEWAY_PROXY_ADDR) == 0) {
            L2WETHGateway(payable(L2_WETH_GATEWAY_PROXY_ADDR)).initialize(
                notnull(L1_WETH_GATEWAY_PROXY_ADDR),
                notnull(L2_GATEWAY_ROUTER_PROXY_ADDR),
                notnull(L2_SCROLL_MESSENGER_PROXY_ADDR)
            );
        }

        // set WETH gateway in router
        address[] memory _tokens = new address[](1);
        _tokens[0] = notnull(L2_WETH_ADDR);
        address[] memory _gateways = new address[](1);
        _gateways[0] = notnull(L2_WETH_GATEWAY_PROXY_ADDR);

        if (L2GatewayRouter(L2_GATEWAY_ROUTER_PROXY_ADDR).ERC20Gateway(_tokens[0]) != _gateways[0]) {
            L2GatewayRouter(L2_GATEWAY_ROUTER_PROXY_ADDR).setERC20Gateway(_tokens, _gateways);
        }
    }

    function initializeScrollStandardERC20Factory() private {
        transferOwnership(
            notnull(L2_SCROLL_STANDARD_ERC20_FACTORY_ADDR),
            notnull(L2_STANDARD_ERC20_GATEWAY_PROXY_ADDR)
        );
    }

    function initializeL2Whitelist() private {
        address[] memory accounts = new address[](1);
        accounts[0] = L2_GAS_ORACLE_SENDER_ADDR;

        if (!Whitelist(L2_WHITELIST_ADDR).isSenderAllowed(accounts[0])) {
            Whitelist(L2_WHITELIST_ADDR).updateWhitelistStatus(accounts, true);
        }
    }

    function transferL2ContractOwnership() private {
        transferOwnership(L1_GAS_PRICE_ORACLE_ADDR, OWNER_ADDR);
        transferOwnership(L2_CUSTOM_ERC20_GATEWAY_PROXY_ADDR, OWNER_ADDR);
        transferOwnership(L2_ERC1155_GATEWAY_PROXY_ADDR, OWNER_ADDR);
        transferOwnership(L2_ERC721_GATEWAY_PROXY_ADDR, OWNER_ADDR);
        transferOwnership(L2_ETH_GATEWAY_PROXY_ADDR, OWNER_ADDR);
        transferOwnership(L2_GATEWAY_ROUTER_PROXY_ADDR, OWNER_ADDR);
        transferOwnership(L2_MESSAGE_QUEUE_ADDR, OWNER_ADDR);
        transferOwnership(L2_SCROLL_MESSENGER_PROXY_ADDR, OWNER_ADDR);
        transferOwnership(L2_STANDARD_ERC20_GATEWAY_PROXY_ADDR, OWNER_ADDR);
        transferOwnership(L2_TX_FEE_VAULT_ADDR, OWNER_ADDR);
        transferOwnership(L2_PROXY_ADMIN_ADDR, OWNER_ADDR);
        transferOwnership(L2_WHITELIST_ADDR, OWNER_ADDR);
        transferOwnership(L2_WETH_GATEWAY_PROXY_ADDR, OWNER_ADDR);
    }
}
