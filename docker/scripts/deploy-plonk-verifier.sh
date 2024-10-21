#!/bin/bash

check_env () {
  local name="$1"
  local value="${!name}"

  if [ -z "$value" ]; then
    echo "$name not set in env"
    exit 1
  fi
}

check_command () {
  local command="$1"

  if ! command -v "$command" &> /dev/null; then
  print_error "$command could not be found"
  exit
fi
}

success_or_exit () {
  if [ $? -ne 0 ]; then
    >&2 echo "$OUTPUT"
    print_error "Execution failed"
    exit 1
  fi
}

# make sure that all cli tools are available
check_command "cast"
check_command "tr"
check_command "xxd"

# make sure that all required environment variables are set
check_env "CHAIN_ID_L1"
check_env "L1_PLONK_VERIFIER_DEPLOYER_PRIVATE_KEY"
check_env "PLONK_VERIFIER_VERSION"
check_env "SCROLL_L1_DEPLOYMENT_RPC"

# read and parse plonk verifier bytecode
PLONK_VERIFIER_PATH="./evm_verifier.bin"
PLONK_VERIFIER_URL="https://circuit-release.s3.us-west-2.amazonaws.com/release-$PLONK_VERIFIER_VERSION/evm_verifier.bin"

echo "Downloading Plonk verifier $PLONK_VERIFIER_VERSION..."
OUTPUT=$(curl "$PLONK_VERIFIER_URL" -o "$PLONK_VERIFIER_PATH" 2>&1)
success_or_exit
PLONK_VERIFIER_BYTECODE=$(xxd -p "$PLONK_VERIFIER_PATH" | tr -d '\n')
rm "$PLONK_VERIFIER_PATH"


##################################################
##################### Deploy #####################
##################################################

echo "Deploying Plonk verifier contract $PLONK_VERIFIER_VERSION..."
OUTPUT=$(cast send --rpc-url "$SCROLL_L1_DEPLOYMENT_RPC" --chain "$CHAIN_ID_L1" --private-key "$L1_PLONK_VERIFIER_DEPLOYER_PRIVATE_KEY" --create "$PLONK_VERIFIER_BYTECODE" 2>&1)
success_or_exit
export L1_PLONK_VERIFIER_ADDR="$(echo "$OUTPUT" | grep "contractAddress" | grep -o --color=never '0x.*')"
echo "L1_PLONK_VERIFIER_ADDR=$L1_PLONK_VERIFIER_ADDR"

echo "Done"