// SPDX-License-Identifier: MIT

pragma solidity =0.8.24;

import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import {IERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import {SafeERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import {AddressUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/AddressUpgradeable.sol";
import {EIP712Upgradeable} from "@openzeppelin/contracts-upgradeable/utils/cryptography/EIP712Upgradeable.sol";
import {ECDSAUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/cryptography/ECDSAUpgradeable.sol";

import {IL1ERC20Gateway} from "../L1/gateways/IL1ERC20Gateway.sol";
import {IWETH} from "../interfaces/IWETH.sol";

/// @title FastWithdrawVault
/// @notice The vault for fast withdrawals from L2 to L1.
/// @dev For consistency with our existing contracts, we use "L1" for the host layer, and "L2" for the validium layer.
///      For most deployments, these should be mapped as "L1" = Scroll (L2), "L2" = Validium (L3).
/// @dev This contract is used to fast withdraw tokens from L2 to L1 with a permit from sequencer.
/// The process for a fast withdrawal is:
/// 1. The user on L2 initiates a withdraw request and sets the recipient address as this `FastWithdrawVault` contract,
///    also sending the proper amount of tokens.
/// 2. The sequencer signs the withdraw request and sends it to the vault.
/// 3. The vault verifies the signature and the message hash, and then withdraws the tokens from L2 to L1.
contract FastWithdrawVault is AccessControlUpgradeable, ReentrancyGuardUpgradeable, EIP712Upgradeable {
    using SafeERC20Upgradeable for IERC20Upgradeable;

    /**********
     * Events *
     **********/

    /// @notice Emitted when a withdraw is processed.
    /// @param l1Token The address of the L1 token.
    /// @param l2Token The address of the L2 token.
    /// @param to The address of the recipient.
    /// @param amount The amount of tokens withdrawn.
    /// @param messageHash The hash of the message.
    event Withdraw(address indexed l1Token, address indexed l2Token, address to, uint256 amount, bytes32 messageHash);

    /**********
     * Errors *
     **********/

    /// @dev Thrown when the given withdraw message has already been processed.
    error ErrorWithdrawAlreadyProcessed();

    /*************
     * Constants *
     *************/

    /// @dev The typehash of the `Withdraw` struct.
    // solhint-disable-next-line var-name-mixedcase
    bytes32 private constant _WITHDRAW_TYPEHASH =
        keccak256("Withdraw(address l1Token,address l2Token,address to,uint256 amount,bytes32 messageHash)");

    /// @notice The role of the sequencer.
    bytes32 public constant SEQUENCER_ROLE = keccak256("SEQUENCER_ROLE");

    /***********************
     * Immutable Variables *
     ***********************/

    /// @notice The address of the WETH token.
    address public immutable weth;

    /// @notice The address of the `L1ERC20Gateway` contract.
    address public immutable gateway;

    /*********************
     * Storage Variables *
     *********************/

    /// @notice Mapping from message hash to whether the message has been withdrawn.
    mapping(bytes32 => bool) public isWithdrawn;

    /***************
     * Constructor *
     ***************/

    /// @notice Initializes the implementation contract.
    /// @param _gateway The address of the `L1ERC20Gateway` contract.
    constructor(address _weth, address _gateway) {
        weth = _weth;
        gateway = _gateway;

        _disableInitializers();
    }

    /// @notice Initializes the contract storage.
    /// @param _admin The address of the admin.
    /// @param _sequencer The address of the sequencer.
    function initialize(address _admin, address _sequencer) external initializer {
        __Context_init();
        __ERC165_init();
        __AccessControl_init();
        __ReentrancyGuard_init();
        __EIP712_init("FastWithdrawVault", "1");

        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        _grantRole(SEQUENCER_ROLE, _sequencer);
    }

    /*****************************
     * Public Mutating Functions *
     *****************************/

    receive() external payable {}

    /// @notice Fast withdraw some tokens from L2 to L1 with signature from sequencer.
    /// @param l1Token The address of the L1 token.
    /// @param to The address of the recipient.
    /// @param amount The amount of tokens to withdraw.
    /// @param messageHash The hash of the message, which is the corresponding withdraw message hash in L2.
    /// @param signature The signature of the message from sequencer.
    function claimFastWithdraw(
        address l1Token,
        address to,
        uint256 amount,
        bytes32 messageHash,
        bytes memory signature
    ) external nonReentrant {
        address l2Token = IL1ERC20Gateway(gateway).getL2ERC20Address(l1Token);
        bytes32 structHash = keccak256(abi.encode(_WITHDRAW_TYPEHASH, l1Token, l2Token, to, amount, messageHash));
        if (isWithdrawn[structHash]) revert ErrorWithdrawAlreadyProcessed();
        isWithdrawn[structHash] = true;

        bytes32 hash = _hashTypedDataV4(structHash);
        address signer = ECDSAUpgradeable.recover(hash, signature);
        _checkRole(SEQUENCER_ROLE, signer);

        if (l1Token == weth) {
            IWETH(weth).withdraw(amount);
            AddressUpgradeable.sendValue(payable(to), amount);
        } else {
            IERC20Upgradeable(l1Token).safeTransfer(to, amount);
        }

        emit Withdraw(l1Token, l2Token, to, amount, messageHash);
    }

    /************************
     * Restricted Functions *
     ************************/

    /// @notice Withdraw some tokens from the vault by admin.
    /// @param token The address of the token.
    /// @param recipient The address of the recipient.
    /// @param amount The amount of tokens to withdraw.
    function withdraw(
        address token,
        address recipient,
        uint256 amount
    ) external nonReentrant onlyRole(DEFAULT_ADMIN_ROLE) {
        IERC20Upgradeable(token).safeTransfer(recipient, amount);
    }
}
