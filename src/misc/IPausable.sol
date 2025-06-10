// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IPausable {
    /// @notice Returns true if the contract is paused, and false otherwise.
    function paused() external view returns (bool);

    /// @notice Pause or unpause this contract.
    /// @param _status Pause this contract if it is true, otherwise unpause this contract.
    function setPause(bool _status) external;
}
