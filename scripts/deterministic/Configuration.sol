// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.24;

import {Script} from "forge-std/Script.sol";
import {VmSafe} from "forge-std/Vm.sol";
import {stdToml} from "forge-std/StdToml.sol";

abstract contract Configuration is Script {
    using stdToml for string;

    /*******************
     * State variables *
     *******************/

    string internal cfg;
    string internal contractsCfg;

    /**********************
     * Internal interface *
     **********************/

    function initialize(string memory workdir) internal {
        string memory cfgPath = string(abi.encodePacked(workdir, "/config.toml"));
        cfg = vm.readFile(cfgPath);

        string memory contractsCfgPath = string(abi.encodePacked(workdir, "/config-contracts.toml"));
        contractsCfg = vm.readFile(contractsCfgPath);
    }

    function readUint(string memory key) internal view returns (uint256) {
        return cfg.readUint(key);
    }

    function readAddress(string memory key) internal view returns (address) {
        return cfg.readAddress(key);
    }

    function readString(string memory key) internal view returns (string memory) {
        return cfg.readString(key);
    }

    function writeToml(address addr, string memory tomlPath) internal {
        vm.writeToml(vm.toString(addr), cfg, tomlPath);
    }

    /// @dev Ensure that `addr` is not the zero address.
    ///      This helps catch bugs arising from incorrect deployment order.
    function notnull(address addr) internal pure returns (address) {
        require(addr != address(0), "null address");
        return addr;
    }

    function tryGetOverride(string memory name) internal returns (address) {
        address addr;
        string memory key;
        if (keccak256(abi.encodePacked(name)) == keccak256(abi.encodePacked("L1_GAS_TOKEN"))) {
            key = string(abi.encodePacked(".gas-token.", name));
        } else {
            key = string(abi.encodePacked(".contracts.overrides.", name));
        }

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
}
