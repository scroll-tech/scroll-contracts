// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.24;

import {stdToml} from "forge-std/StdToml.sol";

import {ADMIN_SYSTEM_BACKEND_CONFIG_PATH, ADMIN_SYSTEM_CRON_CONFIG_PATH, BALANCE_CHECKER_CONFIG_PATH, BALANCE_CHECKER_CONFIG_TEMPLATE_PATH, BRIDGE_HISTORY_API_CONFIG_PATH, BRIDGE_HISTORY_CONFIG_TEMPLATE_PATH, BRIDGE_HISTORY_FETCHER_CONFIG_PATH, CHAIN_MONITOR_CONFIG_PATH, CHAIN_MONITOR_CONFIG_TEMPLATE_PATH, COORDINATOR_API_CONFIG_PATH, COORDINATOR_CONFIG_TEMPLATE_PATH, COORDINATOR_CRON_CONFIG_PATH, GAS_ORACLE_CONFIG_PATH, GENESIS_ALLOC_JSON_PATH, GENESIS_JSON_PATH, ROLLUP_CONFIG_PATH, ROLLUP_CONFIG_TEMPLATE_PATH, ROLLUP_EXPLORER_BACKEND_CONFIG_PATH} from "./Constants.sol";
import {DeployScroll} from "./DeployScroll.s.sol";
import {DeterministicDeployment} from "../DeterministicDeployment.sol";

contract GenerateRollupConfig is DeployScroll {
    using stdToml for string;

    /***************
     * Entry point *
     ***************/

    function run(string memory workdir) public {
        DeterministicDeployment.initialize(ScriptMode.VerifyConfig, workdir);
        predictAllContracts();

        generateRollupConfig(ROLLUP_CONFIG_PATH);
        generateRollupConfig(GAS_ORACLE_CONFIG_PATH);
    }

    /*********************
     * Private functions *
     *********************/

    // prettier-ignore
    function generateRollupConfig(string memory PATH) private {
        // initialize template file
        if (vm.exists(PATH)) {
            vm.removeFile(PATH);
        }

        string memory template = vm.readFile(ROLLUP_CONFIG_TEMPLATE_PATH);
        vm.writeFile(PATH, template);

        // contracts
        vm.writeJson(vm.toString(L1_GAS_PRICE_ORACLE_ADDR), PATH, ".l1_config.relayer_config.gas_price_oracle_contract_address");
        vm.writeJson(vm.toString(L2_MESSAGE_QUEUE_ADDR), PATH, ".l2_config.l2_message_queue_address");
        vm.writeJson(vm.toString(L1_SCROLL_CHAIN_PROXY_ADDR), PATH, ".l2_config.relayer_config.rollup_contract_address");
        vm.writeJson(vm.toString(L1_MESSAGE_QUEUE_V2_PROXY_ADDR), PATH, ".l2_config.relayer_config.gas_price_oracle_contract_address");

        // other
        vm.writeJson(vm.toString(TEST_ENV_MOCK_FINALIZE_ENABLED), PATH, ".l2_config.relayer_config.enable_test_env_bypass_features");
        vm.writeJson(vm.toString(TEST_ENV_MOCK_FINALIZE_TIMEOUT_SEC), PATH, ".l2_config.relayer_config.finalize_batch_without_proof_timeout_sec");
        vm.writeJson(vm.toString(TEST_ENV_MOCK_FINALIZE_TIMEOUT_SEC), PATH, ".l2_config.relayer_config.finalize_bundle_without_proof_timeout_sec");

        vm.writeJson(vm.toString(MAX_BLOCK_IN_CHUNK), PATH, ".l2_config.chunk_proposer_config.max_block_num_per_chunk");
        vm.writeJson(vm.toString(MAX_TX_IN_CHUNK), PATH, ".l2_config.chunk_proposer_config.max_tx_num_per_chunk");
        vm.writeJson(vm.toString(MAX_BATCH_IN_BUNDLE), PATH, ".l2_config.bundle_proposer_config.max_batch_num_per_bundle");
    }
}

contract GenerateCoordinatorConfig is DeployScroll {
    /***************
     * Entry point *
     ***************/

    function run(string memory workdir) public {
        DeterministicDeployment.initialize(ScriptMode.VerifyConfig, workdir);
        predictAllContracts();

        generateCoordinatorConfig(COORDINATOR_API_CONFIG_PATH);
        generateCoordinatorConfig(COORDINATOR_CRON_CONFIG_PATH);
    }

    /*********************
     * Private functions *
     *********************/

    function generateCoordinatorConfig(string memory PATH) private {
        // initialize template file
        if (vm.exists(PATH)) {
            vm.removeFile(PATH);
        }

        string memory template = vm.readFile(COORDINATOR_CONFIG_TEMPLATE_PATH);
        vm.writeFile(PATH, template);

        // coordinator api
        vm.writeJson(CHUNK_COLLECTION_TIME_SEC, PATH, ".prover_manager.chunk_collection_time_sec");
        vm.writeJson(BATCH_COLLECTION_TIME_SEC, PATH, ".prover_manager.batch_collection_time_sec");
        vm.writeJson(BUNDLE_COLLECTION_TIME_SEC, PATH, ".prover_manager.bundle_collection_time_sec");
        vm.writeJson(vm.toString(CHAIN_ID_L2), PATH, ".l2.chain_id");
        vm.writeJson(COORDINATOR_JWT_SECRET_KEY, PATH, ".auth.secret");

        // coordinator cron
        vm.writeJson(CHUNK_COLLECTION_TIME_SEC, PATH, ".prover_manager.chunk_collection_time_sec");
        vm.writeJson(BATCH_COLLECTION_TIME_SEC, PATH, ".prover_manager.batch_collection_time_sec");
        vm.writeJson(BUNDLE_COLLECTION_TIME_SEC, PATH, ".prover_manager.bundle_collection_time_sec");
        vm.writeJson(vm.toString(CHAIN_ID_L2), PATH, ".l2.chain_id");
        vm.writeJson(COORDINATOR_JWT_SECRET_KEY, PATH, ".auth.secret");
    }
}

contract GenerateChainMonitorConfig is DeployScroll {
    /***************
     * Entry point *
     ***************/

    function run(string memory workdir) public {
        DeterministicDeployment.initialize(ScriptMode.VerifyConfig, workdir);
        predictAllContracts();

        generateChainMonitorConfig(CHAIN_MONITOR_CONFIG_PATH);
    }

    /*********************
     * Private functions *
     *********************/

    // prettier-ignore
    function generateChainMonitorConfig(string memory PATH) private {
        // initialize template file
        if (vm.exists(PATH)) {
            vm.removeFile(PATH);
        }

        string memory template = vm.readFile(CHAIN_MONITOR_CONFIG_TEMPLATE_PATH);
        vm.writeFile(PATH, template);

        // L1
        vm.writeJson(L1_RPC_ENDPOINT, PATH, ".l1_config.l1_url");
        vm.writeJson(vm.toString(L1_CONTRACT_DEPLOYMENT_BLOCK), PATH, ".l1_config.start_number");
        vm.writeJson(vm.toString(L1_ETH_GATEWAY_PROXY_ADDR), PATH, ".l1_config.l1_contracts.l1_gateways.eth_gateway");
        vm.writeJson(vm.toString(L1_WETH_GATEWAY_PROXY_ADDR), PATH, ".l1_config.l1_contracts.l1_gateways.weth_gateway");
        vm.writeJson(vm.toString(L1_STANDARD_ERC20_GATEWAY_PROXY_ADDR), PATH, ".l1_config.l1_contracts.l1_gateways.standard_erc20_gateway");
        vm.writeJson(vm.toString(L1_CUSTOM_ERC20_GATEWAY_PROXY_ADDR), PATH, ".l1_config.l1_contracts.l1_gateways.custom_erc20_gateway");
        vm.writeJson(vm.toString(L1_ERC721_GATEWAY_PROXY_ADDR), PATH, ".l1_config.l1_contracts.l1_gateways.erc721_gateway");
        vm.writeJson(vm.toString(L1_ERC1155_GATEWAY_PROXY_ADDR), PATH, ".l1_config.l1_contracts.l1_gateways.erc1155_gateway");
        vm.writeJson(vm.toString(L1_SCROLL_MESSENGER_PROXY_ADDR), PATH, ".l1_config.l1_contracts.scroll_messenger");
        vm.writeJson(vm.toString(L1_MESSAGE_QUEUE_V2_PROXY_ADDR), PATH, ".l1_config.l1_contracts.message_queue");
        vm.writeJson(vm.toString(L1_SCROLL_CHAIN_PROXY_ADDR), PATH, ".l1_config.l1_contracts.scroll_chain");
        vm.writeJson(vm.toString(L2_DEPLOYER_INITIAL_BALANCE), PATH, ".l1_config.start_messenger_balance");

        // L2
        vm.writeJson(L2_RPC_ENDPOINT, PATH, ".l2_config.l2_url");
        vm.writeJson(vm.toString(L2_ETH_GATEWAY_PROXY_ADDR), PATH, ".l2_config.l2_contracts.l2_gateways.eth_gateway");
        vm.writeJson(vm.toString(L2_WETH_GATEWAY_PROXY_ADDR), PATH, ".l2_config.l2_contracts.l2_gateways.weth_gateway");
        vm.writeJson(vm.toString(L2_STANDARD_ERC20_GATEWAY_PROXY_ADDR), PATH, ".l2_config.l2_contracts.l2_gateways.standard_erc20_gateway");
        vm.writeJson(vm.toString(L2_CUSTOM_ERC20_GATEWAY_PROXY_ADDR), PATH, ".l2_config.l2_contracts.l2_gateways.custom_erc20_gateway");
        vm.writeJson(vm.toString(L2_ERC721_GATEWAY_PROXY_ADDR), PATH, ".l2_config.l2_contracts.l2_gateways.erc721_gateway");
        vm.writeJson(vm.toString(L2_ERC1155_GATEWAY_PROXY_ADDR), PATH, ".l2_config.l2_contracts.l2_gateways.erc1155_gateway");
        vm.writeJson(vm.toString(L2_SCROLL_MESSENGER_PROXY_ADDR), PATH, ".l2_config.l2_contracts.scroll_messenger");
        vm.writeJson(vm.toString(L2_MESSAGE_QUEUE_ADDR), PATH, ".l2_config.l2_contracts.message_queue");
    }
}

contract GenerateBridgeHistoryConfig is DeployScroll {
    /***************
     * Entry point *
     ***************/

    function run(string memory workdir) public {
        DeterministicDeployment.initialize(ScriptMode.VerifyConfig, workdir);
        predictAllContracts();

        generateBridgeHistoryConfig(BRIDGE_HISTORY_API_CONFIG_PATH);
        generateBridgeHistoryConfig(BRIDGE_HISTORY_FETCHER_CONFIG_PATH);
    }

    /*********************
     * Private functions *
     *********************/

    // prettier-ignore
    function generateBridgeHistoryConfig(string memory PATH) private {
        // initialize template file
        if (vm.exists(PATH)) {
            vm.removeFile(PATH);
        }

        string memory template = vm.readFile(BRIDGE_HISTORY_CONFIG_TEMPLATE_PATH);
        vm.writeFile(PATH, template);

        // L1 contracts
        vm.writeJson(vm.toString(L1_MESSAGE_QUEUE_V2_PROXY_ADDR), PATH, ".L1.MessageQueueAddr");
        vm.writeJson(vm.toString(L1_SCROLL_MESSENGER_PROXY_ADDR), PATH, ".L1.MessengerAddr");
        vm.writeJson(vm.toString(L1_SCROLL_CHAIN_PROXY_ADDR), PATH, ".L1.ScrollChainAddr");
        vm.writeJson(vm.toString(L1_GATEWAY_ROUTER_PROXY_ADDR), PATH, ".L1.GatewayRouterAddr");
        vm.writeJson(vm.toString(L1_ETH_GATEWAY_PROXY_ADDR), PATH, ".L1.ETHGatewayAddr");
        vm.writeJson(vm.toString(L1_WETH_GATEWAY_PROXY_ADDR), PATH, ".L1.WETHGatewayAddr");
        vm.writeJson(vm.toString(L1_STANDARD_ERC20_GATEWAY_PROXY_ADDR), PATH, ".L1.StandardERC20GatewayAddr");
        vm.writeJson(vm.toString(L1_CUSTOM_ERC20_GATEWAY_PROXY_ADDR), PATH, ".L1.CustomERC20GatewayAddr");
        vm.writeJson(vm.toString(L1_ERC721_GATEWAY_PROXY_ADDR), PATH, ".L1.ERC721GatewayAddr");
        vm.writeJson(vm.toString(L1_ERC1155_GATEWAY_PROXY_ADDR), PATH, ".L1.ERC1155GatewayAddr");
        vm.writeJson(vm.toString(L1_WRAPPED_TOKEN_GATEWAY_ADDR), PATH, ".L1.WrappedTokenGatewayAddr");

        // L2 contracts
        vm.writeJson(vm.toString(L2_MESSAGE_QUEUE_ADDR), PATH, ".L2.MessageQueueAddr");
        vm.writeJson(vm.toString(L2_SCROLL_MESSENGER_PROXY_ADDR), PATH, ".L2.MessengerAddr");
        vm.writeJson(vm.toString(L2_GATEWAY_ROUTER_PROXY_ADDR), PATH, ".L2.GatewayRouterAddr");
        vm.writeJson(vm.toString(L2_ETH_GATEWAY_PROXY_ADDR), PATH, ".L2.ETHGatewayAddr");
        vm.writeJson(vm.toString(L2_WETH_GATEWAY_PROXY_ADDR), PATH, ".L2.WETHGatewayAddr");
        vm.writeJson(vm.toString(L2_STANDARD_ERC20_GATEWAY_PROXY_ADDR), PATH, ".L2.StandardERC20GatewayAddr");
        vm.writeJson(vm.toString(L2_CUSTOM_ERC20_GATEWAY_PROXY_ADDR), PATH, ".L2.CustomERC20GatewayAddr");
        vm.writeJson(vm.toString(L2_ERC721_GATEWAY_PROXY_ADDR), PATH, ".L2.ERC721GatewayAddr");
        vm.writeJson(vm.toString(L2_ERC1155_GATEWAY_PROXY_ADDR), PATH, ".L2.ERC1155GatewayAddr");

        // others
        vm.writeJson(vm.toString(L1_CONTRACT_DEPLOYMENT_BLOCK), PATH, ".L1.startHeight");
    }
}

contract GenerateBalanceCheckerConfig is DeployScroll {
    /***************
     * Entry point *
     ***************/

    function run(string memory workdir) public {
        DeterministicDeployment.initialize(ScriptMode.VerifyConfig, workdir);
        predictAllContracts();

        generateBalanceCheckerConfig(BALANCE_CHECKER_CONFIG_PATH);
    }

    /*********************
     * Private functions *
     *********************/

    function generateBalanceCheckerConfig(string memory PATH) private {
        // initialize template file
        if (vm.exists(PATH)) {
            vm.removeFile(PATH);
        }

        string memory template = vm.readFile(BALANCE_CHECKER_CONFIG_TEMPLATE_PATH);
        vm.writeFile(PATH, template);

        vm.writeJson(vm.toString(L1_COMMIT_SENDER_ADDR), PATH, ".addresses[0].address");
        vm.writeJson(vm.toString(L1_FINALIZE_SENDER_ADDR), PATH, ".addresses[1].address");
        vm.writeJson(vm.toString(L1_GAS_ORACLE_SENDER_ADDR), PATH, ".addresses[2].address");
        vm.writeJson(vm.toString(L1_FEE_VAULT_ADDR), PATH, ".addresses[3].address");
        vm.writeJson(vm.toString(L2_GAS_ORACLE_SENDER_ADDR), PATH, ".addresses[4].address");
        vm.writeJson(vm.toString(L2_TX_FEE_VAULT_ADDR), PATH, ".addresses[5].address");
    }
}
