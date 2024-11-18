#!/bin/sh

# extract values from config file
config_file="./volume/config.toml"
CHAIN_ID_L1=$(grep -E "^CHAIN_ID_L1 =" "$config_file" | sed 's/ *= */=/' | cut -d'=' -f2-)
CHAIN_ID_L2=$(grep -E "^CHAIN_ID_L2 =" "$config_file" | sed 's/ *= */=/' | cut -d'=' -f2-)
RPC_URI_L1=$(grep -E "^RPC_URI_L1 =" "$config_file" | sed 's/ *= */=/' | cut -d'=' -f2- | tr -d '"')
RPC_URI_L2=$(grep -E "^RPC_URI_L2 =" "$config_file" | sed 's/ *= */=/' | cut -d'=' -f2- | tr -d '"')
VERIFIER_TYPE_L1=$(grep -E "^VERIFIER_TYPE_L1 =" "$config_file" | sed 's/ *= */=/' | cut -d'=' -f2- | tr -d '"')
VERIFIER_TYPE_L2=$(grep -E "^VERIFIER_TYPE_L2 =" "$config_file" | sed 's/ *= */=/' | cut -d'=' -f2- | tr -d '"')
EXPLORER_URI_L1=$(grep -E "^EXPLORER_URI_L1 =" "$config_file" | sed 's/ *= */=/' | cut -d'=' -f2- | tr -d '"')
EXPLORER_URI_L2=$(grep -E "^EXPLORER_URI_L2 =" "$config_file" | sed 's/ *= */=/' | cut -d'=' -f2- | tr -d '"')
EXPLORER_API_KEY_L1=$(grep -E "^EXPLORER_API_KEY_L1 =" "$config_file" | sed 's/ *= */=/' | cut -d'=' -f2- | tr -d '"')
EXPLORER_API_KEY_L2=$(grep -E "^EXPLORER_API_KEY_L2 =" "$config_file" | sed 's/ *= */=/' | cut -d'=' -f2- | tr -d '"')
ALTERNATIVE_GAS_TOKEN_ENABLED=$(grep -E "^ALTERNATIVE_GAS_TOKEN_ENABLED =" "$config_file" | sed 's/ *= */=/' | cut -d'=' -f2-)
TEST_ENV_MOCK_FINALIZE_ENABLED=$(grep -E "^TEST_ENV_MOCK_FINALIZE_ENABLED =" "$config_file" | sed 's/ *= */=/' | cut -d'=' -f2-)

# extract contract name and address
extract_contract_info() {
  contract_name=$(cut -d "=" -f 1 <<< "$line" | tr -d '"')
  contract_addr=$(cut -d "=" -f 2 <<< "$line" | tr -d '"' | tr -d ' ')
}

get_source_code_name() {
  # specially handle the case where alternative gas token is enabled
  if [[ "$ALTERNATIVE_GAS_TOKEN_ENABLED" == "true" && "$1" =~ ^(L1_SCROLL_MESSENGER_IMPLEMENTATION_ADDR|L2_TX_FEE_VAULT_ADDR)$ ]]; then
    case "$1" in
      L1_SCROLL_MESSENGER_IMPLEMENTATION_ADDR) echo L1ScrollMessengerNonETH ;;
      L2_TX_FEE_VAULT_ADDR) echo L2TxFeeVaultWithGasToken ;;
      *) 
    esac
  # specially handle the case where mock finalize is enabled
  elif [[ "$TEST_ENV_MOCK_FINALIZE_ENABLED" == "true" && "$1" =~ ^(L1_SCROLL_CHAIN_IMPLEMENTATION_ADDR)$ ]]; then
    case "$1" in
      L1_SCROLL_CHAIN_IMPLEMENTATION_ADDR) echo ScrollChainMockFinalize ;;
      *) 
    esac
  else
    case "$1" in
      L1_WETH_ADDR) echo WrappedEther ;;
      L1_PROXY_IMPLEMENTATION_PLACEHOLDER_ADDR) echo EmptyContract ;;
      L1_PROXY_ADMIN_ADDR) echo ProxyAdminSetOwner ;;
      L1_WHITELIST_ADDR) echo Whitelist ;;
      L1_SCROLL_CHAIN_PROXY_ADDR) echo TransparentUpgradeableProxy ;;
      L1_SCROLL_MESSENGER_PROXY_ADDR) echo TransparentUpgradeableProxy ;;
      L1_ENFORCED_TX_GATEWAY_IMPLEMENTATION_ADDR) echo EnforcedTxGateway ;;
      L1_ENFORCED_TX_GATEWAY_PROXY_ADDR) echo TransparentUpgradeableProxy ;;
      L1_ZKEVM_VERIFIER_V2_ADDR) echo ZkEvmVerifierV2 ;;
      L1_MULTIPLE_VERSION_ROLLUP_VERIFIER_ADDR ) echo MultipleVersionRollupVerifierSetOwner ;;
      L1_MESSAGE_QUEUE_IMPLEMENTATION_ADDR) echo L1MessageQueueWithGasPriceOracle ;;
      L1_MESSAGE_QUEUE_PROXY_ADDR) echo TransparentUpgradeableProxy ;;
      L1_SCROLL_CHAIN_IMPLEMENTATION_ADDR) echo ScrollChain ;;
      L1_GATEWAY_ROUTER_IMPLEMENTATION_ADDR) echo L1GatewayRouter ;;
      L1_GATEWAY_ROUTER_PROXY_ADDR) echo TransparentUpgradeableProxy ;;
      L1_ETH_GATEWAY_PROXY_ADDR) echo TransparentUpgradeableProxy ;;
      L1_WETH_GATEWAY_PROXY_ADDR) echo TransparentUpgradeableProxy ;;
      L1_STANDARD_ERC20_GATEWAY_PROXY_ADDR) echo TransparentUpgradeableProxy ;;
      L1_CUSTOM_ERC20_GATEWAY_PROXY_ADDR) echo TransparentUpgradeableProxy ;;
      L1_ERC721_GATEWAY_PROXY_ADDR) echo TransparentUpgradeableProxy ;;
      L1_ERC1155_GATEWAY_PROXY_ADDR) echo TransparentUpgradeableProxy ;;
      L2_MESSAGE_QUEUE_ADDR) echo L2MessageQueue ;;
      L1_GAS_PRICE_ORACLE_ADDR) echo L1GasPriceOracle ;;
      L1_GAS_TOKEN_GATEWAY_IMPLEMENTATION_ADDR) echo L1GasTokenGateway ;;
      L1_GAS_TOKEN_GATEWAY_PROXY_ADDR) echo TransparentUpgradeableProxy ;;
      L1_WRAPPED_TOKEN_GATEWAY_ADDR) echo L1WrappedTokenGateway ;;
      L2_WHITELIST_ADDR) echo Whitelist ;;
      L2_WETH_ADDR) echo WrappedEther ;;
      L2_TX_FEE_VAULT_ADDR) echo L2TxFeeVault ;;
      L2_PROXY_ADMIN_ADDR) echo ProxyAdminSetOwner ;;
      L2_PROXY_IMPLEMENTATION_PLACEHOLDER_ADDR) echo EmptyContract ;;
      L2_SCROLL_MESSENGER_PROXY_ADDR) echo TransparentUpgradeableProxy ;;
      L2_ETH_GATEWAY_PROXY_ADDR) echo TransparentUpgradeableProxy ;;
      L2_WETH_GATEWAY_PROXY_ADDR) echo TransparentUpgradeableProxy ;;
      L2_STANDARD_ERC20_GATEWAY_PROXY_ADDR) echo TransparentUpgradeableProxy ;;
      L2_CUSTOM_ERC20_GATEWAY_PROXY_ADDR) echo TransparentUpgradeableProxy ;;
      L2_ERC721_GATEWAY_PROXY_ADDR) echo TransparentUpgradeableProxy ;;
      L2_ERC1155_GATEWAY_PROXY_ADDR) echo TransparentUpgradeableProxy ;;
      L2_SCROLL_STANDARD_ERC20_ADDR) echo ScrollStandardERC20 ;;
      L2_SCROLL_STANDARD_ERC20_FACTORY_ADDR) echo ScrollStandardERC20FactorySetOwner ;;
      L1_SCROLL_MESSENGER_IMPLEMENTATION_ADDR) echo L1ScrollMessenger ;;
      L1_STANDARD_ERC20_GATEWAY_IMPLEMENTATION_ADDR) echo L1StandardERC20Gateway ;;
      L1_ETH_GATEWAY_IMPLEMENTATION_ADDR) echo L1ETHGateway ;;
      L1_WETH_GATEWAY_IMPLEMENTATION_ADDR) echo L1WETHGateway ;;
      L1_CUSTOM_ERC20_GATEWAY_IMPLEMENTATION_ADDR) echo L1CustomERC20Gateway ;;
      L1_ERC721_GATEWAY_IMPLEMENTATION_ADDR) echo L1ERC721Gateway ;;
      L1_ERC1155_GATEWAY_IMPLEMENTATION_ADDR ) echo L1ERC1155Gateway ;;
      L2_SCROLL_MESSENGER_IMPLEMENTATION_ADDR) echo L2ScrollMessenger ;;
      L2_GATEWAY_ROUTER_IMPLEMENTATION_ADDR) echo L2GatewayRouter ;;
      L2_GATEWAY_ROUTER_PROXY_ADDR) echo TransparentUpgradeableProxy ;;
      L2_STANDARD_ERC20_GATEWAY_IMPLEMENTATION_ADDR) echo L2StandardERC20Gateway ;;
      L2_ETH_GATEWAY_IMPLEMENTATION_ADDR) echo L2ETHGateway ;;
      L2_WETH_GATEWAY_IMPLEMENTATION_ADDR) echo L2WETHGateway ;;
      L2_CUSTOM_ERC20_GATEWAY_IMPLEMENTATION_ADDR) echo L2CustomERC20Gateway ;;
      L2_ERC721_GATEWAY_IMPLEMENTATION_ADDR) echo L2ERC721Gateway ;;
      L2_ERC1155_GATEWAY_IMPLEMENTATION_ADDR) echo L2ERC1155Gateway ;;
      *) echo "" ;; # default: return void string
    esac
  fi
}

function is_predeploy_contract() {
  local contract_name="$1"

  if [[ "$contract_name" == "L2MessageQueue" || "$contract_name" == "L1GasPriceOracle" || "$contract_name" == "Whitelist" || "$contract_name" == "WrappedEther" || "$contract_name" == "L2TxFeeVault" ]]; then
    return 0  # True
  else
    return 1  # False
  fi
}

# read the file line by line
while IFS= read -r line; do
  extract_contract_info "$line"

  # get contracts deployment layer
  if [[ "$contract_name" =~ ^L1 ]]; then
    layer="L1"
    # specially handle contract_name L1_GAS_PRICE_ORACLE_ADDR
    if [[ "$contract_name" == "L1_GAS_PRICE_ORACLE_ADDR" ]]; then
      layer="L2"
    fi
  elif [[ "$contract_name" =~ ^L2 ]]; then
    layer="L2"
  else
    echo "wrong contract name, not starts with L1 or L2, contract_name: $contract_name"
    continue
  fi

  source_code_name=$(get_source_code_name $contract_name)

  # skip if source_code_name or contract_addr is empty
  if [[ -z $source_code_name || -z $contract_addr ]]; then
    echo "empty source_code_name $source_code_name or contract_addr $contract_addr"
    continue
  fi

  # verify contract
  echo ""
  echo "verifing contract $contract_name with address $contract_addr on $layer"
  EXTRA_PARAMS=""
  if [[ "$layer" == "L1" ]]; then
    if [[ "$VERIFIER_TYPE_L1" == "etherscan" ]]; then
      EXTRA_PARAMS="--api-key $EXPLORER_API_KEY_L1"
    elif [[ "$VERIFIER_TYPE_L1" == "blockscout" ]]; then
      EXTRA_PARAMS="--verifier-url ${EXPLORER_URI_L1}/api/ --verifier $VERIFIER_TYPE_L1"
    elif [[ "$VERIFIER_TYPE_L1" == "sourcify" ]]; then
      EXTRA_PARAMS="--api-key $EXPLORER_API_KEY_L1 --verifier-url $EXPLORER_URI_L1 --verifier $VERIFIER_TYPE_L1"
    fi
    forge verify-contract $contract_addr $source_code_name --rpc-url $RPC_URI_L1 --chain-id $CHAIN_ID_L1 --watch --guess-constructor-args --skip-is-verified-check $EXTRA_PARAMS
  elif [[ "$layer" == "L2" ]]; then
    if [[ "$VERIFIER_TYPE_L2" == "etherscan" ]]; then
      EXTRA_PARAMS="--api-key $EXPLORER_API_KEY_L2"
    elif [[ "$VERIFIER_TYPE_L2" == "blockscout" ]]; then
      EXTRA_PARAMS="--verifier-url ${EXPLORER_URI_L2}/api/ --verifier $VERIFIER_TYPE_L2"
    elif [[ "$VERIFIER_TYPE_L2" == "sourcify" ]]; then
      EXTRA_PARAMS="--api-key $EXPLORER_API_KEY_L2 --verifier-url $EXPLORER_URI_L2 --verifier $VERIFIER_TYPE_L2"
    fi
    if ! is_predeploy_contract "$source_code_name"; then
        string="$EXTRA_PARAMS\" --guess-constructor-args\""
    fi
    forge verify-contract $contract_addr $source_code_name --rpc-url $RPC_URI_L2 --chain-id $CHAIN_ID_L2 --watch --skip-is-verified-check $EXTRA_PARAMS
  fi
done < ./volume/config-contracts.toml