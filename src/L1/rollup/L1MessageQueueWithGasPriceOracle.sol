// SPDX-License-Identifier: MIT

pragma solidity =0.8.24;

import {IWhitelist} from "../../libraries/common/IWhitelist.sol";
import {IL1MessageQueue} from "./IL1MessageQueue.sol";
import {IL1MessageQueueWithGasPriceOracle} from "./IL1MessageQueueWithGasPriceOracle.sol";
import {IL2GasPriceOracle} from "./IL2GasPriceOracle.sol";

import {L1MessageQueue} from "./L1MessageQueue.sol";

contract L1MessageQueueWithGasPriceOracle is L1MessageQueue, IL1MessageQueueWithGasPriceOracle {
    /*************
     * Constants *
     *************/

    /// @notice The intrinsic gas for transaction.
    uint256 private constant INTRINSIC_GAS_TX = 21000;

    /// @notice The appropriate intrinsic gas for each byte.
    uint256 private constant APPROPRIATE_INTRINSIC_GAS_PER_BYTE = 16;

    uint256 private constant PRECISION = 1e18;

    /***********
     * Structs *
     ***********/

    struct L2BaseFeeParameters {
        uint128 overhead;
        uint128 scalar;
    }

    /*************
     * Variables *
     *************/

    /// @dev The storage slot used as `l2BaseFee`, which is deprecated now.
    /// @custom:deprecated
    uint256 private __deprecated_l2BaseFee;

    /// @dev The storage slot used as `whitelistChecker`, which is deprecated now.
    /// @custom:deprecated
    address private __deprecated__whitelistChecker;

    L2BaseFeeParameters public l2BaseFeeParameters;

    /***************
     * Constructor *
     ***************/

    /// @notice Constructor for `L1MessageQueueWithGasPriceOracle` implementation contract.
    ///
    /// @param _messenger The address of `L1ScrollMessenger` contract.
    /// @param _scrollChain The address of `ScrollChain` contract.
    /// @param _enforcedTxGateway The address of `EnforcedTxGateway` contract.
    constructor(
        address _messenger,
        address _scrollChain,
        address _enforcedTxGateway
    ) L1MessageQueue(_messenger, _scrollChain, _enforcedTxGateway) {}

    /// @notice Initialize the storage of L1MessageQueueWithGasPriceOracle.
    function initializeV2() external reinitializer(2) {
        // __deprecated_l2BaseFee = IL2GasPriceOracle(gasOracle).l2BaseFee();
        // whitelistChecker = IL2GasPriceOracle(gasOracle).whitelist();
    }

    function initializeV3() external reinitializer(3) {
        nextUnfinalizedQueueIndex = pendingQueueIndex;
    }

    /*************************
     * Public View Functions *
     *************************/

    /// @inheritdoc IL1MessageQueueWithGasPriceOracle
    function l2BaseFee() public view returns (uint256) {
        L2BaseFeeParameters memory parameters = l2BaseFeeParameters;
        // this is unlikely to happen, use unchecked here
        unchecked {
            return (block.basefee * parameters.scalar) / PRECISION + parameters.overhead;
        }
    }

    /// @inheritdoc IL1MessageQueue
    function estimateCrossDomainMessageFee(uint256 _gasLimit)
        external
        view
        override(IL1MessageQueue, L1MessageQueue)
        returns (uint256)
    {
        return _gasLimit * l2BaseFee();
    }

    /// @inheritdoc IL1MessageQueue
    function calculateIntrinsicGasFee(bytes calldata _calldata)
        public
        pure
        override(IL1MessageQueue, L1MessageQueue)
        returns (uint256)
    {
        // no way this can overflow `uint256`
        unchecked {
            return INTRINSIC_GAS_TX + _calldata.length * APPROPRIATE_INTRINSIC_GAS_PER_BYTE;
        }
    }

    /************************
     * Restricted Functions *
     ************************/

    /// @notice Update whitelist checker contract.
    /// @dev This function can only called by contract owner.
    /// @param overhead The address of new whitelist checker contract.
    /// @param scalar The address of new whitelist checker contract.
    function updateL2BaseFeeParameters(uint128 overhead, uint128 scalar) external onlyOwner {
        l2BaseFeeParameters = L2BaseFeeParameters(overhead, scalar);

        emit UpdateL2BaseFeeParameters(overhead, scalar);
    }
}
