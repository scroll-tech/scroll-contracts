// SPDX-License-Identifier: MIT

pragma solidity =0.8.24;

import {ClonesUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/ClonesUpgradeable.sol";
import {IERC20MetadataUpgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/IERC20MetadataUpgradeable.sol";
import {IERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import {SafeERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";

import {IL1ScrollMessenger} from "../L1/IL1ScrollMessenger.sol";
import {IL1ERC20GatewayValidium} from "./IL1ERC20GatewayValidium.sol";
import {IL2ERC20GatewayValidium} from "./IL2ERC20GatewayValidium.sol";
import {IScrollChainValidium} from "./IScrollChainValidium.sol";

import {ScrollGatewayBase} from "../libraries/gateway/ScrollGatewayBase.sol";

/// @title L1ERC20GatewayValidium
contract L1ERC20GatewayValidium is ScrollGatewayBase, IL1ERC20GatewayValidium {
    using SafeERC20Upgradeable for IERC20Upgradeable;

    /**********
     * Errors *
     **********/

    /// @dev Error thrown when msg.value is not zero.
    error ErrorMsgValueNotZero();

    /// @dev Error thrown when l2 token address is zero.
    error ErrorL2TokenAddressIsZero();

    /// @dev Error thrown when l2 token address mismatch.
    error ErrorL2TokenMismatch();

    /// @dev Error thrown when amount is zero.
    error ErrorAmountIsZero();

    /*************
     * Constants *
     *************/

    /// @notice The address of ScrollStandardERC20 implementation in L2.
    address public immutable l2TokenImplementation;

    /// @notice The address of ScrollStandardERC20Factory contract in L2.
    address public immutable l2TokenFactory;

    /// @notice The address of ScrollChainValidium contract in L2.
    address public immutable scrollChainValidium;

    /*************
     * Variables *
     *************/

    /// @notice Mapping from l1 token address to l2 token address.
    /// @dev This is not necessary, since we can compute the address directly. But, we use this mapping
    /// to keep track on whether we have deployed the token in L2 using the L2ScrollStandardERC20Factory and
    /// pass deploy data on first call to the token.
    mapping(address => address) private tokenMapping;

    /***************
     * Constructor *
     ***************/

    /// @notice Constructor for `L1StandardERC20Gateway` implementation contract.
    ///
    /// @param _counterpart The address of `L2StandardERC20Gateway` contract in L2.
    /// @param _messenger The address of `L1ScrollMessenger` contract in L1.
    /// @param _l2TokenImplementation The address of `ScrollStandardERC20` implementation in L2.
    /// @param _l2TokenFactory The address of `ScrollStandardERC20Factory` contract in L2.
    constructor(
        address _counterpart,
        address _messenger,
        address _l2TokenImplementation,
        address _l2TokenFactory,
        address _scrollChainValidium
    ) ScrollGatewayBase(_counterpart, address(0), _messenger) {
        _disableInitializers();

        l2TokenImplementation = _l2TokenImplementation;
        l2TokenFactory = _l2TokenFactory;
        scrollChainValidium = _scrollChainValidium;
    }

    /// @notice Initialize the storage of L1ERC20GatewayValidium.
    function initialize() external initializer {
        ScrollGatewayBase._initialize(address(0), address(0), address(0));
    }

    /*************************
     * Public View Functions *
     *************************/

    /// @inheritdoc IL1ERC20GatewayValidium
    function getL2ERC20Address(address _l1Token) public view override returns (address) {
        // In StandardERC20Gateway, all corresponding l2 tokens are depoyed by Create2 with salt,
        // we can calculate the l2 address directly.
        bytes32 _salt = keccak256(abi.encodePacked(counterpart, keccak256(abi.encodePacked(_l1Token))));

        return ClonesUpgradeable.predictDeterministicAddress(l2TokenImplementation, _salt, l2TokenFactory);
    }

    /*****************************
     * Public Mutating Functions *
     *****************************/

    /// @inheritdoc IL1ERC20GatewayValidium
    function depositERC20(
        address _token,
        bytes memory _to,
        uint256 _amount,
        uint256 _gasLimit,
        uint256 _keyId
    ) external payable override {
        _deposit(_token, _msgSender(), _to, _amount, new bytes(0), _gasLimit, _keyId);
    }

    /// @inheritdoc IL1ERC20GatewayValidium
    function depositERC20(
        address _token,
        address _realSender,
        bytes memory _to,
        uint256 _amount,
        uint256 _gasLimit,
        uint256 _keyId
    ) external payable override {
        _deposit(_token, _realSender, _to, _amount, new bytes(0), _gasLimit, _keyId);
    }

    /// @inheritdoc IL1ERC20GatewayValidium
    function finalizeWithdrawERC20(
        address _l1Token,
        address _l2Token,
        address _from,
        address _to,
        uint256 _amount,
        bytes calldata _data
    ) external payable virtual override onlyCallByCounterpart nonReentrant {
        _beforeFinalizeWithdrawERC20(_l1Token, _l2Token, _from, _to, _amount);

        IERC20Upgradeable(_l1Token).safeTransfer(_to, _amount);

        emit FinalizeWithdrawERC20(_l1Token, _l2Token, _from, _to, _amount, _data);
    }

    /**********************
     * Internal Functions *
     **********************/

    /// @dev Internal function hook to perform checks and actions before finalizing the withdrawal.
    /// @param _l1Token The address of corresponding L1 token in L1.
    /// @param _l2Token The address of corresponding L2 token in L2.
    function _beforeFinalizeWithdrawERC20(
        address _l1Token,
        address _l2Token,
        address,
        address,
        uint256
    ) internal virtual {
        if (msg.value > 0) revert ErrorMsgValueNotZero();
        if (_l2Token == address(0)) revert ErrorL2TokenAddressIsZero();
        if (getL2ERC20Address(_l1Token) != _l2Token) revert ErrorL2TokenMismatch();

        // update `tokenMapping` on first withdraw
        address _storedL2Token = tokenMapping[_l1Token];
        if (_storedL2Token == address(0)) {
            tokenMapping[_l1Token] = _l2Token;
        } else {
            if (_storedL2Token != _l2Token) revert ErrorL2TokenMismatch();
        }
    }

    /// @dev Internal function to transfer ERC20 token to this contract.
    /// @param _token The address of token to transfer.
    /// @param _amount The amount of token to transfer.
    function _transferERC20In(
        address _from,
        address _token,
        uint256 _amount
    ) internal returns (uint256) {
        // common practice to handle fee on transfer token.
        uint256 _before = IERC20Upgradeable(_token).balanceOf(address(this));
        IERC20Upgradeable(_token).safeTransferFrom(_from, address(this), _amount);
        uint256 _after = IERC20Upgradeable(_token).balanceOf(address(this));
        // no unchecked here, since some weird token may return arbitrary balance.
        _amount = _after - _before;

        return _amount;
    }

    /// @dev Internal function to do all the deposit operations.
    ///
    /// @param _token The token to deposit.
    /// @param _to The recipient address to recieve the token in L2.
    /// @param _amount The amount of token to deposit.
    /// @param _data Optional data to forward to recipient's account. It is always empty for now.
    /// @param _gasLimit Gas limit required to complete the deposit on L2.
    function _deposit(
        address _token,
        address _from,
        bytes memory _to,
        uint256 _amount,
        bytes memory _data,
        uint256 _gasLimit,
        uint256 _keyId
    ) internal virtual nonReentrant {
        // Validate the encryption key with the given key-id.
        IScrollChainValidium(scrollChainValidium).getEncryptionKey(_keyId);

        // 1. Transfer token into this contract.
        _amount = _transferERC20In(_msgSender(), _token, _amount);
        if (_amount == 0) revert ErrorAmountIsZero();

        // 2. Generate message passed to L2StandardERC20Gateway.
        address _l2Token = tokenMapping[_token];
        bytes memory _l2Data;
        if (_l2Token == address(0)) {
            // @note we won't update `tokenMapping` here but update the `tokenMapping` on
            // first successful withdraw. This will prevent user to set arbitrary token
            // metadata by setting a very small `_gasLimit` on the first tx.
            _l2Token = getL2ERC20Address(_token);

            // passing symbol/name/decimal in order to deploy in L2.
            string memory _symbol = IERC20MetadataUpgradeable(_token).symbol();
            string memory _name = IERC20MetadataUpgradeable(_token).name();
            uint8 _decimals = IERC20MetadataUpgradeable(_token).decimals();
            _l2Data = abi.encode(true, abi.encode(_data, abi.encode(_symbol, _name, _decimals)));
        } else {
            _l2Data = abi.encode(false, _data);
        }
        bytes memory _message = abi.encodeCall(
            IL2ERC20GatewayValidium.finalizeDepositERC20Encrypted,
            (_token, _l2Token, _from, _to, _amount, _l2Data)
        );

        // 3. Send message to L1ScrollMessenger.
        IL1ScrollMessenger(messenger).sendMessage{value: msg.value}(counterpart, 0, _message, _gasLimit, _from);

        emit DepositERC20(_token, _l2Token, _from, _to, _amount, _data);
    }
}
