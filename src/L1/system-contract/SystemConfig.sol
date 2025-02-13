// SPDX-License-Identifier: MIT
pragma solidity =0.8.24;

import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

contract SystemConfig is OwnableUpgradeable {
    /***********
     * Structs *
     ***********/

    /// @param maxGasLimit The maximum gas limit allowed for each L1 message.
    /// @param baseFeeOverhead The overhead used to calculate l2 base fee.
    /// @param baseFeeScalar The scalar used to calculate l2 base fee.
    struct MessageQueueParameters {
        uint32 maxGasLimit;
        uint112 baseFeeOverhead;
        uint112 baseFeeScalar;
    }

    /*********************
     * Storage Variables *
     *********************/

    /// @notice The parameters for message queue.
    MessageQueueParameters public messageQueueParameters;

    /// @dev The address of current authorized signer.
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
        MessageQueueParameters memory _params
    ) external initializer {
        __Ownable_init();
        transferOwnership(_owner);

        currentSigner = _signer;
        messageQueueParameters = _params;
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
    function updateMessageQueueParameters(MessageQueueParameters memory _params) external onlyOwner {
        messageQueueParameters = _params;
    }

    /// @notice Update the current signer.
    /// @dev Only the owner can call this function.
    /// @param _newSigner The address of the new authorized signer.
    function updateSigner(address _newSigner) external onlyOwner {
        currentSigner = _newSigner;
    }
}
