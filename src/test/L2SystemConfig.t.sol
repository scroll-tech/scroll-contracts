// SPDX-License-Identifier: MIT

pragma solidity =0.8.24;

import {Test} from "forge-std/Test.sol";

import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import {L2SystemConfig} from "../L2/L2SystemConfig.sol";

contract L2SystemConfigTest is Test {
    address public admin;
    address public owner;
    address public nonOwner;

    L2SystemConfig public l2SystemConfig;

    event BaseFeeOverheadUpdated(uint256 oldBaseFeeOverhead, uint256 newBaseFeeOverhead);
    event BaseFeeScalarUpdated(uint256 oldBaseFeeScalar, uint256 newBaseFeeScalar);

    function setUp() public {
        admin = makeAddr("admin");
        owner = makeAddr("owner");
        nonOwner = makeAddr("nonOwner");

        L2SystemConfig implementation = new L2SystemConfig();
        address proxy = address(new TransparentUpgradeableProxy(address(implementation), admin, ""));
        l2SystemConfig = L2SystemConfig(proxy);

        l2SystemConfig.initialize(owner);
    }

    function test_Initialize() public {
        // Test initialization
        assertEq(l2SystemConfig.owner(), owner);

        // revert when initialize again
        vm.expectRevert("Initializable: contract is already initialized");
        l2SystemConfig.initialize(owner);
    }

    function test_UpdateBaseFeeOverhead(uint256 newBaseFeeOverhead) public {
        // Test that only owner can update base fee overhead
        vm.prank(nonOwner);
        vm.expectRevert("Ownable: caller is not the owner");
        l2SystemConfig.updateBaseFeeOverhead(newBaseFeeOverhead);

        // Test owner can update base fee overhead
        assertEq(l2SystemConfig.baseFeeOverhead(), 0);
        vm.prank(owner);
        vm.expectEmit(true, true, true, true);
        emit BaseFeeOverheadUpdated(0, newBaseFeeOverhead);
        l2SystemConfig.updateBaseFeeOverhead(newBaseFeeOverhead);
        assertEq(l2SystemConfig.baseFeeOverhead(), newBaseFeeOverhead);
    }

    function test_UpdateBaseFeeScalar(uint256 newBaseFeeScalar) public {
        // Test that only owner can update base fee scalar
        vm.prank(nonOwner);
        vm.expectRevert("Ownable: caller is not the owner");
        l2SystemConfig.updateBaseFeeScalar(newBaseFeeScalar);

        // Test owner can update base fee scalar
        assertEq(l2SystemConfig.baseFeeScalar(), 0);
        vm.prank(owner);
        vm.expectEmit(true, true, true, true);
        emit BaseFeeScalarUpdated(0, newBaseFeeScalar);
        l2SystemConfig.updateBaseFeeScalar(newBaseFeeScalar);
        assertEq(l2SystemConfig.baseFeeScalar(), newBaseFeeScalar);
    }

    function test_GetL2BaseFee(
        uint256 l1BaseFee,
        uint256 baseFeeScalar,
        uint256 baseFeeOverhead
    ) public {
        l1BaseFee = bound(l1BaseFee, 0, type(uint64).max);
        baseFeeScalar = bound(baseFeeScalar, 0, type(uint128).max);
        baseFeeOverhead = bound(baseFeeOverhead, 0, type(uint128).max);

        // Set up the contract state
        vm.prank(owner);
        l2SystemConfig.updateBaseFeeScalar(baseFeeScalar);
        vm.prank(owner);
        l2SystemConfig.updateBaseFeeOverhead(baseFeeOverhead);

        // Calculate expected L2 base fee
        uint256 expectedL2BaseFee = (l1BaseFee * baseFeeScalar) / 1e18 + baseFeeOverhead;

        // Test getL2BaseFee function
        uint256 actualL2BaseFee = l2SystemConfig.getL2BaseFee(l1BaseFee);
        assertEq(actualL2BaseFee, expectedL2BaseFee);
    }

    function test_GetL2BaseFeeWithZeroL1BaseFee() public {
        uint256 l1BaseFee = 0;
        uint256 baseFeeScalar = 2000;
        uint256 baseFeeOverhead = 1000;

        // Set up the contract state
        vm.prank(owner);
        l2SystemConfig.updateBaseFeeScalar(baseFeeScalar);
        vm.prank(owner);
        l2SystemConfig.updateBaseFeeOverhead(baseFeeOverhead);

        // Calculate expected L2 base fee
        uint256 expectedL2BaseFee = baseFeeOverhead; // When L1 base fee is 0, only overhead is added

        // Test getL2BaseFee function
        uint256 actualL2BaseFee = l2SystemConfig.getL2BaseFee(l1BaseFee);
        assertEq(actualL2BaseFee, expectedL2BaseFee);
    }

    function test_GetL2BaseFeeWithLargeValues() public {
        uint256 l1BaseFee = 1e18; // 1 ETH
        uint256 baseFeeScalar = 2e18; // 2x multiplier
        uint256 baseFeeOverhead = 1e17; // 0.1 ETH

        // Set up the contract state
        vm.prank(owner);
        l2SystemConfig.updateBaseFeeScalar(baseFeeScalar);
        vm.prank(owner);
        l2SystemConfig.updateBaseFeeOverhead(baseFeeOverhead);

        // Calculate expected L2 base fee
        uint256 expectedL2BaseFee = (l1BaseFee * baseFeeScalar) / 1e18 + baseFeeOverhead;

        // Test getL2BaseFee function
        uint256 actualL2BaseFee = l2SystemConfig.getL2BaseFee(l1BaseFee);
        assertEq(actualL2BaseFee, expectedL2BaseFee);
    }
}
