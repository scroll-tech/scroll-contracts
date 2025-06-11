// SPDX-License-Identifier: MIT
pragma solidity =0.8.24;

import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

contract SystemConfig is OwnableUpgradeable {
    /**********
     * Events *
     **********/

    /// @notice Emitted when the message queue parameters are updated.
    /// @param oldParams The old parameters.
    /// @param newParams The new parameters.
    event MessageQueueParametersUpdated(MessageQueueParameters oldParams, MessageQueueParameters newParams);

    /// @notice Emitted when the enforced batch parameters are updated.
    /// @param oldParams The old parameters.
    /// @param newParams The new parameters.
    event EnforcedBatchParametersUpdated(EnforcedBatchParameters oldParams, EnforcedBatchParameters newParams);

    /// @notice Emitted when the signer is updated.
    /// @param oldSigner The old signer.
    /// @param newSigner The new signer.
    event SignerUpdated(address oldSigner, address newSigner);

    /***********
     * Structs *
     ***********/

    /// @notice Parameters for the message queue.
    /// @param maxGasLimit The maximum gas limit allowed for each L1 message.
    /// @param baseFeeOverhead The overhead used to calculate l2 base fee.
    /// @param baseFeeScalar The scalar used to calculate l2 base fee.
    /// @dev The compiler will pack this struct into single `bytes32`.
    struct MessageQueueParameters {
        uint32 maxGasLimit;
        uint112 baseFeeOverhead;
        uint112 baseFeeScalar;
    }

    /// @notice Parameters for the enforced batch mode.
    /// @param maxDelayEnterEnforcedMode If no batch has been finalized for `maxDelayEnterEnforcedMode`,
    ///        batch submission becomes permissionless. Anyone can submit a batch together with a proof.
    /// @param maxDelayMessageQueue If no message is included/finalized for `maxDelayMessageQueue`,
    ///        batch submission becomes permissionless. Anyone can submit a batch together with a proof.
    /// @dev The compiler will pack this struct into single `bytes32`.
    struct EnforcedBatchParameters {
        uint24 maxDelayEnterEnforcedMode;
        uint24 maxDelayMessageQueue;
    }

    /*********************
     * Storage Variables *
     *********************/

    /// @notice The parameters for the message queue.
    MessageQueueParameters public messageQueueParameters;

    /// @notice The parameters for the enforced batch mode.
    EnforcedBatchParameters public enforcedBatchParameters;

    /// @dev The address of the current authorized signer.
    address private currentSigner;

    /***************
     * Constructor *
     ***************/

    constructor() {
        _disableInitializers();
    }

    function initialize(
        address _owner,
        address _signer,
        MessageQueueParameters memory _messageQueueParameters,
        EnforcedBatchParameters memory _enforcedBatchParameters
    ) external initializer {
        __Ownable_init();
        transferOwnership(_owner);

        currentSigner = _signer;
        messageQueueParameters = _messageQueueParameters;
        enforcedBatchParameters = _enforcedBatchParameters;
    }

    /*************************
     * Public View Functions *
     *************************/

    /// @notice Return the current authorized signer.
    /// @return The authorized signer address.
    function getSigner() external view returns (address) {
        return currentSigner;
    }

    /************************
     * Restricted Functions *
     ************************/

    /// @notice Update the message queue parameters.
    /// @param _params The new message queue parameters.
    /// @dev Only the owner can call this function.
    function updateMessageQueueParameters(MessageQueueParameters memory _params) external onlyOwner {
        MessageQueueParameters memory oldParams = messageQueueParameters;
        messageQueueParameters = _params;
        emit MessageQueueParametersUpdated(oldParams, _params);
    }

    /// @notice Update the enforced batch parameters.
    /// @param _params The new enforced batch parameters.
    /// @dev Only the owner can call this function.
    function updateEnforcedBatchParameters(EnforcedBatchParameters memory _params) external onlyOwner {
        EnforcedBatchParameters memory oldParams = enforcedBatchParameters;
        enforcedBatchParameters = _params;
        emit EnforcedBatchParametersUpdated(oldParams, _params);
    }

    /// @notice Update the current signer.
    /// @param _newSigner The address of the new authorized signer.
    /// @dev Only the owner can call this function.
    function updateSigner(address _newSigner) external onlyOwner {
        address oldSigner = currentSigner;
        currentSigner = _newSigner;
        emit SignerUpdated(oldSigner, _newSigner);
    }
}
