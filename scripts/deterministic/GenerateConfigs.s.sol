// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.24;

import {stdToml} from "forge-std/StdToml.sol";

import {ADMIN_SYSTEM_BACKEND_CONFIG_PATH, ADMIN_SYSTEM_BACKEND_CONFIG_TEMPLATE_PATH, BALANCE_CHECKER_CONFIG_PATH, BALANCE_CHECKER_CONFIG_TEMPLATE_PATH, BRIDGE_HISTORY_CONFIG_PATH, BRIDGE_HISTORY_CONFIG_TEMPLATE_PATH, CHAIN_MONITOR_CONFIG_PATH, CHAIN_MONITOR_CONFIG_TEMPLATE_PATH, CONFIG_PATH, COORDINATOR_CONFIG_PATH, COORDINATOR_CONFIG_TEMPLATE_PATH, FRONTEND_ENV_PATH, ROLLUP_CONFIG_PATH, ROLLUP_CONFIG_TEMPLATE_PATH, ROLLUP_EXPLORER_BACKEND_CONFIG_PATH, ROLLUP_EXPLORER_BACKEND_CONFIG_TEMPLATE_PATH} from "./Constants.sol";
import {DeployScroll} from "./DeployScroll.s.sol";
import {DeterministicDeployment} from "./DeterministicDeployment.sol";

contract GenerateRollupConfig is DeployScroll {
    using stdToml for string;

    /***************
     * Entry point *
     ***************/

    function run() public {
        DeterministicDeployment.initialize(ScriptMode.VerifyConfig);
        predictAllContracts();

        generateRollupConfig();
    }

    /*********************
     * Private functions *
     *********************/

    // prettier-ignore
    function generateRollupConfig() private {
        // initialize template file
        if (vm.exists(ROLLUP_CONFIG_PATH)) {
            vm.removeFile(ROLLUP_CONFIG_PATH);
        }

        string memory template = vm.readFile(ROLLUP_CONFIG_TEMPLATE_PATH);
        vm.writeFile(ROLLUP_CONFIG_PATH, template);

        // endpoints
        vm.writeJson(L1_RPC_ENDPOINT, ROLLUP_CONFIG_PATH, ".l1_config.endpoint");
        vm.writeJson(L2_RPC_ENDPOINT, ROLLUP_CONFIG_PATH, ".l1_config.relayer_config.sender_config.endpoint");
        vm.writeJson(L2_RPC_ENDPOINT, ROLLUP_CONFIG_PATH, ".l2_config.endpoint");
        vm.writeJson(L1_RPC_ENDPOINT, ROLLUP_CONFIG_PATH, ".l2_config.relayer_config.sender_config.endpoint");

        // contracts
        vm.writeJson(vm.toString(L1_GAS_PRICE_ORACLE_ADDR), ROLLUP_CONFIG_PATH, ".l1_config.relayer_config.gas_price_oracle_contract_address");
        vm.writeJson(vm.toString(L2_MESSAGE_QUEUE_ADDR), ROLLUP_CONFIG_PATH, ".l2_config.l2_message_queue_address");
        vm.writeJson(vm.toString(L1_SCROLL_CHAIN_PROXY_ADDR), ROLLUP_CONFIG_PATH, ".l2_config.relayer_config.rollup_contract_address");
        vm.writeJson(vm.toString(L1_MESSAGE_QUEUE_PROXY_ADDR), ROLLUP_CONFIG_PATH, ".l2_config.relayer_config.gas_price_oracle_contract_address");

        // other
        vm.writeJson(vm.toString(TEST_ENV_MOCK_FINALIZE_ENABLED), ROLLUP_CONFIG_PATH, ".l2_config.relayer_config.enable_test_env_bypass_features");
        vm.writeJson(vm.toString(TEST_ENV_MOCK_FINALIZE_TIMEOUT_SEC), ROLLUP_CONFIG_PATH, ".l2_config.relayer_config.finalize_batch_without_proof_timeout_sec");
        vm.writeJson(vm.toString(TEST_ENV_MOCK_FINALIZE_TIMEOUT_SEC), ROLLUP_CONFIG_PATH, ".l2_config.relayer_config.finalize_bundle_without_proof_timeout_sec");

        vm.writeJson(vm.toString(MAX_BLOCK_IN_CHUNK), ROLLUP_CONFIG_PATH, ".l2_config.chunk_proposer_config.max_block_num_per_chunk");
        vm.writeJson(vm.toString(MAX_TX_IN_CHUNK), ROLLUP_CONFIG_PATH, ".l2_config.chunk_proposer_config.max_tx_num_per_chunk");
        vm.writeJson(vm.toString(MAX_BATCH_IN_BUNDLE), ROLLUP_CONFIG_PATH, ".l2_config.bundle_proposer_config.max_batch_num_per_bundle");

        // alternative gas token configuration for gas oracle 
        if (ALTERNATIVE_GAS_TOKEN_ENABLED) {
            bool GAS_ORACLE_INCORPORATE_TOKEN_EXCHANGE_RATE_ENANBLED;
            if (vm.keyExistsToml(cfg, ".gas-token.GAS_ORACLE_INCORPORATE_TOKEN_EXCHANGE_RATE_ENANBLED")) {
                GAS_ORACLE_INCORPORATE_TOKEN_EXCHANGE_RATE_ENANBLED = cfg.readBool(".gas-token.GAS_ORACLE_INCORPORATE_TOKEN_EXCHANGE_RATE_ENANBLED");
                vm.writeJson(vm.toString(GAS_ORACLE_INCORPORATE_TOKEN_EXCHANGE_RATE_ENANBLED), ROLLUP_CONFIG_PATH, ".l1_config.relayer_config.gas_oracle_config.alternative_gas_token_config.enabled");
                vm.writeJson(vm.toString(GAS_ORACLE_INCORPORATE_TOKEN_EXCHANGE_RATE_ENANBLED), ROLLUP_CONFIG_PATH, ".l2_config.relayer_config.gas_oracle_config.alternative_gas_token_config.enabled");
            }
            if (GAS_ORACLE_INCORPORATE_TOKEN_EXCHANGE_RATE_ENANBLED) {
                string memory EXCHANGE_RATE_UPDATE_MODE = cfg.readString(".gas-token.EXCHANGE_RATE_UPDATE_MODE");
                vm.writeJson(EXCHANGE_RATE_UPDATE_MODE, ROLLUP_CONFIG_PATH, ".l1_config.relayer_config.gas_oracle_config.alternative_gas_token_config.mode");
                vm.writeJson(EXCHANGE_RATE_UPDATE_MODE, ROLLUP_CONFIG_PATH, ".l2_config.relayer_config.gas_oracle_config.alternative_gas_token_config.mode");
                if (keccak256(abi.encodePacked(EXCHANGE_RATE_UPDATE_MODE)) == keccak256("Fixed")) {
                    string memory FIXED_EXCHANGE_RATE = cfg.readString(".gas-token.FIXED_EXCHANGE_RATE");
                    vm.writeJson(FIXED_EXCHANGE_RATE, ROLLUP_CONFIG_PATH, ".l1_config.relayer_config.gas_oracle_config.alternative_gas_token_config.fixed_exchange_rate");
                    vm.writeJson(FIXED_EXCHANGE_RATE, ROLLUP_CONFIG_PATH, ".l2_config.relayer_config.gas_oracle_config.alternative_gas_token_config.fixed_exchange_rate");
                } else if (keccak256(abi.encodePacked(EXCHANGE_RATE_UPDATE_MODE)) == keccak256("BinanceApi")) {
                    string memory TOKEN_SYMBOL_PAIR = cfg.readString(".gas-token.TOKEN_SYMBOL_PAIR");
                    vm.writeJson(TOKEN_SYMBOL_PAIR, ROLLUP_CONFIG_PATH, ".l1_config.relayer_config.gas_oracle_config.alternative_gas_token_config.token_symbol_pair");
                    vm.writeJson(TOKEN_SYMBOL_PAIR, ROLLUP_CONFIG_PATH, ".l2_config.relayer_config.gas_oracle_config.alternative_gas_token_config.token_symbol_pair");
                } else {
                    revert(
                        string(
                            abi.encodePacked(
                                "[ERROR] unsupported exchange rate update mode for gas oracle, mode: ",
                                EXCHANGE_RATE_UPDATE_MODE
                            )
                        )
                    );
                }
            }
        }
    }
}

contract GenerateCoordinatorConfig is DeployScroll {
    /***************
     * Entry point *
     ***************/

    function run() public {
        DeterministicDeployment.initialize(ScriptMode.VerifyConfig);
        predictAllContracts();

        generateCoordinatorConfig();
    }

    /*********************
     * Private functions *
     *********************/

    function generateCoordinatorConfig() private {
        // initialize template file
        if (vm.exists(COORDINATOR_CONFIG_PATH)) {
            vm.removeFile(COORDINATOR_CONFIG_PATH);
        }

        string memory template = vm.readFile(COORDINATOR_CONFIG_TEMPLATE_PATH);
        vm.writeFile(COORDINATOR_CONFIG_PATH, template);

        vm.writeJson(CHUNK_COLLECTION_TIME_SEC, COORDINATOR_CONFIG_PATH, ".prover_manager.chunk_collection_time_sec");
        vm.writeJson(BATCH_COLLECTION_TIME_SEC, COORDINATOR_CONFIG_PATH, ".prover_manager.batch_collection_time_sec");
        vm.writeJson(BUNDLE_COLLECTION_TIME_SEC, COORDINATOR_CONFIG_PATH, ".prover_manager.bundle_collection_time_sec");

        vm.writeJson(vm.toString(CHAIN_ID_L2), COORDINATOR_CONFIG_PATH, ".l2.chain_id");
        vm.writeJson(COORDINATOR_JWT_SECRET_KEY, COORDINATOR_CONFIG_PATH, ".auth.secret");
    }
}

contract GenerateChainMonitorConfig is DeployScroll {
    /***************
     * Entry point *
     ***************/

    function run() public {
        DeterministicDeployment.initialize(ScriptMode.VerifyConfig);
        predictAllContracts();

        generateChainMonitorConfig();
    }

    /*********************
     * Private functions *
     *********************/

    // prettier-ignore
    function generateChainMonitorConfig() private {
        // initialize template file
        if (vm.exists(CHAIN_MONITOR_CONFIG_PATH)) {
            vm.removeFile(CHAIN_MONITOR_CONFIG_PATH);
        }

        string memory template = vm.readFile(CHAIN_MONITOR_CONFIG_TEMPLATE_PATH);
        vm.writeFile(CHAIN_MONITOR_CONFIG_PATH, template);

        // L1
        vm.writeJson(L1_RPC_ENDPOINT, CHAIN_MONITOR_CONFIG_PATH, ".l1_config.l1_url");
        vm.writeJson(vm.toString(L1_CONTRACT_DEPLOYMENT_BLOCK), CHAIN_MONITOR_CONFIG_PATH, ".l1_config.start_number");
        vm.writeJson(vm.toString(L1_ETH_GATEWAY_PROXY_ADDR), CHAIN_MONITOR_CONFIG_PATH, ".l1_config.l1_contracts.l1_gateways.eth_gateway");
        vm.writeJson(vm.toString(L1_WETH_GATEWAY_PROXY_ADDR), CHAIN_MONITOR_CONFIG_PATH, ".l1_config.l1_contracts.l1_gateways.weth_gateway");
        vm.writeJson(vm.toString(L1_STANDARD_ERC20_GATEWAY_PROXY_ADDR), CHAIN_MONITOR_CONFIG_PATH, ".l1_config.l1_contracts.l1_gateways.standard_erc20_gateway");
        vm.writeJson(vm.toString(L1_CUSTOM_ERC20_GATEWAY_PROXY_ADDR), CHAIN_MONITOR_CONFIG_PATH, ".l1_config.l1_contracts.l1_gateways.custom_erc20_gateway");
        vm.writeJson(vm.toString(L1_ERC721_GATEWAY_PROXY_ADDR), CHAIN_MONITOR_CONFIG_PATH, ".l1_config.l1_contracts.l1_gateways.erc721_gateway");
        vm.writeJson(vm.toString(L1_ERC1155_GATEWAY_PROXY_ADDR), CHAIN_MONITOR_CONFIG_PATH, ".l1_config.l1_contracts.l1_gateways.erc1155_gateway");
        vm.writeJson(vm.toString(L1_GAS_TOKEN_GATEWAY_PROXY_ADDR), CHAIN_MONITOR_CONFIG_PATH, ".l1_config.l1_contracts.l1_gateways.gas_token_gateway");
        vm.writeJson(vm.toString(L1_SCROLL_MESSENGER_PROXY_ADDR), CHAIN_MONITOR_CONFIG_PATH, ".l1_config.l1_contracts.scroll_messenger");
        vm.writeJson(vm.toString(L1_MESSAGE_QUEUE_PROXY_ADDR), CHAIN_MONITOR_CONFIG_PATH, ".l1_config.l1_contracts.message_queue");
        vm.writeJson(vm.toString(L1_SCROLL_CHAIN_PROXY_ADDR), CHAIN_MONITOR_CONFIG_PATH, ".l1_config.l1_contracts.scroll_chain");
        vm.writeJson(vm.toString(L1_GAS_TOKEN_ADDR), CHAIN_MONITOR_CONFIG_PATH, ".l1_config.l1_contracts.gas_token");
        vm.writeJson(vm.toString(L2_DEPLOYER_INITIAL_BALANCE), CHAIN_MONITOR_CONFIG_PATH, ".l1_config.start_messenger_balance");

        // L2
        vm.writeJson(L2_RPC_ENDPOINT, CHAIN_MONITOR_CONFIG_PATH, ".l2_config.l2_url");
        vm.writeJson(vm.toString(L2_ETH_GATEWAY_PROXY_ADDR), CHAIN_MONITOR_CONFIG_PATH, ".l2_config.l2_contracts.l2_gateways.eth_gateway");
        vm.writeJson(vm.toString(L2_WETH_GATEWAY_PROXY_ADDR), CHAIN_MONITOR_CONFIG_PATH, ".l2_config.l2_contracts.l2_gateways.weth_gateway");
        vm.writeJson(vm.toString(L2_STANDARD_ERC20_GATEWAY_PROXY_ADDR), CHAIN_MONITOR_CONFIG_PATH, ".l2_config.l2_contracts.l2_gateways.standard_erc20_gateway");
        vm.writeJson(vm.toString(L2_CUSTOM_ERC20_GATEWAY_PROXY_ADDR), CHAIN_MONITOR_CONFIG_PATH, ".l2_config.l2_contracts.l2_gateways.custom_erc20_gateway");
        vm.writeJson(vm.toString(L2_ERC721_GATEWAY_PROXY_ADDR), CHAIN_MONITOR_CONFIG_PATH, ".l2_config.l2_contracts.l2_gateways.erc721_gateway");
        vm.writeJson(vm.toString(L2_ERC1155_GATEWAY_PROXY_ADDR), CHAIN_MONITOR_CONFIG_PATH, ".l2_config.l2_contracts.l2_gateways.erc1155_gateway");
        vm.writeJson(vm.toString(L2_SCROLL_MESSENGER_PROXY_ADDR), CHAIN_MONITOR_CONFIG_PATH, ".l2_config.l2_contracts.scroll_messenger");
        vm.writeJson(vm.toString(L2_MESSAGE_QUEUE_ADDR), CHAIN_MONITOR_CONFIG_PATH, ".l2_config.l2_contracts.message_queue");
    }
}

contract GenerateBridgeHistoryConfig is DeployScroll {
    /***************
     * Entry point *
     ***************/

    function run() public {
        DeterministicDeployment.initialize(ScriptMode.VerifyConfig);
        predictAllContracts();

        generateBridgeHistoryConfig();
    }

    /*********************
     * Private functions *
     *********************/

    // prettier-ignore
    function generateBridgeHistoryConfig() private {
        // initialize template file
        if (vm.exists(BRIDGE_HISTORY_CONFIG_PATH)) {
            vm.removeFile(BRIDGE_HISTORY_CONFIG_PATH);
        }

        string memory template = vm.readFile(BRIDGE_HISTORY_CONFIG_TEMPLATE_PATH);
        vm.writeFile(BRIDGE_HISTORY_CONFIG_PATH, template);

        // L1 contracts
        vm.writeJson(vm.toString(L1_MESSAGE_QUEUE_PROXY_ADDR), BRIDGE_HISTORY_CONFIG_PATH, ".L1.MessageQueueAddr");
        vm.writeJson(vm.toString(L1_SCROLL_MESSENGER_PROXY_ADDR), BRIDGE_HISTORY_CONFIG_PATH, ".L1.MessengerAddr");
        vm.writeJson(vm.toString(L1_SCROLL_CHAIN_PROXY_ADDR), BRIDGE_HISTORY_CONFIG_PATH, ".L1.ScrollChainAddr");
        vm.writeJson(vm.toString(L1_GATEWAY_ROUTER_PROXY_ADDR), BRIDGE_HISTORY_CONFIG_PATH, ".L1.GatewayRouterAddr");
        vm.writeJson(vm.toString(L1_ETH_GATEWAY_PROXY_ADDR), BRIDGE_HISTORY_CONFIG_PATH, ".L1.ETHGatewayAddr");
        vm.writeJson(vm.toString(L1_WETH_GATEWAY_PROXY_ADDR), BRIDGE_HISTORY_CONFIG_PATH, ".L1.WETHGatewayAddr");
        vm.writeJson(vm.toString(L1_STANDARD_ERC20_GATEWAY_PROXY_ADDR), BRIDGE_HISTORY_CONFIG_PATH, ".L1.StandardERC20GatewayAddr");
        vm.writeJson(vm.toString(L1_CUSTOM_ERC20_GATEWAY_PROXY_ADDR), BRIDGE_HISTORY_CONFIG_PATH, ".L1.CustomERC20GatewayAddr");
        vm.writeJson(vm.toString(L1_ERC721_GATEWAY_PROXY_ADDR), BRIDGE_HISTORY_CONFIG_PATH, ".L1.ERC721GatewayAddr");
        vm.writeJson(vm.toString(L1_ERC1155_GATEWAY_PROXY_ADDR), BRIDGE_HISTORY_CONFIG_PATH, ".L1.ERC1155GatewayAddr");
        vm.writeJson(vm.toString(L1_GAS_TOKEN_GATEWAY_PROXY_ADDR), BRIDGE_HISTORY_CONFIG_PATH, ".L1.GasTokenGatewayAddr");
        vm.writeJson(vm.toString(L1_WRAPPED_TOKEN_GATEWAY_ADDR), BRIDGE_HISTORY_CONFIG_PATH, ".L1.WrappedTokenGatewayAddr");

        // L2 contracts
        vm.writeJson(vm.toString(L2_MESSAGE_QUEUE_ADDR), BRIDGE_HISTORY_CONFIG_PATH, ".L2.MessageQueueAddr");
        vm.writeJson(vm.toString(L2_SCROLL_MESSENGER_PROXY_ADDR), BRIDGE_HISTORY_CONFIG_PATH, ".L2.MessengerAddr");
        vm.writeJson(vm.toString(L2_GATEWAY_ROUTER_PROXY_ADDR), BRIDGE_HISTORY_CONFIG_PATH, ".L2.GatewayRouterAddr");
        vm.writeJson(vm.toString(L2_ETH_GATEWAY_PROXY_ADDR), BRIDGE_HISTORY_CONFIG_PATH, ".L2.ETHGatewayAddr");
        vm.writeJson(vm.toString(L2_WETH_GATEWAY_PROXY_ADDR), BRIDGE_HISTORY_CONFIG_PATH, ".L2.WETHGatewayAddr");
        vm.writeJson(vm.toString(L2_STANDARD_ERC20_GATEWAY_PROXY_ADDR), BRIDGE_HISTORY_CONFIG_PATH, ".L2.StandardERC20GatewayAddr");
        vm.writeJson(vm.toString(L2_CUSTOM_ERC20_GATEWAY_PROXY_ADDR), BRIDGE_HISTORY_CONFIG_PATH, ".L2.CustomERC20GatewayAddr");
        vm.writeJson(vm.toString(L2_ERC721_GATEWAY_PROXY_ADDR), BRIDGE_HISTORY_CONFIG_PATH, ".L2.ERC721GatewayAddr");
        vm.writeJson(vm.toString(L2_ERC1155_GATEWAY_PROXY_ADDR), BRIDGE_HISTORY_CONFIG_PATH, ".L2.ERC1155GatewayAddr");

        // endpoints
        vm.writeJson(L1_RPC_ENDPOINT, BRIDGE_HISTORY_CONFIG_PATH, ".L1.endpoint");
        vm.writeJson(L2_RPC_ENDPOINT, BRIDGE_HISTORY_CONFIG_PATH, ".L2.endpoint");

        // others
        vm.writeJson(vm.toString(L1_CONTRACT_DEPLOYMENT_BLOCK), BRIDGE_HISTORY_CONFIG_PATH, ".L1.startHeight");
    }
}

contract GenerateBalanceCheckerConfig is DeployScroll {
    /***************
     * Entry point *
     ***************/

    function run() public {
        DeterministicDeployment.initialize(ScriptMode.VerifyConfig);
        predictAllContracts();

        generateBalanceCheckerConfig();
    }

    /*********************
     * Private functions *
     *********************/

    function generateBalanceCheckerConfig() private {
        // initialize template file
        if (vm.exists(BALANCE_CHECKER_CONFIG_PATH)) {
            vm.removeFile(BALANCE_CHECKER_CONFIG_PATH);
        }

        string memory template = vm.readFile(BALANCE_CHECKER_CONFIG_TEMPLATE_PATH);
        vm.writeFile(BALANCE_CHECKER_CONFIG_PATH, template);

        vm.writeJson(L1_RPC_ENDPOINT, BALANCE_CHECKER_CONFIG_PATH, ".addresses[0].rpc_url");
        vm.writeJson(vm.toString(L1_COMMIT_SENDER_ADDR), BALANCE_CHECKER_CONFIG_PATH, ".addresses[0].address");

        vm.writeJson(L1_RPC_ENDPOINT, BALANCE_CHECKER_CONFIG_PATH, ".addresses[1].rpc_url");
        vm.writeJson(vm.toString(L1_FINALIZE_SENDER_ADDR), BALANCE_CHECKER_CONFIG_PATH, ".addresses[1].address");

        vm.writeJson(L1_RPC_ENDPOINT, BALANCE_CHECKER_CONFIG_PATH, ".addresses[2].rpc_url");
        vm.writeJson(vm.toString(L1_GAS_ORACLE_SENDER_ADDR), BALANCE_CHECKER_CONFIG_PATH, ".addresses[2].address");

        vm.writeJson(L1_RPC_ENDPOINT, BALANCE_CHECKER_CONFIG_PATH, ".addresses[3].rpc_url");
        vm.writeJson(vm.toString(L1_FEE_VAULT_ADDR), BALANCE_CHECKER_CONFIG_PATH, ".addresses[3].address");

        vm.writeJson(L2_RPC_ENDPOINT, BALANCE_CHECKER_CONFIG_PATH, ".addresses[4].rpc_url");
        vm.writeJson(vm.toString(L2_GAS_ORACLE_SENDER_ADDR), BALANCE_CHECKER_CONFIG_PATH, ".addresses[4].address");

        vm.writeJson(L2_RPC_ENDPOINT, BALANCE_CHECKER_CONFIG_PATH, ".addresses[5].rpc_url");
        vm.writeJson(vm.toString(L2_TX_FEE_VAULT_ADDR), BALANCE_CHECKER_CONFIG_PATH, ".addresses[5].address");
    }
}

contract GenerateFrontendConfig is DeployScroll {
    /***************
     * Entry point *
     ***************/

    function run() public {
        DeterministicDeployment.initialize(ScriptMode.VerifyConfig);
        predictAllContracts();

        generateFrontendConfig();
    }

    /*********************
     * Private functions *
     *********************/

    // prettier-ignore
    function generateFrontendConfig() private {
        // use writeFile to start a new file
        vm.writeFile(FRONTEND_ENV_PATH, "REACT_APP_ETH_SYMBOL = \"ETH\"\n");
        vm.writeLine(FRONTEND_ENV_PATH, string.concat("REACT_APP_BASE_CHAIN = \"", CHAIN_NAME_L1, "\""));
        vm.writeLine(FRONTEND_ENV_PATH, string.concat("REACT_APP_ROLLUP = \"", CHAIN_NAME_L2, "\""));
        vm.writeLine(FRONTEND_ENV_PATH, string.concat("REACT_APP_CHAIN_ID_L1 = \"", vm.toString(CHAIN_ID_L1), "\""));
        vm.writeLine(FRONTEND_ENV_PATH, string.concat("REACT_APP_CHAIN_ID_L2 = \"", vm.toString(CHAIN_ID_L2), "\""));
        vm.writeLine(FRONTEND_ENV_PATH, "REACT_APP_CONNECT_WALLET_PROJECT_ID = \"14efbaafcf5232a47d93a68229b71028\"");

        // API endpoints
        vm.writeLine(FRONTEND_ENV_PATH, "");
        vm.writeLine(FRONTEND_ENV_PATH, string.concat("REACT_APP_EXTERNAL_RPC_URI_L1 = \"", EXTERNAL_RPC_URI_L1, "\""));
        vm.writeLine(FRONTEND_ENV_PATH, string.concat("REACT_APP_EXTERNAL_RPC_URI_L2 = \"", EXTERNAL_RPC_URI_L2, "\""));
        vm.writeLine(FRONTEND_ENV_PATH, string.concat("REACT_APP_BRIDGE_API_URI = \"", BRIDGE_API_URI, "\""));
        vm.writeLine(FRONTEND_ENV_PATH, string.concat("REACT_APP_ROLLUPSCAN_API_URI = \"", ROLLUPSCAN_API_URI, "\""));
        vm.writeLine(FRONTEND_ENV_PATH, string.concat("REACT_APP_EXTERNAL_EXPLORER_URI_L1 = \"", EXTERNAL_EXPLORER_URI_L1, "\""));
        vm.writeLine(FRONTEND_ENV_PATH, string.concat("REACT_APP_EXTERNAL_EXPLORER_URI_L2 = \"", EXTERNAL_EXPLORER_URI_L2, "\""));
        vm.writeLine(FRONTEND_ENV_PATH, string.concat("ADMIN_SYSTEM_DASHBOARD_URI = \"", ADMIN_SYSTEM_DASHBOARD_URI, "\""));
        vm.writeLine(FRONTEND_ENV_PATH, string.concat("GRAFANA_URI = \"", GRAFANA_URI, "\""));

        // L1 contracts
        vm.writeLine(FRONTEND_ENV_PATH, "");
        vm.writeLine(FRONTEND_ENV_PATH, string.concat("REACT_APP_L1_CUSTOM_ERC20_GATEWAY_PROXY_ADDR = \"", vm.toString(L1_CUSTOM_ERC20_GATEWAY_PROXY_ADDR), "\""));
        vm.writeLine(FRONTEND_ENV_PATH, string.concat("REACT_APP_L1_ETH_GATEWAY_PROXY_ADDR = \"", vm.toString(L1_ETH_GATEWAY_PROXY_ADDR), "\""));
        vm.writeLine(FRONTEND_ENV_PATH, string.concat("REACT_APP_L1_GAS_PRICE_ORACLE = \"", vm.toString(L1_GAS_PRICE_ORACLE_ADDR), "\""));
        vm.writeLine(FRONTEND_ENV_PATH, string.concat("REACT_APP_L1_GATEWAY_ROUTER_PROXY_ADDR = \"", vm.toString(L1_GATEWAY_ROUTER_PROXY_ADDR), "\""));
        vm.writeLine(FRONTEND_ENV_PATH, string.concat("REACT_APP_L1_MESSAGE_QUEUE = \"", vm.toString(L1_MESSAGE_QUEUE_PROXY_ADDR), "\""));
        vm.writeLine(FRONTEND_ENV_PATH, string.concat("REACT_APP_L1_MESSAGE_QUEUE_WITH_GAS_PRICE_ORACLE = \"", vm.toString(L1_MESSAGE_QUEUE_PROXY_ADDR), "\""));
        vm.writeLine(FRONTEND_ENV_PATH, string.concat("REACT_APP_L1_SCROLL_MESSENGER = \"", vm.toString(L1_SCROLL_MESSENGER_PROXY_ADDR), "\""));
        vm.writeLine(FRONTEND_ENV_PATH, string.concat("REACT_APP_L1_STANDARD_ERC20_GATEWAY_PROXY_ADDR = \"", vm.toString(L1_STANDARD_ERC20_GATEWAY_PROXY_ADDR), "\""));
        vm.writeLine(FRONTEND_ENV_PATH, string.concat("REACT_APP_L1_WETH_GATEWAY_PROXY_ADDR = \"", vm.toString(L1_WETH_GATEWAY_PROXY_ADDR), "\""));
        vm.writeLine(FRONTEND_ENV_PATH, string.concat("REACT_APP_SCROLL_CHAIN = \"", vm.toString(L1_SCROLL_CHAIN_PROXY_ADDR), "\""));
        vm.writeLine(FRONTEND_ENV_PATH, string.concat("REACT_APP_L1_GAS_TOKEN_GATEWAY = \"", vm.toString(L1_GAS_TOKEN_GATEWAY_PROXY_ADDR), "\""));
        vm.writeLine(FRONTEND_ENV_PATH, string.concat("REACT_APP_L1_WRAPPED_TOKEN_GATEWAY = \"", vm.toString(L1_WRAPPED_TOKEN_GATEWAY_ADDR), "\""));
        vm.writeLine(FRONTEND_ENV_PATH, string.concat("REACT_APP_L1_GAS_TOKEN_ADDR = \"", vm.toString(L1_GAS_TOKEN_ADDR), "\""));
        vm.writeLine(FRONTEND_ENV_PATH, string.concat("REACT_APP_L1_WETH_ADDR = \"", vm.toString(L1_WETH_ADDR), "\""));

        // L2 contracts
        vm.writeLine(FRONTEND_ENV_PATH, "");
        vm.writeLine(FRONTEND_ENV_PATH, string.concat("REACT_APP_L2_CUSTOM_ERC20_GATEWAY_PROXY_ADDR = \"", vm.toString(L2_CUSTOM_ERC20_GATEWAY_PROXY_ADDR), "\""));
        vm.writeLine(FRONTEND_ENV_PATH, string.concat("REACT_APP_L2_ETH_GATEWAY_PROXY_ADDR = \"", vm.toString(L2_ETH_GATEWAY_PROXY_ADDR), "\""));
        vm.writeLine(FRONTEND_ENV_PATH, string.concat("REACT_APP_L2_GATEWAY_ROUTER_PROXY_ADDR = \"", vm.toString(L2_GATEWAY_ROUTER_PROXY_ADDR), "\""));
        vm.writeLine(FRONTEND_ENV_PATH, string.concat("REACT_APP_L2_SCROLL_MESSENGER = \"", vm.toString(L2_SCROLL_MESSENGER_PROXY_ADDR), "\""));
        vm.writeLine(FRONTEND_ENV_PATH, string.concat("REACT_APP_L2_STANDARD_ERC20_GATEWAY_PROXY_ADDR = \"", vm.toString(L2_STANDARD_ERC20_GATEWAY_PROXY_ADDR), "\""));
        vm.writeLine(FRONTEND_ENV_PATH, string.concat("REACT_APP_L2_WETH_GATEWAY_PROXY_ADDR = \"", vm.toString(L2_WETH_GATEWAY_PROXY_ADDR), "\""));

        // custom token gateways (currently not set)
        vm.writeLine(FRONTEND_ENV_PATH, "");
        vm.writeLine(FRONTEND_ENV_PATH, "REACT_APP_L1_USDC_GATEWAY_PROXY_ADDR = \"\"");
        vm.writeLine(FRONTEND_ENV_PATH, "REACT_APP_L2_USDC_GATEWAY_PROXY_ADDR = \"\"");
        vm.writeLine(FRONTEND_ENV_PATH, "REACT_APP_L1_DAI_GATEWAY_PROXY_ADDR = \"\"");
        vm.writeLine(FRONTEND_ENV_PATH, "REACT_APP_L2_DAI_GATEWAY_PROXY_ADDR = \"\"");
        vm.writeLine(FRONTEND_ENV_PATH, "REACT_APP_L1_LIDO_GATEWAY_PROXY_ADDR = \"\"");
        vm.writeLine(FRONTEND_ENV_PATH, "REACT_APP_L2_LIDO_GATEWAY_PROXY_ADDR = \"\"");
        vm.writeLine(FRONTEND_ENV_PATH, "REACT_APP_L1_PUFFER_GATEWAY_PROXY_ADDR = \"\"");
        vm.writeLine(FRONTEND_ENV_PATH, "REACT_APP_L2_PUFFER_GATEWAY_PROXY_ADDR = \"\"");

        // misc
        vm.writeLine(FRONTEND_ENV_PATH, "");
        vm.writeLine(FRONTEND_ENV_PATH, "REACT_APP_SCROLL_ORIGINS_NFT = \"\"");
        vm.writeLine(FRONTEND_ENV_PATH, "REACT_APP_SCROLL_ORIGINS_NFT_V2 = \"\"");
        vm.writeLine(FRONTEND_ENV_PATH, "REACT_APP_L1_BATCH_BRIDGE_GATEWAY_PROXY_ADDR = \"\"");
    }
}

contract GenerateRollupExplorerBackendConfig is DeployScroll {
    /***************
     * Entry point *
     ***************/

    function run() public {
        DeterministicDeployment.initialize(ScriptMode.VerifyConfig);
        predictAllContracts();

        generateRollupExplorerBackendConfig();
    }

    /*********************
     * Private functions *
     *********************/

    // prettier-ignore
    function generateRollupExplorerBackendConfig() private {
        // initialize template file
        if (vm.exists(ROLLUP_EXPLORER_BACKEND_CONFIG_PATH)) {
            vm.removeFile(ROLLUP_EXPLORER_BACKEND_CONFIG_PATH);
        }

        string memory template = vm.readFile(ROLLUP_EXPLORER_BACKEND_CONFIG_TEMPLATE_PATH);
        vm.writeFile(ROLLUP_EXPLORER_BACKEND_CONFIG_PATH, template);

        vm.writeJson(ROLLUP_EXPLORER_BACKEND_DB_CONNECTION_STRING, ROLLUP_EXPLORER_BACKEND_CONFIG_PATH, ".db_url");
    }
}

contract GenerateAdminSystemBackendConfig is DeployScroll {
    /***************
     * Entry point *
     ***************/

    function run() public {
        DeterministicDeployment.initialize(ScriptMode.VerifyConfig);
        predictAllContracts();

        generateAdminSystemBackendConfig();
    }

    /*********************
     * Private functions *
     *********************/

    // prettier-ignore
    function generateAdminSystemBackendConfig() private {
        // initialize template file
        if (vm.exists(ADMIN_SYSTEM_BACKEND_CONFIG_PATH)) {
            vm.removeFile(ADMIN_SYSTEM_BACKEND_CONFIG_PATH);
        }

        string memory template = vm.readFile(ADMIN_SYSTEM_BACKEND_CONFIG_TEMPLATE_PATH);
        vm.writeFile(ADMIN_SYSTEM_BACKEND_CONFIG_PATH, template);
    }
}
