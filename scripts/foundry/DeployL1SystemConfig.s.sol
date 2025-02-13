// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.24;

import {Script} from "forge-std/Script.sol";
import {SystemConfig} from "../../src/L1/system-contract/SystemConfig.sol"; // adjust the relative path as necessary
import {console} from "forge-std/console.sol";

contract DeployL1SystemConfig is Script {
    function run() external {
        // Retrieve the deployer private key from environment variables
        uint256 deployerKey = vm.envUint("L1_DEPLOYER_PRIVATE_KEY");

        vm.startBroadcast(deployerKey);

        // Deploy the SystemConfig contract with the specified owner.
        SystemConfig sysConfig = new SystemConfig();

        console.log("Deployed SystemConfig Implementation at address:", address(sysConfig));

        vm.stopBroadcast();
    }
}
