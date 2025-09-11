// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.24;

import {Script} from "forge-std/Script.sol";
import {stdToml} from "forge-std/StdToml.sol";

import {Configuration} from "../Configuration.sol";

/// @notice ScrollConfiguration allows inheriting contracts to read the TOML configuration file.
abstract contract ScrollConfiguration is Script, Configuration {
    using stdToml for string;

    /****************************
     * Configuration parameters *
     ****************************/

    // general
    string internal L1_RPC_ENDPOINT;
    string internal L2_RPC_ENDPOINT;

    string internal CHAIN_NAME_L1;
    string internal CHAIN_NAME_L2;
    uint64 internal CHAIN_ID_L1;
    uint64 internal CHAIN_ID_L2;

    uint256 internal MAX_TX_IN_CHUNK;
    uint256 internal MAX_BLOCK_IN_CHUNK;
    uint256 internal MAX_BATCH_IN_BUNDLE;
    uint256 internal MAX_L1_MESSAGE_GAS_LIMIT;
    uint256 internal FINALIZE_BATCH_DEADLINE_SEC;
    uint256 internal RELAY_MESSAGE_DEADLINE_SEC;

    uint256 internal L1_CONTRACT_DEPLOYMENT_BLOCK;

    bool internal TEST_ENV_MOCK_FINALIZE_ENABLED;
    uint256 internal TEST_ENV_MOCK_FINALIZE_TIMEOUT_SEC;

    // accounts
    uint256 internal DEPLOYER_PRIVATE_KEY;
    uint256 internal L1_COMMIT_SENDER_PRIVATE_KEY;
    uint256 internal L1_FINALIZE_SENDER_PRIVATE_KEY;
    uint256 internal L1_GAS_ORACLE_SENDER_PRIVATE_KEY;
    uint256 internal L2_GAS_ORACLE_SENDER_PRIVATE_KEY;

    address internal DEPLOYER_ADDR;
    address internal L1_COMMIT_SENDER_ADDR;
    address internal L1_FINALIZE_SENDER_ADDR;
    address internal L1_GAS_ORACLE_SENDER_ADDR;
    address internal L2_GAS_ORACLE_SENDER_ADDR;

    address internal OWNER_ADDR;

    address internal L2GETH_SIGNER_ADDRESS;

    // db
    string internal ROLLUP_EXPLORER_BACKEND_DB_CONNECTION_STRING;

    // genesis
    uint256 internal L2_MAX_ETH_SUPPLY;
    uint256 internal L2_DEPLOYER_INITIAL_BALANCE;
    uint256 internal L2_SCROLL_MESSENGER_INITIAL_BALANCE;

    // contracts
    string internal DEPLOYMENT_SALT;

    address internal L1_FEE_VAULT_ADDR;

    // coordinator
    string internal CHUNK_COLLECTION_TIME_SEC;
    string internal BATCH_COLLECTION_TIME_SEC;
    string internal BUNDLE_COLLECTION_TIME_SEC;
    string internal COORDINATOR_JWT_SECRET_KEY;

    // frontend
    string internal EXTERNAL_RPC_URI_L1;
    string internal EXTERNAL_RPC_URI_L2;
    string internal BRIDGE_API_URI;
    string internal ROLLUPSCAN_API_URI;
    string internal EXTERNAL_EXPLORER_URI_L1;
    string internal EXTERNAL_EXPLORER_URI_L2;
    string internal ADMIN_SYSTEM_DASHBOARD_URI;
    string internal GRAFANA_URI;

    /**********************
     * Internal interface *
     **********************/

    function readConfig(string memory workdir) internal {
        super.initialize(workdir);

        CHAIN_ID_L1 = uint64(cfg.readUint(".general.CHAIN_ID_L1"));
        CHAIN_ID_L2 = uint64(cfg.readUint(".general.CHAIN_ID_L2"));

        MAX_TX_IN_CHUNK = cfg.readUint(".rollup.MAX_TX_IN_CHUNK");
        MAX_BLOCK_IN_CHUNK = cfg.readUint(".rollup.MAX_BLOCK_IN_CHUNK");
        MAX_BATCH_IN_BUNDLE = cfg.readUint(".rollup.MAX_BATCH_IN_BUNDLE");
        MAX_L1_MESSAGE_GAS_LIMIT = cfg.readUint(".rollup.MAX_L1_MESSAGE_GAS_LIMIT");
        FINALIZE_BATCH_DEADLINE_SEC = cfg.readUint(".rollup.FINALIZE_BATCH_DEADLINE_SEC");
        RELAY_MESSAGE_DEADLINE_SEC = cfg.readUint(".rollup.RELAY_MESSAGE_DEADLINE_SEC");

        L1_CONTRACT_DEPLOYMENT_BLOCK = cfg.readUint(".general.L1_CONTRACT_DEPLOYMENT_BLOCK");

        TEST_ENV_MOCK_FINALIZE_ENABLED = cfg.readBool(".rollup.TEST_ENV_MOCK_FINALIZE_ENABLED");
        TEST_ENV_MOCK_FINALIZE_TIMEOUT_SEC = cfg.readUint(".rollup.TEST_ENV_MOCK_FINALIZE_TIMEOUT_SEC");

        DEPLOYER_PRIVATE_KEY = cfg.readUint(".accounts.DEPLOYER_PRIVATE_KEY");
        L1_COMMIT_SENDER_PRIVATE_KEY = cfg.readUint(".accounts.L1_COMMIT_SENDER_PRIVATE_KEY");
        L1_FINALIZE_SENDER_PRIVATE_KEY = cfg.readUint(".accounts.L1_FINALIZE_SENDER_PRIVATE_KEY");
        L1_GAS_ORACLE_SENDER_PRIVATE_KEY = cfg.readUint(".accounts.L1_GAS_ORACLE_SENDER_PRIVATE_KEY");
        L2_GAS_ORACLE_SENDER_PRIVATE_KEY = cfg.readUint(".accounts.L2_GAS_ORACLE_SENDER_PRIVATE_KEY");

        DEPLOYER_ADDR = cfg.readAddress(".accounts.DEPLOYER_ADDR");
        L1_COMMIT_SENDER_ADDR = cfg.readAddress(".accounts.L1_COMMIT_SENDER_ADDR");
        L1_FINALIZE_SENDER_ADDR = cfg.readAddress(".accounts.L1_FINALIZE_SENDER_ADDR");
        L1_GAS_ORACLE_SENDER_ADDR = cfg.readAddress(".accounts.L1_GAS_ORACLE_SENDER_ADDR");
        L2_GAS_ORACLE_SENDER_ADDR = cfg.readAddress(".accounts.L2_GAS_ORACLE_SENDER_ADDR");

        OWNER_ADDR = cfg.readAddress(".accounts.OWNER_ADDR");

        L2GETH_SIGNER_ADDRESS = cfg.readAddress(".sequencer.L2GETH_SIGNER_ADDRESS");

        L2_MAX_ETH_SUPPLY = cfg.readUint(".genesis.L2_MAX_ETH_SUPPLY");
        L2_DEPLOYER_INITIAL_BALANCE = cfg.readUint(".genesis.L2_DEPLOYER_INITIAL_BALANCE");
        L2_SCROLL_MESSENGER_INITIAL_BALANCE = L2_MAX_ETH_SUPPLY - L2_DEPLOYER_INITIAL_BALANCE;

        DEPLOYMENT_SALT = cfg.readString(".contracts.DEPLOYMENT_SALT");

        L1_FEE_VAULT_ADDR = cfg.readAddress(".contracts.L1_FEE_VAULT_ADDR");

        CHUNK_COLLECTION_TIME_SEC = cfg.readString(".coordinator.CHUNK_COLLECTION_TIME_SEC");
        BATCH_COLLECTION_TIME_SEC = cfg.readString(".coordinator.BATCH_COLLECTION_TIME_SEC");
        BUNDLE_COLLECTION_TIME_SEC = cfg.readString(".coordinator.BUNDLE_COLLECTION_TIME_SEC");
        COORDINATOR_JWT_SECRET_KEY = cfg.readString(".coordinator.COORDINATOR_JWT_SECRET_KEY");

        runSanityCheck();
    }

    /*********************
     * Private functions *
     *********************/

    function runSanityCheck() private view {
        verifyAccount("DEPLOYER", DEPLOYER_PRIVATE_KEY, DEPLOYER_ADDR);
        verifyAccount("L1_COMMIT_SENDER", L1_COMMIT_SENDER_PRIVATE_KEY, L1_COMMIT_SENDER_ADDR);
        verifyAccount("L1_FINALIZE_SENDER", L1_FINALIZE_SENDER_PRIVATE_KEY, L1_FINALIZE_SENDER_ADDR);
        verifyAccount("L1_GAS_ORACLE_SENDER", L1_GAS_ORACLE_SENDER_PRIVATE_KEY, L1_GAS_ORACLE_SENDER_ADDR);
        verifyAccount("L2_GAS_ORACLE_SENDER", L2_GAS_ORACLE_SENDER_PRIVATE_KEY, L2_GAS_ORACLE_SENDER_ADDR);
    }

    function verifyAccount(
        string memory name,
        uint256 privateKey,
        address addr
    ) private pure {
        if (vm.addr(privateKey) != addr) {
            revert(
                string(
                    abi.encodePacked(
                        "[ERROR] ",
                        name,
                        "_ADDR (",
                        vm.toString(addr),
                        ") does not match ",
                        name,
                        "_PRIVATE_KEY"
                    )
                )
            );
        }
    }
}
