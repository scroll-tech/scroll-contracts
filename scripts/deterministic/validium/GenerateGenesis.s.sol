// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.24;

import {console} from "forge-std/console.sol";

import {L1GasPriceOracle} from "../../../src/L2/predeploys/L1GasPriceOracle.sol";
import {L2MessageQueue} from "../../../src/L2/predeploys/L2MessageQueue.sol";
import {L2TxFeeVault} from "../../../src/L2/predeploys/L2TxFeeVault.sol";
import {Whitelist} from "../../../src/L2/predeploys/Whitelist.sol";

import {FEE_VAULT_MIN_WITHDRAW_AMOUNT} from "./Constants.sol";
import {DeployValidium} from "./DeployValidium.s.sol";
import {DeterministicDeployment, DETERMINISTIC_DEPLOYMENT_PROXY_ADDR, EIP_2935_HISTORY_STORAGE_ADDRESS} from "../DeterministicDeployment.sol";

contract GenerateGenesis is DeployValidium {
    /***************
     * Entry point *
     ***************/

    string private genesisAllocTmpPath;

    function run(string memory workdir) public {
        readConfig(workdir);

        string memory templatePath = string(abi.encodePacked(workdir, "/genesis.json.template"));
        string memory outPath = string(abi.encodePacked(workdir, "/genesis.json"));
        genesisAllocTmpPath = string(abi.encodePacked(workdir, "/__genesis-alloc.json"));

        DeterministicDeployment.initialize(ScriptMode.VerifyConfig, workdir);
        predictAllContracts();

        generateGenesisAlloc();
        generateGenesisJson(templatePath, outPath);

        // clean up temporary files
        vm.removeFile(genesisAllocTmpPath);
    }

    /*********************
     * Private functions *
     *********************/

    function generateGenesisAlloc() private {
        if (vm.exists(genesisAllocTmpPath)) {
            vm.removeFile(genesisAllocTmpPath);
        }

        // Scroll predeploys
        setValidiumMessageQueue();
        setValidiumGasPriceOracle();
        setValidiumWhitelist();
        setValidiumFeeVault();

        // other predeploys
        setEIP2935HistoryStorage();
        setDeterministicDeploymentProxy();
        setSafeSingletonFactory();

        // reset sender
        vm.resetNonce(msg.sender);

        // prefunded accounts
        prefundValidiumMessenger();
        prefundL2Deployer();

        // write to file
        vm.dumpState(genesisAllocTmpPath);
        sortJsonByKeys(genesisAllocTmpPath);
    }

    function setValidiumMessageQueue() internal {
        address predeployAddr = tryGetOverride("VALIDIUM_MESSAGE_QUEUE");

        if (predeployAddr == address(0)) {
            return;
        }

        // set code
        L2MessageQueue _queue = new L2MessageQueue(DEPLOYER_ADDR);
        vm.etch(predeployAddr, address(_queue).code);

        // set storage
        bytes32 _ownerSlot = hex"0000000000000000000000000000000000000000000000000000000000000052";
        vm.store(predeployAddr, _ownerSlot, vm.load(address(_queue), _ownerSlot));

        // reset so it's not included state dump
        vm.etch(address(_queue), "");
        vm.resetNonce(address(_queue));
    }

    function setValidiumGasPriceOracle() internal {
        address predeployAddr = tryGetOverride("VALIDIUM_GAS_PRICE_ORACLE");

        if (predeployAddr == address(0)) {
            return;
        }

        // set code
        L1GasPriceOracle _oracle = new L1GasPriceOracle(DEPLOYER_ADDR);
        vm.etch(predeployAddr, address(_oracle).code);

        // set storage
        bytes32 _ownerSlot = hex"0000000000000000000000000000000000000000000000000000000000000000";
        vm.store(predeployAddr, _ownerSlot, vm.load(address(_oracle), _ownerSlot));

        bytes32 _isCurieSlot = hex"0000000000000000000000000000000000000000000000000000000000000008";
        vm.store(predeployAddr, _isCurieSlot, bytes32(uint256(1)));

        bytes32 _penaltyThresholdSlot = hex"0000000000000000000000000000000000000000000000000000000000000009";
        vm.store(predeployAddr, _penaltyThresholdSlot, bytes32(uint256(1e9)));

        bytes32 _penaltyFactorSlot = hex"000000000000000000000000000000000000000000000000000000000000000a";
        vm.store(predeployAddr, _penaltyFactorSlot, bytes32(uint256(1e9)));

        bytes32 _isFeynmanSlot = hex"000000000000000000000000000000000000000000000000000000000000000b";
        vm.store(predeployAddr, _isFeynmanSlot, bytes32(uint256(1)));

        bytes32 _isGalileoSlot = hex"000000000000000000000000000000000000000000000000000000000000000c";
        vm.store(predeployAddr, _isGalileoSlot, bytes32(uint256(1)));

        // reset so it's not included state dump
        vm.etch(address(_oracle), "");
        vm.resetNonce(address(_oracle));
    }

    function setValidiumWhitelist() internal {
        address predeployAddr = tryGetOverride("VALIDIUM_GAS_PRICE_ORACLE_WHITELIST");

        if (predeployAddr == address(0)) {
            return;
        }

        // set code
        Whitelist _whitelist = new Whitelist(DEPLOYER_ADDR);
        vm.etch(predeployAddr, address(_whitelist).code);

        // set storage
        bytes32 _ownerSlot = hex"0000000000000000000000000000000000000000000000000000000000000000";
        vm.store(predeployAddr, _ownerSlot, vm.load(address(_whitelist), _ownerSlot));

        // reset so it's not included state dump
        vm.etch(address(_whitelist), "");
        vm.resetNonce(address(_whitelist));
    }

    function setValidiumFeeVault() internal {
        address predeployAddr = tryGetOverride("VALIDIUM_TX_FEE_VAULT");

        if (predeployAddr == address(0)) {
            return;
        }

        // set code
        address _vaultAddr;
        vm.prank(DEPLOYER_ADDR);
        L2TxFeeVault _vault = new L2TxFeeVault(DEPLOYER_ADDR, L1_FEE_VAULT_ADDR, FEE_VAULT_MIN_WITHDRAW_AMOUNT);
        vm.prank(DEPLOYER_ADDR);
        _vault.updateMessenger(VALIDIUM_MESSENGER_ADDR);
        _vaultAddr = address(_vault);

        vm.etch(predeployAddr, _vaultAddr.code);

        // set storage
        bytes32 _ownerSlot = hex"0000000000000000000000000000000000000000000000000000000000000000";
        vm.store(predeployAddr, _ownerSlot, vm.load(_vaultAddr, _ownerSlot));

        bytes32 _minWithdrawAmountSlot = hex"0000000000000000000000000000000000000000000000000000000000000001";
        vm.store(predeployAddr, _minWithdrawAmountSlot, vm.load(_vaultAddr, _minWithdrawAmountSlot));

        bytes32 _messengerSlot = hex"0000000000000000000000000000000000000000000000000000000000000002";
        vm.store(predeployAddr, _messengerSlot, vm.load(_vaultAddr, _messengerSlot));

        bytes32 _recipientSlot = hex"0000000000000000000000000000000000000000000000000000000000000003";
        vm.store(predeployAddr, _recipientSlot, vm.load(_vaultAddr, _recipientSlot));

        // reset so it's not included state dump
        vm.etch(_vaultAddr, "");
        vm.resetNonce(_vaultAddr);
    }

    function setEIP2935HistoryStorage() internal {
        bytes
            memory code = hex"3373fffffffffffffffffffffffffffffffffffffffe14604657602036036042575f35600143038111604257611fff81430311604257611fff9006545f5260205ff35b5f5ffd5b5f35611fff60014303065500";
        vm.etch(EIP_2935_HISTORY_STORAGE_ADDRESS, code);
    }

    function setDeterministicDeploymentProxy() internal {
        bytes
            memory code = hex"7fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffe03601600081602082378035828234f58015156039578182fd5b8082525050506014600cf3";
        vm.etch(DETERMINISTIC_DEPLOYMENT_PROXY_ADDR, code);
    }

    function setSafeSingletonFactory() internal {
        bytes
            memory code = hex"7fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffe03601600081602082378035828234f58015156039578182fd5b8082525050506014600cf3";
        vm.etch(0x914d7Fec6aaC8cd542e72Bca78B30650d45643d7, code);
    }

    function prefundValidiumMessenger() internal {
        vm.deal(VALIDIUM_MESSENGER_ADDR, VALIDIUM_MESSENGER_INITIAL_BALANCE);
    }

    function prefundL2Deployer() internal {
        vm.deal(DEPLOYER_ADDR, VALIDIUM_DEPLOYER_INITIAL_BALANCE);
    }

    function generateGenesisJson(string memory templatePath, string memory outPath) private {
        // initialize template file
        if (vm.exists(outPath)) {
            vm.removeFile(outPath);
        }

        string memory template = vm.readFile(templatePath);
        vm.writeFile(outPath, template);

        // general config
        vm.writeJson(vm.toString(CHAIN_ID_VALIDIUM), outPath, ".config.chainId");

        uint256 timestamp = vm.unixTime() / 1000;
        vm.writeJson(vm.toString(bytes32(timestamp)), outPath, ".timestamp");

        // serialize explicitly as string, otherwise foundry will serialize it as number
        string memory gasLimit = string(abi.encodePacked('"', vm.toString(VALIDIUM_GAS_LIMIT), '"'));
        vm.writeJson(gasLimit, outPath, ".gasLimit");

        // scroll-specific config
        vm.writeJson(vm.toString(HOST_SYSTEM_CONFIG_ADDR), outPath, ".config.systemContract.system_contract_address");

        vm.writeJson(vm.toString(VALIDIUM_TX_FEE_VAULT_ADDR), outPath, ".config.scroll.feeVaultAddress");

        // serialize explicitly as string, otherwise foundry will serialize it as number
        string memory l1ChainId = string(abi.encodePacked('"', vm.toString(CHAIN_ID_HOST), '"'));
        vm.writeJson(l1ChainId, outPath, ".config.scroll.l1Config.l1ChainId");

        vm.writeJson(vm.toString(HOST_MESSAGE_QUEUE_ADDR), outPath, ".config.scroll.l1Config.l1MessageQueueV2Address");

        vm.writeJson(vm.toString(HOST_VALIDIUM_ADDR), outPath, ".config.scroll.l1Config.scrollChainAddress");

        vm.writeJson(
            vm.toString(VALIDIUM_SYSTEM_CONFIG_ADDR),
            outPath,
            ".config.scroll.l1Config.l2SystemConfigAddress"
        );

        // predeploys and prefunded accounts
        string memory alloc = vm.readFile(genesisAllocTmpPath);
        vm.writeJson(alloc, outPath, ".alloc");
    }

    /// @notice Sorts the allocs by address
    // source: https://github.com/ethereum-optimism/optimism/blob/develop/packages/contracts-bedrock/scripts/L2Genesis.s.sol
    function sortJsonByKeys(string memory _path) private {
        string[] memory commands = new string[](3);
        commands[0] = "/bin/bash";
        commands[1] = "-c";
        commands[2] = string.concat("cat <<< $(jq -S '.' ", _path, ") > ", _path);
        vm.ffi(commands);
    }
}
