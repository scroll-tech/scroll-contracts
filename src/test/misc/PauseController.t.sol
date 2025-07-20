// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";

import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {ITransparentUpgradeableProxy, TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import {PauseController} from "../../misc/PauseController.sol";
import {IPausable} from "../../misc/IPausable.sol";
import {ScrollOwner} from "../../misc/ScrollOwner.sol";

contract MockPausable is IPausable {
    bool private _paused;

    function setPause(bool _status) external {
        _paused = _status;
    }

    function paused() external view returns (bool) {
        return _paused;
    }
}

contract PauseControllerTest is Test {
    event Pause(address indexed component);
    event Unpause(address indexed component);
    event ResetPauseCooldownPeriod(address indexed component);
    event UpdatePauseCooldownPeriod(uint256 oldPauseCooldownPeriod, uint256 newPauseCooldownPeriod);

    uint256 public constant PAUSE_COOLDOWN_PERIOD = 1 days;

    ProxyAdmin public admin;
    PauseController public pauseController;
    MockPausable public mockPausable;
    ScrollOwner public scrollOwner;
    address public owner;

    function setUp() public {
        owner = makeAddr("owner");
        vm.startPrank(owner);

        admin = new ProxyAdmin();
        scrollOwner = new ScrollOwner();
        PauseController impl = new PauseController(address(scrollOwner));
        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(
            address(impl),
            address(admin),
            abi.encodeCall(PauseController.initialize, (PAUSE_COOLDOWN_PERIOD))
        );
        pauseController = PauseController(address(proxy));
        mockPausable = new MockPausable();

        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = IPausable.setPause.selector;
        scrollOwner.updateAccess(address(mockPausable), selectors, pauseController.PAUSE_CONTROLLER_ROLE(), true);
        scrollOwner.grantRole(pauseController.PAUSE_CONTROLLER_ROLE(), address(pauseController));

        vm.stopPrank();

        vm.warp(1e9);
    }

    function test_Pause() public {
        vm.startPrank(owner);

        vm.expectEmit(true, false, false, true);
        emit Pause(address(mockPausable));
        pauseController.pause(mockPausable);
        assertTrue(mockPausable.paused());

        vm.stopPrank();
    }

    function test_Pause_AlreadyPaused() public {
        vm.startPrank(owner);

        pauseController.pause(mockPausable);

        vm.expectRevert(PauseController.ErrorComponentAlreadyPaused.selector);
        pauseController.pause(mockPausable);

        vm.stopPrank();
    }

    function test_Pause_CooldownPeriodNotPassed() public {
        vm.startPrank(owner);

        pauseController.pause(mockPausable);
        pauseController.unpause(mockPausable);
        uint256 lastUnpauseTime = pauseController.getLastUnpauseTime(mockPausable);
        assertEq(lastUnpauseTime, block.timestamp);

        vm.warp(lastUnpauseTime + PAUSE_COOLDOWN_PERIOD - 1);
        vm.expectRevert(PauseController.ErrorCooldownPeriodNotPassed.selector);
        pauseController.pause(mockPausable);
        assertFalse(mockPausable.paused());

        vm.warp(lastUnpauseTime + PAUSE_COOLDOWN_PERIOD);
        vm.expectRevert(PauseController.ErrorCooldownPeriodNotPassed.selector);
        pauseController.pause(mockPausable);
        assertFalse(mockPausable.paused());

        vm.warp(lastUnpauseTime + PAUSE_COOLDOWN_PERIOD + 1);
        pauseController.pause(mockPausable);
        assertTrue(mockPausable.paused());

        vm.stopPrank();
    }

    function test_Unpause() public {
        vm.startPrank(owner);

        pauseController.pause(mockPausable);

        assertEq(pauseController.getLastUnpauseTime(mockPausable), 0);
        vm.expectEmit(true, false, false, true);
        emit Unpause(address(mockPausable));
        pauseController.unpause(mockPausable);
        assertEq(pauseController.getLastUnpauseTime(mockPausable), block.timestamp);
        assertFalse(mockPausable.paused());

        // cannot pause before cooldown period
        vm.expectRevert(PauseController.ErrorCooldownPeriodNotPassed.selector);
        pauseController.pause(mockPausable);

        // reset pause cooldown period
        vm.expectEmit(true, false, false, true);
        emit ResetPauseCooldownPeriod(address(mockPausable));
        pauseController.resetPauseCooldownPeriod(mockPausable);
        assertEq(pauseController.getLastUnpauseTime(mockPausable), 0);

        // can pause after reset
        assertFalse(mockPausable.paused());
        pauseController.pause(mockPausable);
        assertTrue(mockPausable.paused());

        vm.stopPrank();
    }

    function test_Unpause_NotPaused() public {
        vm.startPrank(owner);

        vm.expectRevert(PauseController.ErrorComponentNotPaused.selector);
        pauseController.unpause(mockPausable);

        vm.stopPrank();
    }

    function test_UpdatePauseCooldownPeriod() public {
        vm.startPrank(owner);

        uint256 newCooldownPeriod = 2 days;

        vm.expectEmit(false, false, false, true);
        emit UpdatePauseCooldownPeriod(PAUSE_COOLDOWN_PERIOD, newCooldownPeriod);
        pauseController.updatePauseCooldownPeriod(newCooldownPeriod);

        assertEq(pauseController.pauseCooldownPeriod(), newCooldownPeriod);

        vm.stopPrank();
    }

    function test_UpdatePauseCooldownPeriod_NotOwner() public {
        address notOwner = makeAddr("notOwner");
        vm.startPrank(notOwner);

        vm.expectRevert("Ownable: caller is not the owner");
        pauseController.updatePauseCooldownPeriod(2 days);

        vm.stopPrank();
    }

    function test_Pause_NotOwner() public {
        address notOwner = makeAddr("notOwner");
        vm.startPrank(notOwner);

        vm.expectRevert("Ownable: caller is not the owner");
        pauseController.pause(mockPausable);

        vm.stopPrank();
    }

    function test_Unpause_NotOwner() public {
        address notOwner = makeAddr("notOwner");
        vm.startPrank(notOwner);

        vm.expectRevert("Ownable: caller is not the owner");
        pauseController.unpause(mockPausable);

        vm.stopPrank();
    }
}
