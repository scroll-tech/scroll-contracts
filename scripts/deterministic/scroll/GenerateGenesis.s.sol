// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.24;

import {L1GasPriceOracle} from "../../../src/L2/predeploys/L1GasPriceOracle.sol";
import {L2MessageQueue} from "../../../src/L2/predeploys/L2MessageQueue.sol";
import {L2TxFeeVault} from "../../../src/L2/predeploys/L2TxFeeVault.sol";
import {Whitelist} from "../../../src/L2/predeploys/Whitelist.sol";
import {WrappedEther} from "../../../src/L2/predeploys/WrappedEther.sol";

import {FEE_VAULT_MIN_WITHDRAW_AMOUNT, GENESIS_ALLOC_JSON_PATH, GENESIS_JSON_PATH, GENESIS_JSON_TEMPLATE_PATH} from "./Constants.sol";
import {DeployScroll} from "./DeployScroll.s.sol";
import {DeterministicDeployment, DETERMINISTIC_DEPLOYMENT_PROXY_ADDR} from "../DeterministicDeployment.sol";

contract GenerateGenesis is DeployScroll {
    /***************
     * Entry point *
     ***************/

    function run(string memory workdir) public {
        DeterministicDeployment.initialize(ScriptMode.VerifyConfig, workdir);
        predictAllContracts();

        generateGenesisAlloc();
        generateGenesisJson();

        // clean up temporary files
        vm.removeFile(GENESIS_ALLOC_JSON_PATH);
    }

    /*********************
     * Private functions *
     *********************/

    function generateGenesisAlloc() private {
        if (vm.exists(GENESIS_ALLOC_JSON_PATH)) {
            vm.removeFile(GENESIS_ALLOC_JSON_PATH);
        }

        // Scroll predeploys
        setL2MessageQueue();
        setL1GasPriceOracle();
        setL2Whitelist();
        setL2Weth();
        setL2FeeVault();

        // other predeploys
        setDeterministicDeploymentProxy();

        // reset sender
        vm.resetNonce(msg.sender);

        // prefunded accounts
        setL2ScrollMessenger();
        setL2Deployer();

        // write to file
        vm.dumpState(GENESIS_ALLOC_JSON_PATH);
        sortJsonByKeys(GENESIS_ALLOC_JSON_PATH);
    }

    function setL2MessageQueue() internal {
        address predeployAddr = tryGetOverride("L2_MESSAGE_QUEUE");

        if (predeployAddr == address(0)) {
            return;
        }

        // set code
        L2MessageQueue _queue = new L2MessageQueue(DEPLOYER_ADDR);
        vm.etch(predeployAddr, address(_queue).code);

        // set storage
        bytes32 _ownerSlot = hex"0000000000000000000000000000000000000000000000000000000000000052";
        vm.store(predeployAddr, _ownerSlot, vm.load(address(_queue), _ownerSlot));

        // reset so its not included state dump
        vm.etch(address(_queue), "");
        vm.resetNonce(address(_queue));
    }

    function setL1GasPriceOracle() internal {
        address predeployAddr = tryGetOverride("L1_GAS_PRICE_ORACLE");

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

        // reset so its not included state dump
        vm.etch(address(_oracle), "");
        vm.resetNonce(address(_oracle));
    }

    function setL2Whitelist() internal {
        address predeployAddr = tryGetOverride("L2_WHITELIST");

        if (predeployAddr == address(0)) {
            return;
        }

        // set code
        Whitelist _whitelist = new Whitelist(DEPLOYER_ADDR);
        vm.etch(predeployAddr, address(_whitelist).code);

        // set storage
        bytes32 _ownerSlot = hex"0000000000000000000000000000000000000000000000000000000000000000";
        vm.store(predeployAddr, _ownerSlot, vm.load(address(_whitelist), _ownerSlot));

        // reset so its not included state dump
        vm.etch(address(_whitelist), "");
        vm.resetNonce(address(_whitelist));
    }

    function setL2Weth() internal {
        address predeployAddr = tryGetOverride("L2_WETH");

        if (predeployAddr == address(0)) {
            return;
        }

        // set code
        WrappedEther _weth = new WrappedEther();
        vm.etch(predeployAddr, address(_weth).code);

        // set storage
        bytes32 _nameSlot = hex"0000000000000000000000000000000000000000000000000000000000000003";
        vm.store(predeployAddr, _nameSlot, vm.load(address(_weth), _nameSlot));

        bytes32 _symbolSlot = hex"0000000000000000000000000000000000000000000000000000000000000004";
        vm.store(predeployAddr, _symbolSlot, vm.load(address(_weth), _symbolSlot));

        // reset so its not included state dump
        vm.etch(address(_weth), "");
        vm.resetNonce(address(_weth));
    }

    function setL2FeeVault() internal {
        address predeployAddr = tryGetOverride("L2_TX_FEE_VAULT");

        if (predeployAddr == address(0)) {
            return;
        }

        // set code
        address _vaultAddr;
        vm.prank(DEPLOYER_ADDR);
        L2TxFeeVault _vault = new L2TxFeeVault(DEPLOYER_ADDR, L1_FEE_VAULT_ADDR, FEE_VAULT_MIN_WITHDRAW_AMOUNT);
        vm.prank(DEPLOYER_ADDR);
        _vault.updateMessenger(L2_SCROLL_MESSENGER_PROXY_ADDR);
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

        bytes32 _ETHGatewaySlot = hex"0000000000000000000000000000000000000000000000000000000000000005";
        vm.store(predeployAddr, _ETHGatewaySlot, vm.load(_vaultAddr, _ETHGatewaySlot));

        // reset so its not included state dump
        vm.etch(_vaultAddr, "");
        vm.resetNonce(_vaultAddr);
    }

    function setDeterministicDeploymentProxy() internal {
        bytes
            memory code = hex"7fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffe03601600081602082378035828234f58015156039578182fd5b8082525050506014600cf3";
        vm.etch(DETERMINISTIC_DEPLOYMENT_PROXY_ADDR, code);
    }

    function setL2ScrollMessenger() internal {
        vm.deal(L2_SCROLL_MESSENGER_PROXY_ADDR, L2_SCROLL_MESSENGER_INITIAL_BALANCE);
    }

    function setL2Deployer() internal {
        vm.deal(DEPLOYER_ADDR, L2_DEPLOYER_INITIAL_BALANCE);
    }

    function generateGenesisJson() private {
        // initialize template file
        if (vm.exists(GENESIS_JSON_PATH)) {
            vm.removeFile(GENESIS_JSON_PATH);
        }

        string memory template = vm.readFile(GENESIS_JSON_TEMPLATE_PATH);
        vm.writeFile(GENESIS_JSON_PATH, template);

        // general config
        vm.writeJson(vm.toString(CHAIN_ID_L2), GENESIS_JSON_PATH, ".config.chainId");

        uint256 timestamp = vm.unixTime() / 1000;
        vm.writeJson(vm.toString(bytes32(timestamp)), GENESIS_JSON_PATH, ".timestamp");

        string memory extraData = string(
            abi.encodePacked(
                "0x0000000000000000000000000000000000000000000000000000000000000000",
                vm.replace(vm.toString(L2GETH_SIGNER_ADDRESS), "0x", ""),
                "0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"
            )
        );

        vm.writeJson(extraData, GENESIS_JSON_PATH, ".extraData");

        // scroll-specific config
        vm.writeJson(vm.toString(MAX_TX_IN_CHUNK), GENESIS_JSON_PATH, ".config.scroll.maxTxPerBlock");
        vm.writeJson(vm.toString(L2_TX_FEE_VAULT_ADDR), GENESIS_JSON_PATH, ".config.scroll.feeVaultAddress");

        // serialize explicitly as string, otherwise foundry will serialize it as number
        string memory l1ChainId = string(abi.encodePacked('"', vm.toString(CHAIN_ID_L1), '"'));
        vm.writeJson(l1ChainId, GENESIS_JSON_PATH, ".config.scroll.l1Config.l1ChainId");

        vm.writeJson(
            vm.toString(SYSTEM_CONFIG_PROXY_ADDR),
            GENESIS_JSON_PATH,
            ".config.systemContract.system_contract_address"
        );

        vm.writeJson(
            vm.toString(L1_MESSAGE_QUEUE_V1_PROXY_ADDR),
            GENESIS_JSON_PATH,
            ".config.scroll.l1Config.l1MessageQueueAddress"
        );

        vm.writeJson(
            vm.toString(L1_MESSAGE_QUEUE_V2_PROXY_ADDR),
            GENESIS_JSON_PATH,
            ".config.scroll.l1Config.l1MessageQueueV2Address"
        );

        vm.writeJson(
            vm.toString(L1_SCROLL_CHAIN_PROXY_ADDR),
            GENESIS_JSON_PATH,
            ".config.scroll.l1Config.scrollChainAddress"
        );

        // predeploys and prefunded accounts
        string memory alloc = vm.readFile(GENESIS_ALLOC_JSON_PATH);
        vm.writeJson(alloc, GENESIS_JSON_PATH, ".alloc");
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
