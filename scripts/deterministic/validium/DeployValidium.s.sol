// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.24;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {stdToml} from "forge-std/StdToml.sol";
import {TransparentUpgradeableProxy, ITransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

// host contracts
import {L1MessageQueueV2} from "../../../src/L1/rollup/L1MessageQueueV2.sol";
import {EmptyL1MessageQueueV1} from "../../../src/validium/EmptyL1MessageQueueV1.sol";
import {L1ScrollMessengerValidium} from "../../../src/validium/L1ScrollMessengerValidium.sol";
import {ScrollChainValidium} from "../../../src/validium/ScrollChainValidium.sol";
import {ScrollChainValidiumMock} from "../../../src/mocks/ScrollChainValidiumMock.sol";
import {L1ERC20GatewayValidium} from "../../../src/validium/L1ERC20GatewayValidium.sol";
import {L1WETHGatewayValidium} from "../../../src/validium/L1WETHGatewayValidium.sol";
import {SystemConfig} from "../../../src/L1/system-contract/SystemConfig.sol";
import {L1GatewayRouter} from "../../../src/L1/gateways/L1GatewayRouter.sol";
import {L1ETHGateway} from "../../../src/L1/gateways/L1ETHGateway.sol";
import {FastWithdrawVault} from "../../../src/validium/FastWithdrawVault.sol";

// validium contracts
import {L1GasPriceOracle} from "../../../src/L2/predeploys/L1GasPriceOracle.sol";
import {L2MessageQueue} from "../../../src/L2/predeploys/L2MessageQueue.sol";
import {L2ScrollMessenger} from "../../../src/L2/L2ScrollMessenger.sol";
import {L2SystemConfig} from "../../../src/L2/L2SystemConfig.sol";
import {L2TxFeeVault} from "../../../src/L2/predeploys/L2TxFeeVault.sol";
import {L2GatewayRouter} from "../../../src/L2/gateways/L2GatewayRouter.sol";
import {L2ETHGateway} from "../../../src/L2/gateways/L2ETHGateway.sol";
import {L2StandardERC20Gateway} from "../../../src/L2/gateways/L2StandardERC20Gateway.sol";
import {ScrollStandardERC20} from "../../../src/libraries/token/ScrollStandardERC20.sol";
import {ScrollStandardERC20FactorySetOwner} from "../contracts/ScrollStandardERC20FactorySetOwner.sol";

// misc
import {DeterministicDeployment} from "../DeterministicDeployment.sol";
import {EmptyContract} from "../../../src/misc/EmptyContract.sol";
import {FEE_VAULT_MIN_WITHDRAW_AMOUNT} from "./Constants.sol";
import {ProxyAdminSetOwner} from "../contracts/ProxyAdminSetOwner.sol";
import {Whitelist} from "../../../src/L2/predeploys/Whitelist.sol";
import {WrappedEther} from "../../../src/L2/predeploys/WrappedEther.sol";

import {ValidiumConfiguration} from "./ValidiumConfiguration.sol";

contract DeployValidium is ValidiumConfiguration, DeterministicDeployment {
    using stdToml for string;

    /***********************
     * Contracts to deploy *
     ***********************/

    // Host addresses
    address internal HOST_ENFORCED_TX_GATEWAY_ADDR;
    address internal HOST_ERC20_GATEWAY_ADDR;
    address internal HOST_IMPLEMENTATION_PLACEHOLDER_ADDR;
    address internal HOST_MESSAGE_QUEUE_ADDR;
    address internal HOST_MESSENGER_ADDR;
    address internal HOST_MESSENGER_WHITELIST_ADDR;
    address internal HOST_MULTIPLE_VERSION_ROLLUP_VERIFIER_ADDR;
    address internal HOST_PROXY_ADMIN_ADDR;
    address internal HOST_SYSTEM_CONFIG_ADDR;
    address internal HOST_VALIDIUM_ADDR;
    address internal HOST_WETH_ADDR;
    address internal HOST_WETH_GATEWAY_ADDR;
    address internal HOST_FAST_WITHDRAW_VAULT_ADDR;

    // Validium addresses
    address internal VALIDIUM_ERC20_GATEWAY_ADDR;
    address internal VALIDIUM_GAS_PRICE_ORACLE_ADDR;
    address internal VALIDIUM_GAS_PRICE_ORACLE_WHITELIST_ADDR;
    address internal VALIDIUM_GATEWAY_ROUTER_ADDR;
    address internal VALIDIUM_IMPLEMENTATION_PLACEHOLDER_ADDR;
    address internal VALIDIUM_MESSAGE_QUEUE_ADDR;
    address internal VALIDIUM_MESSENGER_ADDR;
    address internal VALIDIUM_PROXY_ADMIN_ADDR;
    address internal VALIDIUM_STANDARD_ERC20_FACTORY_ADDR;
    address internal VALIDIUM_STANDARD_ERC20_TOKEN_ADDR;
    address internal VALIDIUM_SYSTEM_CONFIG_ADDR;
    address internal VALIDIUM_TX_FEE_VAULT_ADDR;

    /*************
     * Utilities *
     *************/

    enum Layer {
        None,
        Host, // The host layer on which the validium is deployed, usually L2.
        Validium // The validium layer, i.e. L3.
    }

    Layer private broadcastLayer = Layer.None;

    /// @dev Only broadcast code block if we run the script on the specified layer.
    modifier broadcast(Layer layer) {
        // live deployment
        if (broadcastLayer == layer) {
            vm.startBroadcast(DEPLOYER_PRIVATE_KEY);
            _;
            vm.stopBroadcast();
        }
        // simulation
        else {
            // make sure we use the correct sender in simulation
            vm.startPrank(DEPLOYER_ADDR);
            _;
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

    function parseLayer(string memory raw) private pure returns (Layer) {
        if (keccak256(bytes(raw)) == keccak256(bytes("host"))) {
            return Layer.Host;
        } else if (keccak256(bytes(raw)) == keccak256(bytes("validium"))) {
            return Layer.Validium;
        } else if (keccak256(bytes(raw)) == keccak256(bytes(""))) {
            return Layer.None;
        } else {
            revert(string(abi.encodePacked("[ERROR] unknown layer: ", raw)));
        }
    }

    /***************
     * Entry point *
     ***************/

    function run(
        string memory workdir,
        string memory layer,
        string memory scriptMode
    ) public {
        readConfig(workdir);

        broadcastLayer = parseLayer(layer);
        ScriptMode mode = parseScriptMode(scriptMode);

        DeterministicDeployment.initialize(mode, workdir);

        deployAllContracts();
        initializeHostContracts();
        initializeValidiumContracts();
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

    function deployHostProxy(string memory name) private returns (address) {
        bytes memory args = abi.encode(
            notnull(HOST_IMPLEMENTATION_PLACEHOLDER_ADDR),
            notnull(HOST_PROXY_ADMIN_ADDR),
            new bytes(0)
        );

        return deploy(name, type(TransparentUpgradeableProxy).creationCode, args);
    }

    function deployValidiumProxy(string memory name) private returns (address) {
        bytes memory args = abi.encode(
            notnull(VALIDIUM_IMPLEMENTATION_PLACEHOLDER_ADDR),
            notnull(VALIDIUM_PROXY_ADMIN_ADDR),
            new bytes(0)
        );

        return deploy(name, type(TransparentUpgradeableProxy).creationCode, args);
    }

    function transferOwnership(address addr, address newOwner) private {
        if (Ownable(addr).owner() != newOwner) {
            Ownable(addr).transferOwnership(newOwner);
        }
    }

    function deployAllContracts() private {
        deployHostContracts1stPass();
        deployValidiumContracts1stPass();
        deployHostContracts2ndPass();
        deployValidiumContracts2ndPass();
    }

    // @notice deployHostContracts1stPass deploys host-layer contracts whose initialization does not depend on any validium-layer addresses.
    function deployHostContracts1stPass() private broadcast(Layer.Host) {
        deployHostWeth();
        deployHostProxyAdmin();

        // Note: we do not use the enforced gateway on the validium L3,
        // but it is required to be a non-zero address for initializing
        // some other contracts. We just use address(1).
        HOST_ENFORCED_TX_GATEWAY_ADDR = address(1);

        // TODO: deploy verifier
        HOST_MULTIPLE_VERSION_ROLLUP_VERIFIER_ADDR = address(1);

        // deploy empty proxies
        HOST_VALIDIUM_ADDR = deployHostProxy("HOST_VALIDIUM_PROXY");
        HOST_MESSAGE_QUEUE_ADDR = deployHostProxy("HOST_MESSAGE_QUEUE_PROXY");
        HOST_SYSTEM_CONFIG_ADDR = deployHostProxy("HOST_SYSTEM_CONFIG_PROXY");
        HOST_MESSENGER_ADDR = deployHostProxy("HOST_MESSENGER_PROXY");
        HOST_ERC20_GATEWAY_ADDR = deployHostProxy("HOST_ERC20_GATEWAY_PROXY");
        HOST_WETH_GATEWAY_ADDR = deployHostProxy("HOST_WETH_GATEWAY_PROXY");
        HOST_FAST_WITHDRAW_VAULT_ADDR = deployHostProxy("HOST_FAST_WITHDRAW_VAULT_PROXY");

        // deploy implementations
        deployHostValidium();
        deployHostMessageQueue();
        deployHostSystemConfig();
        deployHostMessengerWhitelist();
        deployHostWethGateway();
        deployHostFastWithdrawVault();
    }

    // @notice deployValidiumContracts1stPass deploys validium-layer contracts whose initialization does not depend on any host-layer addresses.
    function deployValidiumContracts1stPass() private broadcast(Layer.Validium) {
        deployValidiumProxyAdmin();

        // Note: we do not use the gateway router on the validium L3,
        // but it is required to be a non-zero address for initializing
        // some other contracts. We just use address(1).
        VALIDIUM_GATEWAY_ROUTER_ADDR = address(1);

        // predeploys
        deployValidiumMessageQueue();
        deployValidiumGasPriceOracle();
        deployValidiumWhitelist();
        deployValidiumTxFeeVault();

        // deploy empty proxies
        VALIDIUM_MESSENGER_ADDR = deployValidiumProxy("VALIDIUM_MESSENGER_PROXY");
        VALIDIUM_SYSTEM_CONFIG_ADDR = deployValidiumProxy("VALIDIUM_SYSTEM_CONFIG_PROXY");
        VALIDIUM_ERC20_GATEWAY_ADDR = deployValidiumProxy("VALIDIUM_ERC20_GATEWAY_PROXY");

        // deploy implementations
        deployValidiumSystemConfig();
        deployValidiumStandardErc20Factory();
    }

    // @notice deployHostContracts2ndPass deploys host-layer contracts whose initialization depends on some validium-layer addresses.
    function deployHostContracts2ndPass() private broadcast(Layer.Host) {
        deployHostMessenger(); // depends on VALIDIUM_MESSENGER_ADDR
        deployHostErc20Gateway(); // depends on VALIDIUM_ERC20_GATEWAY_ADDR
    }

    // @notice deployValidiumContracts2ndPass deploys validium-layer contracts whose initialization depends on some host-layer addresses.
    function deployValidiumContracts2ndPass() private broadcast(Layer.Validium) {
        deployValidiumMessenger(); // depends on HOST_MESSENGER_ADDR
        deployValidiumErc20Gateway(); // depends on HOST_ERC20_GATEWAY_ADDR
    }

    // @notice initializeHostContracts initializes contracts deployed on the host layer.
    function initializeHostContracts() private broadcast(Layer.Host) only(Layer.Host) {
        initializeHostValidium();
        initializeHostSystemConfig();
        initializeHostMessageQueue();
        initializeHostMessenger();
        initializeHostMessengerWhitelist();

        initializeHostErc20Gateway();
        initializeHostFastWithdrawVault();

        // lockTokensOnL1();
        // transferL1ContractOwnership();
    }

    // @notice initializeValidiumContracts initializes contracts deployed on the validium layer.
    function initializeValidiumContracts() private broadcast(Layer.Validium) only(Layer.Validium) {
        initializeValidiumMessageQueue();
        initializeValidiumTxFeeVault();
        initializeValidiumGasPriceOracle();
        initializeValidiumMessenger();
        initializeValidiumSystemConfig();

        initializeValidiumErc20Gateway();

        // transferL2ContractOwnership();
    }

    /********************
     * Host: Deployment *
     *******************/

    function deployHostWeth() private {
        HOST_WETH_ADDR = deploy("HOST_WETH", type(WrappedEther).creationCode);
    }

    function deployHostProxyAdmin() private {
        bytes memory args = abi.encode(DEPLOYER_ADDR);
        HOST_PROXY_ADMIN_ADDR = deploy("HOST_PROXY_ADMIN", type(ProxyAdminSetOwner).creationCode, args);

        HOST_IMPLEMENTATION_PLACEHOLDER_ADDR = deploy(
            "HOST_IMPLEMENTATION_PLACEHOLDER",
            type(EmptyContract).creationCode
        );
    }

    function deployHostValidium() private {
        bytes memory args = abi.encode(
            CHAIN_ID_VALIDIUM,
            notnull(HOST_MESSAGE_QUEUE_ADDR),
            notnull(HOST_MULTIPLE_VERSION_ROLLUP_VERIFIER_ADDR)
        );

        // TODO: disable mock mode
        // bytes memory creationCode = type(ScrollChainValidium).creationCode;
        bytes memory creationCode = type(ScrollChainValidiumMock).creationCode;

        // if (TEST_ENV_MOCK_FINALIZE_ENABLED) {
        //     creationCode = type(ScrollChainValidiumMockFinalize).creationCode;
        // }

        address impl = deploy("HOST_VALIDIUM_IMPLEMENTATION", creationCode, args);
        upgrade(HOST_PROXY_ADMIN_ADDR, HOST_VALIDIUM_ADDR, impl);
    }

    function deployHostMessageQueue() private {
        address queueV1 = deploy("HOST_EMPTY_MESSAGE_QUEUE_V1", type(EmptyL1MessageQueueV1).creationCode);

        bytes memory args = abi.encode(
            notnull(HOST_MESSENGER_ADDR),
            notnull(HOST_VALIDIUM_ADDR),
            notnull(HOST_ENFORCED_TX_GATEWAY_ADDR),
            notnull(queueV1),
            notnull(HOST_SYSTEM_CONFIG_ADDR)
        );

        address impl = deploy("HOST_MESSAGE_QUEUE_IMPLEMENTATION", type(L1MessageQueueV2).creationCode, args);

        upgrade(HOST_PROXY_ADMIN_ADDR, HOST_MESSAGE_QUEUE_ADDR, impl);
    }

    function deployHostSystemConfig() private {
        address impl = deploy("HOST_SYSTEM_CONFIG_IMPLEMENTATION", type(SystemConfig).creationCode);
        upgrade(HOST_PROXY_ADMIN_ADDR, HOST_SYSTEM_CONFIG_ADDR, impl);
    }

    function deployHostMessengerWhitelist() private {
        bytes memory args = abi.encode(notnull(OWNER_ADDR));
        HOST_MESSENGER_WHITELIST_ADDR = deploy("HOST_MESSENGER_WHITELIST", type(Whitelist).creationCode, args);
    }

    function deployHostWethGateway() private {
        bytes memory args = abi.encode(notnull(HOST_WETH_ADDR), notnull(HOST_ERC20_GATEWAY_ADDR));

        address impl = deploy("HOST_WETH_GATEWAY_IMPLEMENTATION", type(L1WETHGatewayValidium).creationCode, args);

        upgrade(HOST_PROXY_ADMIN_ADDR, HOST_WETH_GATEWAY_ADDR, impl);
    }

    function deployHostFastWithdrawVault() private {
        bytes memory args = abi.encode(notnull(HOST_WETH_ADDR), notnull(HOST_ERC20_GATEWAY_ADDR));

        address impl = deploy("HOST_FAST_WITHDRAW_VAULT_IMPLEMENTATION", type(FastWithdrawVault).creationCode, args);

        upgrade(HOST_PROXY_ADMIN_ADDR, HOST_FAST_WITHDRAW_VAULT_ADDR, impl);
    }

    function deployHostMessenger() private {
        bytes memory args = abi.encode(
            notnull(VALIDIUM_MESSENGER_ADDR),
            notnull(HOST_VALIDIUM_ADDR),
            notnull(HOST_MESSAGE_QUEUE_ADDR),
            notnull(HOST_MESSENGER_WHITELIST_ADDR)
        );

        address impl = deploy("HOST_MESSENGER_IMPLEMENTATION", type(L1ScrollMessengerValidium).creationCode, args);

        upgrade(HOST_PROXY_ADMIN_ADDR, HOST_MESSENGER_ADDR, impl);
    }

    function deployHostErc20Gateway() private {
        bytes memory args = abi.encode(
            notnull(VALIDIUM_ERC20_GATEWAY_ADDR),
            notnull(HOST_MESSENGER_ADDR),
            notnull(VALIDIUM_STANDARD_ERC20_TOKEN_ADDR),
            notnull(VALIDIUM_STANDARD_ERC20_FACTORY_ADDR),
            notnull(HOST_VALIDIUM_ADDR)
        );

        address impl = deploy("HOST_ERC20_GATEWAY_IMPLEMENTATION", type(L1ERC20GatewayValidium).creationCode, args);

        upgrade(HOST_PROXY_ADMIN_ADDR, HOST_ERC20_GATEWAY_ADDR, impl);
    }

    /************************
     * Validium: Deployment *
     ***********************/

    function deployValidiumProxyAdmin() private {
        bytes memory args = abi.encode(DEPLOYER_ADDR);
        VALIDIUM_PROXY_ADMIN_ADDR = deploy("VALIDIUM_PROXY_ADMIN", type(ProxyAdminSetOwner).creationCode, args);

        VALIDIUM_IMPLEMENTATION_PLACEHOLDER_ADDR = deploy(
            "VALIDIUM_IMPLEMENTATION_PLACEHOLDER",
            type(EmptyContract).creationCode
        );
    }

    function deployValidiumMessageQueue() private {
        bytes memory args = abi.encode(DEPLOYER_ADDR);
        VALIDIUM_MESSAGE_QUEUE_ADDR = deploy("VALIDIUM_MESSAGE_QUEUE", type(L2MessageQueue).creationCode, args);
    }

    function deployValidiumGasPriceOracle() private {
        bytes memory args = abi.encode(DEPLOYER_ADDR, true);
        VALIDIUM_GAS_PRICE_ORACLE_ADDR = deploy("VALIDIUM_GAS_PRICE_ORACLE", type(L1GasPriceOracle).creationCode, args);
    }

    function deployValidiumWhitelist() private {
        bytes memory args = abi.encode(DEPLOYER_ADDR);
        VALIDIUM_GAS_PRICE_ORACLE_WHITELIST_ADDR = deploy(
            "VALIDIUM_GAS_PRICE_ORACLE_WHITELIST",
            type(Whitelist).creationCode,
            args
        );
    }

    function deployValidiumTxFeeVault() private {
        bytes memory args = abi.encode(DEPLOYER_ADDR, L1_FEE_VAULT_ADDR, FEE_VAULT_MIN_WITHDRAW_AMOUNT);
        VALIDIUM_TX_FEE_VAULT_ADDR = deploy("VALIDIUM_TX_FEE_VAULT", type(L2TxFeeVault).creationCode, args);
    }

    function deployValidiumSystemConfig() private {
        address impl = deploy("VALIDIUM_SYSTEM_CONFIG_IMPLEMENTATION", type(L2SystemConfig).creationCode, new bytes(0));
        upgrade(VALIDIUM_PROXY_ADMIN_ADDR, VALIDIUM_SYSTEM_CONFIG_ADDR, impl);
    }

    function deployValidiumStandardErc20Factory() private {
        VALIDIUM_STANDARD_ERC20_TOKEN_ADDR = deploy(
            "VALIDIUM_STANDARD_ERC20_TOKEN",
            type(ScrollStandardERC20).creationCode
        );

        bytes memory args = abi.encode(
            VALIDIUM_ERC20_GATEWAY_ADDR, // Note: The factory contract must be owned by the ERC20 gateway contract.
            notnull(VALIDIUM_STANDARD_ERC20_TOKEN_ADDR)
        );

        VALIDIUM_STANDARD_ERC20_FACTORY_ADDR = deploy(
            "VALIDIUM_STANDARD_ERC20_FACTORY",
            type(ScrollStandardERC20FactorySetOwner).creationCode,
            args
        );
    }

    function deployValidiumMessenger() private {
        bytes memory args = abi.encode(notnull(HOST_MESSENGER_ADDR), notnull(VALIDIUM_MESSAGE_QUEUE_ADDR));

        address impl = deploy("VALIDIUM_MESSENGER_IMPLEMENTATION", type(L2ScrollMessenger).creationCode, args);

        upgrade(VALIDIUM_PROXY_ADMIN_ADDR, VALIDIUM_MESSENGER_ADDR, impl);
    }

    function deployValidiumErc20Gateway() private {
        bytes memory args = abi.encode(
            notnull(HOST_ERC20_GATEWAY_ADDR),
            notnull(VALIDIUM_GATEWAY_ROUTER_ADDR),
            notnull(VALIDIUM_MESSENGER_ADDR),
            notnull(VALIDIUM_STANDARD_ERC20_FACTORY_ADDR)
        );

        address impl = deploy("VALIDIUM_ERC20_GATEWAY_IMPLEMENTATION", type(L2StandardERC20Gateway).creationCode, args);

        upgrade(VALIDIUM_PROXY_ADMIN_ADDR, VALIDIUM_ERC20_GATEWAY_ADDR, impl);
    }

    /************************
     * Host: initialization *
     ************************/

    function initializeHostValidium() private {
        ScrollChainValidium validium = ScrollChainValidium(HOST_VALIDIUM_ADDR);

        if (getInitializeCount(HOST_VALIDIUM_ADDR) != 0) {
            // assume initialization went through correctly
            return;
        }

        // temporarily set deployer as admin
        validium.initialize(notnull(DEPLOYER_ADDR));

        // grant operational roles
        validium.grantRole(validium.GENESIS_IMPORTER_ROLE(), notnull(COMMIT_SENDER_ADDR));
        validium.grantRole(validium.SEQUENCER_ROLE(), notnull(COMMIT_SENDER_ADDR));
        validium.grantRole(validium.PROVER_ROLE(), notnull(FINALIZE_SENDER_ADDR));
        validium.grantRole(validium.KEY_MANAGER_ROLE(), notnull(DEPLOYER_ADDR));

        validium.registerNewEncryptionKey(vm.parseBytes(SEQUENCER_ENCRYPTION_KEY));

        // transfer roles to owner
        validium.grantRole(validium.KEY_MANAGER_ROLE(), notnull(OWNER_ADDR));
        validium.renounceRole(validium.KEY_MANAGER_ROLE(), DEPLOYER_ADDR);

        validium.grantRole(validium.DEFAULT_ADMIN_ROLE(), notnull(OWNER_ADDR));
        validium.renounceRole(validium.DEFAULT_ADMIN_ROLE(), DEPLOYER_ADDR);
    }

    function initializeHostSystemConfig() private {
        address owner = OWNER_ADDR;
        address signer = SEQUENCER_SIGNER_ADDRESS;

        SystemConfig.MessageQueueParameters memory messageQueueParameters = SystemConfig.MessageQueueParameters({
            maxGasLimit: uint32(VALIDIUM_GAS_LIMIT),
            baseFeeOverhead: 1000000000,
            baseFeeScalar: 1000000000
        });

        SystemConfig.EnforcedBatchParameters memory enforcedBatchParameters = SystemConfig.EnforcedBatchParameters({
            maxDelayEnterEnforcedMode: uint24(2**24 - 1),
            maxDelayMessageQueue: uint24(2**24 - 1)
        });

        if (getInitializeCount(HOST_SYSTEM_CONFIG_ADDR) == 0) {
            SystemConfig(HOST_SYSTEM_CONFIG_ADDR).initialize(
                owner,
                signer,
                messageQueueParameters,
                enforcedBatchParameters
            );
        }
    }

    function initializeHostMessageQueue() private {
        if (getInitializeCount(HOST_MESSAGE_QUEUE_ADDR) == 0) {
            L1MessageQueueV2(HOST_MESSAGE_QUEUE_ADDR).initialize();
        }
    }

    function initializeHostMessenger() private {
        if (getInitializeCount(HOST_MESSENGER_ADDR) == 0) {
            L1ScrollMessengerValidium(payable(HOST_MESSENGER_ADDR)).initialize(
                notnull(VALIDIUM_MESSENGER_ADDR),
                notnull(L1_FEE_VAULT_ADDR),
                notnull(HOST_VALIDIUM_ADDR),
                notnull(HOST_MESSAGE_QUEUE_ADDR)
            );
        }
    }

    function initializeHostMessengerWhitelist() private {
        address[] memory gateways = new address[](2);
        gateways[0] = HOST_ERC20_GATEWAY_ADDR;
        Whitelist(HOST_MESSENGER_WHITELIST_ADDR).updateWhitelistStatus(gateways, true);
    }

    function initializeHostErc20Gateway() private {
        if (getInitializeCount(HOST_ERC20_GATEWAY_ADDR) == 0) {
            L1ERC20GatewayValidium(payable(HOST_ERC20_GATEWAY_ADDR)).initialize();
        }
    }

    function initializeHostFastWithdrawVault() private {
        if (getInitializeCount(HOST_FAST_WITHDRAW_VAULT_ADDR) == 0) {
            FastWithdrawVault(payable(HOST_FAST_WITHDRAW_VAULT_ADDR)).initialize(
                notnull(OWNER_ADDR),
                notnull(FAST_WITHDRAW_SIGNER_ADDR)
            );
        }
    }

    /****************************
     * Validium: initialization *
     ***************************/

    function initializeValidiumMessageQueue() private {
        if (L2MessageQueue(VALIDIUM_MESSAGE_QUEUE_ADDR).messenger() != notnull(VALIDIUM_MESSENGER_ADDR)) {
            L2MessageQueue(VALIDIUM_MESSAGE_QUEUE_ADDR).initialize(VALIDIUM_MESSENGER_ADDR);
        }
    }

    function initializeValidiumTxFeeVault() private {
        if (L2TxFeeVault(payable(VALIDIUM_TX_FEE_VAULT_ADDR)).messenger() != notnull(VALIDIUM_MESSENGER_ADDR)) {
            L2TxFeeVault(payable(VALIDIUM_TX_FEE_VAULT_ADDR)).updateMessenger(VALIDIUM_MESSENGER_ADDR);
        }
    }

    function initializeValidiumGasPriceOracle() private {
        if (
            address(L1GasPriceOracle(VALIDIUM_GAS_PRICE_ORACLE_ADDR).whitelist()) !=
            notnull(VALIDIUM_GAS_PRICE_ORACLE_WHITELIST_ADDR)
        ) {
            L1GasPriceOracle(VALIDIUM_GAS_PRICE_ORACLE_ADDR).updateWhitelist(VALIDIUM_GAS_PRICE_ORACLE_WHITELIST_ADDR);
        }
    }

    function initializeValidiumMessenger() private {
        if (getInitializeCount(VALIDIUM_MESSENGER_ADDR) == 0) {
            L2ScrollMessenger(payable(VALIDIUM_MESSENGER_ADDR)).initialize(notnull(HOST_MESSENGER_ADDR));
        }
    }

    function initializeValidiumSystemConfig() private {
        if (getInitializeCount(VALIDIUM_SYSTEM_CONFIG_ADDR) == 0) {
            L2SystemConfig(payable(VALIDIUM_SYSTEM_CONFIG_ADDR)).initialize(notnull(OWNER_ADDR));
        }
    }

    function initializeValidiumErc20Gateway() private {
        if (getInitializeCount(VALIDIUM_ERC20_GATEWAY_ADDR) == 0) {
            L2StandardERC20Gateway(VALIDIUM_ERC20_GATEWAY_ADDR).initialize(
                notnull(HOST_ERC20_GATEWAY_ADDR),
                notnull(VALIDIUM_GATEWAY_ROUTER_ADDR),
                notnull(VALIDIUM_MESSENGER_ADDR),
                notnull(VALIDIUM_STANDARD_ERC20_FACTORY_ADDR)
            );
        }
    }
}
