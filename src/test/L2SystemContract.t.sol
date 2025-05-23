// SPDX-License-Identifier: MIT

pragma solidity =0.8.24;

import {Test} from "forge-std/Test.sol";

import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import {L2SystemContract} from "../L2/L2SystemContract.sol";

contract L2SystemContractTest is Test {
    address public admin;
    address public owner;
    address public nonOwner;

    L2SystemContract public l2SystemContract;

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    function setUp() public {
        admin = makeAddr("admin");
        owner = makeAddr("owner");
        nonOwner = makeAddr("nonOwner");

        L2SystemContract implementation = new L2SystemContract();
        address proxy = address(new TransparentUpgradeableProxy(address(implementation), admin, ""));
        l2SystemContract = L2SystemContract(proxy);

        l2SystemContract.initialize(owner);
    }

    function test_Initialize() public {
        // Test initialization
        assertEq(l2SystemContract.owner(), owner);

        // revert when initialize again
        vm.expectRevert("Initializable: contract is already initialized");
        l2SystemContract.initialize(owner);
    }

    function test_UpdateBaseFeeOverhead(uint256 newBaseFeeOverhead) public {
        // Test that only owner can update base fee overhead
        vm.prank(nonOwner);
        vm.expectRevert("Ownable: caller is not the owner");
        l2SystemContract.updateBaseFeeOverhead(newBaseFeeOverhead);

        // Test owner can update base fee overhead
        assertEq(l2SystemContract.baseFeeOverhead(), 0);
        vm.prank(owner);
        l2SystemContract.updateBaseFeeOverhead(newBaseFeeOverhead);
        assertEq(l2SystemContract.baseFeeOverhead(), newBaseFeeOverhead);
    }

    function test_UpdateBaseFeeScalar(uint256 newBaseFeeScalar) public {
        // Test that only owner can update base fee scalar
        vm.prank(nonOwner);
        vm.expectRevert("Ownable: caller is not the owner");
        l2SystemContract.updateBaseFeeScalar(newBaseFeeScalar);

        // Test owner can update base fee scalar
        assertEq(l2SystemContract.baseFeeScalar(), 0);
        vm.prank(owner);
        l2SystemContract.updateBaseFeeScalar(newBaseFeeScalar);
        assertEq(l2SystemContract.baseFeeScalar(), newBaseFeeScalar);
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
        l2SystemContract.updateBaseFeeScalar(baseFeeScalar);
        vm.prank(owner);
        l2SystemContract.updateBaseFeeOverhead(baseFeeOverhead);

        // Calculate expected L2 base fee
        uint256 expectedL2BaseFee = (l1BaseFee * baseFeeScalar) / 1e18 + baseFeeOverhead;

        // Test getL2BaseFee function
        uint256 actualL2BaseFee = l2SystemContract.getL2BaseFee(l1BaseFee);
        assertEq(actualL2BaseFee, expectedL2BaseFee);
    }

    function test_GetL2BaseFeeWithZeroL1BaseFee() public {
        uint256 l1BaseFee = 0;
        uint256 baseFeeScalar = 2000;
        uint256 baseFeeOverhead = 1000;

        // Set up the contract state
        vm.prank(owner);
        l2SystemContract.updateBaseFeeScalar(baseFeeScalar);
        vm.prank(owner);
        l2SystemContract.updateBaseFeeOverhead(baseFeeOverhead);

        // Calculate expected L2 base fee
        uint256 expectedL2BaseFee = baseFeeOverhead; // When L1 base fee is 0, only overhead is added

        // Test getL2BaseFee function
        uint256 actualL2BaseFee = l2SystemContract.getL2BaseFee(l1BaseFee);
        assertEq(actualL2BaseFee, expectedL2BaseFee);
    }

    function test_GetL2BaseFeeWithLargeValues() public {
        uint256 l1BaseFee = 1e18; // 1 ETH
        uint256 baseFeeScalar = 2e18; // 2x multiplier
        uint256 baseFeeOverhead = 1e17; // 0.1 ETH

        // Set up the contract state
        vm.prank(owner);
        l2SystemContract.updateBaseFeeScalar(baseFeeScalar);
        vm.prank(owner);
        l2SystemContract.updateBaseFeeOverhead(baseFeeOverhead);

        // Calculate expected L2 base fee
        uint256 expectedL2BaseFee = (l1BaseFee * baseFeeScalar) / 1e18 + baseFeeOverhead;

        // Test getL2BaseFee function
        uint256 actualL2BaseFee = l2SystemContract.getL2BaseFee(l1BaseFee);
        assertEq(actualL2BaseFee, expectedL2BaseFee);
    }
}
