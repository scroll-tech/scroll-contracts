#!/bin/bash

# the deployment of the L1GasTokenGateway implementation necessitates fetching the gas token decimal
# in this case it requires the context of layer 1
gen_config_contracts_toml() {
    config_file="./volume/config.toml"
    gas_token_addr=$(grep -E "^L1_GAS_TOKEN =" "$config_file" | sed 's/ *= */=/' | cut -d'=' -f2-)
    gas_token_enabled=$(grep -E "^ALTERNATIVE_GAS_TOKEN_ENABLED =" "$config_file" | sed 's/ *= */=/' | cut -d'=' -f2-)
    l1_rpc_url=$(grep -E "^L1_RPC_ENDPOINT =" "$config_file" | sed 's/ *= */=/' | cut -d'=' -f2- | sed 's/"//g')

    if [[ "$gas_token_enabled" == "true" && "$gas_token_addr" != "" && "$gas_token_addr" != "0x0000000000000000000000000000000000000000" ]]; then
        echo "gas token enabled and address provided"
        forge script scripts/deterministic/DeployScroll.s.sol:DeployScroll --rpc-url "$l1_rpc_url" --sig "run(string,string)" "none" "write-config" || exit 1
    else
        echo "gas token disabled or address not provided"
        forge script scripts/deterministic/DeployScroll.s.sol:DeployScroll --sig "run(string,string)" "none" "write-config" || exit 1
    fi
}

echo ""
echo "generating config-contracts.toml"
gen_config_contracts_toml

echo ""
echo "generating genesis.json"
forge script scripts/deterministic/GenerateGenesis.s.sol:GenerateGenesis || exit 1

echo ""
echo "generating rollup-config.json"
forge script scripts/deterministic/GenerateConfigs.s.sol:GenerateRollupConfig || exit 1

echo ""
echo "generating coordinator-config.json"
forge script scripts/deterministic/GenerateConfigs.s.sol:GenerateCoordinatorConfig || exit 1

echo ""
echo "generating chain-monitor-config.json"
forge script scripts/deterministic/GenerateConfigs.s.sol:GenerateChainMonitorConfig || exit 1

echo ""
echo "generating bridge-history-config.json"
forge script scripts/deterministic/GenerateConfigs.s.sol:GenerateBridgeHistoryConfig || exit 1

echo ""
echo "generating balance-checker-config.json"
forge script scripts/deterministic/GenerateConfigs.s.sol:GenerateBalanceCheckerConfig || exit 1

echo ""
echo "generating .env.frontend"
forge script scripts/deterministic/GenerateConfigs.s.sol:GenerateFrontendConfig || exit 1

echo ""
echo "generating rollup-explorer-backend-config.json"
forge script scripts/deterministic/GenerateConfigs.s.sol:GenerateRollupExplorerBackendConfig || exit 1
