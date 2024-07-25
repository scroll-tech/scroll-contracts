// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.24;

import {Script} from "forge-std/Script.sol";
import {VmSafe} from "forge-std/Vm.sol";
import {stdToml} from "forge-std/StdToml.sol";

import {CONFIG_PATH, CONFIG_CONTRACTS_PATH, CONFIG_CONTRACTS_TEMPLATE_PATH} from "./Constants.sol";

/// @notice Configuration allows inheriting contracts to read the TOML configuration file.
abstract contract Configuration is Script {
    using stdToml for string;

    /*******************
     * State variables *
     *******************/

    string internal cfg;
    string internal contractsCfg;

    /****************************
     * Configuration parameters *
     ****************************/

    // general
    string internal L1_RPC_ENDPOINT;
    string internal L2_RPC_ENDPOINT;

    uint64 internal CHAIN_ID_L1;
    uint64 internal CHAIN_ID_L2;

    uint256 internal MAX_TX_IN_CHUNK;
    uint256 internal MAX_BLOCK_IN_CHUNK;
    uint256 internal MAX_L1_MESSAGE_GAS_LIMIT;

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

    address internal L2GETH_SIGNER_0_ADDRESS;

    // db
    string internal SCROLL_DB_CONNECTION_STRING;
    string internal CHAIN_MONITOR_DB_CONNECTION_STRING;
    string internal BRIDGE_HISTORY_DB_CONNECTION_STRING;
    string internal ROLLUP_EXPLORER_BACKEND_DB_CONNECTION_STRING;

    // genesis
    uint256 internal L2_MAX_ETH_SUPPLY;
    uint256 internal L2_DEPLOYER_INITIAL_BALANCE;
    uint256 internal L2_SCROLL_MESSENGER_INITIAL_BALANCE;

    // contracts
    string internal DEPLOYMENT_SALT;

    address internal L1_FEE_VAULT_ADDR;
    address internal L1_PLONK_VERIFIER_ADDR;

    // coordinator
    string internal COORDINATOR_JWT_SECRET_KEY;

    // frontend
    string internal EXTERNAL_RPC_URI_L1;
    string internal EXTERNAL_RPC_URI_L2;
    string internal BRIDGE_API_URI;
    string internal ROLLUPSCAN_API_URI;
    string internal EXTERNAL_EXPLORER_URI_L1;
    string internal EXTERNAL_EXPLORER_URI_L2;

    /***************
     * Constructor *
     ***************/

    constructor() {
        if (!vm.exists(CONFIG_CONTRACTS_PATH)) {
            string memory template = vm.readFile(CONFIG_CONTRACTS_TEMPLATE_PATH);
            vm.writeFile(CONFIG_CONTRACTS_PATH, template);
        }

        cfg = vm.readFile(CONFIG_PATH);
        contractsCfg = vm.readFile(CONFIG_CONTRACTS_PATH);

        L1_RPC_ENDPOINT = cfg.readString(".general.L1_RPC_ENDPOINT");
        L2_RPC_ENDPOINT = cfg.readString(".general.L2_RPC_ENDPOINT");

        CHAIN_ID_L1 = uint64(cfg.readUint(".general.CHAIN_ID_L1"));
        CHAIN_ID_L2 = uint64(cfg.readUint(".general.CHAIN_ID_L2"));

        MAX_TX_IN_CHUNK = cfg.readUint(".general.MAX_TX_IN_CHUNK");
        MAX_BLOCK_IN_CHUNK = cfg.readUint(".general.MAX_BLOCK_IN_CHUNK");
        MAX_L1_MESSAGE_GAS_LIMIT = cfg.readUint(".general.MAX_L1_MESSAGE_GAS_LIMIT");

        L1_CONTRACT_DEPLOYMENT_BLOCK = cfg.readUint(".general.L1_CONTRACT_DEPLOYMENT_BLOCK");

        TEST_ENV_MOCK_FINALIZE_ENABLED = cfg.readBool(".general.TEST_ENV_MOCK_FINALIZE_ENABLED");
        TEST_ENV_MOCK_FINALIZE_TIMEOUT_SEC = cfg.readUint(".general.TEST_ENV_MOCK_FINALIZE_TIMEOUT_SEC");

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

        L2GETH_SIGNER_0_ADDRESS = cfg.readAddress(".accounts.L2GETH_SIGNER_0_ADDRESS");

        SCROLL_DB_CONNECTION_STRING = cfg.readString(".db.SCROLL_DB_CONNECTION_STRING");
        CHAIN_MONITOR_DB_CONNECTION_STRING = cfg.readString(".db.CHAIN_MONITOR_DB_CONNECTION_STRING");
        BRIDGE_HISTORY_DB_CONNECTION_STRING = cfg.readString(".db.BRIDGE_HISTORY_DB_CONNECTION_STRING");
        ROLLUP_EXPLORER_BACKEND_DB_CONNECTION_STRING = cfg.readString(".db.ROLLUP_EXPLORER_DB_CONNECTION_STRING");

        L2_MAX_ETH_SUPPLY = cfg.readUint(".genesis.L2_MAX_ETH_SUPPLY");
        L2_DEPLOYER_INITIAL_BALANCE = cfg.readUint(".genesis.L2_DEPLOYER_INITIAL_BALANCE");
        L2_SCROLL_MESSENGER_INITIAL_BALANCE = L2_MAX_ETH_SUPPLY - L2_DEPLOYER_INITIAL_BALANCE;

        DEPLOYMENT_SALT = cfg.readString(".contracts.DEPLOYMENT_SALT");

        L1_FEE_VAULT_ADDR = cfg.readAddress(".contracts.L1_FEE_VAULT_ADDR");
        L1_PLONK_VERIFIER_ADDR = cfg.readAddress(".contracts.L1_PLONK_VERIFIER_ADDR");

        COORDINATOR_JWT_SECRET_KEY = cfg.readString(".coordinator.COORDINATOR_JWT_SECRET_KEY");

        EXTERNAL_RPC_URI_L1 = cfg.readString(".frontend.EXTERNAL_RPC_URI_L1");
        EXTERNAL_RPC_URI_L2 = cfg.readString(".frontend.EXTERNAL_RPC_URI_L2");
        BRIDGE_API_URI = cfg.readString(".frontend.BRIDGE_API_URI");
        ROLLUPSCAN_API_URI = cfg.readString(".frontend.ROLLUPSCAN_API_URI");
        EXTERNAL_EXPLORER_URI_L1 = cfg.readString(".frontend.EXTERNAL_EXPLORER_URI_L1");
        EXTERNAL_EXPLORER_URI_L2 = cfg.readString(".frontend.EXTERNAL_EXPLORER_URI_L2");

        runSanityCheck();
    }

    /**********************
     * Internal interface *
     **********************/

    /// @dev Ensure that `addr` is not the zero address.
    ///      This helps catch bugs arising from incorrect deployment order.
    function notnull(address addr) internal pure returns (address) {
        require(addr != address(0), "null address");
        return addr;
    }

    function tryGetOverride(string memory name) internal returns (address) {
        address addr;
        string memory key = string(abi.encodePacked(".contracts.overrides.", name));

        if (!vm.keyExistsToml(cfg, key)) {
            return address(0);
        }

        addr = cfg.readAddress(key);

        if (addr.code.length == 0) {
            (VmSafe.CallerMode callerMode, , ) = vm.readCallers();

            // if we're ready to start broadcasting transactions, then we
            // must ensure that the override contract has been deployed.
            if (callerMode == VmSafe.CallerMode.Broadcast || callerMode == VmSafe.CallerMode.RecurrentBroadcast) {
                revert(
                    string(
                        abi.encodePacked(
                            "[ERROR] override ",
                            name,
                            " = ",
                            vm.toString(addr),
                            " not deployed in broadcast mode"
                        )
                    )
                );
            }
        }

        return addr;
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
