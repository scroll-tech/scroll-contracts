// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.24;

import { Script } from "forge-std/Script.sol";
import { SystemConfig } from "../../src/L1/system-contract/SystemConfig.sol";
import { ScrollOwner } from "../../src/misc/ScrollOwner.sol"; // Adjust this path as needed

/**
 * @title InitializeL1SystemConfig
 * @notice Configures the deployed SystemConfig contract.
 *         This script grants the Security Council (as defined by L1_SECURITY_COUNCIL_ADDR)
 *         access to call updateSigner() on the SystemConfig contract with no delay.
 */
contract InitializeL1SystemConfig is Script {
    function run() external {
        // Retrieve required environment variables.
        uint256 deployerKey = vm.envUint("L1_DEPLOYER_PRIVATE_KEY");
        address systemConfigAddr = vm.envAddress("SYSTEM_CONTRACT_ADDR");
        address securityCouncilAddr = vm.envAddress("L1_SECURITY_COUNCIL_ADDR");
        address scrollOwnerAddr = vm.envAddress("L1_SCROLL_OWNER_ADDR");
        
        // Compute the role hash for the Security Council with no delay.
        bytes32 SECURITY_COUNCIL_NO_DELAY_ROLE = keccak256("SECURITY_COUNCIL_NO_DELAY_ROLE");

        vm.startBroadcast(deployerKey);

        // Instantiate the ScrollOwner contract instance which manages access control.
        ScrollOwner owner = ScrollOwner(payable(scrollOwnerAddr));
        // Instantiate the already-deployed SystemConfig contract.
        SystemConfig sys = SystemConfig(systemConfigAddr);

        // Prepare a single-element array containing the function selector for updateSigner.
        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = sys.updateSigner.selector;

        // Grant the SECURITY_COUNCIL_NO_DELAY_ROLE permission on SystemConfig,
        // so that the Security Council address can call updateSigner() with no delay.
        owner.updateAccess(
            systemConfigAddr,           // Address of the SystemConfig contract.
            selectors,                  // The function selectors (only updateSigner here).
            SECURITY_COUNCIL_NO_DELAY_ROLE,
            true                        // Grant access.
        );

        vm.stopBroadcast();
    }
}