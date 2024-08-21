// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.24;

/// @dev The default deterministic deployment salt prefix.
string constant DEFAULT_DEPLOYMENT_SALT = "ScrollStack";

/// @dev The address of DeterministicDeploymentProxy.
///      See https://github.com/Arachnid/deterministic-deployment-proxy.
address constant DETERMINISTIC_DEPLOYMENT_PROXY_ADDR = 0x4e59b44847b379578588920cA78FbF26c0B4956C;

/// @dev The default minimum withdraw amount configured on L2TxFeeVault.
uint256 constant FEE_VAULT_MIN_WITHDRAW_AMOUNT = 1 ether;

// template files
string constant CONFIG_CONTRACTS_TEMPLATE_PATH = "./docker/templates/config-contracts.toml";
string constant GENESIS_JSON_TEMPLATE_PATH = "./docker/templates/genesis.json";
string constant ROLLUP_CONFIG_TEMPLATE_PATH = "./docker/templates/rollup-config.json";
string constant COORDINATOR_CONFIG_TEMPLATE_PATH = "./docker/templates/coordinator-config.json";
string constant CHAIN_MONITOR_CONFIG_TEMPLATE_PATH = "./docker/templates/chain-monitor-config.json";
string constant BRIDGE_HISTORY_CONFIG_TEMPLATE_PATH = "./docker/templates/bridge-history-config.json";
string constant BALANCE_CHECKER_CONFIG_TEMPLATE_PATH = "./docker/templates/balance-checker-config.json";
string constant ROLLUP_EXPLORER_BACKEND_CONFIG_TEMPLATE_PATH = "./docker/templates/rollup-explorer-backend-config.json";

// input files
string constant CONFIG_PATH = "./volume/config.toml";

// output files
string constant CONFIG_CONTRACTS_PATH = "./volume/config-contracts.toml";
string constant GENESIS_ALLOC_JSON_PATH = "./volume/__genesis-alloc.json";
string constant GENESIS_JSON_PATH = "./volume/genesis.json";
string constant ROLLUP_CONFIG_PATH = "./volume/rollup-config.json";
string constant COORDINATOR_CONFIG_PATH = "./volume/coordinator-config.json";
string constant CHAIN_MONITOR_CONFIG_PATH = "./volume/chain-monitor-config.json";
string constant BRIDGE_HISTORY_CONFIG_PATH = "./volume/bridge-history-config.json";
string constant BALANCE_CHECKER_CONFIG_PATH = "./volume/balance-checker-config.json";
string constant FRONTEND_ENV_PATH = "./volume/frontend-config";
string constant ROLLUP_EXPLORER_BACKEND_CONFIG_PATH = "./volume/rollup-explorer-backend-config.json";
