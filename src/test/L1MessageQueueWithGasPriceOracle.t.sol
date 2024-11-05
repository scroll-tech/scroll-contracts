// SPDX-License-Identifier: MIT

pragma solidity =0.8.24;

import {DSTestPlus} from "solmate/test/utils/DSTestPlus.sol";

import {ITransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import {IL1MessageQueueWithGasPriceOracle} from "../L1/rollup/IL1MessageQueueWithGasPriceOracle.sol";
import {L1MessageQueueWithGasPriceOracle} from "../L1/rollup/L1MessageQueueWithGasPriceOracle.sol";
import {L2GasPriceOracle} from "../L1/rollup/L2GasPriceOracle.sol";
import {Whitelist} from "../L2/predeploys/Whitelist.sol";

import {ScrollTestBase} from "./ScrollTestBase.t.sol";

contract L1MessageQueueWithGasPriceOracleTest is ScrollTestBase {
    // events
    event UpdateL2BaseFeeParameters(uint256 overhead, uint256 scalar);

    L1MessageQueueWithGasPriceOracle private queue;
    L2GasPriceOracle internal gasOracle;
    Whitelist private whitelist;

    function setUp() public {
        __ScrollTestBase_setUp();

        queue = L1MessageQueueWithGasPriceOracle(_deployProxy(address(0)));
        gasOracle = L2GasPriceOracle(_deployProxy(address(new L2GasPriceOracle())));
        whitelist = new Whitelist(address(this));

        // initialize L2GasPriceOracle
        gasOracle.initialize(1, 2, 1, 1);
        gasOracle.updateWhitelist(address(whitelist));

        // Setup whitelist
        address[] memory _accounts = new address[](1);
        _accounts[0] = address(this);
        whitelist.updateWhitelistStatus(_accounts, true);

        // Upgrade the L1MessageQueueWithGasPriceOracle implementation and initialize
        admin.upgrade(
            ITransparentUpgradeableProxy(address(queue)),
            address(new L1MessageQueueWithGasPriceOracle(address(1), address(1), address(1)))
        );
        queue.initialize(address(1), address(1), address(1), address(gasOracle), 10000000);
        queue.initializeV2();
    }

    function testUpdateL2BaseFeeParameters(
        uint256 basefee,
        uint128 overhead,
        uint128 scalar
    ) external {
        basefee = bound(basefee, 1, 1e18);
        hevm.fee(basefee);

        // call by non-owner, should revert
        hevm.startPrank(address(1));
        hevm.expectRevert("Ownable: caller is not the owner");
        queue.updateL2BaseFeeParameters(overhead, scalar);
        hevm.stopPrank();

        // call by owner, should succeed
        (uint128 x, uint128 y) = queue.l2BaseFeeParameters();
        assertEq(x, 0);
        assertEq(y, 0);
        hevm.expectEmit(false, false, false, true);
        emit UpdateL2BaseFeeParameters(overhead, scalar);
        queue.updateL2BaseFeeParameters(overhead, scalar);
        (x, y) = queue.l2BaseFeeParameters();
        assertEq(x, overhead);
        assertEq(y, scalar);

        assertEq(queue.l2BaseFee(), overhead + (scalar * block.basefee) / 1e18);
    }

    function testEstimateCrossDomainMessageFee(
        uint256 basefee,
        uint128 overhead,
        uint128 scalar,
        uint256 gasLimit
    ) external {
        basefee = bound(basefee, 0, 1 ether);
        gasLimit = bound(gasLimit, 0, 3000000);

        assertEq(queue.estimateCrossDomainMessageFee(gasLimit), 0);

        hevm.fee(basefee);
        queue.updateL2BaseFeeParameters(overhead, scalar);
        assertEq(queue.estimateCrossDomainMessageFee(gasLimit), ((basefee * scalar) / 1e18 + overhead) * gasLimit);
    }

    function testCalculateIntrinsicGasFee(bytes memory data) external {
        assertEq(queue.calculateIntrinsicGasFee(data), 21000 + data.length * 16);
    }
}
