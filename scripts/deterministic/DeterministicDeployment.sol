// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.24;

import {console} from "forge-std/Script.sol";
import {stdToml} from "forge-std/StdToml.sol";

import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {ITransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ERC1967Upgrade} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Upgrade.sol";

import {Configuration} from "./Configuration.sol";

/// @dev The address of DeterministicDeploymentProxy.
///      See https://github.com/Arachnid/deterministic-deployment-proxy.
address constant DETERMINISTIC_DEPLOYMENT_PROXY_ADDR = 0x4e59b44847b379578588920cA78FbF26c0B4956C;

/// @notice DeterministicDeployment provides utilities for deterministic contract deployments.
abstract contract DeterministicDeployment is Configuration {
    using stdToml for string;

    /*********
     * Types *
     *********/

    enum ScriptMode {
        None,
        LogAddresses,
        WriteConfig,
        VerifyConfig,
        EmptyConfig
    }

    /*******************
     * State variables *
     *******************/

    ScriptMode private mode;
    string private saltPrefix;
    bool private skipDeploy;

    /**********************
     * Internal interface *
     **********************/

    function initialize(ScriptMode _mode, string memory workdir) internal {
        mode = _mode;
        skipDeploy = false;

        if (mode != ScriptMode.EmptyConfig) {
            super.initialize(workdir);
        }

        // salt prefix used for deterministic deployments
        string memory DEPLOYMENT_SALT = readString(".contracts.DEPLOYMENT_SALT");
        if (bytes(DEPLOYMENT_SALT).length != 0) {
            saltPrefix = DEPLOYMENT_SALT;
        } else {
            revert("Missing deployment salt");
        }

        // sanity check: make sure DeterministicDeploymentProxy exists
        if (DETERMINISTIC_DEPLOYMENT_PROXY_ADDR.code.length == 0) {
            revert(
                string(
                    abi.encodePacked(
                        "[ERROR] DeterministicDeploymentProxy (",
                        vm.toString(DETERMINISTIC_DEPLOYMENT_PROXY_ADDR),
                        ") is not available"
                    )
                )
            );
        }
    }

    function parseScriptMode(string memory scriptMode) internal pure returns (ScriptMode) {
        if (keccak256(bytes(scriptMode)) == keccak256(bytes("log-addresses"))) {
            return ScriptMode.LogAddresses;
        } else if (keccak256(bytes(scriptMode)) == keccak256(bytes("write-config"))) {
            return ScriptMode.WriteConfig;
        } else if (keccak256(bytes(scriptMode)) == keccak256(bytes("verify-config"))) {
            return ScriptMode.VerifyConfig;
        } else {
            return ScriptMode.None;
        }
    }

    function skipDeployment() internal {
        skipDeploy = true;
    }

    function deploy(string memory name, bytes memory codeWithArgs) internal returns (address) {
        return _deploy(name, codeWithArgs);
    }

    function deploy(
        string memory name,
        bytes memory code,
        bytes memory args
    ) internal returns (address) {
        return _deploy(name, abi.encodePacked(code, args));
    }

    function predict(string memory name, bytes memory codeWithArgs) internal view returns (address) {
        return _predict(name, codeWithArgs);
    }

    function predict(
        string memory name,
        bytes memory code,
        bytes memory args
    ) internal view returns (address) {
        return _predict(name, abi.encodePacked(code, args));
    }

    function upgrade(
        address proxyAdminAddr,
        address proxyAddr,
        address implAddr
    ) internal {
        address addr = _getImplementation(proxyAddr);

        if (!skipDeploy && addr != implAddr) {
            ProxyAdmin(notnull(proxyAdminAddr)).upgrade(
                ITransparentUpgradeableProxy(notnull(proxyAddr)),
                notnull(implAddr)
            );
        }
    }

    function getInitializeCount(address contractAddr) internal view returns (uint8) {
        bytes32 slotValue = vm.load(address(contractAddr), bytes32(uint256(0)));
        return uint8(uint256(slotValue));
    }

    /*********************
     * Private functions *
     *********************/

    function _getSalt(string memory name) private view returns (bytes32) {
        return keccak256(abi.encodePacked(saltPrefix, name));
    }

    function _deploy(string memory name, bytes memory codeWithArgs) private returns (address) {
        // check override (mainly used with predeploys)
        address addr = tryGetOverride(name);

        if (addr != address(0)) {
            _label(name, addr);
            return addr;
        }

        // predict determinstic deployment address
        addr = _predict(name, codeWithArgs);
        _label(name, addr);

        if (skipDeploy) {
            return addr;
        }

        // skip if the contract is already deployed
        if (addr.code.length > 0) {
            return addr;
        }

        // deploy contract
        bytes32 salt = _getSalt(name);
        bytes memory data = abi.encodePacked(salt, codeWithArgs);
        (bool success, ) = DETERMINISTIC_DEPLOYMENT_PROXY_ADDR.call(data);
        require(success, "call failed");
        require(addr.code.length != 0, "deployment address mismatch");

        return addr;
    }

    function _predict(string memory name, bytes memory codeWithArgs) private view returns (address) {
        bytes32 salt = _getSalt(name);

        return
            address(
                uint160(
                    uint256(
                        keccak256(
                            abi.encodePacked(
                                bytes1(0xff),
                                DETERMINISTIC_DEPLOYMENT_PROXY_ADDR,
                                salt,
                                keccak256(codeWithArgs)
                            )
                        )
                    )
                )
            );
    }

    function _label(string memory name, address addr) internal {
        vm.label(addr, name);

        if (mode == ScriptMode.None) {
            return;
        }

        if (mode == ScriptMode.LogAddresses) {
            console.log(string(abi.encodePacked(name, "_ADDR=", vm.toString(address(addr)))));
            return;
        }

        string memory tomlPath = string(abi.encodePacked(".", name, "_ADDR"));

        if (mode == ScriptMode.WriteConfig) {
            writeToml(addr, tomlPath);
            return;
        }

        if (mode == ScriptMode.VerifyConfig) {
            address expectedAddr = contractsCfg.readAddress(tomlPath);

            if (addr != expectedAddr) {
                revert(
                    string(
                        abi.encodePacked(
                            "[ERROR] unexpected address for ",
                            name,
                            ", expected = ",
                            vm.toString(expectedAddr),
                            " (from toml config), got = ",
                            vm.toString(addr)
                        )
                    )
                );
            }
        }
    }

    function _getImplementation(address proxyAddr) private view returns (address) {
        // ERC1967Upgrade implementation slot
        bytes32 _IMPLEMENTATION_SLOT = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;
        // get implementation address
        return address(uint160(uint256(vm.load(address(proxyAddr), _IMPLEMENTATION_SLOT))));
    }
}
