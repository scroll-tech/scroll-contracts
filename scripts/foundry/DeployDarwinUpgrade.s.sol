// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.24;

// solhint-disable no-console
// solhint-disable var-name-mixedcase
// solhint-disable state-visibility

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";

import {L1MessageQueueWithGasPriceOracle} from "../../src/L1/rollup/L1MessageQueueWithGasPriceOracle.sol";
import {MultipleVersionRollupVerifier} from "../../src/L1/rollup/MultipleVersionRollupVerifier.sol";
import {ScrollChain} from "../../src/L1/rollup/ScrollChain.sol";
import {ITransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";

contract DeployDarwinUpgrade is Script {
    address L1_PROXY_ADMIN_ADDR = vm.envAddress("L1_PROXY_ADMIN_ADDR");
    address L1_SCROLL_CHAIN_PROXY_ADDR = vm.envAddress("L1_SCROLL_CHAIN_PROXY_ADDR");
    address L1_MESSAGE_QUEUE_PROXY_ADDR = vm.envAddress("L1_MESSAGE_QUEUE_PROXY_ADDR");
    address L1_SCROLL_MESSENGER_PROXY_ADDR = vm.envAddress("L1_SCROLL_MESSENGER_PROXY_ADDR");
    address L2_SCROLL_MESSENGER_PROXY_ADDR = vm.envAddress("L2_SCROLL_MESSENGER_PROXY_ADDR");
    address L1_ENFORCED_TX_GATEWAY_PROXY_ADDR = vm.envAddress("L1_ENFORCED_TX_GATEWAY_PROXY_ADDR");
    uint256 FORKED_L1_SCROLL_OWNER_PRIVATE_KEY = vm.envUint("FORKED_L1_SCROLL_OWNER_PRIVATE_KEY");

    uint64 CHAIN_ID_L2 = uint64(vm.envUint("CHAIN_ID_L2"));
    address L1_ZKEVM_VERIFIER_V0_ADDR = vm.envAddress("L1_ZKEVM_VERIFIER_V0_ADDR");
    address L1_ZKEVM_VERIFIER_V1_ADDR = vm.envAddress("L1_ZKEVM_VERIFIER_V1_ADDR");
    address L1_ZKEVM_VERIFIER_V2_ADDR = vm.envAddress("L1_ZKEVM_VERIFIER_V2_ADDR");
    address L1_ZKEVM_VERIFIER_V3_ADDR = vm.envAddress("L1_ZKEVM_VERIFIER_V3_ADDR");

    function run() external {
        vm.startBroadcast(FORKED_L1_SCROLL_OWNER_PRIVATE_KEY);
        address darwinL1MessageQueue = deployL1MessageQueue();
        address darwinRollupVerifier = deployMultipleVersionRollupVerifier();
        address darwinScrollChain = deployScrollChain(darwinRollupVerifier);

        ProxyAdmin proxyAdmin = ProxyAdmin(L1_PROXY_ADMIN_ADDR);
        proxyAdmin.upgrade(ITransparentUpgradeableProxy(L1_SCROLL_CHAIN_PROXY_ADDR), darwinScrollChain);
        proxyAdmin.upgrade(ITransparentUpgradeableProxy(L1_MESSAGE_QUEUE_PROXY_ADDR), darwinL1MessageQueue);
        vm.stopBroadcast();
    }

    function deployL1MessageQueue() internal returns (address) {
        L1MessageQueueWithGasPriceOracle impl = new L1MessageQueueWithGasPriceOracle(
            L1_SCROLL_MESSENGER_PROXY_ADDR,
            L1_SCROLL_CHAIN_PROXY_ADDR,
            L1_ENFORCED_TX_GATEWAY_PROXY_ADDR
        );
        logAddress("L1_MESSAGE_QUEUE_IMPLEMENTATION_ADDR", address(impl));
        return address(impl);
    }

    function deployScrollChain(address rollupVerifier) internal returns (address) {
        ScrollChain impl = new ScrollChain(CHAIN_ID_L2, L1_MESSAGE_QUEUE_PROXY_ADDR, address(rollupVerifier));
        logAddress("L1_SCROLL_CHAIN_IMPLEMENTATION_ADDR", address(impl));
        return address(impl);
    }

    function deployMultipleVersionRollupVerifier() internal returns (address) {
        uint256[] memory _versions = new uint256[](3);
        address[] memory _verifiers = new address[](3);
        _versions[0] = 0;
        _verifiers[0] = L1_ZKEVM_VERIFIER_V0_ADDR;
        _versions[1] = 1;
        _verifiers[1] = L1_ZKEVM_VERIFIER_V1_ADDR;
        _versions[2] = 2;
        _verifiers[2] = L1_ZKEVM_VERIFIER_V2_ADDR;
        _versions[2] = 3;
        _verifiers[2] = L1_ZKEVM_VERIFIER_V3_ADDR;
        MultipleVersionRollupVerifier rollupVerifier = new MultipleVersionRollupVerifier(_versions, _verifiers);

        logAddress("L1_MULTIPLE_VERSION_ROLLUP_VERIFIER_ADDR", address(rollupVerifier));
        return address(rollupVerifier);
    }

    function logAddress(string memory name, address addr) internal view {
        console.log(string(abi.encodePacked(name, "=", vm.toString(address(addr)))));
    }
}
