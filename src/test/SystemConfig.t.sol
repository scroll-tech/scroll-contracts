// SPDX-License-Identifier: MIT

pragma solidity =0.8.24;

import {ITransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import {SystemConfig} from "../L1/system-contract/SystemConfig.sol";

import {ScrollTestBase} from "./ScrollTestBase.t.sol";

contract SystemConfigTest is ScrollTestBase {
    SystemConfig private system;

    function setUp() public {
        __ScrollTestBase_setUp();

        system = SystemConfig(_deployProxy(address(0)));

        // Upgrade the SystemConfig implementation and initialize
        admin.upgrade(ITransparentUpgradeableProxy(address(system)), address(new SystemConfig()));
        system.initialize(
            address(this),
            address(uint160(1)),
            SystemConfig.MessageQueueParameters({maxGasLimit: 1, baseFeeOverhead: 2, baseFeeScalar: 3}),
            SystemConfig.EnforcedBatchParameters({maxDelayEnterEnforcedMode: 4, maxDelayMessageQueue: 5})
        );
    }

    function testInitialize() external {
        assertEq(system.owner(), address(this));
        assertEq(system.getSigner(), address(uint160(1)));
        (uint256 maxGasLimit, uint256 baseFeeOverhead, uint256 baseFeeScalar) = system.messageQueueParameters();
        assertEq(maxGasLimit, 1);
        assertEq(baseFeeOverhead, 2);
        assertEq(baseFeeScalar, 3);
        (uint256 maxDelayEnterEnforcedMode, uint256 maxDelayMessageQueue) = system.enforcedBatchParameters();
        assertEq(maxDelayEnterEnforcedMode, 4);
        assertEq(maxDelayMessageQueue, 5);

        hevm.expectRevert("Initializable: contract is already initialized");
        system.initialize(
            address(this),
            address(uint160(1)),
            SystemConfig.MessageQueueParameters({maxGasLimit: 1, baseFeeOverhead: 2, baseFeeScalar: 3}),
            SystemConfig.EnforcedBatchParameters({maxDelayEnterEnforcedMode: 4, maxDelayMessageQueue: 5})
        );
    }

    function testUpdateMessageQueueParameters(SystemConfig.MessageQueueParameters memory params) external {
        // set by non-owner, should revert
        hevm.startPrank(address(1));
        hevm.expectRevert("Ownable: caller is not the owner");
        system.updateMessageQueueParameters(params);
        hevm.stopPrank();

        // succeed
        system.updateMessageQueueParameters(params);
        (uint256 maxGasLimit, uint256 baseFeeOverhead, uint256 baseFeeScalar) = system.messageQueueParameters();
        assertEq(maxGasLimit, params.maxGasLimit);
        assertEq(baseFeeOverhead, params.baseFeeOverhead);
        assertEq(baseFeeScalar, params.baseFeeScalar);
    }

    function testUpdateEnforcedBatchParameters(SystemConfig.EnforcedBatchParameters memory params) external {
        // set by non-owner, should revert
        hevm.startPrank(address(1));
        hevm.expectRevert("Ownable: caller is not the owner");
        system.updateEnforcedBatchParameters(params);
        hevm.stopPrank();

        // succeed
        system.updateEnforcedBatchParameters(params);
        (uint256 maxDelayEnterEnforcedMode, uint256 maxDelayMessageQueue) = system.enforcedBatchParameters();
        assertEq(maxDelayEnterEnforcedMode, params.maxDelayEnterEnforcedMode);
        assertEq(maxDelayMessageQueue, params.maxDelayMessageQueue);
    }

    function testUpdateSigner(address signer) external {
        // set by non-owner, should revert
        hevm.startPrank(address(1));
        hevm.expectRevert("Ownable: caller is not the owner");
        system.updateSigner(signer);
        hevm.stopPrank();

        // succeed
        system.updateSigner(signer);
        assertEq(system.getSigner(), signer);
    }
}
