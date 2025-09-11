// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.24;

import {stdToml} from "forge-std/StdToml.sol";

import {Configuration} from "../Configuration.sol";

/// @notice Configuration allows inheriting contracts to read the TOML configuration file.
abstract contract ValidiumConfiguration is Configuration {
    using stdToml for string;

    /****************************
     * Configuration parameters *
     ****************************/

    // general
    uint64 internal CHAIN_ID_HOST;
    uint64 internal CHAIN_ID_VALIDIUM;

    uint256 internal VALIDIUM_GAS_LIMIT;
    uint256 internal VALIDIUM_MAX_ETH_SUPPLY;
    uint256 internal VALIDIUM_DEPLOYER_INITIAL_BALANCE;
    uint256 internal VALIDIUM_MESSENGER_INITIAL_BALANCE;

    // accounts
    address internal DEPLOYER_ADDR;
    address internal OWNER_ADDR;
    address internal L1_FEE_VAULT_ADDR;
    address internal SEQUENCER_SIGNER_ADDRESS;
    address internal COMMIT_SENDER_ADDR;
    address internal FINALIZE_SENDER_ADDR;
    address internal FAST_WITHDRAW_SIGNER_ADDR;

    // keys
    uint256 internal DEPLOYER_PRIVATE_KEY;
    string internal SEQUENCER_ENCRYPTION_KEY;
    string internal SEQUENCER_DECRYPTION_KEY;

    /**********************
     * Internal interface *
     **********************/

    function readConfig(string memory workdir) internal {
        super.initialize(workdir);

        CHAIN_ID_HOST = uint64(cfg.readUint(".general.chain_id_host"));
        CHAIN_ID_VALIDIUM = uint64(cfg.readUint(".general.chain_id_validium"));

        VALIDIUM_GAS_LIMIT = cfg.readUint(".general.gas_limit");
        VALIDIUM_MAX_ETH_SUPPLY = cfg.readUint(".general.max_eth_supply");
        VALIDIUM_DEPLOYER_INITIAL_BALANCE = cfg.readUint(".general.deployer_initial_balance");
        VALIDIUM_MESSENGER_INITIAL_BALANCE = VALIDIUM_MAX_ETH_SUPPLY - VALIDIUM_DEPLOYER_INITIAL_BALANCE;

        DEPLOYER_ADDR = cfg.readAddress(".accounts.deployer");
        OWNER_ADDR = cfg.readAddress(".accounts.owner");
        L1_FEE_VAULT_ADDR = cfg.readAddress(".accounts.fee_vault");
        SEQUENCER_SIGNER_ADDRESS = cfg.readAddress(".accounts.sequencer");
        COMMIT_SENDER_ADDR = cfg.readAddress(".accounts.commit_sender");
        FINALIZE_SENDER_ADDR = cfg.readAddress(".accounts.finalize_sender");
        FAST_WITHDRAW_SIGNER_ADDR = cfg.readAddress(".accounts.fast_withdraw_signer");

        DEPLOYER_PRIVATE_KEY = cfg.readUint(".keys.deployer");
        SEQUENCER_ENCRYPTION_KEY = cfg.readString(".keys.sequencer_encryption");
        SEQUENCER_DECRYPTION_KEY = cfg.readString(".keys.sequencer_decryption");
    }
}
