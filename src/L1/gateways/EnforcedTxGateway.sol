// SPDX-License-Identifier: MIT

pragma solidity =0.8.24;

import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {ECDSAUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/cryptography/ECDSAUpgradeable.sol";
import {EIP712Upgradeable} from "@openzeppelin/contracts-upgradeable/utils/cryptography/EIP712Upgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";

import {IL1MessageQueueV2} from "../rollup/IL1MessageQueueV2.sol";

import {AddressAliasHelper} from "../../libraries/common/AddressAliasHelper.sol";

// solhint-disable reason-string

contract EnforcedTxGateway is OwnableUpgradeable, ReentrancyGuardUpgradeable, PausableUpgradeable, EIP712Upgradeable {
    /**********
     * Events *
     **********/

    /// @notice Emitted when owner updates fee vault contract.
    /// @param _oldFeeVault The address of old fee vault contract.
    /// @param _newFeeVault The address of new fee vault contract.
    event UpdateFeeVault(address _oldFeeVault, address _newFeeVault);

    /*************
     * Constants *
     *************/

    // solhint-disable-next-line var-name-mixedcase
    bytes32 private constant _ENFORCED_TX_TYPEHASH =
        keccak256(
            "EnforcedTransaction(address sender,address target,uint256 value,uint256 gasLimit,bytes data,uint256 nonce,uint256 deadline)"
        );

    /***********************
     * Immutable Variables *
     ***********************/

    /// @notice The address of `L1MessageQueueV2`.
    address public immutable messageQueue;

    /// @notice The address of `FeeVault`.
    address public immutable feeVault;

    /*************
     * Variables *
     *************/

    /// @dev The storage slot used as `L1MessageQueueV2` contract, which is deprecated now.
    address private __deprecated_messageQueue;

    /// @dev The storage slot used as `FeeVault` contract, which is deprecated now.
    address private __deprecated_feeVault;

    /// @notice Mapping from EOA address to current nonce.
    /// @dev Every successful call to `sendTransaction` with signature increases `_sender`'s nonce by one.
    /// This prevents a signature from being used multiple times.
    mapping(address => uint256) public nonces;

    /***************
     * Constructor *
     ***************/

    constructor(address _messageQueue, address _feeVault) {
        _disableInitializers();

        messageQueue = _messageQueue;
        feeVault = _feeVault;
    }

    function initialize() external initializer {
        OwnableUpgradeable.__Ownable_init();
        ReentrancyGuardUpgradeable.__ReentrancyGuard_init();
        PausableUpgradeable.__Pausable_init();
        EIP712Upgradeable.__EIP712_init("EnforcedTxGateway", "1");
    }

    /*************************
     * Public View Functions *
     *************************/

    /// @notice return the domain separator for the typed transaction
    // solhint-disable-next-line func-name-mixedcase
    function DOMAIN_SEPARATOR() external view returns (bytes32) {
        return _domainSeparatorV4();
    }

    /*****************************
     * Public Mutating Functions *
     *****************************/

    /// @notice Add an enforced transaction to L2.
    /// @dev The caller should be EOA only.
    /// @param _target The address of target contract to call in L2.
    /// @param _value The value passed
    /// @param _gasLimit The maximum gas should be used for this transaction in L2.
    /// @param _data The calldata passed to target contract.
    function sendTransaction(
        address _target,
        uint256 _value,
        uint256 _gasLimit,
        bytes calldata _data
    ) external payable whenNotPaused {
        address sender = _msgSender();
        if (sender != tx.origin) {
            // If sender is a classic SCA, then we apply address aliasing (consistent with message from L1ScrollMessenger).
            // If sender is an EOA with no code, no aliasing is applied.
            // If sender is an EIP-7702 delegated EOA, then aliasing behavior depends on which wallet initiated the call.
            sender = AddressAliasHelper.applyL1ToL2Alias(sender);
        }

        _sendTransaction(sender, _target, _value, _gasLimit, _data, msg.sender);
    }

    /// @notice Add an enforced transaction to L2.
    /// @dev The `_sender` should be EOA and match with the signature.
    /// @param _sender The address of sender who will initiate this transaction in L2.
    /// @param _target The address of target contract to call in L2.
    /// @param _value The value passed
    /// @param _gasLimit The maximum gas should be used for this transaction in L2.
    /// @param _data The calldata passed to target contract.
    /// @param _deadline The deadline of the signature.
    /// @param _signature The signature for the transaction.
    /// @param _refundAddress The address to refund exceeded fee.
    function sendTransaction(
        address _sender,
        address _target,
        uint256 _value,
        uint256 _gasLimit,
        bytes calldata _data,
        uint256 _deadline,
        bytes memory _signature,
        address _refundAddress
    ) external payable whenNotPaused {
        // solhint-disable-next-line not-rely-on-time
        require(block.timestamp <= _deadline, "signature expired");

        uint256 _nonce = nonces[_sender];
        bytes32 _structHash = keccak256(
            abi.encode(_ENFORCED_TX_TYPEHASH, _sender, _target, _value, _gasLimit, keccak256(_data), _nonce, _deadline)
        );
        unchecked {
            nonces[_sender] = _nonce + 1;
        }

        bytes32 _hash = _hashTypedDataV4(_structHash);
        address _signer = ECDSAUpgradeable.recover(_hash, _signature);

        // no need to check `_signer != address(0)`, since it is checked in `recover`.
        require(_signer == _sender, "Incorrect signature");

        _sendTransaction(_sender, _target, _value, _gasLimit, _data, _refundAddress);
    }

    /************************
     * Restricted Functions *
     ************************/

    /// @notice Pause or unpause this contract.
    /// @param _status Pause this contract if it is true, otherwise unpause this contract.
    function setPause(bool _status) external onlyOwner {
        if (_status) {
            _pause();
        } else {
            _unpause();
        }
    }

    /**********************
     * Internal Functions *
     **********************/

    /// @dev Internal function to charge fee and add enforced transaction.
    /// @param _sender The address of sender who will initiate this transaction in L2.
    /// @param _target The address of target contract to call in L2.
    /// @param _value The value passed
    /// @param _gasLimit The maximum gas should be used for this transaction in L2.
    /// @param _data The calldata passed to target contract.
    /// @param _refundAddress The address to refund exceeded fee.
    function _sendTransaction(
        address _sender,
        address _target,
        uint256 _value,
        uint256 _gasLimit,
        bytes calldata _data,
        address _refundAddress
    ) internal nonReentrant {
        address _messageQueue = messageQueue;

        // charge fee
        uint256 _fee = IL1MessageQueueV2(_messageQueue).estimateCrossDomainMessageFee(_gasLimit);
        require(msg.value >= _fee, "Insufficient value for fee");
        if (_fee > 0) {
            (bool _success, ) = feeVault.call{value: _fee}("");
            require(_success, "Failed to deduct the fee");
        }

        // append transaction
        IL1MessageQueueV2(_messageQueue).appendEnforcedTransaction(_sender, _target, _value, _gasLimit, _data);

        // refund fee to `_refundAddress`
        unchecked {
            uint256 _refund = msg.value - _fee;
            if (_refund > 0) {
                (bool _success, ) = _refundAddress.call{value: _refund}("");
                require(_success, "Failed to refund the fee");
            }
        }
    }
}
