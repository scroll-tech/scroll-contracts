#!/bin/bash

echo ""
echo "generating config-contracts.toml"
forge script scripts/deterministic/DeployScroll.s.sol:DeployScroll --sig "run(string,string)" "none" "write-config" || exit 1

echo ""
echo "updating genesis.yaml"
forge script scripts/deterministic/GenerateGenesis.s.sol:GenerateGenesis || exit 1

echo ""
echo "updating rollup-config.yaml"
forge script scripts/deterministic/GenerateConfigs.s.sol:GenerateRollupConfig || exit 1

echo ""
echo "updating coordinator-config.yaml"
forge script scripts/deterministic/GenerateConfigs.s.sol:GenerateCoordinatorConfig || exit 1

echo ""
echo "updating chain-monitor-config.yaml"
forge script scripts/deterministic/GenerateConfigs.s.sol:GenerateChainMonitorConfig || exit 1

echo ""
echo "updating bridge-history-config.yaml"
forge script scripts/deterministic/GenerateConfigs.s.sol:GenerateBridgeHistoryConfig || exit 1

echo ""
echo "updating balance-checker-config.yaml"
forge script scripts/deterministic/GenerateConfigs.s.sol:GenerateBalanceCheckerConfig || exit 1