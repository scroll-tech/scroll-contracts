// SPDX-License-Identifier: MIT

pragma solidity =0.8.24;

import {MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";
import {WETH} from "solmate/tokens/WETH.sol";

import {ITransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import {L1WrappedTokenGateway} from "../../alternative-gas-token/L1WrappedTokenGateway.sol";
import {L1StandardERC20Gateway} from "../../L1/gateways/L1StandardERC20Gateway.sol";
import {L2StandardERC20Gateway} from "../../L2/gateways/L2StandardERC20Gateway.sol";
import {ScrollStandardERC20} from "../../libraries/token/ScrollStandardERC20.sol";
import {ScrollStandardERC20Factory} from "../../libraries/token/ScrollStandardERC20Factory.sol";

import {AlternativeGasTokenTestBase} from "./AlternativeGasTokenTestBase.t.sol";

contract L1WrappedTokenGatewayTest is AlternativeGasTokenTestBase {
    event OnDropMessageCalled(uint256, bytes);

    event OnRelayMessageWithProof(uint256, bytes);

    MockERC20 private gasToken;

    ScrollStandardERC20 private template;
    ScrollStandardERC20Factory private factory;

    L1StandardERC20Gateway private l1ERC20Gateway;
    L2StandardERC20Gateway private l2ERC20Gateway;

    WETH private weth;
    L1WrappedTokenGateway private gateway;

    receive() external payable {}

    function setUp() external {
        gasToken = new MockERC20("X", "Y", 18);

        __AlternativeGasTokenTestBase_setUp(1234, address(gasToken));

        template = new ScrollStandardERC20();
        factory = new ScrollStandardERC20Factory(address(template));
        l1ERC20Gateway = L1StandardERC20Gateway(_deployProxy(address(0)));
        l2ERC20Gateway = L2StandardERC20Gateway(_deployProxy(address(0)));

        admin.upgrade(
            ITransparentUpgradeableProxy(address(l1ERC20Gateway)),
            address(
                new L1StandardERC20Gateway(
                    address(l2ERC20Gateway),
                    address(l1Router),
                    address(l1Messenger),
                    address(template),
                    address(factory)
                )
            )
        );
        admin.upgrade(
            ITransparentUpgradeableProxy(address(l2ERC20Gateway)),
            address(
                new L2StandardERC20Gateway(
                    address(l1ERC20Gateway),
                    address(l2Router),
                    address(l2Messenger),
                    address(factory)
                )
            )
        );

        weth = new WETH();
        gateway = new L1WrappedTokenGateway(address(weth), address(l1ERC20Gateway));
    }

    function testInitialization() external view {
        assertEq(gateway.WETH(), address(weth));
        assertEq(gateway.gateway(), address(l1ERC20Gateway));
        assertEq(gateway.sender(), address(1));
    }

    function testReceive(uint256 amount) external {
        amount = bound(amount, 0, address(this).balance);

        vm.expectRevert(L1WrappedTokenGateway.ErrorCallNotFromFeeRefund.selector);
        payable(address(gateway)).transfer(amount);
    }

    function testDeposit(
        uint256 amount,
        address recipient,
        uint256 l2BaseFee,
        uint256 exceedValue
    ) external {
        amount = bound(amount, 1, address(this).balance / 2);
        l2BaseFee = bound(l2BaseFee, 0, 10**9);
        exceedValue = bound(exceedValue, 0, 1 ether);

        l1MessageQueue.setL2BaseFee(l2BaseFee);
        uint256 fee = l2BaseFee * 200000;

        uint256 ethBalance = address(this).balance;
        uint256 wethBalance = weth.balanceOf(address(l1ERC20Gateway));
        gateway.deposit{value: amount + fee + exceedValue}(recipient, amount);
        assertEq(ethBalance - amount - fee, address(this).balance);
        assertEq(wethBalance + amount, weth.balanceOf(address(l1ERC20Gateway)));
    }
}
