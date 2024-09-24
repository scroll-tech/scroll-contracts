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

# format_config_file will add "scrollConfig: |" to the first line and indent the rest
format_config_file() {
    local file="$1"
    local config_scroll_key="scrollConfig: |"
    temp_file=$(mktemp)

    {
        echo $config_scroll_key
        while IFS= read -r line; do
            echo "  $line"
        done < <(grep "" "$file")
    } > "$temp_file"

    mv "$temp_file" "$file"
}

echo ""
echo "generating config-contracts.toml"
gen_config_contracts_toml

echo ""
echo "generating genesis.yaml"
forge script scripts/deterministic/GenerateGenesis.s.sol:GenerateGenesis || exit 1
format_config_file "./volume/genesis.yaml"

echo ""
echo "generating rollup-config.yaml"
forge script scripts/deterministic/GenerateConfigs.s.sol:GenerateRollupConfig || exit 1
format_config_file "./volume/rollup-config.yaml"

echo ""
echo "generating coordinator-config.yaml"
forge script scripts/deterministic/GenerateConfigs.s.sol:GenerateCoordinatorConfig || exit 1
format_config_file "./volume/coordinator-config.yaml"

echo ""
echo "generating chain-monitor-config.yaml"
forge script scripts/deterministic/GenerateConfigs.s.sol:GenerateChainMonitorConfig || exit 1
format_config_file "./volume/chain-monitor-config.yaml"

echo ""
echo "generating bridge-history-config.yaml"
forge script scripts/deterministic/GenerateConfigs.s.sol:GenerateBridgeHistoryConfig || exit 1
format_config_file "./volume/bridge-history-config.yaml"

echo ""
echo "generating balance-checker-config.yaml"
forge script scripts/deterministic/GenerateConfigs.s.sol:GenerateBalanceCheckerConfig || exit 1
format_config_file "./volume/balance-checker-config.yaml"

echo ""
echo "generating frontend-config.yaml"
forge script scripts/deterministic/GenerateConfigs.s.sol:GenerateFrontendConfig || exit 1
format_config_file "./volume/frontend-config.yaml"

echo ""
echo "generating rollup-explorer-backend-config.yaml"
forge script scripts/deterministic/GenerateConfigs.s.sol:GenerateRollupExplorerBackendConfig || exit 1
format_config_file "./volume/rollup-explorer-backend-config.yaml"

echo ""
echo "generating admin-system-backend-config.yaml"
forge script scripts/deterministic/GenerateConfigs.s.sol:GenerateAdminSystemBackendConfig || exit 1
format_config_file "./volume/admin-system-backend-config.yaml"