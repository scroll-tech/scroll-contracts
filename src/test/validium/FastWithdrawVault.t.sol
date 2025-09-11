// SPDX-License-Identifier: MIT

pragma solidity =0.8.24;

import {MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";

import {StringsUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/StringsUpgradeable.sol";
import {ITransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {IERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";

import {IL1ERC20Gateway} from "../../L1/gateways/IL1ERC20Gateway.sol";
import {WrappedEther} from "../../L2/predeploys/WrappedEther.sol";
import {L2StandardERC20Gateway} from "../../L2/gateways/L2StandardERC20Gateway.sol";
import {ScrollStandardERC20} from "../../libraries/token/ScrollStandardERC20.sol";
import {ScrollStandardERC20Factory} from "../../libraries/token/ScrollStandardERC20Factory.sol";
import {IWETH} from "../../interfaces/IWETH.sol";
import {FastWithdrawVault} from "../../validium/FastWithdrawVault.sol";
import {L1ERC20GatewayValidium} from "../../validium/L1ERC20GatewayValidium.sol";

import {ValidiumTestBase} from "./ValidiumTestBase.t.sol";

// Helper contract to access private functions
contract FastWithdrawVaultHelper is FastWithdrawVault {
    constructor(address _weth, address _gateway) FastWithdrawVault(_weth, _gateway) {}

    function getWithdrawTypehash() public pure returns (bytes32) {
        return keccak256("Withdraw(address l1Token,address l2Token,address to,uint256 amount,bytes32 messageHash)");
    }

    function hashTypedDataV4(bytes32 structHash) public view returns (bytes32) {
        return _hashTypedDataV4(structHash);
    }
}

contract FastWithdrawVaultTest is ValidiumTestBase {
    event Withdraw(address indexed l1Token, address indexed l2Token, address to, uint256 amount, bytes32 messageHash);

    L1ERC20GatewayValidium private gateway;

    ScrollStandardERC20 private template;
    ScrollStandardERC20Factory private factory;
    L2StandardERC20Gateway private counterpartGateway;

    FastWithdrawVaultHelper private vault;
    MockERC20 private l1Token;
    WrappedEther private weth;
    MockERC20 private l2Token;

    address private vaultAdmin;

    uint256 private sequencerPrivateKey;
    address private sequencer;

    uint256 private userPrivateKey;
    address private user;

    function setUp() public {
        __ValidiumTestBase_setUp(1233);

        // Setup addresses and keys
        vaultAdmin = address(this);

        sequencerPrivateKey = 0x1234567890123456789012345678901234567890123456789012345678901234;
        userPrivateKey = 0x1234567890123456789012345678901234567890123456789012345678901235;
        sequencer = hevm.addr(sequencerPrivateKey);
        user = hevm.addr(userPrivateKey);

        // Deploy tokens
        weth = new WrappedEther();
        l1Token = new MockERC20("Mock", "M", 18);

        // Deploy L2 contracts
        template = new ScrollStandardERC20();
        factory = new ScrollStandardERC20Factory(address(template));
        counterpartGateway = new L2StandardERC20Gateway(address(1), address(1), address(1), address(factory));

        // Deploy L1 contracts
        gateway = _deployGateway(address(l1Messenger));
        vault = _deployVault();

        // Initialize L1 contracts
        gateway.initialize();
        vault.initialize(vaultAdmin, sequencer);

        // Setup token balances
        l1Token.mint(address(vault), 100 ether);
        weth.deposit{value: 100 ether}();
        weth.transfer(address(vault), 100 ether);
    }

    function testInitialize() public {
        // Test that the vault was initialized correctly in setUp
        assertTrue(vault.hasRole(vault.DEFAULT_ADMIN_ROLE(), vaultAdmin));
        assertTrue(vault.hasRole(vault.SEQUENCER_ROLE(), sequencer));

        assertEq(vault.weth(), address(weth));
        assertEq(vault.gateway(), address(gateway));

        // Test role constants
        assertEq(vault.SEQUENCER_ROLE(), keccak256("SEQUENCER_ROLE"));
    }

    function testClaimFastWithdrawERC20(
        address to,
        uint256 amount,
        bytes32 messageHash
    ) public {
        hevm.assume(to != address(0));
        hevm.assume(to.code.length == 0);

        amount = bound(amount, 1, 100 ether);
        l2Token = MockERC20(gateway.getL2ERC20Address(address(l1Token)));

        // Create the struct hash
        bytes32 structHash = keccak256(
            abi.encode(
                vault.getWithdrawTypehash(),
                address(l1Token),
                address(l2Token), // l2Token
                to,
                amount,
                messageHash
            )
        );

        // Create the typed data hash
        bytes32 hash = vault.hashTypedDataV4(structHash);

        // revert when the signature is invalid
        hevm.expectRevert("ECDSA: invalid signature length");
        vault.claimFastWithdraw(address(l1Token), to, amount, messageHash, bytes("invalid"));
        hevm.expectRevert("ECDSA: invalid signature");
        vault.claimFastWithdraw(address(l1Token), to, amount, messageHash, new bytes(65));

        // revert when signer mismatch is not sequencer
        bytes memory invalidSignature;
        {
            (uint8 v, bytes32 r, bytes32 s) = hevm.sign(userPrivateKey, hash);
            invalidSignature = abi.encodePacked(r, s, v);
        }
        hevm.expectRevert(
            abi.encodePacked(
                "AccessControl: account ",
                StringsUpgradeable.toHexString(user),
                " is missing role ",
                StringsUpgradeable.toHexString(uint256(vault.SEQUENCER_ROLE()), 32)
            )
        );
        vault.claimFastWithdraw(address(l1Token), to, amount, messageHash, invalidSignature);

        // Sign the hash with sequencer's private key
        bytes memory signature;
        {
            (uint8 v, bytes32 r, bytes32 s) = hevm.sign(sequencerPrivateKey, hash);
            signature = abi.encodePacked(r, s, v);
        }

        // Call claimFastWithdraw and Expect the Withdraw event
        uint256 toBalanceBefore = l1Token.balanceOf(to);
        uint256 vaultBalanceBefore = l1Token.balanceOf(address(vault));
        hevm.expectEmit(true, true, true, true);
        emit Withdraw(address(l1Token), address(l2Token), to, amount, messageHash);
        vault.claimFastWithdraw(address(l1Token), to, amount, messageHash, signature);
        uint256 toBalanceAfter = l1Token.balanceOf(to);
        uint256 vaultBalanceAfter = l1Token.balanceOf(address(vault));

        // Verify token transfer
        assertEq(toBalanceAfter - toBalanceBefore, amount);
        assertEq(vaultBalanceBefore - vaultBalanceAfter, amount);

        // Verify the withdraw is marked as processed
        assertTrue(vault.isWithdrawn(structHash));

        // revert when claim again on the same struct hash
        hevm.expectRevert(FastWithdrawVault.ErrorWithdrawAlreadyProcessed.selector);
        hevm.startPrank(sequencer);
        vault.claimFastWithdraw(address(l1Token), to, amount, messageHash, signature);
        hevm.stopPrank();
    }

    /*
    function testClaimFastWithdrawWETH() public {
        address wethAddr = address(weth);
        address from = user;
        address to = recipient;
        uint256 amount = 50 ether;
        bytes32 messageHash = keccak256("test_weth_message_hash");

        // Create the struct hash
        bytes32 structHash = keccak256(
            abi.encode(
                vault.getWithdrawTypehash(),
                wethAddr,
                address(l2Token), // l2Token
                to,
                amount,
                messageHash
            )
        );

        // Create the typed data hash
        bytes32 hash = vault.hashTypedDataV4(structHash);

        // Sign the hash with sequencer's private key
        (uint8 v, bytes32 r, bytes32 s) = hevm.sign(sequencerPrivateKey, hash);
        bytes memory signature = abi.encodePacked(r, s, v);

        // Mock the gateway to return l2Token address
        hevm.mockCall(
            address(0x123), // gateway address
            abi.encodeWithSelector(IL1ERC20Gateway.getL2ERC20Address.selector, wethAddr),
            abi.encode(address(l2Token))
        );

        // Mock WETH withdraw function
        hevm.mockCall(wethAddr, abi.encodeWithSelector(IWETH.withdraw.selector, amount), abi.encode());

        // Expect the Withdraw event
        hevm.expectEmit(true, true, true, true);
        emit Withdraw(wethAddr, address(l2Token), to, amount, messageHash);

        // Call claimFastWithdraw
        vault.claimFastWithdraw(wethAddr, to, amount, messageHash, signature);

        // Verify the withdraw is marked as processed
        assertTrue(vault.isWithdrawn(structHash));
    }
    */

    function testWithdrawByAdmin(address recipient, uint256 amount) public {
        hevm.assume(recipient != address(0));
        hevm.assume(recipient.code.length == 0);
        amount = bound(amount, 1, 100 ether);

        // revert when caller is not admin
        hevm.expectRevert(
            abi.encodePacked(
                "AccessControl: account ",
                StringsUpgradeable.toHexString(user),
                " is missing role ",
                StringsUpgradeable.toHexString(uint256(vault.DEFAULT_ADMIN_ROLE()), 32)
            )
        );
        hevm.prank(user);
        vault.withdraw(address(l1Token), recipient, amount);

        // Admin should be able to withdraw
        uint256 balanceBefore = l1Token.balanceOf(recipient);
        uint256 vaultBalanceBefore = l1Token.balanceOf(address(vault));
        hevm.prank(vaultAdmin);
        vault.withdraw(address(l1Token), recipient, amount);
        uint256 balanceAfter = l1Token.balanceOf(recipient);
        uint256 vaultBalanceAfter = l1Token.balanceOf(address(vault));

        // Verify token transfer
        assertEq(balanceAfter - balanceBefore, amount);
        assertEq(vaultBalanceBefore - vaultBalanceAfter, amount);
    }

    function _deployGateway(address messenger) internal returns (L1ERC20GatewayValidium _gateway) {
        _gateway = L1ERC20GatewayValidium(_deployProxy(address(0)));

        admin.upgrade(
            ITransparentUpgradeableProxy(address(_gateway)),
            address(
                new L1ERC20GatewayValidium(
                    address(counterpartGateway),
                    address(messenger),
                    address(template),
                    address(factory),
                    address(rollup)
                )
            )
        );
    }

    function _deployVault() internal returns (FastWithdrawVaultHelper _vault) {
        _vault = FastWithdrawVaultHelper(payable(_deployProxy(address(0))));

        admin.upgrade(
            ITransparentUpgradeableProxy(address(_vault)),
            address(new FastWithdrawVaultHelper(address(weth), address(gateway)))
        );
    }
}
